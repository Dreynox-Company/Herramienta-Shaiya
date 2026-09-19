import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'editor_document_test.dart' show binaryTable;

void main() {
  for (final path in [
    'Importado/DBMonsterData.SData',
    r'BinarySData\DBMonsterData.SData',
    'DBItemData.SData',
  ]) {
    test('known DB table imports outside its original folder: $path', () {
      final bytes = binaryTable(
        ['ID', 'Money1'],
        [
          [1, 5],
        ],
      );
      final d = EditorReader.open(bytes, path);
      expect(d.profile, 'binary');
      expect(d.complete, true);
      d.edit(0, d.fields(0)[1], '-5');
      final fresh = EditorReader.open(d.exportBytes(), path);
      expect(fresh.read(fresh.fields(0)[1]), '-5');
    });
  }
  test(
    'opaque monster extension cannot claim complete structural coverage',
    () {
      final out = BytesBuilder();
      void u32(int v) {
        out.add(
          (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
        );
      }

      u32(1); // Record count.
      u32(1);
      out.add([65]); // Name with no terminator.
      out.add(Uint8List(31)); // Documented fixed monster fields.
      out.add([1, 2, 3, 4, 5]); // Uninterpreted extension.
      final d = EditorReader.open(
        out.takeBytes(),
        'Monster.SData',
        encoding: GameTextEncoding.windows1252,
        forceProfile: 'monster-5',
      );
      expect(d.profile, 'monster-5');
      expect(d.complete, false);
      expect(d.fields(0).last.spec.type, 'opaque');
    },
  );
}
