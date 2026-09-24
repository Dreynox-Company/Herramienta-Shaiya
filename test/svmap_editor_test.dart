import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/svmap_editor.dart';

class _Writer {
  final BytesBuilder out = BytesBuilder(copy: false);

  void i32(int value) {
    final b = ByteData(4)..setInt32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void u32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void u16(int value) {
    final b = ByteData(2)..setUint16(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void f32(double value) {
    final b = ByteData(4)..setFloat32(0, value, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void vec(double x, double y, double z) {
    f32(x);
    f32(y);
    f32(z);
  }

  Uint8List done() => out.takeBytes();
}

Uint8List fixture() {
  final w = _Writer();
  w.i32(8);
  w.out.add(List<int>.generate(8, (i) => 0xa0 + i));
  w.i32(128);

  w.u32(1);
  w.out.add(List<int>.generate(12, (i) => 0xb0 + i));

  w.u32(1);
  w.vec(1, 2, 3);
  w.vec(10, 20, 30);
  w.u32(2);
  w.u32(1001);
  w.u32(4);
  w.u32(1002);
  w.u32(8);

  w.u32(1);
  w.i32(3);
  w.i32(2001);
  w.u32(2);
  w.vec(2, 3, 4);
  w.f32(45);
  w.vec(5, 6, 7);
  w.f32(90);

  w.u32(1);
  w.vec(100, 5, 200);
  w.i32(2);
  w.u16(10);
  w.u16(60);
  w.u32(7);
  w.vec(300, 8, 400);

  w.u32(1);
  w.i32(0x11223344);
  w.i32(1);
  w.i32(0x55667788);
  w.vec(11, 12, 13);
  w.vec(21, 22, 23);

  w.u32(1);
  w.vec(31, 32, 33);
  w.vec(41, 42, 43);
  w.i32(5001);
  w.i32(5002);

  w.out.add(const [0xde, 0xad, 0xbe, 0xef]);
  return w.done();
}

bool containsBytes(Uint8List data, List<int> needle) {
  if (needle.isEmpty || needle.length > data.length) return false;
  for (var i = 0; i <= data.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (data[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  test('SVMAP fixed-width edits preserve unknown bytes and topology', () {
    final original = fixture();
    final doc = SvmapEditorDocument.parse(original, 'world/test.svmap');

    expect(doc.mapSize, 8);
    expect(doc.cellSize, 128);
    expect(doc.ladderCount, 1);
    expect(doc.mobAreas, hasLength(1));
    expect(doc.mobAreas.single.mobs, hasLength(2));
    expect(doc.npcs.single.route, hasLength(2));
    expect(doc.portals, hasLength(1));
    expect(doc.spawns, hasLength(1));
    expect(doc.namedAreas, hasLength(1));
    expect(doc.tailBytes, 4);

    doc.setMobSpawn(0, 1, id: 9002, count: 12);
    doc.setNpcIdentity(0, type: 5, id: 777);
    doc.setNpcWaypoint(0, 1, position: const [6, 7, 8], yaw: 135);
    doc.setPortal(
      0,
      position: const [101, 6, 201],
      factionOrId: 4,
      minLevel: 20,
      maxLevel: 70,
      targetMap: 9,
      target: const [301, 9, 401],
    );
    doc.setSpawn(
      0,
      faction: 3,
      lower: const [12, 13, 14],
      upper: const [22, 23, 24],
    );
    doc.setNamedArea(0, name1: 6001, name2: 6002);

    final encoded = doc.encode();
    doc.validateEncoded(encoded);
    final parsed = SvmapEditorDocument.parse(encoded, 'world/test.svmap');

    expect(parsed.mobAreas.single.mobs[1].id, 9002);
    expect(parsed.mobAreas.single.mobs[1].count, 12);
    expect(parsed.npcs.single.type, 5);
    expect(parsed.npcs.single.id, 777);
    expect(parsed.npcs.single.route[1].position.values, [6, 7, 8]);
    expect(parsed.npcs.single.route[1].yaw, 135);
    expect(parsed.portals.single.targetMap, 9);
    expect(parsed.portals.single.minLevel, 20);
    expect(parsed.portals.single.maxLevel, 70);
    expect(parsed.spawns.single.faction, 3);
    expect(parsed.namedAreas.single.name1, 6001);
    expect(parsed.namedAreas.single.name2, 6002);

    expect(encoded.sublist(4, 12), original.sublist(4, 12));
    expect(encoded.sublist(20, 32), original.sublist(20, 32));
    expect(encoded.sublist(encoded.length - 4), const [0xde, 0xad, 0xbe, 0xef]);

    expect(containsBytes(encoded, const [0x44, 0x33, 0x22, 0x11]), isTrue);
    expect(containsBytes(encoded, const [0x88, 0x77, 0x66, 0x55]), isTrue);

    final semantic = SvmapData.parse(encoded, 'world/test.svmap');
    expect(semantic.portals.single.targetMap, 9);
    expect(semantic.mobAreas.single.mobs[1].id, 9002);
  });

  test('SVMAP authoring is fail-closed on numeric overflow', () {
    final doc = SvmapEditorDocument.parse(fixture(), 'world/test.svmap');
    expect(() => doc.setPortal(0, minLevel: 70000), throwsFormatException);
    expect(() => doc.setMobSpawn(0, 0, id: -1), throwsFormatException);
    expect(
      () => doc.setNpcWaypoint(0, 0, yaw: double.nan),
      throwsFormatException,
    );
  });

  test('SVMAP unchanged document round-trips byte-for-byte', () {
    final original = fixture();
    final doc = SvmapEditorDocument.parse(original, 'world/test.svmap');
    expect(doc.encode(), orderedEquals(original));
  });
}
