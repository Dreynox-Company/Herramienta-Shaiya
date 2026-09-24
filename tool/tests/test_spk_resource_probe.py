import importlib.util
import pathlib
import tempfile
import unittest

from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE = ROOT / 'tool' / 'spk_resource_probe' / 'resource_probe.py'
AGENT = ROOT / 'tool' / 'spk_resource_probe' / 'resource_probe.js'
SPEC = importlib.util.spec_from_file_location('spk_resource_probe', MODULE)
probe = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(probe)


class ResourceProbeContractTest(unittest.TestCase):
    def test_v13_agent_recovers_and_authenticates_crypto_candidates(self):
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
        self.assertIn("candidate-key", text)
        self.assertIn("BCryptKeyDerivation", text)
        self.assertIn("BCryptDeriveKeyPBKDF2", text)
        self.assertIn("BCryptFinishHash", text)
        self.assertIn("AES_set_decrypt_key", text)
        self.assertIn("EVP_DecryptInit_ex", text)
        self.assertIn("EVP_AEAD_CTX_init", text)
        self.assertIn("mbedtls_gcm_setkey", text)
        self.assertIn("mbedtls_aes_setkey_enc", text)
        self.assertIn("mbedtls_aes_setkey_dec", text)
        self.assertIn("wc_AesGcmSetKey", text)
        self.assertIn("wc_AesSetKey", text)
        self.assertIn("mbedcrypto", text)
        self.assertIn("wolfssl", text)
        self.assertIn("CANDIDATE_HOOK_READY", text)
        self.assertIn("RUNTIME_INDEX_KEY_SCAN", text)
        self.assertIn("runtime-near-index-key", text)
        self.assertIn("CONFIG.indexKeyHex", text)
        probe_text = MODULE.read_text(encoding='utf-8')
        self.assertIn("print('EVENT'", probe_text)
        self.assertIn("'RESUMEN capturas='", probe_text)
        self.assertIn("'indexKeyHex':index_key.hex()", probe_text)

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
        self.assertIn('spkFriendlyErrorMessage(error)', browser)
        self.assertIn('SPK_TEXT_ENCODING_INVALID', browser)
        self.assertIn('ResourceProbe V13', browser)

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

    def test_static_key_sweep_accepts_only_candidate_authenticated_by_oracle(self):
        index_key = bytes.fromhex('9a1f9c1bd3e9488dba7aa4543a466a5f')
        resource_key = bytes.fromhex('102132435465768798a9bacbdcedfe0f')
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            spk = root / 'data.spk'
            game = root / 'game.exe'
            out = root / 'probe'
            out.mkdir()

            # The discovery mechanics are tested without importing the optional
            # runtime cryptography wheel used by the packaged Windows helper.
            spk.write_bytes(b'fixture')
            game.write_bytes(
                b'MZ' + b'X' * 512 + index_key + b'Y' * 64 +
                resource_key + b'Z' * 512
            )
            records = [
                {
                    'ordinal': n,
                    'entryId': f'{0x1000+n:016x}',
                    'dataOffset': 0,
                    'storedBytes': 1,
                    'decodedBytes': 1,
                    'recordType': 1,
                    'auxStart': 0xffffffff,
                    'chunkCount': 0,
                    'metadataHex': '00' * 32,
                }
                for n in range(3)
            ]
            with patch.object(
                probe,
                '_key_authenticates_samples',
                side_effect=lambda _spk, _rows, key: key == resource_key,
            ):
                key, source, report = probe.discover_static_resource_key(
                    game,
                    spk,
                    {'records': records, 'aux': []},
                    index_key,
                    probe.EXPECTED_INDEX,
                    out,
                )
            self.assertEqual(key, resource_key)
            self.assertIsNotNone(source)
            self.assertGreater(report['tested'], 0)
            self.assertIsNotNone(report['match'])
            self.assertTrue((out / 'static-key-sweep.json').is_file())

    def test_v13_deep_pe_data_sweep_finds_key_without_nearby_anchor(self):
        index_key = bytes.fromhex('9a1f9c1bd3e9488dba7aa4543a466a5f')
        resource_key = bytes.fromhex('102132435465768798a9bacbdcedfe0f')
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            spk = root / 'data.spk'
            game = root / 'game.exe'
            out = root / 'probe'
            out.mkdir()
            spk.write_bytes(b'fixture')

            blob = bytearray(0x600)
            blob[:2] = b'MZ'
            blob[0x3c:0x40] = (0x80).to_bytes(4, 'little')
            blob[0x80:0x84] = b'PE\0\0'
            blob[0x86:0x88] = (1).to_bytes(2, 'little')
            blob[0x94:0x96] = (0xE0).to_bytes(2, 'little')
            section = 0x80 + 24 + 0xE0
            blob[section:section + 8] = b'.rdata\0\0'
            blob[section + 16:section + 20] = (0x200).to_bytes(4, 'little')
            blob[section + 20:section + 24] = (0x200).to_bytes(4, 'little')
            blob[section + 36:section + 40] = (0x40000040).to_bytes(
                4, 'little'
            )
            for i in range(0x200, 0x400):
                blob[i] = (i * 37 + 19) & 0xff
            blob[0x280:0x290] = resource_key
            game.write_bytes(blob)

            records = [
                {
                    'ordinal': n,
                    'entryId': f'{0x3000+n:016x}',
                    'dataOffset': 0,
                    'storedBytes': n + 1,
                    'decodedBytes': 1,
                    'recordType': 1,
                    'auxStart': 0xffffffff,
                    'chunkCount': 0,
                    'metadataHex': '00' * 32,
                }
                for n in range(3)
            ]
            with patch.object(
                probe,
                '_key_authenticates_samples',
                side_effect=lambda _spk, _rows, key: key == resource_key,
            ):
                key, source, report = probe.discover_static_resource_key(
                    game,
                    spk,
                    {'records': records, 'aux': []},
                    index_key,
                    probe.EXPECTED_INDEX,
                    out,
                )
            self.assertEqual(key, resource_key)
            self.assertIn(':pe-data:.rdata:', source)
            self.assertGreater(report['deepTested'], 0)
            self.assertEqual(report['schema'], 2)
            self.assertIsNotNone(report['match'])

    def test_deep_pe_data_sweep_finds_key_outside_anchor_windows(self):
        index_key = bytes.fromhex('9a1f9c1bd3e9488dba7aa4543a466a5f')
        resource_key = bytes.fromhex('102132435465768798a9bacbdcedfe0f')
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            spk = root / 'data.spk'
            game = root / 'game.exe'
            out = root / 'probe'
            out.mkdir()
            spk.write_bytes(b'fixture')

            # Minimal PE with one readable initialized, non-executable section.
            # The resource key sits far from the index key so the normal
            # anchor-window pass cannot see it; the V13 deep data-section pass
            # must recover it and still confirm it through the GCM oracle.
            blob = bytearray(0x3200)
            blob[:2] = b'MZ'
            blob[0x3c:0x40] = (0x80).to_bytes(4, 'little')
            blob[0x80:0x84] = b'PE\0\0'
            blob[0x86:0x88] = (1).to_bytes(2, 'little')
            blob[0x94:0x96] = (0).to_bytes(2, 'little')
            section = 0x98
            blob[section:section + 8] = b'.rdata\0\0'
            blob[section + 16:section + 20] = (0x3000).to_bytes(4, 'little')
            blob[section + 20:section + 24] = (0x200).to_bytes(4, 'little')
            blob[section + 36:section + 40] = (0x40000040).to_bytes(4, 'little')
            blob[0x300:0x310] = index_key
            blob[0x2500:0x2510] = resource_key
            game.write_bytes(blob)

            records = [
                {
                    'ordinal': n,
                    'entryId': f'{0x3000+n:016x}',
                    'dataOffset': 0,
                    'storedBytes': 1,
                    'decodedBytes': 1,
                    'recordType': 1,
                    'auxStart': 0xffffffff,
                    'chunkCount': 0,
                    'metadataHex': '00' * 32,
                }
                for n in range(3)
            ]
            with patch.object(
                probe,
                '_nearby_binary_candidates',
                return_value=iter(()),
            ), patch.object(
                probe,
                '_key_authenticates_samples',
                side_effect=lambda _spk, _rows, key: key == resource_key,
            ):
                key, source, report = probe.discover_static_resource_key(
                    game,
                    spk,
                    {'records': records, 'aux': []},
                    index_key,
                    probe.EXPECTED_INDEX,
                    out,
                )
            self.assertEqual(key, resource_key)
            self.assertIn('pe-data:.rdata', source)
            self.assertGreater(report['deepTested'], 0)
            self.assertEqual(report['match']['secretHex'], resource_key.hex())

    def test_static_key_sweep_rejects_every_candidate_when_gcm_oracle_fails(self):
        index_key = bytes.fromhex('9a1f9c1bd3e9488dba7aa4543a466a5f')
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            spk = root / 'data.spk'
            game = root / 'game.exe'
            out = root / 'probe'
            out.mkdir()
            spk.write_bytes(b'fixture')
            game.write_bytes(
                b'MZ' + b'R' * 256 + index_key +
                bytes.fromhex('ffeeddccbbaa99887766554433221100') +
                b'S' * 256
            )
            records = [
                {
                    'ordinal': n,
                    'entryId': f'{0x2000+n:016x}',
                    'dataOffset': 0,
                    'storedBytes': 1,
                    'decodedBytes': 1,
                    'recordType': 1,
                    'auxStart': 0xffffffff,
                    'chunkCount': 0,
                    'metadataHex': '00' * 32,
                }
                for n in range(3)
            ]
            with patch.object(
                probe,
                '_key_authenticates_samples',
                return_value=False,
            ):
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

    def test_static_authenticator_is_aes_gcm_fail_closed(self):
        text = MODULE.read_text(encoding='utf-8')
        self.assertIn('AESGCM(key)', text)
        self.assertIn('aes.decrypt(nonce,ct+tag,None)', text)
        self.assertIn('return False', text)

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