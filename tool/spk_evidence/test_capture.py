"""Run the compiled Windows evidence tool on synthetic files only.

No test result is evidence of decrypting the user's SPK. The manifest must
explicitly retain fullDecryptionVerified=false after a successful capture.
"""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import zipfile

EXE = Path(os.environ['SPK_EVIDENCE_EXE']).resolve()


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.spk = self.root / 'data.spk'
        self.plan_path = self.root / 'plan.json'
        self.output = self.root / 'evidence.zip'
        blob = bytearray((i * 37) % 256 for i in range(4096))
        blob[:128] = bytes(128)
        struct.pack_into('<IIQQQII', blob, 0, 0x9e7bd34c, 0x30000,
                         3808, 224, 96, 1, 262144)
        struct.pack_into('<QI', blob, 100, 3776, 1)
        self.blob = bytes(blob)
        self.spk.write_bytes(self.blob)
        self.plan = {
            'schema': 1, 'fileBytes': len(blob),
            'headerSha256': hashlib.sha256(blob[:128]).hexdigest(),
            'indexSha256': hashlib.sha256(blob[3808:4032]).hexdigest(),
            'ranges': [{'offset': 128, 'length': 43, 'purpose': 'sample'},
                       {'offset': 2048, 'length': 101, 'purpose': 'sample'}],
        }

    def run_capture(self, *args, expected=0):
        self.plan_path.write_text(json.dumps(self.plan), encoding='utf-8')
        process = subprocess.run([str(EXE), '--spk', str(self.spk), '--plan',
                                  str(self.plan_path), '--out', str(self.output), *map(str, args)],
                                 capture_output=True, text=True, timeout=30)
        self.assertEqual(process.returncode, expected, process.stdout + process.stderr)
        self.assertEqual(self.spk.read_bytes(), self.blob)
        self.assertFalse(list(self.root.glob('*.partial-*')))
        return process

    def test_capture_is_exact_and_does_not_claim_decryption(self):
        self.run_capture()
        with zipfile.ZipFile(self.output) as z:
            self.assertIsNone(z.testzip())
            manifest = json.loads(z.read('manifest.json'))
            self.assertIs(manifest['fullDecryptionVerified'], False)
            self.assertIs(manifest['privateResourceProfileIncluded'], False)
            self.assertEqual(manifest['sourceFileBytes'], len(self.blob))
            for item in manifest['entries']:
                value = z.read(item['file'])
                self.assertEqual(len(value), item['bytes'])
                self.assertEqual(hashlib.sha256(value).hexdigest(), item['sha256'])
                if item['sourceOffset'] is not None:
                    start = item['sourceOffset']
                    self.assertEqual(value, self.blob[start:start+len(value)])

    def test_wrong_size_rejected(self):
        self.plan['fileBytes'] += 1
        self.run_capture(expected=1)
        self.assertFalse(self.output.exists())

    def test_wrong_header_rejected(self):
        self.plan['headerSha256'] = '0' * 64
        self.run_capture(expected=1)
        self.assertFalse(self.output.exists())

    def test_wrong_index_rejected(self):
        self.plan['indexSha256'] = '0' * 64
        self.run_capture(expected=1)
        self.assertFalse(self.output.exists())

    def test_bad_ranges_fail_before_publication(self):
        for ranges in [
            [{'offset': -1, 'length': 10}],
            [{'offset': 128, 'length': 0}],
            [{'offset': 128, 'length': -1}],
            [{'offset': 3770, 'length': 100}],
            [{'offset': 128, 'length': 9 * 1024 * 1024}],
            [{'offset': 128, 'length': 40}, {'offset': 135, 'length': 40}],
            [None],
        ]:
            with self.subTest(ranges=ranges):
                self.plan['ranges'] = ranges
                self.run_capture(expected=1)
                self.assertFalse(self.output.exists())

    def test_existing_output_is_never_overwritten(self):
        self.output.write_bytes(b'existing file')
        self.run_capture(expected=1)
        self.assertEqual(self.output.read_bytes(), b'existing file')

    def test_schema_and_entry_count_are_bounded(self):
        self.plan['schema'] = 99
        self.run_capture(expected=1)
        self.plan['schema'] = 1
        self.plan['ranges'] = [{'offset': 128, 'length': 1}] * 4097
        self.run_capture(expected=1)

    def test_profile_requires_explicit_cli_consent(self):
        profile = self.root / 'profile.json'
        profile.write_text(json.dumps({'resourceSecretHex': '10' * 16}))
        self.run_capture('--profile', profile, expected=1)
        self.assertFalse(self.output.exists())

    def test_private_profile_kept_out_of_public_manifest(self):
        profile = self.root / 'profile.json'
        profile.write_text(json.dumps({'resourceSecretHex': '10' * 16,
                                       'indexSha256': self.plan['indexSha256']}))
        self.run_capture('--profile', profile, '--allow-private')
        with zipfile.ZipFile(self.output) as z:
            self.assertEqual(z.read('PRIVATE/resource-profile.json'), profile.read_bytes())
            self.assertNotIn(b'10' * 16, z.read('manifest.json'))
            self.assertIs(json.loads(z.read('manifest.json'))['privateResourceProfileIncluded'], True)

    def test_nested_resource_profile_supported(self):
        profile = self.root / 'profile.json'
        profile.write_text(json.dumps({'resources': {'secretHex': '20' * 32}}))
        self.run_capture('--profile', profile, '--allow-private')

    def test_foreign_or_unrelated_profile_rejected(self):
        profile = self.root / 'profile.json'
        for data in [{'resourceSecretHex': '10' * 16, 'indexSha256': 'bad'},
                     {'password': 'not a resource profile'},
                     {'secretHex': '10' * 16, 'target': 'index'},
                     {'resourceSecretHex': 'XX' * 16}]:
            with self.subTest(data=data):
                profile.write_text(json.dumps(data))
                self.run_capture('--profile', profile, '--allow-private', expected=1)
                self.assertFalse(self.output.exists())

    def test_executable_is_copied_not_executed(self):
        executable = self.root / 'game.exe'
        data = bytearray(512)
        data[:2] = b'MZ'
        struct.pack_into('<I', data, 60, 128)
        data[128:134] = b'PE\0\0\x64\x86'
        executable.write_bytes(data)  # Deliberately NOT a runnable program.
        self.run_capture('--game', executable, '--allow-private')
        with zipfile.ZipFile(self.output) as z:
            self.assertEqual(z.read('PRIVATE/game.exe'), data)

    def test_non_executable_rejected(self):
        executable = self.root / 'game.exe'
        executable.write_bytes(b'wrong file')
        self.run_capture('--game', executable, '--allow-private', expected=1)
        self.assertFalse(self.output.exists())

    def test_unknown_arguments_rejected(self):
        self.run_capture('--unrecognized', 'value', expected=1)
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
