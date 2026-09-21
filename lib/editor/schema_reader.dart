import 'dart:typed_data';
import '../core/game_text_codec.dart';
import '../core/seed_data.dart';
import 'document.dart';
import 'catalog_document.dart';
import 'text_document.dart';
import 'csv_document.dart';
import 'primitive_schemas.dart';

class EditorReader {
  static EditDocument open(
    Uint8List input,
    String path, {
    GameTextEncoding encoding = GameTextEncoding.big5,
    String? forceProfile,
  }) {
    if (input.length > 128 * 1024 * 1024) {
      throw const FormatException('El editor limita cada tabla a 128 MiB.');
    }
    if (RegExp(r'\.(mlt|itm|mon)$', caseSensitive: false).hasMatch(path)) {
      return CatalogDocument.open(input, path, encoding);
    }
    if (RegExp(r'\.(ini|cfg|txt|xml)$', caseSensitive: false).hasMatch(path)) {
      return TextDocument.open(input, path, encoding);
    }
    final payload = SeedData.decode(input), warnings = <String>[];
    if (SeedData.isEncoded(input)) {
      try {
        SeedData.decode(input, verifyChecksum: true);
      } catch (e) {
        warnings.add(
          'El checksum original no coincide. Se conserva sin cambios; una copia editada recalcula el CRC. $e',
        );
      }
    }
    final name = path.replaceAll('\\', '/').split('/').last.toLowerCase();
    final codec = GameTextCodec(encoding);
    final candidates = <String>[];
    if (forceProfile != null) {
      candidates.add(forceProfile);
    } else if (name == 'item.sdata') {
      candidates.addAll(['item-64', 'item-60', 'item-50']);
    } else if (name == 'skill.sdata' || name == 'npcskill.sdata') {
      candidates.addAll(['skill-60', 'skill-50']);
    } else if (name == 'monster.sdata') {
      candidates.addAll(['monster-0', 'monster-5']);
    } else if (name == 'killstatus.sdata') {
      candidates.add('killstatus');
    } else if (name == 'duallayerclothes.sdata') {
      candidates.add('dual-clothes');
    } else if (name == 'cash.sdata') {
      candidates.add('cash');
    } else if (name == 'setitem.sdata') {
      candidates.add('setitem');
    } else if (name.startsWith('npcquesttrans')) {
      candidates.addAll(['npc-trans-15', 'npc-trans-13']);
    } else if (name == 'npcquest.sdata') {
      candidates.addAll([
        'npc-80-15',
        'npc-80-13',
        'npc-60-15',
        'npc-60-13',
        'npc-50-13',
      ]);
    } else if (name.endsWith('.svmap')) {
      candidates.add('svmap');
    } else if (path
            .replaceAll('\\', '/')
            .toLowerCase()
            .contains('binarysdata/') ||
        (name.startsWith('db') && name.endsWith('.sdata'))) {
      candidates.add('binary');
    }
    final errors = <String>[];
    for (final profile in candidates) {
      try {
        final c = _Cursor(payload, codec);
        if (profile == 'binary') {
          _binary(c, name, warnings);
        } else if (profile.startsWith('item-')) {
          _grouped(
            c,
            primitiveSchemas['ItemDefinition${profile.substring(5)}']!,
            'Objeto',
          );
        } else if (profile.startsWith('skill-')) {
          final ep = profile.endsWith('60') ? 60 : 50;
          _grouped(
            c,
            primitiveSchemas['SkillDefinition$ep']!,
            'Habilidad',
            fixed: ep == 60 ? 15 : 9,
          );
        } else if (profile.startsWith('monster-')) {
          final schema = [...primitiveSchemas['MonsterRecord50']!];
          final ext = int.parse(profile.substring(8));
          final n = c.count();
          for (var i = 0; i < n; i++) {
            if (ext == 0) {
              c.record(schema, 'Criatura', ordinal: i);
            } else {
              c.begin('Criatura', i);
              c.primitives(schema);
              c.opaque(ext, 'Extensión del cliente (sin interpretación)');
              c.finish();
            }
          }
          if (ext > 0) {
            warnings.add(
              'Extensión de $ext bytes por criatura conservada, sin atribuirle un significado inventado.',
            );
          }
        } else if (profile == 'killstatus') {
          for (var i = 0, n = c.count(); i < n; i++) {
            c.begin('Bendición de facción', i);
            c.field('Faction', 'u8');
            c.field('BlessValue', 'i32');
            c.field('Index', 'u16');
            for (var j = 0; j < 6; j++) {
              c.field('Bonus[$j].Type', 'u8');
              c.field('Bonus[$j].Value', 'u16');
            }
            c.finish();
          }
        } else if (profile == 'dual-clothes') {
          for (var i = 0, n = c.count(); i < n; i++) {
            c.begin('Traje integral', i);
            for (final name in [
              'Index',
              'Upper',
              'Hands',
              'Lower',
              'Feet',
              'Face',
              'Head',
            ]) {
              c.field(name, 'u16');
            }
            c.finish();
          }
        } else if (profile == 'cash') {
          _cash(c);
        } else if (profile == 'setitem') {
          _setItem(c);
        } else if (profile.startsWith('npc-trans-')) {
          _npcTranslations(c, int.parse(profile.substring(10)));
        } else if (profile.startsWith('npc-')) {
          final parts = profile.split('-');
          _npcs(c, int.parse(parts[1]), int.parse(parts[2]), warnings);
        } else if (profile == 'svmap') {
          _svmap(c);
        } else {
          throw const FormatException('Perfil desconocido.');
        }
        final parsed = c.at;
        if (c.remaining <= 15 && payload.sublist(c.at).every((b) => b == 0)) {
          c.skip(c.remaining);
        }
        if (c.remaining != 0) {
          throw FormatException('Quedan ${c.remaining} bytes en ${c.at}.');
        }
        return EditDocument(
          path: path,
          profile: profile,
          original: Uint8List.fromList(input),
          payload: payload,
          codec: codec,
          rows: c.rows,
          warnings: [...warnings],
          parsedBytes: parsed,
          complete: !c.partial,
        );
      } catch (e) {
        errors.add('$profile: $e');
      }
    }
    // A failed schema is never silently used for editing. The file stays
    // visible and exportable, with full binary inspection and its exact hash.
    final spec = const FieldSpec(
      'Contenido original no interpretado',
      'opaque',
      editable: false,
    );
    return EditDocument(
      path: path,
      profile: 'binary-inspection',
      original: Uint8List.fromList(input),
      payload: payload,
      codec: codec,
      rows: [
        RecordRef(
          0,
          payload.length,
          const [],
          kind: 'Sin esquema validado',
          dynamicSpans: [FieldSpan(spec, 0, payload.length)],
        ),
      ],
      warnings: [
        ...warnings,
        ...errors,
        if (candidates.isEmpty)
          'No existe todavía un esquema validado para este archivo. Sus bytes no se omiten ni se modifican.',
      ],
      parsedBytes: 0,
      complete: false,
    );
  }

