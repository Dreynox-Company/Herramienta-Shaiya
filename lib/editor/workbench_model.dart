import 'document.dart';
import 'schema_reader.dart';
import 'field_semantics.dart';

enum EditorDomain {
  items,
  skills,
  creatures,
  shops,
  npcs,
  maps,
  models,
  configuration,
  other,
}

EditorDomain editorDomain(String path) {
  final p = path.toLowerCase();
  if (RegExp(r'\.(mlt|itm|mon)$').hasMatch(p)) return EditorDomain.models;
  if (RegExp(r'\.(ini|cfg|txt|xml)$').hasMatch(p)) {
    return EditorDomain.configuration;
  }
  if (p.endsWith('.svmap')) return EditorDomain.maps;
  if (p.contains('skill')) return EditorDomain.skills;
  if (p.contains('cash') || p.contains('selllist')) return EditorDomain.shops;
  if (p.contains('monster')) return EditorDomain.creatures;
  if (p.contains('npc')) return EditorDomain.npcs;
  if (p.contains('item')) return EditorDomain.items;
  return EditorDomain.other;
}

const domainLabels = {
  EditorDomain.items: 'Objetos',
  EditorDomain.skills: 'Habilidades',
  EditorDomain.creatures: 'Monstruos',
  EditorDomain.shops: 'Tiendas',
  EditorDomain.npcs: 'NPC y misiones',
  EditorDomain.maps: 'Mapas del servidor',
  EditorDomain.models: 'Modelos y animaciones',
  EditorDomain.configuration: 'Configuración',
  EditorDomain.other: 'Otras tablas',
};
const itemCategories = {
  1: 'Espada de una mano',
  2: 'Espada de dos manos',
  3: 'Hacha de una mano',
  4: 'Hacha de dos manos',
  5: 'Arma doble',
  6: 'Lanza',
  7: 'Contundente de una mano',
  8: 'Contundente de dos manos',
  9: 'Garras',
  10: 'Daga',
  11: 'Arco',
  12: 'Bastón',
  13: 'Jabalina',
  14: 'Ballesta',
  15: 'Puños',
  16: 'Casco de Luz',
  17: 'Torso de Luz',
  18: 'Piernas de Luz',
  19: 'Escudo de Luz',
  20: 'Guantes de Luz',
  21: 'Botas de Luz',
  22: 'Anillo',
  23: 'Brazalete',
  24: 'Collar',
  25: 'Lapis',
  27: 'Consumible',
  28: 'Consumible',
  29: 'Objeto de misión',
  30: 'Consumible',
  31: 'Casco de Furia',
  32: 'Torso de Furia',
  33: 'Piernas de Furia',
  34: 'Escudo de Furia',
  35: 'Guantes de Furia',
  36: 'Botas de Furia',
  39: 'Capa',
  40: 'Capa',
  41: 'Capa',
  42: 'Montura',
  43: 'Etin',
  44: 'Consumible',
  67: 'Torso de Luz II',
  68: 'Piernas de Luz II',
  69: 'Escudo de Luz II',
  70: 'Guantes de Luz II',
  71: 'Botas de Luz II',
  82: 'Torso de Furia II',
  83: 'Piernas de Furia II',
  84: 'Escudo de Furia II',
  85: 'Guantes de Furia II',
  86: 'Botas de Furia II',
  94: 'Lapisia',
  95: 'Material',
  100: 'Consumible',
};
String itemCountryLabel(String? c) =>
    const {
      '0': 'Humano',
      '1': 'Elfo',
      '2': 'Luz',
      '3': 'Nordein',
      '4': 'Vail',
      '5': 'Furia',
      '6': 'Ambas',
    }[c] ??
    (c == null ? '—' : 'Código $c');
String foldedSearch(String s) {
  const a = 'áéíóúüñàèìòù', b = 'aeiouunaeiou';
  var result = s.toLowerCase();
  for (var i = 0; i < a.length; i++) {
    result = result.replaceAll(a[i], b[i]);
  }
  return result;
}

