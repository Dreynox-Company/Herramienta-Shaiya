from pathlib import Path
import hashlib
import importlib.util
import tempfile
import unittest
from unittest.mock import patch

script = Path(__file__).resolve().parents[1]/'configure_spanish_client.py'
spec = importlib.util.spec_from_file_location('client_spanish', script)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SpanishConfigurationTest(unittest.TestCase):
    def test_only_language_changes_and_crlf_preserved(self):
        before = b'[LOGIN]\r\nLANGUAGE=4\r\nID=abc\r\n[OTHER]\r\nLANGUAGE=2\r\n'
        after, old = module.update_language_bytes(before)
        self.assertEqual(old, '4')
        self.assertEqual(after, before.replace(b'LANGUAGE=4', b'LANGUAGE=6'))

    def test_different_encodings_preserve_names(self):
        for encoding, bom in [('cp1252', b''), ('utf-8', b'\xef\xbb\xbf'), ('utf-16-le', b'\xff\xfe'), ('utf-16-be', b'\xfe\xff')]:
            text = '; José Ñúñez\n[LOGIN]\n language = 4 ; comentario\n'
            out, _ = module.update_language_bytes(bom+text.encode(encoding))
            self.assertEqual(out, bom+text.replace('= 4', '= 6').encode(encoding))

    def test_ambiguous_and_missing_settings_not_rewritten(self):
        for text in [b'[LOGIN]\nLANGUAGE=4\nLANGUAGE=4\n', b'[GENERAL]\nLANGUAGE=4\n', b'[LOGIN]\nLANGUAGE=abc\n']:
            with self.assertRaises(ValueError):
                module.update_language_bytes(text)

    def test_exact_native_version_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'game.exe').write_bytes(b'unrecognized binary')
            (root/'config.ini').write_bytes(b'[LOGIN]\nLANGUAGE=4\n')
            with self.assertRaises(ValueError):
                module.configure(root, True)
            self.assertEqual((root/'config.ini').read_bytes(), b'[LOGIN]\nLANGUAGE=4\n')

    def test_backup_and_dry_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = b'test fixture only'
            (root/'game.exe').write_bytes(binary)
            original = b'[LOGIN]\r\nLANGUAGE=4\r\nID=unused\r\n'
            (root/'config.ini').write_bytes(original)
            with patch.object(module, 'AUDITED_EXE_SHA256', hashlib.sha256(binary).hexdigest()):
                dry = module.configure(root)
                self.assertEqual(dry['mode'], 'inspect')
                self.assertEqual((root/'config.ini').read_bytes(), original)
                actual = module.configure(root, True)
                self.assertEqual(actual['mode'], 'updated')
                self.assertEqual((root/actual['backup_name']).read_bytes(), original)
                self.assertEqual((root/'game.exe').read_bytes(), binary)
                self.assertEqual(module.configure(root, True)['mode'], 'unchanged')