  static void _grouped(
    _Cursor c,
    List<(String, String)> schema,
    String kind, {
    int? fixed,
  }) {
    final groups = c.count(10000);
    for (var group = 0; group < groups; group++) {
      final n = fixed ?? c.count(100000);
      for (var i = 0; i < n; i++) {
        c.record(schema, kind, group: group, ordinal: i);
      }
    }
  }

  static void _binary(_Cursor c, String name, List<String> warnings) {
    c.skip(128);
    final columns = c.count(256);
    if (columns == 0) throw const FormatException('Tabla sin columnas.');
    final header = <String>[];
    for (var i = 0; i < columns; i++) {
      final n = c.byte();
      header.add(
        const GameTextCodec(
          GameTextEncoding.utf16le,
        ).decode(c.take(n * 2)).replaceAll('\u0000', ''),
      );
    }
    final count = c.count(200000);
    List<(String, String)>? layout;
    // Numeric tables are physically indexed by the client's column contract.
    // Text tables below have documented physical order; header order alone is
    // not used because some translated tables keep reordered header captions.
    final special = {
      'dbitemtext': 'DBItemTextRecord',
      'dbmonstertext': 'DBMonsterTextRecord',
      'dbskilltext': 'DBSkillTextRecord',
      'dbnpcskilltext': 'DBNpcSkillTextRecord',
      'dbsetitemtext': 'DBSetItemTextRecord',
      'dbitemselltext': 'DBItemSellTextRecord',
    };
    for (final e in special.entries) {
      if (name.startsWith(e.key)) layout = primitiveSchemas[e.value];
    }
    if (name == 'dbitemsell.sdata' || name == 'dbitemselldata.sdata') {
      // Client header exposes newer columns (e.g. ProductAccCount, Marriage).
      // ProductCode is physically the sole u8-length string, followed by int64.
      if (header.first != 'ProductCode') {
        throw const FormatException(
          'El código de producto no ocupa la primera columna esperada.',
        );
      }
      layout = [
        ('ProductCode', 'text8'),
        ...header.skip(1).map((h) => (h, 'i64')),
      ];
    }
    if (layout == null) {
      if (c.remaining < count * columns * 8 ||
          c.remaining - count * columns * 8 > 15) {
        throw const FormatException(
          'La tabla no coincide con enteros de 64 bits; requiere un esquema específico.',
        );
      }
      final seen = <String, int>{};
      layout = header.map((name) {
        final n = seen.update(name, (v) => v + 1, ifAbsent: () => 1);
        return (n == 1 ? name : '$name [$n]', 'i64');
      }).toList();
    } else if (layout.length != columns &&
        !(name.startsWith('dbitemselltext') &&
            columns == 2 &&
            layout.length == 3)) {
      throw FormatException(
        'El esquema físico tiene ${layout.length} columnas; la cabecera declara $columns.',
      );
    }
    for (var i = 0; i < count; i++) {
      c.record(layout, 'Tabla ${name.replaceAll('.sdata', '')}', ordinal: i);
    }
    warnings.add(
      'Archivo cliente. Oro, botín, precios y balance pueden necesitar una modificación equivalente en el servidor. No se presentan como una modificación del servidor.',
    );
    if (layout.any((s) => s.$1.toLowerCase().contains('droprate'))) {
      warnings.add(
        'Las tasas de botín se muestran en su unidad entera original. No se presupone que todos los slots usen porcentajes de 0 a 100.',
      );
    }
  }

