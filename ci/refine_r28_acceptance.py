"""Native regression coverage and transactional wing switching for R28."""
from pathlib import Path
import subprocess
import re
ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r28-acceptance-applied'


def apply(root):
    changes = {}
    def replace(path, old, new, count=1):
        text = changes.get(path, (root / path).read_text(encoding='utf-8'))
        if text.count(old) != count:
            raise RuntimeError(f'R28 acceptance anchor: {path}: {old[:80]}')
        changes[path] = text.replace(old, new)
    path = 'lib/render/studio_scene.dart'
    marker = '  Future<void> selectCreature(CreatureRecord? c, String kind) async {'
    helper = '''  Future<void> _selectWingAtomic(CreatureRecord? record) async {
    final revision = ++_wingRevision, source = catalog;
    final bodyRevision = _appearanceRevision;
    final staged = record == null ? null : await loadCreature(record);
    if (disposed || revision != _wingRevision || bodyRevision != _appearanceRevision ||
        !identical(source, catalog)) {
      staged?.dispose();
      return;
    }
    // Capture the most recent edits, including changes made while I/O ran.
    _rememberWingSettings();
    final old = wing, oldRecord = wingRecord;
    final oldEnabled = flightEnabled, oldAuto = wingAutoMotion;
    final oldPhase = _wingMotionPhase;
    try {
      wing = staged; wingRecord = record;
      _wingMotionPhase = null;
      if (record == null) {
        flightEnabled = false;
      } else {
        wingAutoMotion = true;
        _restoreWingSettings();
        _syncWingMotion(false);
      }
      if (staged != null) {
        staged.root.matrixAutoUpdate = false;
        view!.scene.add(staged.root);
      }
      refreshIdle();
      movementTransitions.invalidate();
      game.jump.reset();
      applyLocomotion(walkX == 0 && walkZ == 0 ? GroundMotion.idle :
        (running || touchRun ? GroundMotion.run : GroundMotion.walk));
      updateAttachments();
    } catch (_) {
      wing = old; wingRecord = oldRecord;
      flightEnabled = oldEnabled; wingAutoMotion = oldAuto; _wingMotionPhase = oldPhase;
      staged?.dispose();
      if (oldRecord != null) _restoreWingSettings();
      rethrow;
    } finally {
      if (!disposed) changed();
    }
    // Cleanup/reporting cannot roll back to an already disposed old actor.
    old?.dispose();
    say(record == null ? 'Alas retiradas.' : '${source!.creatureLabel(record)} cargado.');
  }

'''
    replace(path, marker, helper + marker + '''
    if (kind == 'wing') { await _selectWingAtomic(c); return; }
    if (kind != 'enemy' && kind != 'mount') {
      throw ArgumentError.value(kind, 'kind');
    }''')
    replace(path, "    return '$identity|${characterClass.id}|${record.source}#${record.id}';",
        "    return '${identityHashCode(catalog?.library)}|$identity|${characterClass.id}|${record.source}#${record.id}';")
    path = 'lib/render/studio_gameplay.dart'
    replace(path, '''  Future<void> combatEventFor(String id, String who, String event) async {
    refreshIdle();''', '''  Future<void> combatEventFor(String id, String who, String event) async {
    if (!const {'attack', 'hit', 'death'}.contains(event)) return;
    refreshIdle();''')
    replace(path, "      final original = entry.record.sounds[key] ?? '';", '''      final soundSlot = nativeMonSoundSlot(event);
      final original = soundSlot == null ? '' : entry.record.sounds[soundSlot] ?? '';''')
    replace(path, "      final cacheKey = '${catalog!.library.location}/$path';", '''      final source = catalog!.library;
      final sourceRevision = source.revision;
      final cacheKey = '${identityHashCode(source)}|$sourceRevision|$path';''')
    replace(path, '''        final bytes = await catalog!.library.read(
              path,''', '''        final bytes = await source.read(
              path,''')
    replace(path, '''      if (disposed) return;
      if (game.players.length < 6)''', '''      if (disposed || !sound || !identical(catalog?.library, source) || source.revision != sourceRevision) return;
      if (game.players.length < 6)''')
    path = 'tool/make_native_fixture.py'
    replace(path, "('Character/Wing',['test_wing'])", "('Character/Wing',['test_wing','test_wing_b'])")
    path = 'integration_test/native_studio_test.dart'
    replace(path, "import 'package:herramienta_shaiya/render/studio_scene.dart';", "import 'package:herramienta_shaiya/render/studio_scene.dart';\nimport 'package:herramienta_shaiya/render/native_view.dart';")
    replace(path, '''    final c = scene.catalog!;
    expect(c.weapons, isNotEmpty);''', '''    final native = state.renderer as NativeView;
    Future<void> expectViewport() async {
      await waitFor(() {
        final bounds = tester.getSize(find.byKey(const ValueKey('viewport-region')));
        final expected = NativeView.validViewport(bounds);
        return native.surfaceSize.value == expected &&
            (native.camera.aspect - expected!.width / expected.height).abs() < 1e-8;
      }, 'R28 camera projection and native surface match the actual central viewport');
      expect(native.frameFailures, 0);
    }
    await expectViewport();
    for (final side in ['right', 'left']) {
      final splitter = find.byKey(ValueKey('resize-$side-dock'));
      await tester.drag(splitter, Offset(side == 'right' ? -65 : 65, 0));
      await tester.pump(); await expectViewport();
      await tester.tap(find.byKey(ValueKey('float-$side')));
      await tester.pump(); await expectViewport();
      final viewportSize = native.surfaceSize.value;
      await tester.drag(find.byKey(ValueKey('floating-resize-$side')), const Offset(85, 60));
      await tester.pump(); await expectViewport();
      expect(native.surfaceSize.value, viewportSize);
      await tester.tap(find.byKey(ValueKey('dock-$side')));
      await tester.pump(); await expectViewport();
    }
    await screenshot('r28_resized_viewport');
    final c = scene.catalog!;
    expect(c.weapons, isNotEmpty);''')
    replace(path, '''    expect(c.wings, isNotEmpty);''', '''    expect(c.wings.length, greaterThanOrEqualTo(2));
    for (var i = 0; i < 3; i++) {
      await scene.selectCreature(c.wings[0], 'wing');
      scene.wingScaleX = 1.37; scene.wingScaleY = .82; scene.wingScaleZ = 1.16;
      scene.changed(); await tester.pump();
      await scene.selectCreature(c.wings[1], 'wing');
      expect(scene.wingScaleX, 1);
      await scene.selectCreature(c.wings[0], 'wing');
      expect(scene.wingScaleX, 1.37); expect(scene.wingScaleY, .82); expect(scene.wingScaleZ, 1.16);
      final frames = native.renderedFrames;
      await waitFor(() => native.renderedFrames > frames + 2,
        'R28 native rendering remains responsive after scale edits and wing switches');
      expect(native.frameFailures, 0);
    }
    scene.resetWingPreviewOnlyTransform();
    await scene.selectCreature(null, 'wing');''')
    # Simulate a platform that supports logical < >, as in the existing flight
    # tests. Keep all event down/repeat/up pairs on that same platform.
    path = 'test/r28_inspector_input_audio_test.dart'
    text = (root / path).read_text(encoding='utf-8')
    def key_platform(match):
        args = match.group(2).rstrip().rstrip(',')
        return f"tester.sendKey{match.group(1)}Event({args}, platform: 'web')"
    text, total = re.subn(r'tester\.sendKey(Down|Up|Repeat)Event\((.*?)\)',
        key_platform, text, flags=re.S)
    if total != 11:
        raise RuntimeError(f'Expected 11 keyboard calls, found {total}')
    changes[path] = text
    path = 'test/r28_startup_presentation_test.dart'
    replace(path, '    expect(opacity(), 0);',
        '    expect(opacity(), 0);\n    await tester.pump(); // Establish the ticker timestamp before advancing it.')
    for path, text in changes.items():
        (root / path).write_text(text, encoding='utf-8')


def main():
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip() != 'fix/studio-0628-startup-spk-recovery':
        raise RuntimeError('Refusing a different branch.')
    if MARKER.exists():
        return
    apply(ROOT)
    MARKER.write_text('R28 transactional wing and native resize acceptance\n')


if __name__ == '__main__':
    main()
