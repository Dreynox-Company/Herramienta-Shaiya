from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SpkWorkspaceUiContractTest(unittest.TestCase):
    def test_unlocked_spk_exposes_real_data_workspaces(self):
        browser = (ROOT / 'lib' / 'ui' / 'spk_archive_browser.dart').read_text(
            encoding='utf-8'
        )
        self.assertIn("BinarySData/DBItemData.SData", browser)
        self.assertIn("BinarySData/DBMonsterData.SData", browser)
        self.assertIn("BinarySData/DBSkillData.SData", browser)
        self.assertIn("Objetos / trade", browser)
        self.assertIn("Mobs / drops", browser)
        self.assertIn("Abrir Studio 3D", browser)
        self.assertIn("requireCharacter: false", browser)

    def test_spk_editor_exposes_verified_repack(self):
        editor = (ROOT / 'lib' / 'ui' / 'data_editor.dart').read_text(
            encoding='utf-8'
        )
        self.assertIn("Construir SPK", editor)
        self.assertIn("Construir nuevo DATA.SPK verificado", editor)
        self.assertIn("_rebuildSpkWorkspace", editor)

    def test_table_only_mode_is_explicit_and_default_stays_strict(self):
        library = (ROOT / 'lib' / 'data' / 'library.dart').read_text(
            encoding='utf-8'
        )
        self.assertIn("bool requireCharacter = true", library)
        self.assertIn("if (!hasCharacter && requireCharacter)", library)


if __name__ == '__main__':
    unittest.main()