  static void _cash(_Cursor c) {
    final n = c.count(20000);
    for (var i = 0; i < n; i++) {
      c.begin('Producto de tienda', i);
      for (final f in ['Index', 'Bag', 'Icon', 'Cost']) {
        c.field(f, 'u32');
      }
      for (var j = 1; j <= 24; j++) {
        c.field('Item$j.Id', 'u32');
        c.field('Item$j.Count', 'u8');
      }
      for (final f in ['ProductName', 'ProductCode', 'Description']) {
        c.field(f, 'text');
      }
      c.finish();
    }
  }

  static void _setItem(_Cursor c) {
    final n = c.count(20000);
    for (var i = 0; i < n; i++) {
      c.begin('Conjunto', i);
      c.field('Index', 'u16');
      c.field('Name', 'text');
      for (var j = 1; j <= 13; j++) {
        c.field('Item$j.Type', 'u16');
        c.field('Item$j.TypeId', 'u16');
      }
      for (var j = 1; j <= 13; j++) {
        c.field('Synergy$j', 'text');
      }
      c.finish();
    }
  }

  static const npcGroups = [
    'Comerciantes',
    'Portales',
    'Herreros',
    'Gestores PvP',
    'Casas de juego',
    'Almacenes',
    'NPC normales',
    'Guardias',
    'Animales',
    'Aprendices',
    'Maestros de gremio',
    'NPC muertos',
    'Comandantes',
    'Categoría NPC 13',
    'Categoría NPC 14',
  ];
  static void _npcTranslations(_Cursor c, int groups) {
    for (var group = 0; group <= groups; group++) {
      final n = c.count(40000);
      for (var i = 0; i < n; i++) {
        c.begin(
          group == groups ? 'Traducción de misión' : npcGroups[group],
          i,
          group: group,
        );
        final names = group == groups
            ? [
                'Name',
                'Summary',
                'CompletionMessage',
                'CompletionMessage2',
                'CompletionMessage3',
                'CompletionMessage4',
                'CompletionMessage5',
                'CompletionMessage6',
                'InitialDescription',
                'WelcomeMessage',
                'ReminderMessage',
                'AlternateResponse',
              ]
            : group == 1
            ? [
                'Name',
                'WelcomeMessage',
                'TeleportName1',
                'TeleportName2',
                'TeleportName3',
              ]
            : ['Name', 'WelcomeMessage'];
        for (final name in names) {
          c.field(name, 'text');
        }
        c.finish();
      }
    }
  }

