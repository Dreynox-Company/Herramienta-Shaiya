"""Make resource workspaces independent of playable character catalogs.

Keep strict validation for character-only consumers. Apply reviewed anchors
before writing; never infer SPK paths or relax payload authentication.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r27-catalog-mount-applied'


def apply(root: Path):
    changes = {}
    def replace(path, old, new, count=1):
        text = changes.get(path, (root / path).read_text(encoding='utf-8'))
        if text.count(old) != count:
            raise RuntimeError(f'Expected {count} anchors in {path}: {old[:90]}')
        changes[path] = text.replace(old, new)
    replace('lib/data/catalog.dart',
        '  Future<void> load(void Function(String) progress) async {',
        '''  Future<void> load(
    void Function(String) progress, {
    bool requireArchetypes = true,
  }) async {''')
    replace('lib/data/catalog.dart',
        '''    if (archetypes.isEmpty) {
      throw const FormatException(
        'No se encontraron arquetipos MLT utilizables. Revisa el diagnóstico.',
      );
    }''',
        '''    if (archetypes.isEmpty) {
      const message = 'No se encontraron arquetipos MLT utilizables. Revisa el diagnóstico.';
      if (requireArchetypes) throw const FormatException(message);
      warnings.add('$message La biblioteca de recursos permanece disponible.');
    }''')
    replace('lib/main.dart', "const studioVersion = '0.6.26';", "const studioVersion = '0.6.27';")
    replace('lib/main.dart', '      await next.load(report);',
        '      await next.load(report, requireArchetypes: false);', count=2)
    replace('lib/main.dart', '''      await refreshed.load((s) {
        if (mounted) setState(() => progress = s);
      });''', '''      await refreshed.load((s) {
        if (mounted) setState(() => progress = s);
      }, requireArchetypes: false);''')
    replace('lib/main.dart', '''        await scene.setAppearance(
          Appearance(archetype, slots, preset: look.preset),
        );
      }
      scene.say(''', '''        await scene.setAppearance(
          Appearance(archetype, slots, preset: look.preset),
        );
      } else {
        scene.clearAppearance();
        tab = 6;
      }
      scene.say(''')
    replace('lib/main.dart', '''      await loadBundledExtras();
      final next = Catalog(candidate);''', '''      await loadBundledExtras();
      await loadBundledFlightV3();
      final next = Catalog(candidate);''')
    replace('lib/main.dart', '''      if (!mounted) return;
      scene.catalog = next;
      final first =
          next.archetypes.where((a) => a.id == 'humf').firstOrNull ??
          next.archetypes.first;
      await scene.setAppearance(Appearance.initial(first));''', '''      if (!mounted) {
        candidate.dispose();
        return;
      }
      scene.catalog = next;
      final first = next.archetypes.where((a) => a.id == 'humf').firstOrNull ??
          next.archetypes.firstOrNull;
      if (first != null) {
        await scene.setAppearance(Appearance.initial(first));
      } else {
        scene.clearAppearance();
        tab = 6;
      }''')
    replace('lib/main.dart', '''      await next.load(report, requireArchetypes: false);
      if (!mounted) return;

      scene.catalog = next;''', '''      await next.load(report, requireArchetypes: false);
      if (!mounted) {
        candidate.dispose();
        return;
      }

      scene.catalog = next;''')
    replace('lib/main.dart', '''      progress = next.archetypes.isEmpty
          ? '${candidate.files.length} recursos SPK montados · editor listo · '
                '3D pendiente de más rutas Character · overlay editable: '
                '${candidate.spkOverlayRoot}'
          : '${candidate.files.length} recursos SPK montados · editor + 3D · '
                'overlay editable: ${candidate.spkOverlayRoot}';''', '''      progress = '${source.index.resources.length} registros SPK indexados · '
          '${candidate.files.length} accesibles según perfil · '
          'selecciona un recurso para verificar y editar · '
          'overlay: ${candidate.spkOverlayRoot}';''')
    for path, text in changes.items():
        (root / path).write_text(text, encoding='utf-8')


def main():
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    if branch != 'fix/studio-0627-spk-navigation-orbit-brand':
        raise RuntimeError('Refusing to modify a different branch.')
    if MARKER.exists():
        return
    apply(ROOT)
    MARKER.write_text('R27 resources load without Character; character consumers stay strict\n')


if __name__ == '__main__':
    main()
