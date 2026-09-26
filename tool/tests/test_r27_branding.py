import pathlib
import tempfile
import unittest
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from prepare_branding import prepare
ROOT = pathlib.Path(__file__).resolve().parents[2]

class BrandingTests(unittest.TestCase):
    def test_original_icon_frames_are_verified_and_asset_reproduced(self):
        with tempfile.TemporaryDirectory() as td:
            root=pathlib.Path(td); source=root/'platform/branding/app_icon.ico.b64'
            source.parent.mkdir(parents=True)
            source.write_bytes((ROOT/'platform/branding/app_icon.ico.b64').read_bytes())
            ico=prepare(root)
            self.assertEqual(len(ico),44698)
            self.assertTrue((root/'assets/branding/shstudio-emblem.png').read_bytes().startswith(b'\x89PNG'))
            first=(root/'assets/branding/shstudio-emblem.png').read_bytes()
            prepare(root)
            self.assertEqual((root/'assets/branding/shstudio-emblem.png').read_bytes(),first)

    def test_bad_artwork_is_not_silently_substituted(self):
        with tempfile.TemporaryDirectory() as td:
            root=pathlib.Path(td); source=root/'platform/branding/app_icon.ico.b64'
            source.parent.mkdir(parents=True); source.write_text('QUJD')
            with self.assertRaises(ValueError): prepare(root)
            self.assertFalse((root/'assets/branding/shstudio-emblem.png').exists())

if __name__=='__main__': unittest.main()
