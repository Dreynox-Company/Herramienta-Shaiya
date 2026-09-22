import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/client_locale.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/core/game_metadata.dart';
import 'package:herramienta_shaiya/ui/data_editor.dart';

Uint8List nameTable(List<String> fields, List<int> payload, int count) {
  final out = BytesBuilder()..add(Uint8List(128));
  void i(int v) => out.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  i(fields.length);
  for (final name in fields) {
    out.add([name.length]);
    out.add(const GameTextCodec(GameTextEncoding.utf16le).encode(name));
  }
  i(count);
  out.add(payload);
  return out.takeBytes();
}

Uint8List sampleItemName() {
  final out = BytesBuilder()
    ..add(
      (ByteData(16)
            ..setInt64(0, 1, Endian.little)
            ..setInt64(8, 25, Endian.little))
          .buffer
          .asUint8List(),
    );
  for (final text in [
    'Espada de Ascalón Ñandú',
    '¿Daño mágico? ¡Sí! <p> → 10 €',
  ]) {
    // Arrow is representable only in Unicode: original Western client gets an
    // explicitly Western fixture with its actual representable characters.
    final t = text.replaceAll('→', '-'), b = GameTextCodec.windows.encode(t);
    out.add(
      (ByteData(
        4,
      )..setUint32(0, b.length + 1, Endian.little)).buffer.asUint8List(),
    );
    out.add(b);
    out.add([0]);
  }
  return nameTable(
    ['itemtype', 'itemtypeid', 'itemname', 'text'],
    out.takeBytes(),
    1,
  );
}

