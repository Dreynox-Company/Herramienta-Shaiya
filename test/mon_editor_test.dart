import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/mon_editor.dart';

void addU32(BytesBuilder out, int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  out.add(data.buffer.asUint8List());
}

void addString(BytesBuilder out, String value) {
  final bytes = ascii.encode(value);
  addU32(out, bytes.length);
  out.add(bytes);
}

Uint8List fixture(String signature) {
  final out = BytesBuilder(copy: false)..add(ascii.encode(signature));
  addU32(out, 1);
  addString(out, 'Wing 01');
  out.addByte(7);
  for (var i = 0; i < monAnimationSlots.length; i++) {
    addString(out, 'wing_anim_$i.ani');
  }
  for (var i = 0; i < monSoundSlots.length; i++) {
    addString(out, 'wing_sound_$i.wav');
  }
  for (var i = 0; i < monEffectSlots.length; i++) {
    addString(out, 'wing_effect_$i.eft');
  }
  if (signature == 'MO4') addString(out, 'wing_attach');
  addU32(out, 1);
  addString(out, 'wing_mesh.3DC');
  addString(out, 'wing_texture.DDS');
  final height = ByteData(4)..setFloat32(0, 1.25, Endian.little);
  out.add(height.buffer.asUint8List());
  addU32(out, 2);
  out.add(List<int>.generate(16, (i) => i + 1));
  return out.takeBytes();
}

void main() {
  for (final signature in ['MO2', 'MO4']) {
    test('$signature unchanged MON round-trips byte-for-byte', () {
      final original = fixture(signature);
      final doc = EditableMonDocument.parse(
        original,
        'Character/Wing/Wing.MON',
      );
      expect(doc.signature, signature);
      expect(doc.records, hasLength(1));
      expect(
        doc.records.single.animations['Respirar']!.value,
        'wing_anim_6.ani',
      );
      expect(doc.encode(), orderedEquals(original));
    });

    test('$signature edits one ANI slot and preserves opaque tail', () {
      final original = fixture(signature);
      final doc = EditableMonDocument.parse(
        original,
        'Character/Wing/Wing.MON',
      );
      final beforeTail = Uint8List.fromList(doc.records.single.tailRaw);
      doc.setAnimation(0, 'Ataque 2', 'custom_attack.ani');
      final encoded = doc.encode();
      doc.validateEncoded(encoded);

      final reparsed = EditableMonDocument.parse(
        encoded,
        'Character/Wing/Wing.MON',
      );
      expect(
        reparsed.records.single.animations['Ataque 2']!.value,
        'custom_attack.ani',
      );
      expect(
        reparsed.records.single.animations['Ataque 1']!.value,
        'wing_anim_2.ani',
      );
      expect(reparsed.records.single.tailRaw, orderedEquals(beforeTail));
      expect(reparsed.records.single.tailCount, 2);
    });
  }

  test('MO4 edits sound effect attached and model resources losslessly', () {
    final original = fixture('MO4');
    final doc = EditableMonDocument.parse(original, 'Character/Wing/Wing.MON');
    final beforeTail = Uint8List.fromList(doc.records.single.tailRaw);

    doc.setSound(0, 'Ataque 1', 'custom_attack.wav');
    doc.setEffect(0, 'Ataque 2', 'custom_hit.eft');
    doc.setAttachedEffect(0, 'wing_aura.3de');
    doc.setPart(0, 0, mesh: 'wing_new.3DC', texture: 'wing_new.DDS');

    final encoded = doc.encode();
    doc.validateEncoded(encoded);
    final reparsed = EditableMonDocument.parse(
      encoded,
      'Character/Wing/Wing.MON',
    );
    expect(
      reparsed.records.single.sounds['Ataque 1']!.value,
      'custom_attack.wav',
    );
    expect(
      reparsed.records.single.effects['Ataque 2']!.value,
      'custom_hit.eft',
    );
    expect(reparsed.records.single.attached!.value, 'wing_aura.3de');
    expect(reparsed.records.single.parts.single.mesh.value, 'wing_new.3DC');
    expect(reparsed.records.single.parts.single.texture.value, 'wing_new.DDS');
    expect(reparsed.records.single.tailRaw, orderedEquals(beforeTail));
  });

  test('MON editor can clear optional sound/effect fields but not ANI', () {
    final doc = EditableMonDocument.parse(
      fixture('MO4'),
      'Character/Wing/Wing.MON',
    );
    doc.setSound(0, 'Ataque 1', '');
    doc.setEffect(0, 'Ataque 1', '');
    doc.setAttachedEffect(0, '');
    final encoded = doc.encode();
    doc.validateEncoded(encoded);
    final parsed = EditableMonDocument.parse(
      encoded,
      'Character/Wing/Wing.MON',
    );
    expect(parsed.records.single.sounds['Ataque 1']!.value, isEmpty);
    expect(parsed.records.single.effects['Ataque 1']!.value, isEmpty);
    expect(parsed.records.single.attached!.value, isEmpty);
    expect(() => doc.setAnimation(0, 'Ataque 1', ''), throwsFormatException);
  });

  test('MON native LOAD sentinel round-trips across resource slots', () {
    final doc = EditableMonDocument.parse(
      fixture('MO4'),
      'Vehicle/Vehicle_Hu_01.MON',
    );
    doc.setAnimation(0, 'Ataque 2', 'load');
    doc.setSound(0, 'Ataque 1', 'LOAD');
    doc.setEffect(0, 'Ataque 3', 'Load');
    doc.setAttachedEffect(0, 'load');

    final encoded = doc.encode();
    doc.validateEncoded(encoded);
    final parsed = EditableMonDocument.parse(
      encoded,
      'Vehicle/Vehicle_Hu_01.MON',
    );
    expect(parsed.records.single.animations['Ataque 2']!.value, monLoadSentinel);
    expect(parsed.records.single.sounds['Ataque 1']!.value, monLoadSentinel);
    expect(parsed.records.single.effects['Ataque 3']!.value, monLoadSentinel);
    expect(parsed.records.single.attached!.value, monLoadSentinel);
    expect(isMonLoadSentinel(' load '), isTrue);
    expect(isMonLoadSentinel('custom.ani'), isFalse);
  });

  test('MON editor rejects unsafe or non-ANI replacement paths', () {
    final doc = EditableMonDocument.parse(
      fixture('MO4'),
      'Character/Wing/Wing.MON',
    );
    expect(
      () => doc.setAnimation(0, 'Ataque 1', '../outside.ani'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => doc.setAnimation(0, 'Ataque 1', 'sound.wav'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => doc.setAnimation(0, 'No existe', 'ok.ani'),
      throwsA(isA<FormatException>()),
    );
  });
}
