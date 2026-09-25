"""No-network checks for delivery safety and source preservation."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare
import publish_sources
import build

PACKAGE_WINDOWS = Path(__file__).resolve().parents[2] / 'ci' / 'package_windows.py'
PACKAGE_SPEC = importlib.util.spec_from_file_location('package_windows', PACKAGE_WINDOWS)
package_windows = importlib.util.module_from_spec(PACKAGE_SPEC)
assert PACKAGE_SPEC.loader is not None
PACKAGE_SPEC.loader.exec_module(package_windows)

ANGLE_HARDEN = Path(__file__).resolve().parents[2] / 'ci' / 'harden_angle_runtime.py'
ANGLE_SPEC = importlib.util.spec_from_file_location(
    'harden_angle_runtime',
    ANGLE_HARDEN,
)
harden_angle_runtime = importlib.util.module_from_spec(ANGLE_SPEC)
assert ANGLE_SPEC.loader is not None
ANGLE_SPEC.loader.exec_module(harden_angle_runtime)


class DeliveryToolsTest(unittest.TestCase):
    def test_windows_package_readme_uses_pubspec_version(self):
        root = Path(__file__).resolve().parents[2]
        text = (root / 'ci' / 'package_windows.py').read_text(encoding='utf-8')
        self.assertIn("SHAIYA STUDIO {version} - DATA.SPK V13", text)
        self.assertNotIn("SHAIYA STUDIO 0.6.17 - DATA.SPK V11", text)
        self.assertNotIn("SHAIYA STUDIO 0.6.18 - DATA.SPK V11", text)

    def test_windows_package_emits_completion_gate_manifest(self):
        root = Path(__file__).resolve().parents[2]
        text = (root / 'ci' / 'package_windows.py').read_text(encoding='utf-8')
        self.assertIn("distribution-status.json", text)
        self.assertIn("delivery_status['productionComplete100']=not blocking", text)
        self.assertIn("'spk-payload-key'", text)
        self.assertIn("'real-data-visual-qa'", text)
        self.assertIn("'spk-50135-full-audit-and-reopen'", text)
        self.assertIn("'windows-angle-release-runtime'", text)
        self.assertIn("graphicsRuntimeHardeningEvidence", text)

    def test_windows_package_tracks_real_flight_v3_runtime_hashes(self):
        root = Path(__file__).resolve().parents[2]
        text = (root / 'ci' / 'package_windows.py').read_text(encoding='utf-8')
        self.assertIn(
            '6d0422c69a0e5c4b7f2a42061e30a91a6c6b452afaacac53af1e7034267cb5ba',
            text,
        )
        self.assertIn(
            '7f720a9e339d96a6e47cdce11094ecb64663c2f80f102de179f76e7f0b2c8a44',
            text,
        )
        self.assertIn("'FLIGHT_V3_REAL_RUNTIME_AUDIT.md'", text)
        self.assertIn("'WINDOWS_RELEASE_AUDIT.md'", text)

    def test_flight_runtime_bundling_is_hash_locked(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            release = root / 'release'
            runtime = root / package_windows.FLIGHT_RUNTIME_NAME
            release.mkdir()
            runtime.write_bytes(b'real-runtime-fixture')
            expected = hashlib.sha256(runtime.read_bytes()).hexdigest()
            with patch.object(package_windows, 'ROOT', root), \
                    patch.object(package_windows, 'FLIGHT_RUNTIME_SHA256', expected), \
                    patch.dict(
                        package_windows.os.environ,
                        {'SHAIYA_FLIGHT_V3_RUNTIME': str(runtime)},
                        clear=False,
                    ):
                target = package_windows.install_flight_runtime(release)
            self.assertIsNotNone(target)
            self.assertEqual(target.read_bytes(), runtime.read_bytes())
            self.assertEqual(
                target,
                release / 'Extras' / 'FlightV3' /
                package_windows.FLIGHT_RUNTIME_NAME,
            )

    def test_flight_runtime_bundling_rejects_wrong_hash(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            release = root / 'release'
            runtime = root / package_windows.FLIGHT_RUNTIME_NAME
            release.mkdir()
            runtime.write_bytes(b'tampered-runtime')
            with patch.object(package_windows, 'ROOT', root), \
                    patch.object(
                        package_windows,
                        'FLIGHT_RUNTIME_SHA256',
                        '0' * 64,
                    ), \
                    patch.dict(
                        package_windows.os.environ,
                        {'SHAIYA_FLIGHT_V3_RUNTIME': str(runtime)},
                        clear=False,
                    ):
                with self.assertRaisesRegex(RuntimeError, 'hash mismatch'):
                    package_windows.install_flight_runtime(release)

    def test_angle_debug_crt_internal_cluster_does_not_count_as_external_user(self):
        imports = {
            'herramienta_shaiya.exe': ['kernel32.dll'],
            'flutter_angle_plugin.dll': ['vcruntime140.dll', 'libEGL.dll'],
            'libEGL.dll': ['kernel32.dll'],
            'libGLESv2.dll': ['d3d11.dll'],
            'libc++.dll': ['msvcp140d.dll', 'ucrtbased.dll'],
            'vccorlib140d.dll': ['msvcp140d.dll'],
            'msvcp140d.dll': ['vcruntime140d.dll'],
        }
        users = harden_angle_runtime.legacy_external_users(imports)
        self.assertEqual(users['msvcp140d.dll'], [])
        self.assertEqual(users['ucrtbased.dll'], [])
        self.assertEqual(users['vcruntime140d.dll'], [])

    def test_angle_debug_crt_import_from_retained_plugin_is_blocking(self):
        imports = {
            'flutter_angle_plugin.dll': [
                'libEGL.dll',
                'vcruntime140d.dll',
            ],
            'vcruntime140d.dll': ['kernel32.dll'],
        }
        users = harden_angle_runtime.legacy_external_users(imports)
        self.assertEqual(
            users['vcruntime140d.dll'],
            ['flutter_angle_plugin.dll'],
        )

    def test_angle_hardening_evidence_is_bound_to_release_dll_hashes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            release = root / 'release'
            qa = root / 'qa-windows'
            release.mkdir()
            qa.mkdir()
            egl = release / 'libEGL.dll'
            gles = release / 'libGLESv2.dll'
            egl.write_bytes(b'egl-release')
            gles.write_bytes(b'gles-release')
            payload = {
                'schema': 1,
                'provider': 'comfy-angle',
                'providerVersion': '0.1.1',
                'releaseDllSha256': {
                    'libEGL.dll': hashlib.sha256(egl.read_bytes()).hexdigest(),
                    'libGLESv2.dll': hashlib.sha256(gles.read_bytes()).hexdigest(),
                },
                'debugCrtImports': {},
                'hardened': True,
            }
            (qa / 'angle-runtime.json').write_text(
                json.dumps(payload),
                encoding='utf-8',
            )
            with patch.object(package_windows, 'ROOT', root):
                result = package_windows.load_angle_hardening(release)
            self.assertTrue(result['hardened'])
            self.assertEqual(result['provider'], 'comfy-angle')
            self.assertEqual(result['providerVersion'], '0.1.1')

    def test_angle_hardening_rejects_evidence_for_other_binaries(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            release = root / 'release'
            qa = root / 'qa-windows'
            release.mkdir()
            qa.mkdir()
            (release / 'libEGL.dll').write_bytes(b'egl-release')
            (release / 'libGLESv2.dll').write_bytes(b'gles-release')
            payload = {
                'schema': 1,
                'provider': 'comfy-angle',
                'providerVersion': '0.1.1',
                'releaseDllSha256': {
                    'libEGL.dll': '0' * 64,
                    'libGLESv2.dll': hashlib.sha256(
                        (release / 'libGLESv2.dll').read_bytes()
                    ).hexdigest(),
                },
                'debugCrtImports': {},
                'hardened': True,
            }
            (qa / 'angle-runtime.json').write_text(
                json.dumps(payload),
                encoding='utf-8',
            )
            with patch.object(package_windows, 'ROOT', root):
                with self.assertRaisesRegex(
                    RuntimeError,
                    'does not match libEGL.dll',
                ):
                    package_windows.load_angle_hardening(release)

    def test_real_acceptance_is_hash_bound_and_can_close_gates(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            qa = root / 'qa-real'
            qa.mkdir()
            game_sha = package_windows.PS0032_GAME_SHA256
            payload = {
                'schema': 1,
                'gameExeSha256': game_sha,
                'wing': {
                    'positionGameExe': True,
                    'positionSha256': package_windows.WING_POSITION_SHA256,
                    'monExactInstall': True,
                    'monSha256': package_windows.WING_MON_SHA256,
                },
                'vehicle': {
                    'monExactInstall': True,
                    'bridgeGameExe': True,
                    'monSha256': dict(package_windows.VEHICLE_MON_SHA256),
                },
                'spk': {
                    'indexSha256': package_windows.REAL_INDEX_SHA256,
                    'canReadSimpleResources': True,
                    'canReadFragmentedResources': True,
                    'canExtractAll': True,
                    'validatedResources': 50135,
                    'failures': 0,
                    'repackReopened': True,
                    'gameExeAccepted': True,
                    'gameExeSha256': 'ef' * 32,
                },
            }
            (qa / 'acceptance.json').write_text(
                json.dumps(payload),
                encoding='utf-8',
            )
            with patch.object(package_windows, 'ROOT', root), \
                    patch.dict(package_windows.os.environ, {}, clear=True):
                result = package_windows.load_real_acceptance()
            self.assertTrue(result['wingPositionGameExe'])
            self.assertTrue(result['wingMonExactInstall'])
            self.assertTrue(result['vehicleMonExactInstall'])
            self.assertTrue(result['vehicleBridgeGameExe'])
            self.assertTrue(result['spkFullAuditComplete'])
            self.assertTrue(result['spkRepackReopened'])
            self.assertTrue(result['spkGameExeAccepted'])
            self.assertEqual(result['gameExeSha256'], game_sha)
            self.assertEqual(result['spkGameExeSha256'], 'ef' * 32)

    def test_real_acceptance_rejects_mismatched_real_resource_hashes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            qa = root / 'qa-real'
            qa.mkdir()
            payload = {
                'schema': 1,
                'gameExeSha256': 'cd' * 32,
                'wing': {
                    'positionGameExe': True,
                    'positionSha256': '0' * 64,
                    'monExactInstall': True,
                    'monSha256': '0' * 64,
                },
                'vehicle': {
                    'monExactInstall': True,
                    'bridgeGameExe': True,
                    'monSha256': {
                        key: '0' * 64
                        for key in package_windows.VEHICLE_MON_SHA256
                    },
                },
                'spk': {
                    'indexSha256': '0' * 64,
                    'canReadSimpleResources': True,
                    'canReadFragmentedResources': True,
                    'canExtractAll': True,
                    'validatedResources': 50135,
                    'failures': 0,
                    'repackReopened': True,
                    'gameExeAccepted': True,
                    'gameExeSha256': 'ef' * 32,
                },
            }
            (qa / 'acceptance.json').write_text(
                json.dumps(payload),
                encoding='utf-8',
            )
            with patch.object(package_windows, 'ROOT', root), \
                    patch.dict(package_windows.os.environ, {}, clear=True):
                result = package_windows.load_real_acceptance()
            self.assertFalse(result['wingPositionGameExe'])
            self.assertFalse(result['wingMonExactInstall'])
            self.assertFalse(result['vehicleMonExactInstall'])
            self.assertFalse(result['vehicleBridgeGameExe'])
            self.assertFalse(result['spkFullAuditComplete'])
            self.assertFalse(result['spkRepackReopened'])
            self.assertFalse(result['spkGameExeAccepted'])

    def test_unknown_platform_is_rejected_before_running_flutter(self):
        with patch.object(prepare.subprocess, 'run') as run:
            with self.assertRaises(ValueError):
                prepare.prepare('browser')
            run.assert_not_called()

    def test_source_restored_even_when_runner_generation_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'lib').mkdir()
            (root / 'lib/main.dart').write_text('REAL APP')
            (root / 'pubspec.yaml').write_text('version: 0.5.0+7')
            def destructive_template(*args, **kwargs):
                (root / 'lib/main.dart').write_text('COUNTER APP')
                (root / 'pubspec.yaml').write_text('new template')
                raise subprocess.CalledProcessError(1, 'flutter')
            with patch.object(prepare, 'ROOT', root), patch.object(prepare.shutil, 'which', return_value='flutter'), patch.object(prepare.subprocess, 'run', side_effect=destructive_template):
                with self.assertRaises(subprocess.CalledProcessError):
                    prepare.prepare('windows')
            self.assertEqual((root / 'lib/main.dart').read_text(), 'REAL APP')
            self.assertEqual((root / 'pubspec.yaml').read_text(), 'version: 0.5.0+7')

    def test_cmake_version_uses_successful_version_command(self):
        result = subprocess.CompletedProcess([], 0, 'cmake version 3.31.4\n', '')
        with patch.object(build.subprocess, 'run', return_value=result):
            self.assertEqual(build.cmake_version('cmake'), (3, 31, 4))

    def test_failed_cmake_is_not_claimed_available(self):
        with patch.object(build.subprocess, 'run', side_effect=OSError('missing')):
            self.assertIsNone(build.cmake_version('cmake'))

    def manifest(self, root):
        names = ['lib/main.dart', 'lib/data/catalog.dart', 'lib/data/game_names.dart', 'pubspec.yaml']
        files = {}
        for name in names:
            p = root / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('source ' + name)
            files[name] = hashlib.sha256(p.read_bytes()).hexdigest()
        manifest = {'version': '0.6.0+8', 'base_commit': publish_sources.BASE, 'files': files}
        (root / 'manifest-entrega.json').write_text(json.dumps(manifest))
        return manifest

    def test_manifest_checks_actual_data_source_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.manifest(root)
            with patch.object(publish_sources, 'SOURCE', root):
                self.assertEqual(len(publish_sources.verified_sources()), 4)

    def test_changed_source_is_not_published_as_verified(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.manifest(root)
            (root / 'lib/main.dart').write_text('modified after delivery')
            with patch.object(publish_sources, 'SOURCE', root):
                with self.assertRaisesRegex(RuntimeError, 'modificó'):
                    publish_sources.verified_sources()

    def test_manifest_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            manifest = self.manifest(root)
            manifest['files'] = {'../outside.dart': '0' * 64}
            (root / 'manifest-entrega.json').write_text(json.dumps(manifest))
            with patch.object(publish_sources, 'SOURCE', root):
                with self.assertRaisesRegex(RuntimeError, 'Ruta no permitida'):
                    publish_sources.verified_sources()


if __name__ == '__main__':
    unittest.main()