  static void _npcs(_Cursor c, int ep, int groups, List<String> warnings) {
    for (var group = 0; group < groups; group++) {
      final n = c.count(20000);
      for (var i = 0; i < n; i++) {
        c.begin(npcGroups[group], i, group: group);
        c.field('NpcType', 'u8');
        c.field('NpcTypeId', 'i16');
        if (group == 0) c.field('MerchantType', 'u8');
        for (final name in ['Model', 'MoveDistance', 'MoveSpeed', 'Faction']) {
          c.field(name, 'i32');
        }
        if (ep < 80) {
          c.field('Name', 'text');
          c.field('WelcomeMessage', 'text');
        }
        if (group == 0) {
          final count = c.count(4096);
          for (var j = 0; j < count; j++) {
            c.field('Inventory[$j].ItemType', 'u8');
            c.field('Inventory[$j].ItemTypeId', 'u8');
          }
        }
        if (group == 1) {
          for (var j = 0; j < 3; j++) {
            c.field('Gate[$j].MapId', 'u16');
            c.vector('Gate[$j].Position');
            if (ep < 80) c.field('Gate[$j].Name', 'text');
            c.field('Gate[$j].Cost', 'u32');
          }
        }
        for (final q in ['InQuestIds', 'OutQuestIds']) {
          final n = c.count(10000);
          for (var j = 0; j < n; j++) {
            c.field('$q[$j]', 'i16');
          }
        }
        c.finish();
      }
    }
    // Preserve the 256x256 quest link structure, editable individual references.
    for (var i = 0; i < 65536; i++) {
      final begin = c.at;
      final spans = <FieldSpan>[];
      for (final name in ['StartQuest', 'EndQuest']) {
        final n = c.count(10000);
        for (var j = 0; j < n; j++) {
          spans.add(c.span(FieldSpec('$name[$j]', 'u16')));
        }
      }
      if (spans.isNotEmpty) {
        c.rows.add(
          RecordRef(
            begin,
            c.at,
            const [],
            kind: 'Vínculo de misiones · ${i ~/ 256}:${i % 256}',
            ordinal: i,
            dynamicSpans: spans,
          ),
        );
      }
    }
    final count = c.count(30000);
    // This client's EP8 extension has fixed 313-byte quests (not the known
    // 287-byte contract). NPCs, inventory, gates and links were fully parsed.
    // Preserve every extended quest as a read-only record; do not assign
    // plausible but wrong offsets to rewards or damage fields.
    if (ep == 80 && count > 0 && c.remaining == count * 313) {
      c.partial = true;
      for (var i = 0; i < count; i++) {
        c.begin('Misión ampliada · inspección binaria', i);
        c.opaque(313, 'Registro de misión ampliado (313 bytes)');
        c.finish();
      }
      warnings.add(
        'Los NPC, tiendas, portales y vínculos son editables. Este cliente contiene $count misiones ampliadas de 313 bytes: se conservan íntegras y no se interpreta el esquema estándar de 287 bytes como si fuera compatible.',
      );
    } else {
      for (var i = 0; i < count; i++) {
        _quest(c, i, ep);
      }
    }
  }

