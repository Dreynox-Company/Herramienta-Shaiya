import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ROOT / 'tool' / 'spk_resource_probe' / 'resource_probe.py'
AGENT = ROOT / 'tool' / 'spk_resource_probe' / 'resource_probe.js'
SPEC = importlib.util.spec_from_file_location('spk_resource_probe', MODULE)
probe = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(probe)


class ResourceProbeContractTest(unittest.TestCase):
    def test_v10_agent_can_recover_keys_from_live_bcrypt_handles(self):
        text = AGENT.read_text(encoding='utf-8')
        self.assertIn("BCryptExportKey", text)
        self.assertIn("KeyDataBlob", text)
        self.assertIn("BCryptImportKey", text)
        self.assertIn("BCryptDuplicateKey", text)
        self.assertIn("KEY_EXPORTED_FROM_LIVE_HANDLE", text)
        self.assertIn("['x64', 'ia32'].includes(Process.arch)", text)
        self.assertIn("pointerSize: Process.pointerSize", text)

    def test_windows_probe_and_studio_force_utf8_safe_evidence(self):
        probe_text = MODULE.read_text(encoding='utf-8')
        write_lines = [
            line for line in probe_text.splitlines()
            if '.write_text(' in line
        ]
        self.assertGreaterEqual(len(write_lines), 3)
        for line in write_lines:
            self.assertIn("encoding='utf-8'", line)
        browser = (
            ROOT / 'lib' / 'ui' / 'spk_archive_browser.dart'
        ).read_text(encoding='utf-8')
        self.assertIn("'PYTHONUTF8': '1'", browser)
        self.assertIn("'PYTHONIOENCODING': 'utf-8'", browser)
        self.assertIn('Utf8Decoder(allowMalformed: true)', browser)
        self.assertIn('!source.canReadRecord(record)', browser)
        self.assertIn('CONTENIDO CIFRADO:', browser)

    def test_pe_arch_detects_x86_and_x64_clients(self):
        for machine, expected in ((0x014c, 'x86'), (0x8664, 'x64')):
            blob = bytearray(128)
            blob[:2] = b'MZ'
            blob[0x3c:0x40] = (64).to_bytes(4, 'little')
            blob[64:68] = b'PE\0\0'
            blob[68:70] = machine.to_bytes(2, 'little')
            with tempfile.TemporaryDirectory() as td:
                path = pathlib.Path(td) / 'game.exe'
                path.write_bytes(blob)
                self.assertEqual(probe.pe_arch(path), expected)

    def test_simple_and_chunks_same_key_make_ready_for_all(self):
        key = '11' * 32
        base = {
            'offlineValid': True,
            'key': {
                'secretHex': key,
                'chainingMode': 'ChainingModeGCM',
                'source': 'BCryptExportKey:KeyDataBlob',
            },
            'auth': {'authDataHex': ''},
            'format': 'DDS',
            'plainSha256': 'aa' * 32,
            'matchesNative': True,
        }
        rows = []
        for n in range(2):
            rows.append({
                **base,
                'target': {'kind': 'simple', 'entryId': f'{n + 1:016x}', 'ordinal': n},
                'metadataNonceMatch': True,
                'metadataTagMatch': True,
            })
        for n in range(2):
            rows.append({
                **base,
                'target': {'kind': 'chunk', 'entryId': '0000000000000003', 'ordinal': n, 'parentOrdinal': 2},
                'metadataTagMatch': True,
                'nonceRule': 'offset_chunk0_le96',
            })
        result = probe.derive_profile(rows)
        self.assertTrue(result['readyForSimple'])
        self.assertTrue(result['readyForFragmented'])
        self.assertTrue(result['readyForAll'])
        self.assertEqual(result['resourceSecretBytes'], 32)
        self.assertEqual(
            result['keySources'],
            ['BCryptExportKey:KeyDataBlob'],
        )
        self.assertEqual(result['chunkNonceRule'], 'offset_le96')
        self.assertEqual(result['aadRule'], 'none')

    def test_conflicting_resource_keys_fail_closed(self):
        rows = [
            {
                'offlineValid': True,
                'target': {'kind': 'simple', 'entryId': '1', 'ordinal': 1},
                'key': {'secretHex': '11' * 16, 'chainingMode': 'ChainingModeGCM'},
                'auth': {'authDataHex': ''},
                'metadataNonceMatch': True,
                'metadataTagMatch': True,
                'format': 'BIN',
                'plainSha256': 'aa' * 32,
            },
            {
                'offlineValid': True,
                'target': {'kind': 'simple', 'entryId': '2', 'ordinal': 2},
                'key': {'secretHex': '22' * 16, 'chainingMode': 'ChainingModeGCM'},
                'auth': {'authDataHex': ''},
                'metadataNonceMatch': True,
                'metadataTagMatch': True,
                'format': 'BIN',
                'plainSha256': 'bb' * 32,
            },
        ]
        result = probe.derive_profile(rows)
        self.assertFalse(result['readyForSimple'])
        self.assertNotIn('resourceSecretHex', result)

    def test_constant_aad_is_preserved(self):
        key = '33' * 16
        rows = []
        for n in range(2):
            rows.append({
                'offlineValid': True,
                'target': {'kind': 'simple', 'entryId': f'{n + 1:016x}', 'ordinal': n},
                'key': {'secretHex': key, 'chainingMode': 'ChainingModeGCM'},
                'auth': {'authDataHex': 'aabbccdd'},
                'metadataNonceMatch': True,
                'metadataTagMatch': True,
                'format': 'BIN',
                'plainSha256': 'cc' * 32,
            })
        result = probe.derive_profile(rows)
        self.assertTrue(result['readyForSimple'])
        self.assertEqual(result['aadRule'], 'constant')
        self.assertEqual(result['aadHex'], 'aabbccdd')


if __name__ == '__main__':
    unittest.main()