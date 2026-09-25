"""Correct test assumptions without relaxing production validation.

MLT has mesh rows, texture rows and material rows. Two edits must leave a
version different from the original to test rejection of its stale hash.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r27-material-tests-applied'


def main():
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip() != 'fix/studio-0627-spk-navigation-orbit-brand':
        raise RuntimeError('Refusing a different branch.')
    if MARKER.exists():
        return
    changes = {}
    def replace(path, old, new):
        text = changes.get(path, (ROOT / path).read_text(encoding='utf-8'))
        if text.count(old) != 1:
            raise RuntimeError(f'Expected one test anchor in {path}: {old[:80]}')
        changes[path] = text.replace(old, new, 1)
    path = 'test/r27_resource_workspace_test.dart'
    replace(path, '''      expect(doc.rows, hasLength(2));
      final encoded = doc.exportBytes();
      expect(
        CatalogDocument.open(
          encoded,
          path,
          GameTextEncoding.automatic,
        ).materials(0),
        (doc as CatalogDocument).materials(0),
      );''', '''      // Two mesh definitions + two textures + two actual material records.
      expect(doc.rows, hasLength(6));
      final catalog = doc as CatalogDocument;
      final materials = List.generate(doc.rows.length, (i) => i)
          .where((i) => catalog.materials(i).isNotEmpty).toList();
      expect(materials, hasLength(2));
      expect(catalog.materials(materials.first), [('upper015.3dc', 'upper016.dds', 0)]);
      expect(catalog.materials(materials.last), [('upper016.3dc', 'upper015.dds', 1)]);
      final encoded = doc.exportBytes();
      final restored = CatalogDocument.open(encoded, path, GameTextEncoding.automatic);
      for (final row in materials) {
        expect(restored.materials(row), catalog.materials(row));
      }
      expect(encoded, modelMlt());''')
    replace(path, '''      ByteData.sublistView(
        second,
      ).setUint32(second.length - 4, 1, Endian.little);''', '''      // Second edit changes the texture reference to another valid entry.
      // Do not restore the original payload here: its hash would not be stale.
      ByteData.sublistView(second).setUint32(second.length - 8, 1, Endian.little);
      expect(FileSave.hash(second), isNot(read.hash));
      expect(FileSave.hash(second), isNot(FileSave.hash(first)));''')
    path = 'integration_test/native_studio_test.dart'
    replace(path, '''      final numeric = doc
          .fields(0)
          .where((f) => f.spec.name.toLowerCase().contains('alpha'))
          .first;
      final initial = doc.read(numeric);
      doc.edit(0, numeric, initial == '0' ? '1' : '0');''', '''      final materialRow = List.generate(doc.rows.length, (i) => i).firstWhere(
        (row) => doc.fields(row).any((f) => f.spec.name == 'Alpha'));
      final numeric = doc.fields(materialRow).firstWhere((f) => f.spec.name == 'Alpha');
      final initial = doc.read(numeric);
      doc.edit(materialRow, numeric, initial == '0' ? '1' : '0');''')
    replace(path, '''      doc2.edit(
        0,
        doc2.fields(0).firstWhere((f) => f.spec.name == numeric.spec.name),
        initial,
      );''', '''      doc2.edit(
        materialRow,
        doc2.fields(materialRow).firstWhere((f) => f.spec.name == numeric.spec.name),
        initial,
      );''')
    for path, text in changes.items():
        (ROOT / path).write_text(text, encoding='utf-8')
    MARKER.write_text('R27 material row identity and distinct overlay versions verified in tests\n')


if __name__ == '__main__':
    main()
