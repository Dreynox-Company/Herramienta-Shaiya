"""Integrate per-resource authenticated editing without loosening repack gates."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r26-readable-applied'


def main():
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip() != 'feat/studio-0626-compact-model-picker':
        raise RuntimeError('Refusing to mutate another branch.')
    if not MARKER.exists():
        path = ROOT / 'lib/ui/spk_archive_browser.dart'
        text = path.read_text(encoding='utf-8')
        a = text.index('    if (!source.fullyValidatedResources)', text.index('  String _editableLibraryPath('))
        b = text.index("    final format = source.validatedFormat", a)
        text = text[:a] + """    if (!source.canReadRecord(record) || source.validatedFormat(record.entryId) == null) {
      throw const SpkFailure('SPK_EDIT_RESOURCE_REQUIRED',
        'Lee y autentica este Entry ID antes de abrirlo en el editor.');
    }
""" + text[b:]
        a = text.index('    if (!source.canExtractAll)', text.index('  Future<void> openRecordInEditor('))
        b = text.index('    final path = _editableLibraryPath(record);', a)
        text = text[:a] + """    if (!source.canReadRecord(record)) {
      throw const SpkFailure('SPK_EDITOR_PROFILE',
        'Este recurso no está desbloqueado. No se omite su autenticación.');
    }
    await source.readEntry(record);
""" + text[b:]
        a = text.index('    if (!source.canExtractAll)', text.index('  Future<void> replaceRecordInOverlay('))
        b = text.index('    final path = _editableLibraryPath(record);', a)
        text = text[:a] + """    if (!source.canReadRecord(record)) {
      throw const SpkFailure('SPK_OVERLAY_PROFILE', 'Este recurso no está desbloqueado.');
    }
    await source.readEntry(record);

""" + text[b:]
        # Only these two selected-resource methods switch to the selective mount.
        # Core-table autodiscovery and repack retain their existing full audit.
        a = text.index('  Future<void> openRecordInEditor(')
        b = text.index('  Future<Uint8List?> _matchingTexturePng(', a)
        region = text[a:b].replace('Library.fromSpk(', 'Library.fromSpkEditable(')
        region = region.replace('      requireCharacter: false,\n', '')
        text = text[:a] + region + text[b:]
        text = text.replace('if (source.canReadRecord(record) && source.canExtractAll) ...[',
            'if (source.canReadRecord(record)) ...[')
        a = text.index('  Future<void> inspectResource(')
        b = text.index('  Widget folderTree()', a)
        region = text[a:b].replace('if (source.canExtractAll)', 'if (source.canReadRecord(record))')
        text = text[:a] + region + text[b:]
        path.write_text(text, encoding='utf-8')

        # Changing the model is inapplicable to icon-only consumables. They keep
        # all their actual SData fields, but no unrelated geometry chooser.
        path = ROOT / 'lib/ui/items_page.dart'
        text = path.read_text(encoding='utf-8')
        text = text.replace("import '../editor/model_reference.dart';", "import '../editor/model_reference.dart';\nimport '../editor/item_model_catalog.dart';")
        anchor = "          OutlinedButton.icon(\n            key: const ValueKey('change-selected-item-model'),"
        if anchor not in text:
            raise RuntimeError('Missing model command after R26 integration.')
        text = text.replace(anchor, "          if (ItemModelCatalog.supports(item.type)) OutlinedButton.icon(\n            key: const ValueKey('change-selected-item-model'),")
        path.write_text(text, encoding='utf-8')
        MARKER.write_text('Per-resource editing remains authenticated; full repack unchanged\n')

    # Generate the complete runner deterministically, including every suite.
    suites = sorted((ROOT / 'test').glob('*_test.dart'))
    imports = [f"import '../test/{p.name}' as suite{i};" for i, p in enumerate(suites)]
    calls = [f'  suite{i}.main();' for i in range(len(suites))]
    (ROOT / 'tool/run_all_local.dart').write_text(
        '// Complete regression runner: all top-level test suites.\n' +
        '\n'.join(imports) + '\n\nvoid main() {\n' + '\n'.join(calls) + '\n}\n',
        encoding='utf-8')


if __name__ == '__main__':
    main()
