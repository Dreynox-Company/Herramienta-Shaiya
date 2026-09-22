import importlib.util
import pathlib
import tempfile
import unittest

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ROOT / 'tool' / 'spk_resource_probe' / 'resource_probe.py'
AGENT = ROOT / 'tool' / 'spk_resource_probe' / 'resource_probe.js'
SPEC = importlib.util.spec_from_file_location('spk_resource_probe', MODULE)
probe = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(probe)


class ResourceProbeContractTest(unittest.TestCase):
    def test_v11_agent_can_recover_keys_from_live_bcrypt_handles(self):
        text = AGENT.read_text(encoding='utf-8')
        self.assertIn("BCryptExportKey", text)
        self.assertIn("KeyDataBlob", text)
        self.assertIn("BCryptImportKey", text)
        self.assertIn("BCryptDuplicateKey", text)
        self.assertIn("KEY_EXPORTED_FROM_LIVE_HANDLE", text)
        self.assertIn("['x64', 'ia32'].includes(Process.arch)", text)
        self.assertIn("pointerSize: Process.pointerSize", text)
        self.assertIn("RESOURCE_MATCH_INCOMPLETE_CRYPTO", text)
        self.assertIn("No se marca como visto", text)
        probe_text = MODULE.read_text(encoding='utf-8')
        self.assertIn("print('EVENT'", probe_text)
        self.assertIn("'RESUMEN capturas='", probe_text)

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

    def test_static_key_sweep_finds_nearby_resource_key_only_after_gcm_auth(self):
        index_key = bytes.fromhex('9a1f9c1bd3e9488dba7aa4543a466a5f')
        resource_key = bytes.fromhex('102132435465768798a9bacbdcedfe0f')
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            spk = root / 'data.spk'
            game = root / 'game.exe'
            out = root / 'probe'
            out.mkdir()

            payload = bytearray(128)
            records = []
            for ordinal in range(3):
                plain = (b'DDS ' + bytes([ordinal + 1]) * (64 + ordinal))
                nonce = bytes(range(ordinal, ordinal + 12))
                encrypted = AESGCM(resource_key).encrypt(nonce, plain, None)
                cipher, tag = encrypted[:-16], encrypted[-16:]
                offset = len(payload)
                payload.extend(cipher)
                metadata = nonce + tag + (0).to_bytes(4, 'little')
                records.append({
                    'ordinal': ordinal,
                    'entryId': f'{0x1000 + ordinal:016x}',
                    'dataOffset': offset,
                    'storedBytes': len(cipher),
                    'decodedBytes': len(plain),
                    'recordType': 1,
                    'auxStart': 0xffffffff,
                    'chunkCount': 0,
                    'metadataHex': metadata.hex(),
                })
            spk.write_bytes(payload)
            game.write_bytes(
                b'MZ' + b'X' * 512 + index_key + b'Y' * 64 +
                resource_key + b'Z' * 512
            )
            cat = {'records': records, 'aux': []}

            key, source, report = probe.discover_static_resource_key(
                game,
                spk,
                cat,
                index_key,
                probe.EXPECTED_INDEX,
                out,
            )
            self.assertEqual(key, resource_key)
            self.assertIsNotNone(source)
            self.assertGreater(report['tested'], 0)
            self.assertIsNotNone(report['match'])
            self.assertTrue((out / 'static-key-sweep.json').is_file())

    def test_static_key_sweep_rejects_unrelated_nearby_constants(self):
        index_key = bytes.fromhex('9a1f9c1bd3e9488dba7aa4543a466a5f')
        resource_key = bytes.fromhex('102132435465768798a9bacbdcedfe0f')
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            spk = root / 'data.spk'
            game = root / 'game.exe'
            out = root / 'probe'
            out.mkdir()

            payload = bytearray(128)
            records = []
            for ordinal in range(3):
                plain = b'DDS ' + bytes([ordinal + 9]) * 80
                nonce = bytes(range(ordinal + 20, ordinal + 32))
                encrypted = AESGCM(resource_key).encrypt(nonce, plain, None)
                cipher, tag = encrypted[:-16], encrypted[-16:]
                offset = len(payload)
                payload.extend(cipher)
                records.append({
                    'ordinal': ordinal,
                    'entryId': f'{0x2000 + ordinal:016x}',
                    'dataOffset': offset,
                    'storedBytes': len(cipher),
                    'decodedBytes': len(plain),
                    'recordType': 1,
                    'auxStart': 0xffffffff,
                    'chunkCount': 0,
                    'metadataHex': (nonce + tag + b'\0\0\0\0').hex(),
                })
            spk.write_bytes(payload)
            game.write_bytes(
                b'MZ' + b'R' * 256 + index_key +
                bytes.fromhex('ffeeddccbbaa99887766554433221100') +
                b'S' * 256
            )

            key, source, report = probe.discover_static_resource_key(
                game,
                spk,
                {'records': records, 'aux': []},
                index_key,
                probe.EXPECTED_INDEX,
                out,
            )
            self.assertIsNone(key)
            self.assertIsNone(source)
            self.assertIsNone(report['match'])

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