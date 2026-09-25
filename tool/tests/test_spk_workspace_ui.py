from pathlib import Path
import re
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
        self.assertIn("PAYLOAD NO LEÍDO", browser)
        self.assertIn("Desbloquear con AutoPerfil SPK", browser)
        self.assertIn("rutas aún no confirmadas por contenido", browser)
        self.assertIn("SPK_TEXT_ENCODING_INVALID", browser)
        self.assertIn("RUTA INFERIDA", browser)
        self.assertIn("Ruta inferida", browser)
        self.assertIn(": captureResourceProfile", browser)
        self.assertIn("build-provenance.json", browser)
        self.assertIn("'studioBuild': studioBuild", browser)
        self.assertIn("'schema': 3", browser)
        self.assertIn("studioBuildLabel", browser)
        self.assertIn("_loadStudioBuildLabel", browser)
        self.assertIn("visor HEX + ASCII", browser)
        self.assertIn("CADENAS DETECTADAS", browser)
        self.assertIn("Reemplazar en overlay", browser)
        self.assertIn("writeSpkOverlay", browser)
        self.assertIn("SPK_REPLACEMENT_FORMAT", browser)

    def test_name_resolution_stays_one_to_one(self):
        source = (ROOT / 'lib' / 'data' / 'spk_source.dart').read_text(
            encoding='utf-8'
        )
        archive = (ROOT / 'lib' / 'core' / 'spk_archive.dart').read_text(
            encoding='utf-8'
        )
        self.assertIn("decoded-sha256-one-to-one-reference", source)
        self.assertIn("ambiguousRecords", source)
        self.assertIn("names.removeAmbiguousHints()", source)
        self.assertIn("decoded-sha256-one-to-one-reference", source)
        self.assertIn("confirmedPaths.contains(key)", archive)
        self.assertIn("External/legacy maps may contain", source)

    def test_spk_editor_exposes_verified_repack(self):
        editor = (ROOT / 'lib' / 'ui' / 'data_editor.dart').read_text(
            encoding='utf-8'
        )
        self.assertIn("Construir SPK", editor)
        self.assertIn("Construir nuevo DATA.SPK verificado", editor)
        self.assertIn("_rebuildSpkWorkspace", editor)

    def test_table_only_mode_is_explicit_and_default_stays_strict(self):
        library = (ROOT / 'lib' / 'data' / 'library.dart').read_text(encoding='utf-8')
        normalise = library.split('  static Library _normalise(', 1)[1].split('  String? resolve(', 1)[0]
        compact = re.sub(r'\s+', '', normalise)
        self.assertIn('boolrequireCharacter=true', compact)
        # Resource mode must still normalize nested roots, not skip validation.
        # The behavior (strict default, explicit opt-in, nested and ambiguous
        # roots, relative-path safety) is executed by r27_library_policy_test.dart.
        self.assertIn("if(!hasCharacter&&(requireCharacter||map.keys.any((p)=>p.contains('/character/'))))", compact)
        self.assertIn('if(nested.isEmpty){throwconstFormatException(', compact)
        self.assertIn('if(prefixes.length!=1){throwconstFormatException(', compact)
        main = (ROOT / 'lib' / 'main.dart').read_text(encoding='utf-8')
        self.assertIn('requireCharacter: false', main)
        self.assertIn('requireArchetypes: false', main)
        runner = (ROOT / 'tool' / 'run_all_local.dart').read_text(encoding='utf-8')
        self.assertIn('../test/r27_library_policy_test.dart', runner)


if __name__ == '__main__':
    unittest.main()