  static void _quest(_Cursor c, int index, int ep) {
    c.begin('Misión', index);
    c.field('Id', 'u16');
    if (ep < 80) {
      c.field('Name', 'text');
      c.field('Summary', 'text');
    }
    for (final n in ['MinLevel', 'MaxLevel']) {
      c.field(n, 'u16');
    }
    for (final n in [
      'Faction',
      'Mode',
      'MaleSex',
      'FemaleSex',
      'Fighter',
      'Defender',
      'Ranger',
      'Archer',
      'Mage',
      'Priest',
    ]) {
      c.field(n, 'u8');
    }
    c.field('HG', 'u16');
    c.field('VG', 'i16');
    for (final n in ['CG', 'OG', 'IG']) {
      c.field(n, 'u8');
    }
    c.field('PreviousQuestId', 'u16');
    c.field('RequireParty', 'u8');
    for (final n in [
      'Fighter',
      'Defender',
      'Ranger',
      'Archer',
      'Mage',
      'Priest',
    ]) {
      c.field('Party$n', 'u8');
    }
    for (final n in [
      'MinimumTime',
      'Time',
      'TickStartTerm',
      'TickKeepTime',
      'TickReceiveCount',
    ]) {
      c.field(n, 'u32');
    }
    c.field('StartType', 'u8');
    c.field('StartNpcType', 'u8');
    c.field('StartNpcId', 'u16');
    c.field('StartItemType', 'u8');
    c.field('StartItemId', 'u8');
    for (var j = 0; j < 3; j++) {
      for (final n in ['Type', 'TypeId', 'Count']) {
        c.field('RequiredItems[$j].$n', 'u8');
      }
    }
    c.field('EndType', 'u8');
    c.field('EndNpcType', 'u8');
    c.field('EndNpcId', 'i16');
    for (var j = 0; j < 3; j++) {
      for (final n in ['Type', 'TypeId', 'Count']) {
        c.field('FarmItems[$j].$n', 'u8');
      }
    }
    c.field('PvpKillCount', 'u8');
    for (var j = 1; j <= 2; j++) {
      c.field('RequiredMobId$j', 'u16');
      c.field('RequiredMobCount$j', 'u8');
    }
    c.field('ResultType', 'u8');
    c.field('ResultUserSelect', 'u8');
    final n = ep <= 50 ? 3 : 6;
    for (var j = 0; j < n; j++) {
      final p = 'Results[$j].';
      c.field('${p}NeedMobId', 'u16');
      c.field('${p}NeedMobCount', 'u8');
      c.field('${p}NeedItemId', 'u8');
      c.field('${p}NeedItemCount', 'u8');
      c.field('${p}NeedTime', 'u32');
      c.field('${p}NeedHG', 'u16');
      c.field('${p}NeedVG', 'i16');
      c.field('${p}NeedOG', 'u8');
      c.field('${p}Exp', 'u32');
      c.field('${p}Money', 'u32');
      c.field('${p}ItemType1', 'u8');
      c.field('${p}ItemTypeId1', 'u8');
      if (ep > 50) {
        c.field('${p}ItemCount1', 'u8');
        for (var k = 2; k <= 3; k++) {
          for (final f in ['ItemType', 'ItemTypeId', 'ItemCount']) {
            c.field('$p$f$k', 'u8');
          }
        }
      }
      c.field('${p}NextQuestId', 'u16');
      if (ep > 50 && ep < 80) c.field('${p}CompletionMessage', 'text');
    }
    if (ep < 80) {
      for (final name in [
        'InitialDescription',
        'QuestWindowSummary',
        'ReminderInstructions',
        'AlternateResponse',
      ]) {
        c.field(name, 'text');
      }
    }
    if (ep <= 50) {
      for (var j = 0; j < n; j++) {
        c.field('Results[$j].CompletionMessage', 'text');
      }
    }
    c.finish();
  }

  static void _svmap(_Cursor c) {
    final size = c.count(16384);
    if (size < 1) throw const FormatException('Tamaño del mapa inválido.');
    c.skip(size * size ~/ 8);
    c.skip(4);
    for (var i = 0, n = c.count(); i < n; i++) {
      c.begin('Escalera', i);
      c.vector('Position');
      c.finish();
    }
    for (var i = 0, n = c.count(); i < n; i++) {
      c.begin('Zona de aparición de criaturas', i);
      c.vector('Min');
      c.vector('Max');
      for (var j = 0, n = c.count(10000); j < n; j++) {
        c.field('Monster[$j].MobId', 'u32');
        c.field('Monster[$j].Count', 'u32');
      }
      c.finish();
    }
    for (var i = 0, n = c.count(); i < n; i++) {
      c.begin('Ubicación NPC', i);
      c.field('NpcType', 'i32');
      c.field('NpcId', 'i32');
      for (var j = 0, n = c.count(10000); j < n; j++) {
        c.vector('Positions[$j]');
        c.field('Positions[$j].Yaw', 'f32');
      }
      c.finish();
    }
    for (var i = 0, n = c.count(); i < n; i++) {
      c.begin('Portal de mapa', i);
      c.vector('Position');
      c.field('FactionOrPortalId', 'i32');
      c.field('MinLevel', 'u16');
      c.field('MaxLevel', 'u16');
      c.field('TargetMapId', 'u32');
      c.vector('TargetPosition');
      c.finish();
    }
    for (var i = 0, n = c.count(); i < n; i++) {
      c.begin('Área de aparición', i);
      c.field('Unknown1', 'i32');
      c.field('Faction', 'i32');
      c.field('Unknown2', 'i32');
      c.vector('Min');
      c.vector('Max');
      c.finish();
    }
    for (var i = 0, n = c.count(); i < n; i++) {
      c.begin('Área con nombre', i);
      c.vector('Min');
      c.vector('Max');
      c.field('NameIdentifier1', 'i32');
      c.field('NameIdentifier2', 'i32');
      c.finish();
    }
  }
}