int compareEditorValues(String a, String b) {
  final x = BigInt.tryParse(a), y = BigInt.tryParse(b);
  if (x != null && y != null) return x.compareTo(y);
  final aa = RegExp(r'\d+|\D+')
      .allMatches(a.toLowerCase())
      .map((m) => m[0]!)
      .toList();
  final bb = RegExp(r'\d+|\D+')
      .allMatches(b.toLowerCase())
      .map((m) => m[0]!)
      .toList();
  for (var i = 0; i < aa.length && i < bb.length; i++) {
    final u = BigInt.tryParse(aa[i]), v = BigInt.tryParse(bb[i]);
    final r = u != null && v != null ? u.compareTo(v) : aa[i].compareTo(bb[i]);
    if (r != 0) return r;
  }
  return aa.length.compareTo(bb.length);
}

class RecordSummary {
  final int row;
  final String id, name, category;
  final Map<String, String> values;
  RecordSummary(this.row, this.id, this.name, this.category, this.values);
  factory RecordSummary.from(EditDocument doc, int row, {String? name}) {
    final v = {
      for (final f in doc.fields(row))
        if (f.spec.type != 'opaque') f.spec.name.toLowerCase(): doc.read(f),
    };
    final id = editorIdentityKey(v, doc.rows[row]);
    final title =
        v['name'] ??
        v['productname'] ??
        v['mobname'] ??
        v['itemname'] ??
        v['skillname'] ??
        v['mesh'] ??
        v['texture'] ??
        v['text'] ??
        name;
    final type = int.tryParse(v['itemtype'] ?? v['type'] ?? '');
    return RecordSummary(
      row,
      id,
      title?.isNotEmpty == true ? title! : '${doc.rows[row].kind} $id',
      editorDomain(doc.path) == EditorDomain.items
          ? itemCategories[type] ?? 'Tipo ${type ?? "—"}'
          : doc.rows[row].kind,
      v,
    );
  }
}

/// Each window owns a draft; validation is atomic and detects concurrent edits
/// to the same fields, without rejecting unrelated changes in another window.
class RecordDraft {
  final EditDocument document;
  final int row;
  final Map<String, FieldSpan> fields;
  final Map<String, String> before = {}, values = {};
  RecordDraft(this.document, this.row)
    : fields = {for (final f in document.fields(row)) f.spec.name: f} {
    for (final f in fields.values) {
      before[f.spec.name] = document.read(f);
      values[f.spec.name] = document.read(f);
    }
  }
  bool get dirty => values.entries.any((e) => e.value != before[e.key]);
  int get changes =>
      values.entries.where((e) => e.value != before[e.key]).length;
  void apply() {
    final changes = <(int, FieldSpan, String)>[];
    for (final e in values.entries) {
      if (e.value == before[e.key]) continue;
      final f = fields[e.key]!;
      if (document.read(f) != before[e.key]) {
        throw FormatException(
          '${e.key} cambió en otra ventana. Cierra y vuelve a abrir el registro para resolver el conflicto.',
        );
      }
      changes.add((row, f, e.value));
    }
    document.editMany(changes, title: 'Editar registro #${row + 1}');
    for (final f in fields.values) {
      before[f.spec.name] = document.read(f);
      values[f.spec.name] = document.read(f);
    }
  }

  EditDocument previewDocument() {
    final copy = reopenDocument(document, document.exportBytes());
    final edits = <(int, FieldSpan, String)>[];
    for (final f in copy.fields(row)) {
      final value = values[f.spec.name];
      if (value != null && value != before[f.spec.name]) {
        edits.add((row, f, value));
      }
    }
    copy.editMany(edits, title: 'Vista previa del borrador');
    return copy;
  }

  void reset() {
    values
      ..clear()
      ..addAll(before);
  }
}