void main() {
  test(
    'loose catalogue preserves conflicting originals without discarding valid labels',
    () {
      final catalogue = ClientLocale.indexedCatalogue(
        Uint8List.fromList(
          utf8.encode('1\t"Daño <v>"\n2\t"A"\n2\t"B"\n3\t"Ñ"\n3\t"Ñ"'),
        ),
        'systemmessage/spn.txt',
      );
      expect(catalogue.resolved, {1: 'Daño <v>', 3: 'Ñ'});
      expect(catalogue.conflicts, {
        2: ['A', 'B'],
      });
      expect(catalogue.duplicates.keys, containsAll([2, 3]));
    },
  );
  test(
    'library retains loose localization and CSV files rather than filtering them out',
    () {
      expect(supportedPath('World/1_spn.txt'), true);
      expect(supportedPath('systemmessage/spn.txt'), true);
      expect(supportedPath('dbitemdata.csv'), true);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  for (final suffix in ['spn', 'spa', 'esp', 'es', 'spain', 'spanish']) {
    test('Spanish suffix $suffix selects Western text', () {
      expect(
        ClientLocale.languageOf(
          'DATA\\BinarySData\\DBItemText_${suffix.toUpperCase()}.SData',
        ),
        'es',
      );
      expect(
        ClientLocale.encodingForPath('npc/npcquesttrans_$suffix.sdata'),
        GameTextEncoding.windows1252,
      );
    });
  }
  test('Spanish names stay in the numeric table dataset', () {
    final paths = [
      'dbitemtext_spn.sdata',
      'binarysdata/dbitemtext_chn.sdata',
      'binarysdata/dbitemtext_usa.sdata',
      'binarysdata/dbitemtext_spn.sdata',
      'binarysdata/dbitemtext_spn_generated.sdata',
    ];
    final sorted = ClientLocale.tableCandidates(
      paths,
      'dbitemtext',
      beside: 'binarysdata/dbitemdata.sdata',
    );
    expect(sorted.first, 'binarysdata/dbitemtext_spn.sdata');
    expect(sorted, hasLength(3));
    expect(sorted, isNot(contains('dbitemtext_spn.sdata')));
  });
  test('exact DB text table is a fallback but localized Spanish wins', () {
    final files = [
      'binarysdata/dbmonstertext.sdata',
      'binarysdata/dbmonstertext_usa.sdata',
      'binarysdata/dbmonstertext_spn.sdata',
    ];
    final localized = ClientLocale.tableCandidates(
      files,
      'dbmonstertext',
      beside: 'binarysdata/dbmonsterdata.sdata',
    );
    expect(localized.first, 'binarysdata/dbmonstertext_spn.sdata');
    expect(localized.last, 'binarysdata/dbmonstertext.sdata');

    final exactOnly = ClientLocale.tableCandidates(
      const ['binarysdata/dbmonstertext.sdata'],
      'dbmonstertext',
      beside: 'binarysdata/dbmonsterdata.sdata',
    );
    expect(exactOnly, ['binarysdata/dbmonstertext.sdata']);
  });

  test(
    'english and alternate fallback are deterministic not enumeration order',
    () {
      final files = [
        'b/dbitemtext_chn.sdata',
        'b/dbitemtext_ger.sdata',
        'b/dbitemtext_usa.sdata',
      ];
      expect(
        ClientLocale.tableCandidates(
          files,
          'dbitemtext',
          beside: 'b/dbitemdata.sdata',
        ),
        ClientLocale.tableCandidates(
          files.reversed,
          'dbitemtext',
          beside: 'b/dbitemdata.sdata',
        ),
      );
      expect(
        ClientLocale.tableCandidates(
          files,
          'dbitemtext',
          beside: 'b/dbitemdata.sdata',
        ).first,
        'b/dbitemtext_usa.sdata',
      );
    },
  );
  test('NPC skill, shop and set names are not confused with item text', () {
    expect(
      ClientLocale.nameFamily('binarysdata/dbnpcskilldata.sdata'),
      'dbnpcskilltext',
    );
    expect(
      ClientLocale.nameFamily('binarysdata/dbitemselldata.sdata'),
      'dbitemselltext',
    );
    expect(
      ClientLocale.nameFamily('binarysdata/dbsetitemdata.sdata'),
      'dbsetitemtext',
    );
  });
  test('Item display preserves Spanish instead of guessing Chinese', () {
    final rows = readItemNames(
      sampleItemName(),
      'binarysdata/dbitemtext_spn.sdata',
    );
    expect(rows.single.key, '1:25');
    expect(rows.single.name, 'Espada de Ascalón Ñandú');
    expect(rows.single.description, '¿Daño mágico? ¡Sí! <p> - 10 €');
  });
  test(
    'editor automatic mode adopts actual filename locale and round trips',
    () {
      final bytes = sampleItemName();
      final doc = parseEditorDocument({
        'bytes': bytes,
        'path': 'binarysdata/dbitemtext_spn.sdata',
        'encoding': 'automatic',
      });
      expect(doc.complete, true);
      expect(doc.codec.encoding, GameTextEncoding.windows1252);
      expect(doc.exportBytes(), bytes);
    },
  );
  test('explicit encoding override is respected', () {
    final d = parseEditorDocument({
      'bytes': sampleItemName(),
      'path': 'binarysdata/dbitemtext_spn.sdata',
      'encoding': 'big5',
    });
    expect(d.codec.encoding, GameTextEncoding.big5);
  });
  test('UTF16 world labels retain ñ, diacritics and placeholders', () {
    final b = Uint8List.fromList([
      255,
      254,
      ...const GameTextCodec(GameTextEncoding.utf16le).encode(
        '0\tAldea de Keolloseu\r\n1\tHábitat de Leopardo Hembra\r\n2\t¿Daño? <v>\r\n',
      ),
    ]);
    final m = ClientLocale.indexedText(b, 'world/1_spn.txt');
    expect(m[1], 'Hábitat de Leopardo Hembra');
    expect(m[2], '¿Daño? <v>');
  });
  test('UTF8 BOM with emoji does not get decoded into Windows mojibake', () {
    expect(
      ClientLocale.decodeTextFile(
        Uint8List.fromList([239, 187, 191, ...utf8.encode('Niño 🎮')]),
        'loca_spa.ini',
      ),
      'Niño 🎮',
    );
  });
  test('UTF16 BE with BOM is recognized and malformed UTF16 rejected', () {
    expect(
      ClientLocale.decodeTextFile(
        Uint8List.fromList([254, 255, 0, 209]),
        'spn.txt',
      ),
      'Ñ',
    );
    expect(
      () => ClientLocale.decodeTextFile(
        Uint8List.fromList([255, 254, 17]),
        'spn.txt',
      ),
      throwsFormatException,
    );
  });
  test('duplicate localization IDs cannot silently mask content', () {
    expect(
      () => ClientLocale.indexedText(
        Uint8List.fromList(utf8.encode('2\tA\n2\tB')),
        'spn.txt',
      ),
      throwsFormatException,
    );
  });
  test('new unrelated filenames do not imply a character class or locale', () {
    expect(ClientLocale.languageOf('DBWingBaseData.SData'), isNull);
    expect(ClientLocale.nameFamily('DBGodPowerData.SData'), isNull);
  });
}
