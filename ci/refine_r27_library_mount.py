"""Propagate explicit resource-only mounting through all source adapters.

Default behavior stays strict for existing character-only clients. The Studio
workspace opts in; nested DATA normalization and path checks are retained.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r27-catalog-mount-applied'
FLAG = 'R27 resource-library adapters v2'


def main():
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    if branch != 'fix/studio-0627-spk-navigation-orbit-brand':
        raise RuntimeError('Refusing a different branch.')
    if not MARKER.exists():
        raise RuntimeError('Apply the catalog mount patch first.')
    if FLAG in MARKER.read_text():
        return
    changes = {}
    def replace(path, old, new, count=1):
        text = changes.get(path, (ROOT / path).read_text(encoding='utf-8'))
        if text.count(old) != count:
            raise RuntimeError(f'Expected {count} anchors in {path}: {old[:90]}')
        changes[path] = text.replace(old, new)
    path = 'lib/data/library.dart'
    replace(path, '  static Future<Library?> choose(void Function(String) progress) async {',
        '  static Future<Library?> choose(void Function(String) progress, {bool requireCharacter = true}) async {')
    replace(path, '        rows.map((k, v) => MapEntry(k.toString(), v.toString())),',
        '        rows.map((k, v) => MapEntry(k.toString(), v.toString())),\n        requireCharacter: requireCharacter,')
    replace(path, '    return fromDirectory(dir, progress);',
        '    return fromDirectory(dir, progress, requireCharacter: requireCharacter);')
    replace(path, '  static Future<Library?> chooseArchive(void Function(String) progress) async {',
        '  static Future<Library?> chooseArchive(void Function(String) progress, {bool requireCharacter = true}) async {')
    replace(path, '      }, archive: source);',
        '      }, archive: source, requireCharacter: requireCharacter);', count=2)
    replace(path, '  static Future<Library> fromArchive(String sah, String saf) async {',
        '  static Future<Library> fromArchive(String sah, String saf, {bool requireCharacter = true}) async {')
    replace(path, '''    String dir,
    void Function(String) progress,
  ) async {''', '''    String dir,
    void Function(String) progress, {
    bool requireCharacter = true,
  }) async {''')
    replace(path, '    return _normalise(root.path, false, map);',
        '    return _normalise(root.path, false, map, requireCharacter: requireCharacter);')
    replace(path, '    if (!hasCharacter && requireCharacter) {',
        "    if (!hasCharacter && (requireCharacter || map.keys.any((p) => p.contains('/character/')))) {")
    path = 'lib/main.dart'
    replace(path, 'await Library.chooseArchive(report)', 'await Library.chooseArchive(report, requireCharacter: false)')
    replace(path, 'await Library.choose(report)', 'await Library.choose(report, requireCharacter: false)')
    replace(path, 'await Library.fromDirectory(path, report)', 'await Library.fromDirectory(path, report, requireCharacter: false)')
    path = 'test/r27_catalog_mount_test.dart'
    replace(path, 'await Library.fromDirectory(root.path, (_) {});',
        'await Library.fromDirectory(root.path, (_) {}, requireCharacter: false);')
    for path, text in changes.items():
        (ROOT / path).write_text(text, encoding='utf-8')
    MARKER.write_text(MARKER.read_text() + FLAG + '\n')


if __name__ == '__main__':
    main()
