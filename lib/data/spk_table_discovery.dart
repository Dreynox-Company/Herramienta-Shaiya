import 'dart:typed_data';

import '../core/game_text_codec.dart';
import '../core/seed_data.dart';
import '../editor/primitive_schemas.dart';
import '../editor/schema_reader.dart';
import 'spk_source.dart';

class SpkCoreTableDiscovery {
  static const _binaryLayouts = <String, String>{
    'BinarySData/DBItemData.SData': 'DBItemDataRecord',
    'BinarySData/DBMonsterData.SData': 'DBMonsterDataRecord',
    'BinarySData/DBSkillData.SData': 'DBSkillDataRecord',
    'BinarySData/DBNpcSkillData.SData': 'DBNpcSkillDataRecord',
    'BinarySData/DBSetItemData.SData': 'DBSetItemDataRecord',
    'BinarySData/DBDualLayerClothesData.SData':
        'DBDualLayerClothesDataRecord',
    'BinarySData/DBTransformModelData.SData': 'DBTransformModelDataRecord',
    'BinarySData/DBTransformWeaponModelData.SData':
        'DBTransformWeaponModelDataRecord',
    'BinarySData/DBItemSell.SData': 'DBItemSellRecord',
    'BinarySData/DBItemText.SData': 'DBItemTextRecord',
    'BinarySData/DBMonsterText.SData': 'DBMonsterTextRecord',
    'BinarySData/DBSkillText.SData': 'DBSkillTextRecord',
    'BinarySData/DBNpcSkillText.SData': 'DBNpcSkillTextRecord',
    'BinarySData/DBSetItemText.SData': 'DBSetItemTextRecord',
    'BinarySData/DBItemSellText.SData': 'DBItemSellTextRecord',
  };

  static List<String>? _binaryHeader(Uint8List payload) {
    if (payload.length < 133) return null;
    final data = ByteData.sublistView(payload);
    var at = 128;
    if (at + 4 > payload.length) return null;
    final columns = data.getUint32(at, Endian.little);
    at += 4;
    if (columns < 1 || columns > 256) return null;

    final out = <String>[];
    for (var i = 0; i < columns; i++) {
      if (at >= payload.length) return null;
      final units = payload[at++];
      final bytes = units * 2;
      if (units == 0 || at + bytes > payload.length) return null;
      final chars = <int>[];
      for (var j = 0; j < units; j++) {
        final value = data.getUint16(at + j * 2, Endian.little);
        if (value != 0) chars.add(value);
      }
      at += bytes;
      final value = String.fromCharCodes(chars).trim();
      if (value.isEmpty) return null;
      out.add(value);
    }
    return out;
  }

  static String _normalHeader(String value) =>
      value.toLowerCase().replaceAll('_', '').replaceAll(' ', '');

  static String? _classifyBinary(List<String> header) {
    final actual = header.map(_normalHeader).toList(growable: false);
    String? hit;
    for (final entry in _binaryLayouts.entries) {
      final layout = primitiveSchemas[entry.value];
      if (layout == null || layout.length != actual.length) continue;
      final expected = layout
          .map((field) => _normalHeader(field.$1))
          .toList(growable: false);
      var same = true;
      for (var i = 0; i < expected.length; i++) {
        if (actual[i] != expected[i]) {
          same = false;
          break;
        }
      }
      if (!same) continue;
      if (hit != null) return null;
      hit = entry.key;
    }
    return hit;
  }

  static ({String profile, int rows})? _tryProfile(
    Uint8List bytes,
    String path,
    Iterable<String> profiles, {
    int minimumRows = 1,
  }) {
    ({String profile, int rows})? found;
    for (final profile in profiles) {
      final document = EditorReader.open(
        bytes,
        path,
        encoding: GameTextEncoding.automatic,
        forceProfile: profile,
      );
      if (!document.complete ||
          document.profile != profile ||
          document.rows.length < minimumRows) {
        continue;
      }
      final value = (profile: profile, rows: document.rows.length);
      if (found != null && found.rows != value.rows) {
        return null;
      }
      found = value;
    }
    return found;
  }

  static bool _encodedLengthCandidate(int decodedBytes) =>
      decodedBytes >= 64 && (decodedBytes - 64) % 16 == 0;

