import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/native_sound_events.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/resource_choices_cache.dart';
import 'package:herramienta_shaiya/input/viewport_movement_input.dart';
import 'package:herramienta_shaiya/ui/inspector_number_control.dart';
import 'package:herramienta_shaiya/render/native_view.dart';

void main() {
  test('jump and unrelated actions can never select a weapon impact sound', () {
    for (final family in [0, 1, 6, 11, 15, 99]) {
      for (final action in [
        'jump',
        'land',
        'walk',
        'fly',
        'idle',
        'death',
        '',
      ]) {
        expect(nativeWeaponSoundPrefix(family, action), isNull);
      }
    }
    expect(nativeWeaponSoundPrefix(6, 'attack'), 'ch_att_spear');
    expect(nativeWeaponSoundPrefix(6, 'hit'), 'ch_hit_spear');
    expect(nativeWeaponSoundPrefix(11, 'attack'), 'ch_att_javelin');
    expect(nativeWeaponSoundPrefix(1, 'hit'), 'ch_hit_swordone');
  });

  test(
    'victim voice and explicit MON slots do not manufacture jump/hit banks',
    () {
      expect(nativeCharacterVoice('humf', 'hit'), 'ch_hum_dam.wav');
      expect(nativeCharacterVoice('huwf', 'death'), 'ch_huw_die.wav');
      expect(nativeCharacterVoice('panda', 'hit'), isNull);
      expect(nativeCharacterVoice('humf', 'jump'), isNull);
      expect(nativeMonSoundSlot('attack', attackIndex: 1), 'Ataque 2');
      expect(nativeMonSoundSlot('death'), 'Caída');
      expect(nativeMonSoundSlot('hit'), isNull);
      expect(nativeMonSoundSlot('jump'), isNull);
    },
  );

  test(
    'inspector choices scan once per library revision, not once per field/frame',
    () {
      final lib = Library('one', false, {
        'sound/b.wav': 'b',
        'sound/a.wav': 'a',
      });
      final other = Library('two', false, {'sound/c.wav': 'c'});
      final cache = ResourceChoicesCache();
      addTearDown(lib.dispose);
      addTearDown(other.dispose);
      final first = cache.select(lib, 'sounds', (p) => p.endsWith('.wav'));
      expect(first, ['sound/a.wav', 'sound/b.wav']);
      for (var i = 0; i < 1000; i++) {
        expect(
          identical(
            cache.select(lib, 'sounds', (_) => throw StateError('rescan')),
            first,
          ),
          isTrue,
        );
      }
      expect(cache.scans, 1);
      lib.files['sound/d.wav'] = 'd';
      lib.revision++;
      expect(cache.select(lib, 'sounds', (_) => true), hasLength(3));
      expect(cache.scans, 2);
      expect(cache.select(other, 'sounds', (_) => true), ['sound/c.wav']);
      expect(cache.scans, 3);
    },
  );

  test(
    'native viewport rejects zero/nonfinite sizes and uses local integer geometry',
    () {
      expect(NativeView.validViewport(const Size(0, 600)), isNull);
      expect(
        NativeView.validViewport(const Size(double.infinity, 600)),
        isNull,
      );
      expect(
        NativeView.validViewport(const Size(734.5, 601.75)),
        const Size(734, 601),
      );
    },
  );

  testWidgets(
    'scale text survives parent frames and cannot leak to the next wing',
    (tester) async {
      var wing = 'A', value = 1.0, commits = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return SizedBox(
                  width: 280,
                  child: InspectorNumberControl(
                    key: ValueKey(wing),
                    title: 'Escala X',
                    value: value,
                    min: .05,
                    max: 5,
                    onChanged: (v) => update(() {
                      value = v;
                      commits++;
                    }),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.enterText(field, '1,25');
      final original = tester.widget<TextField>(field).controller;
      for (var i = 0; i < 30; i++) {
        update(() {});
        await tester.pump();
      }
      expect(tester.widget<TextField>(field).controller, same(original));
      expect(original!.text, '1,25');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, 1.25);
      expect(commits, 1);
      await tester.enterText(field, '2.8');
      update(() {
        wing = 'B';
        value = .75;
      });
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '0.750');
      expect(commits, 1);
      await tester.tap(field);
      await tester.enterText(field, 'NaN');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, .75);
      expect(commits, 1);
      expect(find.textContaining('Introduce un número'), findsOneWidget);
      await tester.enterText(field, '1.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(value, 1.5);
      expect(commits, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final symbol in [LogicalKeyboardKey.less, LogicalKeyboardKey.greater]) {
    testWidgets(
      'ISO $symbol toggles once, keeps W and never jumps while held',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var toggles = 0, jumps = 0;
        double z = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ViewportMovementInput(
                focusNode: focus,
                onChanged: (_, next, _) => z = next,
                onFlightToggle: () => toggles++,
                onAction: (_) => jumps++,
                child: const TextField(key: ValueKey('editor')),
              ),
            ),
          ),
        );
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, platform: 'web');
        await tester.sendKeyDownEvent(
          symbol,
          physicalKey: PhysicalKeyboardKey.intlBackslash,
          platform: 'web',
        );
        for (var i = 0; i < 4; i++) {
          await tester.sendKeyRepeatEvent(
            symbol,
            physicalKey: PhysicalKeyboardKey.intlBackslash,
            platform: 'web',
          );
        }
        expect(toggles, 1);
        expect(jumps, 0);
        expect(z, -1);
        await tester.sendKeyUpEvent(
          symbol,
          physicalKey: PhysicalKeyboardKey.intlBackslash,
          platform: 'web',
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW, platform: 'web');
        await tester.tap(find.byKey(const ValueKey('editor')));
        await tester.pump();
        await tester.sendKeyDownEvent(
          symbol,
          physicalKey: PhysicalKeyboardKey.intlBackslash,
          platform: 'web',
        );
        await tester.sendKeyUpEvent(
          symbol,
          physicalKey: PhysicalKeyboardKey.intlBackslash,
          platform: 'web',
        );
        expect(toggles, 1);
        expect(jumps, 0);
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.controlLeft,
          platform: 'web',
        );
        await tester.sendKeyDownEvent(
          symbol,
          physicalKey: PhysicalKeyboardKey.intlBackslash,
          platform: 'web',
        );
        await tester.sendKeyUpEvent(
          symbol,
          physicalKey: PhysicalKeyboardKey.intlBackslash,
          platform: 'web',
        );
        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.controlLeft,
          platform: 'web',
        );
        expect(toggles, 1);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
