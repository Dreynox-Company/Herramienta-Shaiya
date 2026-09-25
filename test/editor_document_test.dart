import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/core/seed_data.dart';
import 'package:herramienta_shaiya/editor/document.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/editor/csv_document.dart';
import 'package:herramienta_shaiya/editor/field_semantics.dart';

Uint8List binaryTable(List<String> fields, List<List<int>> rows) {
  final out = BytesBuilder();
  out.add(Uint8List(128));
  void u32(int v) {
    final d = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(d.buffer.asUint8List());
  }

  u32(fields.length);
  for (final f in fields) {
    out.add([f.length]);
    out.add(const GameTextCodec(GameTextEncoding.utf16le).encode(f));
  }
  u32(rows.length);
  for (final row in rows) {
    for (final v in row) {
      final d = ByteData(8)..setInt64(0, v, Endian.little);
      out.add(d.buffer.asUint8List());
    }
  }
  return out.toBytes();
}

EditDocument typedDoc(String type, Uint8List bytes) => EditDocument(
  path: 'fixture.sdata',
  profile: 'fixture',
  original: bytes,
  payload: bytes,
  codec: const GameTextCodec(GameTextEncoding.utf8),
  rows: [
    RecordRef(0, bytes.length, [FieldSpec('Value', type)]),
  ],
  warnings: [],
  parsedBytes: bytes.length,
);
void main() {
  group('Codificación sin pérdida', () {
    for (final enc in [
      GameTextEncoding.utf8,
      GameTextEncoding.windows1252,
      GameTextEncoding.utf16le,
    ]) {
      test('${enc.name} conserva Ñ, signos y acentos', () {
        final c = GameTextCodec(enc),
            s = 'Niño · ¡Espada áéíóú, pingüino! ¿Cuánto? €';
        expect(c.decode(c.encode(s)), s);
      });
    }
    test('UTF-8 y UTF-16 conservan caracteres fuera del BMP', () {
      for (final e in [GameTextEncoding.utf8, GameTextEncoding.utf16le]) {
        final c = GameTextCodec(e);
        expect(c.decode(c.encode('山 🔥 𐐷')), '山 🔥 𐐷');
      }
    });
    test('Windows-1252 rechaza emoji en lugar de poner interrogaciones', () {
      expect(
        () => GameTextCodec.windows.encode('Fuego 🔥'),
        throwsFormatException,
      );
    });
    test('Big5 conserva texto chino tradicional', () {
      const c = GameTextCodec(GameTextEncoding.big5);
      expect(c.decode(c.encode('武器 裝備')), '武器 裝備');
    });
    test('Coreano conserva texto de mapas', () {
      const c = GameTextCodec(GameTextEncoding.korean);
      expect(c.decode(c.encode('안녕하세요')), '안녕하세요');
    });
    test('automático recupera Ñ occidental y UTF-8', () {
      expect(GameTextCodec.autoDecode([0x4e, 0x69, 0xf1, 0x6f]), 'Niño');
      expect(GameTextCodec.autoDecode(utf8.encode('Águila')), 'Águila');
    });
    test('automático no escribe texto con una suposición', () {
      expect(
        () => const GameTextCodec(GameTextEncoding.automatic).encode('a'),
        throwsFormatException,
      );
    });
    test('UTF-16 incompleto y sustitutos aislados no se aceptan', () {
      expect(
        () => const GameTextCodec(GameTextEncoding.utf16le).decode([0]),
        throwsFormatException,
      );
      expect(
        () => const GameTextCodec(
          GameTextEncoding.utf8,
        ).encode(String.fromCharCode(0xd800)),
        throwsFormatException,
      );
    });
  });
  group('SEED reversible y CRC', () {
    for (final n in [0, 1, 15, 16, 17, 64, 1023]) {
      test('longitud $n y relleno íntegro', () {
        final data = Uint8List.fromList(
          List.generate(n, (i) => (i * 71) % 256),
        );
        final encrypted = SeedData.encode(data);
        expect(SeedData.decode(encrypted, verifyChecksum: true), data);
      });
    }
    test('cabecera extendida válida', () {
      final data = Uint8List.fromList([1, 2, 3]);
      expect(
        SeedData.decode(
          SeedData.encode(data, extended: true),
          verifyChecksum: true,
        ),
        data,
      );
    });
    test('un campo editado se cifra y relee', () {
      final raw = binaryTable(
            ['id', 'money1', 'money2'],
            [
              [1, 10, 20],
            ],
          ),
          input = SeedData.encode(raw);
      final d = EditorReader.open(input, 'BinarySData/DBMonsterData.SData');
      d.edit(0, d.fields(0)[1], '-1');
      final re = EditorReader.open(
        d.exportBytes(),
        'BinarySData/DBMonsterData.SData',
      );
      expect(re.read(re.fields(0)[1]), '-1');
      expect(
        () => SeedData.decode(d.exportBytes(), verifyChecksum: true),
        returnsNormally,
      );
    });
  });
  test(
    'filtros de clase interpretan campos clásicos y DB sin inventar permisos',
    () {
      const pairs = {
        'Fighter': 'AttackFighter',
        'Defender': 'DefenseFighter',
        'Ranger': 'PatrolRogue',
        'Archer': 'ShootRogue',
        'Mage': 'AttackMage',
        'Priest': 'DefenseMage',
      };
      for (final e in pairs.entries) {
        expect(editorMatchesClass({e.value.toLowerCase(): '1'}, e.key), true);
        expect(editorMatchesClass({e.key.toLowerCase(): '1'}, e.key), true);
        expect(editorMatchesClass({e.value.toLowerCase(): '0'}, e.key), false);
        expect(editorMatchesClass({}, e.key), false);
        expect(FieldMeaning.of(e.value).group, 'Requisitos');
      }
    },
  );
  test('precios Buy Sell numéricos no desaparecen en Otros', () {
    final d = EditorReader.open(
      binaryTable(
        ['Buy', 'Sell'],
        [
          [-1, -2],
        ],
      ),
      'BinarySData/DBItemData.SData',
    );
    expect(FieldMeaning.of('Buy').group, 'Precios y tienda');
    expect(FieldMeaning.of('Sell').label, 'Precio de venta al NPC');
    expect(rowWarnings(d, 0).length, 2);
  });
  test('nombres de objetos se enlazan por Type y TypeId reales', () {
    const rec = RecordRef(0, 0, [], kind: 'Objeto', group: 1, ordinal: 3);
    expect(
      editorIdentityKey({'itemtype': '5', 'itemtypeid': '123'}, rec),
      '5:123',
    );
    expect(editorIdentityKey({'type': '5', 'typeid': '123'}, rec), '5:123');
    expect(editorIdentityKey({'skilllevel': '15'}, rec), '2:15');
    expect(
      editorIdentityKey(
        {},
        const RecordRef(0, 0, [], kind: 'Criatura', ordinal: 6),
      ),
      '7',
    );
  });
  group('Tipos y transacciones del editor', () {
    for (final type in ['i8', 'i16', 'i32', 'i64']) {
      test('$type admite límites y signo menos Unicode', () {
        final w = FieldSpec('v', type).width,
            d = typedDoc(type, Uint8List(w)),
            f = FieldSpan(FieldSpec('Value', type), 0, w);
        d.edit(0, f, '−1');
        expect(d.read(f), '-1');
        final max = (BigInt.one << (w * 8 - 1)) - BigInt.one;
        d.edit(0, f, '$max');
        expect(d.read(f), '$max');
        expect(
          () => d.edit(0, f, '${max + BigInt.one}'),
          throwsFormatException,
        );
      });
    }
    for (final type in ['u8', 'u16', 'u32', 'u64']) {
      test('$type rechaza negativos y no da la vuelta al máximo', () {
        final w = FieldSpec('v', type).width,
            d = typedDoc(type, Uint8List(w)),
            f = d.fields(0).single;
        expect(() => d.edit(0, f, '-1'), throwsFormatException);
        expect(d.dirty, isFalse);
        final max = (BigInt.one << (w * 8)) - BigInt.one;
        d.edit(0, f, '$max');
        expect(d.read(f), '$max');
      });
    }
    test('float32 rechaza NaN e infinito', () {
      final d = typedDoc('f32', Uint8List(4)), f = d.fields(0).single;
      for (final s in ['NaN', 'Infinity', '1e99']) {
        expect(() => d.edit(0, f, s), throwsFormatException);
      }
      d.edit(0, f, '-0,25');
      expect(d.read(f), '-0.25');
    });
    test('tabla conserva los 18 espacios de loot sin truncar a 9', () {
      final names = [
        'id',
        'money1',
        'money2',
        for (var i = 1; i <= 18; i++) ...['item$i', 'itemdroprate$i'],
      ];
      final d = EditorReader.open(
        binaryTable(names, [List.filled(names.length, 0)]),
        'BinarySData/DBMonsterData.SData',
      );
      expect(d.fields(0).length, 39);
      expect(d.fields(0).last.spec.name, 'itemdroprate18');
      expect(FieldMeaning.of('item18').group, 'Botín y oro');
    });
    test('sin modificaciones los bytes son idénticos incluso con padding', () {
      final raw = binaryTable(
            ['id'],
            [
              [1],
            ],
          ),
          bytes = SeedData.encode(raw);
      final d = EditorReader.open(bytes, 'BinarySData/DBMonsterData.SData');
      expect(d.exportBytes(), bytes);
    });
    test('edición masiva valida todos antes de aplicar', () {
      final d = typedDoc('u8', Uint8List(1));
      expect(
        () => d.editMany([
          (0, d.fields(0).single, '3'),
          (4, d.fields(0).single, '5'),
        ]),
        throwsFormatException,
      );
      expect(d.dirty, isFalse);
    });
    test('deshacer, rehacer y retorno al original', () {
      final d = typedDoc('i64', Uint8List(8)), f = d.fields(0).single;
      d.edit(0, f, '42');
      d.undo();
      expect(d.dirty, isFalse);
      d.redo();
      expect(d.read(f), '42');
      d.edit(0, f, '0');
      expect(d.dirty, isFalse);
    });
    test('parche aplica solo al hash y a los valores previstos', () {
      final raw = binaryTable(
            ['id', 'money1'],
            [
              [1, 20],
            ],
          ),
          d = EditorReader.open(raw, 'BinarySData/DBMonsterData.SData');
      d.edit(0, d.fields(0)[1], '-1');
      final p = d.exportPatch(),
          other = EditorReader.open(raw, 'BinarySData/DBMonsterData.SData');
      other.importPatch(p);
      expect(other.read(other.fields(0)[1]), '-1');
      expect(() => other.importPatch(p), throwsFormatException);
    });
    test('bytes desconhecidos permanecen presentes y no editables', () {
      final data = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
          d = EditorReader.open(data, 'unknown.sdata');
      expect(d.complete, isFalse);
      expect(d.exportBytes(), data);
      expect(() => d.edit(0, d.fields(0).first, '5'), throwsFormatException);
    });
    test('intervalo de oro invertido genera una advertencia', () {
      final d = EditorReader.open(
        binaryTable(
          ['money1', 'money2'],
          [
            [20, 10],
          ],
        ),
        'BinarySData/DBMonsterData.SData',
      );
      expect(rowWarnings(d, 0).join(), contains('Money1'));
    });
  });
  group('CSV de servidor separado', () {
    test('CSV legado sin cambios conserva su codificación para relectura', () {
      final bytes = GameTextCodec.windows.encode(
        'id;nombre\r\n1;Español á Ñ\r\n',
      );
      final d = CsvDocument.open(
        bytes,
        'legacy.csv',
        GameTextEncoding.windows1252,
      );
      expect(d.exportEncoding, GameTextEncoding.windows1252);
      final before = CsvDocument.open(
        d.exportBytes(),
        d.path,
        d.exportEncoding,
      );
      expect(before.read(before.fields(0)[1]), 'Español á Ñ');
      d.edit(0, d.fields(0)[1], 'Niño 🔥');
      expect(d.exportEncoding, GameTextEncoding.utf8);
      final after = CsvDocument.open(d.exportBytes(), d.path, d.exportEncoding);
      expect(after.read(after.fields(0)[1]), 'Niño 🔥');
      d.undo();
      expect(d.exportEncoding, GameTextEncoding.windows1252);
      expect(d.exportBytes(), bytes);
    });

    test('nombre español y números negativos conservados', () {
      final b = Uint8List.fromList(
        utf8.encode(
          'MobID,MobName,Money1,Money2\r\n1,"Niño, dragón",-1,20\r\n',
        ),
      );
      final d = CsvDocument.open(b, 'Mobs.csv', GameTextEncoding.utf8);
      expect(d.exportBytes(), b);
      d.edit(0, d.fields(0)[2], '-25');
      final r = CsvDocument.open(
        d.exportBytes(),
        'Mobs.csv',
        GameTextEncoding.utf8,
      );
      expect(r.read(r.fields(0)[2]), '-25');
      expect(r.read(r.fields(0)[1]), 'Niño, dragón');
    });
    test('comillas y salto de línea dentro de celda', () {
      final b = Uint8List.fromList(
            utf8.encode('id;text\n1;"uno\ndos ""tres"""\n'),
          ),
          d = CsvDocument.open(b, 'a.csv', GameTextEncoding.utf8);
      expect(d.read(d.fields(0)[1]), 'uno\ndos "tres"');
    });
    test('encabezado ambiguo y CSV truncado rechazados', () {
      for (final s in ['a,a\n1,2', 'a,b\n1', 'a,b\n1,"x']) {
        expect(
          () => CsvDocument.open(
            Uint8List.fromList(utf8.encode(s)),
            'a.csv',
            GameTextEncoding.utf8,
          ),
          throwsFormatException,
        );
      }
    });
  });
}
