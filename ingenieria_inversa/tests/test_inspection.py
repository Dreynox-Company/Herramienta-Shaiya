"""Own synthetic PE fixtures; never executes the inspected binary."""
import importlib.util
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'tools' / 'inspect_client.py'
spec = importlib.util.spec_from_file_location('inspect_client', MODULE)
assert spec and spec.loader
inspect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspect)


def synthetic_pe():
    b = bytearray(1024)
    b[0:2] = b'MZ'
    struct.pack_into('<I', b, 0x3c, 0x80)
    b[0x80:0x84] = b'PE\0\0'
    struct.pack_into('<HHIIIHH', b, 0x84, 0x14c, 1, 0, 0, 0, 0xe0, 0x102)
    o = 0x98
    struct.pack_into('<H', b, o, 0x10b)
    struct.pack_into('<IIIIII', b, o+4, 0x200, 0, 0, 0x1000, 0x1000, 0x2000)
    struct.pack_into('<III', b, o+28, 0x400000, 0x1000, 0x200)
    struct.pack_into('<HH', b, o+40, 6, 0)
    struct.pack_into('<II', b, o+56, 0x2000, 0x200)
    struct.pack_into('<HH', b, o+68, 3, 0)
    struct.pack_into('<IIIIII', b, o+72, 0x100000, 0x1000, 0x100000, 0x1000, 0, 16)
    s = o+0xe0
    b[s:s+8] = b'.text\0\0\0'
    struct.pack_into('<IIIIIIHHI', b, s+8, 0x200, 0x1000, 0x200, 0x200, 0, 0, 0, 0, 0x60000020)
    b[0x200:0x201] = b'\xc3'
    b[0x210:0x219] = b'data.sah\0'
    b[0x230:0x239] = b'game.exe\0'
    return bytes(b)


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.client = self.root/'synthetic.exe'
        self.body = synthetic_pe()
        self.client.write_bytes(self.body)

    def tearDown(self):
        self.temp.cleanup()

    def test_inventory_has_explicit_unknown_profile(self):
        result = inspect.inventory(self.client)
        self.assertEqual(result['profile'], 'unrecognized-no-address-assumptions')
        self.assertEqual(result['knownDisassembly'], {})
        self.assertTrue(result['readOnly'])
        self.assertEqual(result['machine'], '0x14c')

    def test_addresses_and_sections_are_not_guessed(self):
        r = inspect.inventory(self.client)
        self.assertEqual(r['entryPoint'], '0x401000')
        self.assertEqual(r['sections'][0]['fileOffset'], 0x200)
        self.assertTrue(r['sections'][0]['executable'])
        self.assertFalse(r['sections'][0]['writable'])

    def test_strings_retain_file_location(self):
        r = inspect.inventory(self.client)
        s = next(x for x in r['selectedStrings'] if x['text'] == 'data.sah')
        self.assertEqual(s['fileOffset'], 0x210)
        self.assertEqual(s['virtualAddress'], '0x401010')

    def test_original_bytes_never_change(self):
        inspect.inventory(self.client)
        self.assertEqual(self.client.read_bytes(), self.body)

    def test_missing_file_rejected(self):
        with self.assertRaises(ValueError):
            inspect.inventory(self.root/'missing.exe')

    def test_directory_rejected(self):
        with self.assertRaises(ValueError):
            inspect.inventory(self.root)

    def test_too_small_rejected(self):
        self.client.write_bytes(b'MZ')
        with self.assertRaises(ValueError):
            inspect.inventory(self.client)

    def test_size_limit_checked_before_parsing(self):
        with self.client.open('wb') as f:
            f.truncate(64*1024*1024+1)
        with self.assertRaisesRegex(ValueError, '64 MiB'):
            inspect.inventory(self.client)

    def test_malformed_pe_does_not_produce_report(self):
        self.client.write_bytes(b'not an executable'*100)
        with self.assertRaises(inspect.pefile.PEFormatError):
            inspect.inventory(self.client)

    def test_entropy_has_no_inference_of_encryption(self):
        self.assertEqual(inspect.entropy(b''), 0)
        self.assertEqual(inspect.entropy(b'\0'*500), 0)
        self.assertEqual(inspect.entropy(bytes(range(256))), 8)
        self.assertTrue(math.isfinite(inspect.entropy(self.body)))

    def test_cli_exclusive_report_and_valid_json(self):
        out = self.root/'report'
        command = [sys.executable, str(MODULE), '--client', str(self.client), '--out', str(out)]
        first = subprocess.run(command, capture_output=True, text=True, timeout=20)
        self.assertEqual(first.returncode, 0, first.stderr)
        data = (out/'pe_inventory.json').read_bytes()
        self.assertEqual(json.loads(data)['bytes'], len(self.body))
        second = subprocess.run(command, capture_output=True, text=True, timeout=20)
        self.assertNotEqual(second.returncode, 0)
        self.assertEqual((out/'pe_inventory.json').read_bytes(), data)

    @unittest.skipIf(sys.platform == 'win32', 'Creating test symlinks needs extra Windows privilege')
    def test_symlink_input_rejected(self):
        link = self.root/'link.exe'
        link.symlink_to(self.client)
        with self.assertRaises(ValueError):
            inspect.inventory(link)

if __name__ == '__main__':
    unittest.main()
