import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/game_text_codec.dart';
import 'package:herramienta_shaiya/core/client_locale.dart';
import 'package:herramienta_shaiya/editor/document.dart';
import 'package:herramienta_shaiya/editor/text_document.dart';
import 'package:herramienta_shaiya/editor/schema_reader.dart';
import 'package:herramienta_shaiya/editor/field_semantics.dart';
import 'package:herramienta_shaiya/editor/relations.dart';
import 'package:herramienta_shaiya/ui/editor_map.dart';
import 'package:herramienta_shaiya/ui/editor_pickers.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/ui/editor_icons.dart';
import 'editor_document_test.dart' show binaryTable;

void main() {
  test(
    'UTF16 BE config roundtrip and editing preserve endian, BOM and CRLF',
    () {
      Uint8List encode(String text) {
        final le = const GameTextCodec(GameTextEncoding.utf16le).encode(text),
            b = Uint8List(le.length + 2);
        b[0] = 0xfe;
        b[1] = 0xff;
        for (var i = 0; i < le.length; i += 2) {
          b[i + 2] = le[i + 1];
          b[i + 3] = le[i];
        }
        return b;
      }

      final original = encode('[Español]\r\nTítulo=Ñandú\r\n'),
          d = TextDocument.open(
            original,
            'config.ini',
            GameTextEncoding.automatic,
          );
      expect(d.bigEndian, true);
      expect(d.exportBytes(), original);
      d.edit(1, d.fields(1).single, 'Título=Águila');
      expect(d.exportBytes(), encode('[Español]\r\nTítulo=Águila\r\n'));
      expect(
        () => TextDocument.open(
          Uint8List.fromList([254, 255, 0]),
          'bad.ini',
          GameTextEncoding.automatic,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'NPC identities keep NPC type namespace and match translation ordinals',
    () {
      const rec = RecordRef(
        0,
        0,
        [],
        kind: 'Comerciantes',
        group: 0,
        ordinal: 0,
      );
      expect(editorIdentityKey({'npctype': '1', 'npctypeid': '1'}, rec), '1:1');
      expect(editorIdentityKey({}, rec), '1:1');
      expect(editorIdentityKey({'npctype': '2', 'npctypeid': '1'}, rec), '2:1');
      expect(ClientLocale.nameFamily('Npc/NpcQuest.SData'), 'npcquesttrans');
    },
  );
  test(
    'typed relations distinguish inventory object IDs from monster drop Grade',
    () {
      final npc = EditorReader.open(
        binaryTable(
          [
            'id',
            'Inventory[0].ItemType',
            'Inventory[0].ItemTypeId',
            'Inventory[1].ItemType',
            'Inventory[1].ItemTypeId',
          ],
          [
            [1, 6, 2, 0, 0],
          ],
        ),
        'binarysdata/npc.sdata',
      );
      final links = recordRelations(npc, 0);
      expect(links.length, 1);
      expect(links.single.key, '6:2');
      expect(links.single.family, 'item');
      final mob = EditorReader.open(
        binaryTable(
          ['id', 'item1', 'itemdroprate1', 'skillid1'],
          [
            [1, 206, 10, 40],
          ],
        ),
        'binarysdata/dbmonsterdata.sdata',
      );
      final drops = recordRelations(mob, 0);
      expect(drops.map((r) => r.family), containsAll(['grade', 'npcskill']));
      expect(matchesRelation(drops.first, {'grade': '206'}, mob.rows[0]), true);
      expect(matchesRelation(drops.first, {'id': '206'}, mob.rows[0]), false);
    },
  );
  test(
    'map markers preserve multiple NPC positions and exclude portal destination',
    () {
      final d = EditorReader.open(
        binaryTable(
          [
            'id',
            'Positions[0].X',
            'Positions[0].Z',
            'Positions[1].X',
            'Positions[1].Z',
            'TargetPosition.X',
            'TargetPosition.Z',
          ],
          [
            [1, 10, 20, 30, 40, 900, 900],
          ],
        ),
        'binarysdata/locations.sdata',
      );
      final markers = mapMarkers(d, [0]);
      expect(markers.length, 2);
      expect(markers[0].x, 10);
      expect(markers[1].z, 40);
    },
  );
  test(
    'known flag choices never relabel arbitrary numeric fields as enums',
    () {
      final d = EditorReader.open(
        binaryTable(
          ['ItemType', 'ItemTypeId'],
          [
            [1, 1],
          ],
        ),
        'dbitemdata.sdata',
      );
      expect(fieldChoices(d, 'Country')!['3'], 'Nordein');
      expect(fieldChoices(d, 'AttackFighter')!['1'], 'Permitido');
      expect(fieldChoices(d, 'ReqOg')!['0'], 'Intercambiable');
      expect(fieldChoices(d, 'Og')!['1'], 'No intercambiable');
      expect(fieldChoices(d, 'Og')!['2'], contains('Vinculado'));
      expect(fieldChoices(d, 'CustomParameter'), null);
      expect(isAssetField('Animation.Attack'), true);
      expect(isAssetField('Inventory[0].ItemType'), false);
    },
  );
  testWidgets(
    'map view is bounded without requiring a texture or fake geometry',
    (tester) async {
      // Structural map data is exercised separately; unsupported profile must not
      // draw coordinates based on an unrelated first integer in a random table.
      final d = EditorReader.open(
        binaryTable(
          ['id'],
          [
            [1],
          ],
        ),
        'locations.sdata',
      );
      expect(d.profile, isNot('svmap'));
      final library = Library('test', false, {}),
          images = EditorImages(Library('test', false, {}));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorMapView(
              document: d,
              images: images,
              rows: [0],
              selected: 0,
              onSelect: (_) {
                throw StateError(
                  'No marker may be selected on an invalid profile',
                );
              },
              onEdit: (_) {
                throw StateError('No invalid map may open an edit');
              },
            ),
          ),
        ),
      );
      expect(find.text('El plano necesita un SVMAP validado.'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.pumpWidget(const SizedBox());
      images.dispose();
      library.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
