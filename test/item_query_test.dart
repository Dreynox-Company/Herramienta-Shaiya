import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/editor/item_query.dart';
import 'package:herramienta_shaiya/editor/item_semantics.dart';
import 'fixtures/item_workspace_fixture.dart';

void main() {
  final w = memoryItems(), fields = w.byKey.values.first.values.keys.toSet();
  List<String> search(String query) {
    final q = ItemQuery.parse(query, fields);
    return w.items.where(q.matches).map((i) => i.key).toList();
  }

  test('names retain accents while search is accent and case insensitive', () {
    expect(search('angeles'), ['121:1']);
    expect(search('ANTIPIRETICO'), ['128:1']);
    expect(search('manzana'), ['25:1']);
  });
  test('quoted names, exact typed ID and description predicates work', () {
    expect(search('nombre~"espada larga"'), ['1:1']);
    expect(search('id=95:1'), ['95:1']);
    expect(search('descripcion~"restaura 119"'), ['25:1']);
    expect(search('Lapisia itemtype=95'), ['95:1']);
  });
  test('numeric comparisons retain values beyond double exactness', () {
    expect(search('arg3>9223372036854774999'), ['1:1']);
    expect(search('arg3=9223372036854775000'), ['1:1']);
    expect(search('arg3=9223372036854775001'), isEmpty);
    expect(search('level>=60 conststr>0'), ['121:1']);
  });
  test('unknown property or malformed query is reported, never ignored', () {
    for (final q in [
      'inventado>3',
      'level>not-a-number',
      'nombre>4',
      'nombre~"sin cerrar',
    ]) {
      expect(() => ItemQuery.parse(q, fields), throwsFormatException);
    }
  });
  test(
    'absent numeric fields do not accidentally satisfy a less-than predicate',
    () {
      final q = ItemQuery.parse('missing<0', {...fields, 'missing'});
      expect(w.items.where(q.matches), isEmpty);
    },
  );
  test(
    'categories agree with audited supplied items instead of the old generic labels',
    () {
      expect(ItemSemantics.kind(25), 'Consumibles y servicios');
      expect(ItemSemantics.kind(30), 'Lapis');
      expect(ItemSemantics.kind(95), 'Lapisia');
      expect(ItemSemantics.kind(125), 'Monturas');
      expect(ItemSemantics.category(11), contains('Jabalinas'));
      expect(ItemSemantics.category(13), contains('Arcos'));
      expect(ItemSemantics.field(1, 'effect2').label, contains('Amplitud'));
      expect(ItemSemantics.field(95, 'rec').help, contains('0.1.2'));
      for (final f in itemFields) {
        expect(ItemSemantics.field(25, f).label, isNotEmpty);
      }
    },
  );
}
