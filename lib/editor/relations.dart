import '../core/client_locale.dart';
import 'document.dart';

class RecordRelation {
  final String family, field, key;
  const RecordRelation(this.family, this.field, this.key);
  String get label => switch (family) {
    'item' => 'Objeto',
    'grade' => 'Grupo de botín / Grade',
    'monster' => 'Monstruo',
    'skill' => 'Habilidad',
    'npcskill' => 'Habilidad de NPC',
    _ => family,
  };
}

List<RecordRelation> recordRelations(EditDocument d, int row) {
  final v = {
        for (final f in d.fields(row)) f.spec.name.toLowerCase(): d.read(f),
      },
      result = <RecordRelation>[];
  void add(String family, String field, String key) {
    if (key.isNotEmpty &&
        key != '0' &&
        key != '-1' &&
        !result.any((r) => r.family == family && r.key == key)) {
      result.add(RecordRelation(family, field, key));
    }
  }

  for (final e in v.entries) {
    if (e.key.endsWith('.itemtype') || e.key.endsWith('.type')) {
      final stem = e.key.substring(0, e.key.lastIndexOf('.') + 1),
          id = v['${e.key}id'];
      if (id != null && e.value != '0' && id != '0') {
        add('item', stem, '${e.value}:$id');
      }
    }
    if (RegExp(r'^(item|itemtype)\d+$').hasMatch(e.key) &&
        !ClientLocale.stem(d.path).contains('monster')) {
      final m = RegExp(r'^(?:itemtype)(\d+)$').firstMatch(e.key);
      if (m != null) {
        final id = v['itemtypeid${m[1]}'];
        if (id != null) add('item', e.key, '${e.value}:$id');
      }
    }
    if (e.key.endsWith('.mobid') ||
        RegExp(r'^requiredmobid\d+$').hasMatch(e.key)) {
      add('monster', e.key, e.value);
    }
    if (RegExp(r'^item\d+$').hasMatch(e.key) &&
        ClientLocale.stem(d.path).contains('monster')) {
      add('grade', e.key, e.value);
    }
    if (RegExp(r'(^|\.)skillid\d*$').hasMatch(e.key)) {
      add(
        ClientLocale.stem(d.path).contains('monster') ? 'npcskill' : 'skill',
        e.key,
        e.value,
      );
    }
  }
  return result;
}

bool matchesRelation(
  RecordRelation r,
  Map<String, String> v,
  RecordRef record,
) {
  switch (r.family) {
    case 'item':
      return '${v['itemtype'] ?? v['type']}:${v['itemtypeid'] ?? v['typeid']}' ==
          r.key;
    case 'grade':
      return v['grade'] == r.key;
    case 'monster':
      return (v['id'] ?? v['mobid'] ?? '${record.ordinal + 1}') == r.key;
    case 'skill':
    case 'npcskill':
      return (v['id'] ?? v['skillid'] ?? '${record.group + 1}') == r.key;
    default:
      return false;
  }
}