  static Future<Map<String, Object?>> discover(
    SpkArchiveSource source, {
    required SpkExtractControl control,
    required SpkProgress progress,
    int maxCandidates = 16000,
  }) async {
    if (!source.canExtractAll) {
      throw const SpkFailure(
        'SPK_TABLE_DISCOVERY_PROFILE',
        'El descubrimiento estructural de tablas requiere lectura completa y '
            'autenticada de simples y fragmentados.',
      );
    }

    final candidates = source.index.resources
        .where((record) {
          final known = source.names[record.entryId];
          if (known != null && !known.toLowerCase().endsWith('.sdata')) {
            return false;
          }
          return _encodedLengthCandidate(record.decodedBytes);
        })
        .take(maxCandidates + 1)
        .toList(growable: false);

    if (candidates.length > maxCandidates) {
      throw SpkFailure(
        'SPK_TABLE_DISCOVERY_LIMIT',
        'Hay más candidatos SData de los que permite una pasada segura.',
        {
          'maxCandidates': maxCandidates,
          'candidateCountAtLeast': candidates.length,
        },
      );
    }

    final confirmed = <int, String>{};
    final binaryRows = <String, int>{};
    final itemCandidates = <({int id, int rows, String profile})>[];
    final monsterCandidates = <({int id, int rows, String profile})>[];
    final skillCandidates = <({int id, int rows, String profile})>[];
    var authenticated = 0;
    var encoded = 0;
    var rejected = 0;

    for (var i = 0; i < candidates.length; i++) {
      control.check();
      final record = candidates[i];
      final result = await source.readEntry(record);
      authenticated++;

      if (!SeedData.isEncoded(result.bytes)) {
        rejected++;
        if ((i + 1) % 100 == 0) {
          progress(
            'Descubriendo tablas SPK por estructura SEED…',
            i + 1,
            candidates.length,
          );
        }
        continue;
      }

      encoded++;
      Uint8List payload;
      try {
        payload = SeedData.decode(result.bytes, verifyChecksum: true);
      } catch (_) {
        rejected++;
        continue;
      }

      final header = _binaryHeader(payload);
      final binaryPath = header == null ? null : _classifyBinary(header);
      if (binaryPath != null) {
        final doc = EditorReader.open(
          result.bytes,
          binaryPath,
          encoding: GameTextEncoding.automatic,
          forceProfile: 'binary',
        );
        if (doc.complete && doc.profile == 'binary') {
          confirmed[record.entryId] = binaryPath;
          binaryRows[binaryPath] = doc.rows.length;
          progress(
            'Tabla confirmada: $binaryPath',
            i + 1,
            candidates.length,
          );
          continue;
        }
      }

      final item = _tryProfile(
        result.bytes,
        'Item/Item.SData',
        const ['item-64', 'item-60', 'item-50'],
        minimumRows: 20,
      );
      if (item != null) {
        itemCandidates.add((
          id: record.entryId,
          rows: item.rows,
          profile: item.profile,
        ));
      }

      final monster = _tryProfile(
        result.bytes,
        'Monster/Monster.SData',
        const ['monster-0', 'monster-5'],
        minimumRows: 20,
      );
      if (monster != null) {
        monsterCandidates.add((
          id: record.entryId,
          rows: monster.rows,
          profile: monster.profile,
        ));
      }

      final skill = _tryProfile(
        result.bytes,
        'Skill/Skill.SData',
        const ['skill-60', 'skill-50'],
        minimumRows: 9,
      );
      if (skill != null) {
        skillCandidates.add((
          id: record.entryId,
          rows: skill.rows,
          profile: skill.profile,
        ));
      }

      if ((i + 1) % 100 == 0) {
        progress(
          'Descubriendo tablas SPK por estructura SEED…',
          i + 1,
          candidates.length,
        );
      }
    }

    void confirmSingleOrRowMatched(
      List<({int id, int rows, String profile})> values,
      String path,
      String binaryPath,
    ) {
      if (values.isEmpty) return;
      final expectedRows = binaryRows[binaryPath];
      final matching = expectedRows == null
          ? values
          : values.where((value) => value.rows == expectedRows).toList();
      if (matching.length == 1) {
        confirmed[matching.single.id] = path;
      }
    }

    confirmSingleOrRowMatched(
      itemCandidates,
      'Item/Item.SData',
      'BinarySData/DBItemData.SData',
    );
    confirmSingleOrRowMatched(
      monsterCandidates,
      'Monster/Monster.SData',
      'BinarySData/DBMonsterData.SData',
    );

    final dbSkillRows = binaryRows['BinarySData/DBSkillData.SData'];
    final dbNpcRows = binaryRows['BinarySData/DBNpcSkillData.SData'];
    final unassignedSkills = [...skillCandidates];

    void assignSkill(String path, int? rows) {
      if (rows == null) return;
      final matches = unassignedSkills
          .where((value) => value.rows == rows)
          .toList();
      if (matches.length != 1) return;
      confirmed[matches.single.id] = path;
      unassignedSkills.remove(matches.single);
    }

    assignSkill('Skill/Skill.SData', dbSkillRows);
    assignSkill('Skill/NpcSkill.SData', dbNpcRows);
    if (skillCandidates.length == 1 &&
        !confirmed.containsKey(skillCandidates.single.id)) {
      confirmed[skillCandidates.single.id] = 'Skill/Skill.SData';
    }

    source.names.mergeConfirmed(confirmed);
    progress(
      'Descubrimiento terminado: ${confirmed.length} tablas confirmadas.',
      candidates.length,
      candidates.length,
    );

    return {
      'candidateResources': candidates.length,
      'authenticatedResources': authenticated,
      'seedEncodedResources': encoded,
      'rejectedResources': rejected,
      'confirmedTables': {
        for (final entry in confirmed.entries)
          entry.key.toRadixString(16).padLeft(16, '0'): entry.value,
      },
      'binaryRows': binaryRows,
      'itemCandidates': itemCandidates
          .map(
            (e) => {
              'entryId': e.id.toRadixString(16).padLeft(16, '0'),
              'rows': e.rows,
              'profile': e.profile,
            },
          )
          .toList(),
      'monsterCandidates': monsterCandidates
          .map(
            (e) => {
              'entryId': e.id.toRadixString(16).padLeft(16, '0'),
              'rows': e.rows,
              'profile': e.profile,
            },
          )
          .toList(),
      'skillCandidates': skillCandidates
          .map(
            (e) => {
              'entryId': e.id.toRadixString(16).padLeft(16, '0'),
              'rows': e.rows,
              'profile': e.profile,
            },
          )
          .toList(),
      'unresolvedSkillCandidates': unassignedSkills.length,
      'method':
          'authenticated-payload+SEED-checksum+binary-header+schema-roundtrip+row-correlation',
    };
  }
}
