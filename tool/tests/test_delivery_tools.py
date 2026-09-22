"""No-network checks for delivery safety and source preservation."""
import hashlib
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


class DeliveryToolsTest(unittest.TestCase):
    def test_windows_package_readme_uses_pubspec_version(self):
        root = Path(__file__).resolve().parents[2]
        text = (root / 'ci' / 'package_windows.py').read_text(encoding='utf-8')
        self.assertIn("SHAIYA STUDIO {version} - DATA.SPK V11", text)
        self.assertNotIn("SHAIYA STUDIO 0.6.17 - DATA.SPK V11", text)

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
