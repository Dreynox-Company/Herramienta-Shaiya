"""Integrate reviewed R28 repairs. Check every anchor before any source write."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r28-repairs-applied'


def apply(root):
    changes = {}
    def replace(path, old, new, count=1):
        text = changes.get(path, (root / path).read_text(encoding='utf-8'))
        if text.count(old) != count:
            raise RuntimeError(f'Expected {count} anchors in {path}: {old[:100]}')
        changes[path] = text.replace(old, new)
    def section(path, begin, end, new):
        text = changes.get(path, (root / path).read_text(encoding='utf-8'))
        if text.count(begin) != 1 or text.count(end) != 1:
            raise RuntimeError(f'Ambiguous section in {path}: {begin}')
        start = text.index(begin)
        stop = text.index(end, start)
        changes[path] = text[:start] + new + text[stop:]

    path = 'lib/main.dart'
    replace(path, "import 'ui/studio_brand.dart';", "import 'ui/startup_presentation.dart';\nimport 'ui/inspector_number_control.dart';")
    replace(path, "const studioVersion = '0.6.27';", "const studioVersion = '0.6.28';")
    replace('pubspec.yaml', 'version: 0.6.27+35', 'version: 0.6.28+36')
    section(path, '  Widget preciseSlider(', '  Widget toggle(', '''  Widget preciseSlider(
    String title, double value, double min, double max,
    ValueChanged<double> change, {double step = .01, int decimals = 3}) =>
      InspectorNumberControl(
        key: ValueKey((title, scene.appearance?.archetype.id,
          scene.wingRecord?.source, scene.wingRecord?.id,
          scene.mountRecord?.source, scene.mountRecord?.id)),
        title: title, value: value, min: min, max: max,
        step: step, decimals: decimals, enabled: !disabled, onChanged: change,
      );

''')
    replace(path, '''        viewport: IndexedStack(
          index: resourceMode ? 1 : 0,
          children: [
            Stack(
              children: [
                Positioned.fill(child: viewport()),
                if (catalog == null && !importing)
                  const Center(child: StudioBrand(full: true, size: 430)),
              ],
            ),''', '''        viewport: StudioStartupPresentation(
          enabled: catalog == null && !importing,
          child: IndexedStack(
          index: resourceMode ? 1 : 0,
          children: [
            viewport(),''')
    replace(path, '''        leftOwnsScroll: resourceMode,''', '''        ),
        leftOwnsScroll: resourceMode,''')

    path = 'lib/input/viewport_movement_input.dart'
    replace(path, '''    // Flight follows the requested Shaiya Studio contract:''', '''    // ISO Spanish < > shares one physical key. Logical symbols also work on
    // other layouts, but an unshifted comma/period is not a flight shortcut.
    final angleKey = event.physicalKey == PhysicalKeyboardKey.intlBackslash ||
        event.logicalKey == LogicalKeyboardKey.less ||
        event.logicalKey == LogicalKeyboardKey.greater;
    if (angleKey) {
      final keyboard = HardwareKeyboard.instance;
      if (!_active || event.synthesized || keyboard.isControlPressed ||
          keyboard.isAltPressed || keyboard.isMetaPressed) return KeyEventResult.ignored;
      if (event is KeyDownEvent) widget.onFlightToggle?.call();
      return KeyEventResult.handled;
    }
    // Flight follows the requested Shaiya Studio contract:''')

    path = 'lib/ui/asset_selector.dart'
    section(path, '  Future<void> _drain() async {', '  Future<void> _open() async {', '''  Future<void> _drain() async {
    if (_loading || !mounted || _desired == null) return;
    setState(() => _loading = true);
    try {
      while (mounted && _desired != null) {
        final next = _desired as T, version = _generation;
        try {
          await widget.onChanged(next);
          if (mounted && version == _generation) widget.memory.cursor = widget.id(next);
        } catch (error, stack) {
          if (mounted) {
            if (version == _generation) setState(() => _error = error.toString());
            try {
              widget.onError?.call(error);
            } catch (reportError) {
              FlutterError.reportError(FlutterErrorDetails(exception: reportError,
                stack: stack, library: 'ShStudio asset selection'));
            }
          }
        }
        if (!mounted) return;
        if (version == _generation) {
          setState(() => _desired = null);
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

''')

    path = 'lib/render/studio_scene.dart'
    replace(path, "import '../data/library.dart';", "import '../data/library.dart';\nimport '../data/resource_choices_cache.dart';\nimport '../core/native_sound_events.dart';")
    replace(path, '  List<String> get wingMonSoundSlots => monSoundSlots;', '  final _inspectorResources = ResourceChoicesCache();\n\n  List<String> get wingMonSoundSlots => monSoundSlots;')
    section(path, '  List<String> get wingMonSoundCandidates {', '  String? wingMonSound(String slot)', '''  List<String> get wingMonSoundCandidates => catalog == null ? const [] :
      _inspectorResources.select(catalog!.library, 'sound',
        (p) => p.endsWith('.wav') || p.endsWith('.ogg'));

  List<String> get wingMonEffectCandidates => catalog == null ? const [] :
      _inspectorResources.select(catalog!.library, 'effect',
        (p) => p.endsWith('.eft') || p.endsWith('.3de'));

  List<String> get wingMonMeshCandidates => catalog == null ? const [] :
      _inspectorResources.select(catalog!.library, 'wing-mesh',
        (p) => p.startsWith('character/wing/') &&
          (p.endsWith('.3dc') || p.endsWith('.3do')));

  List<String> get wingMonTextureCandidates => catalog == null ? const [] :
      _inspectorResources.select(catalog!.library, 'wing-texture',
        (p) => p.startsWith('character/wing/') &&
          (p.endsWith('.dds') || p.endsWith('.tga') || p.endsWith('.png') || p.endsWith('.bmp')));

''')
    replace(path, '    return c.wingAnimationCandidates(record);', '''    final prefix = '${directoryName(record.source)}/ani/';
    return _inspectorResources.select(c.library, 'ani:$prefix',
      (p) => p.startsWith(prefix) && p.endsWith('.ani'));''')
    replace(path, '''    final out =
        c.library.files.keys
            .where((path) => path.startsWith(prefix) && path.endsWith('.ani'))
            .toList()
          ..sort();
    return out;''', '''    return _inspectorResources.select(c.library, 'ani:$prefix',
      (p) => p.startsWith(prefix) && p.endsWith('.ani'));''')
    replace(path, '''  void clearAppearance() {
    ++_appearanceRevision;''', '''  void clearAppearance() {
    ++_mountRevision;
    ++_wingRevision;
    mount?.dispose(); wing?.dispose();
    mount = null; wing = null;
    mountRecord = null; wingRecord = null;
    flightEnabled = false;
    _inspectorResources.clear();
    ++_appearanceRevision;''')
    replace(path, '        final part = await skinned(m, tex);', '''        final mesh = MeshData.skinned(await lib.read(m), m);
        final part = await makePartFromLibrary(lib, mesh, tex);''')
    begin = changes[path].index('  Future<Actor> loadCreature(')
    end = changes[path].index('  List<int> get riderProfileOptions', begin)
    block = changes[path][begin:end]
    old = '          final animation = await clip(p);'
    if block.count(old) != 1: raise RuntimeError('Missing creature clip load')
    block = block.replace(old, '          final animation = await ClipData.parse(await lib.read(p), p);')
    changes[path] = changes[path][:begin] + block + changes[path][end:]
    replace(path, '''    final staged = c == null ? null : await loadCreature(c);
    final current''', '''    final source = catalog;
    final staged = c == null ? null : await loadCreature(c);
    final current''')
    replace(path, '''    if (disposed || revision != current) {
      staged?.dispose();''', '''    if (disposed || revision != current || !identical(source, catalog)) {
      staged?.dispose();''')

    path = 'lib/render/studio_gameplay.dart'
    replace(path, "      unawaited(weaponSound('jump'));", '''      // Jump has no generic ps0032 weapon sound. Do not substitute a hit.
      // Tyros-specific jump WAVs are not valid for an arbitrary character.''')
    section(path, '  Future<void> weaponSound(String action) async {', '  Future<void> pooledSound(', '''  Future<void> weaponSound(String action) async {
    final c = catalog;
    if (!sound || c == null) return;
    final prefix = nativeWeaponSoundPrefix(weaponFamily(weaponRecord), action);
    if (prefix == null) return;
    final available = c.sounds.where((p) => baseName(p).toLowerCase().startsWith(prefix)).toList();
    if (available.isNotEmpty) {
      await playSound(available[attackCounter % available.length]);
    } else {
      final fallback = c.library.resolve(
        action == 'attack' ? 'ch_att_weaponone001.wav' : 'mob_hit001.wav', ['sound']);
      if (fallback != null) await playSound(fallback);
    }
  }

  Future<void> characterVoice(String event) async {
    final c = catalog, actor = character;
    final id = appearance?.archetype.id;
    if (!sound || c == null || actor == null || id == null) return;
    final name = nativeCharacterVoice(id, event);
    if (name == null) return;
    final path = c.library.resolve(name, ['sound']);
    if (path != null && identical(catalog, c) && identical(character, actor)) {
      await playSound(path);
    }
  }

''')
    replace(path, "      if (event == 'hit') unawaited(weaponSound('hit'));", "      if (event == 'hit' || event == 'death') unawaited(characterVoice(event));")
    for path, text in changes.items():
        (root / path).write_text(text, encoding='utf-8')


def main():
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip() != 'fix/studio-0628-startup-spk-recovery':
        raise RuntimeError('Refusing to modify a different branch.')
    if MARKER.exists(): return
    apply(ROOT)
    MARKER.write_text('R28 integrated repairs; no SPK authentication gates bypassed\n')

if __name__ == '__main__': main()
