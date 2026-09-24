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