class _Cursor {
  final Uint8List b;
  late final ByteData d = ByteData.sublistView(b);
  final GameTextCodec codec;
  final List<RecordRef> rows = [];
  int at = 0, start = 0, index = 0, group = 0;
  bool partial = false;
  String kind = '';
  List<FieldSpan> spans = [];
  _Cursor(this.b, this.codec);
  int get remaining => b.length - at;
  void need(int n) {
    if (n < 0 || n > remaining) {
      throw FormatException('Lectura fuera de rango en $at ($n bytes).');
    }
  }

  void skip(int n) {
    need(n);
    at += n;
  }

  Uint8List take(int n) {
    need(n);
    final value = Uint8List.sublistView(b, at, at + n);
    at += n;
    return value;
  }

  int byte() {
    need(1);
    return b[at++];
  }

  int count([int max = 200000]) {
    need(4);
    final value = d.getUint32(at, Endian.little);
    at += 4;
    if (value > max) {
      throw FormatException('Recuento $value fuera de límite en ${at - 4}.');
    }
    return value;
  }

  FieldSpan span(FieldSpec spec) {
    final begin = at;
    if (spec.text) {
      final prefix = spec.type == 'text8' ? 1 : 4,
          n = prefix == 1 ? byte() : count(65536),
          unit = codec.encoding == GameTextEncoding.utf16le ? 2 : 1;
      need(n * unit);
      var zeros = 0;
      while (zeros + unit <= n * unit &&
          b
              .sublist(at + n * unit - zeros - unit, at + n * unit - zeros)
              .every((v) => v == 0)) {
        zeros += unit;
      }
      at += n * unit;
      return FieldSpan(
        spec,
        begin,
        at - begin,
        prefix: prefix,
        stringUnit: unit,
        terminators: zeros,
      );
    }
    need(spec.width);
    if (spec.type == 'f32' && !d.getFloat32(at, Endian.little).isFinite) {
      throw FormatException('Coordenada no finita en $at.');
    }
    at += spec.width;
    return FieldSpan(spec, begin, spec.width);
  }

  void record(
    List<(String, String)> schema,
    String kind, {
    int group = 0,
    int ordinal = 0,
  }) {
    final begin = at;
    final shared = _schemas.putIfAbsent(
      schema,
      () => schema.map((s) => FieldSpec(s.$1, s.$2)).toList(growable: false),
    );
    for (final s in shared) {
      span(s);
    }
    rows.add(
      RecordRef(begin, at, shared, kind: kind, group: group, ordinal: ordinal),
    );
    if (rows.length > 200000) {
      throw const FormatException('Más de 200.000 registros.');
    }
  }

  final Map<List<(String, String)>, List<FieldSpec>> _schemas = {};
  void begin(String label, int ordinal, {int group = 0}) {
    start = at;
    kind = label;
    index = ordinal;
    this.group = group;
    spans = [];
  }

  void field(String name, String type) =>
      spans.add(span(FieldSpec(name, type)));
  void vector(String name) {
    for (final axis in ['X', 'Y', 'Z']) {
      field('$name.$axis', 'f32');
    }
  }

  void primitives(List<(String, String)> specs) {
    for (final s in specs) {
      field(s.$1, s.$2);
    }
  }

  void opaque(int n, String label) {
    partial = true;
    final s = at;
    skip(n);
    spans.add(FieldSpan(FieldSpec(label, 'opaque', editable: false), s, n));
  }

  void finish() {
    if (rows.length >= 200000) {
      throw const FormatException('Más de 200.000 registros.');
    }
    rows.add(
      RecordRef(
        start,
        at,
        const [],
        kind: kind,
        group: group,
        ordinal: index,
        dynamicSpans: spans,
      ),
    );
  }
}

EditDocument reopenDocument(EditDocument d, Uint8List bytes) {
  if (d is TextDocument) {
    return TextDocument.open(bytes, d.path, d.sourceEncoding);
  }
  if (d is CsvDocument) {
    return CsvDocument.open(bytes, d.path, d.exportEncoding);
  }
  return EditorReader.open(
    bytes,
    d.path,
    encoding: d.codec.encoding,
    forceProfile: d.profile,
  );
}
