import '../data/item_workspace.dart';
import 'workbench_model.dart';

/// AND queries: text/name/ID plus native field comparisons. Numeric predicates
/// use BigInt, not lossy double coercion of the int64 SData values.
class ItemQuery {
  final List<bool Function(ItemEntry)> _predicates;
  ItemQuery._(this._predicates);
  factory ItemQuery.parse(String input, Set<String> fields) {
    if (input.length > 4096)
      throw const FormatException('Búsqueda demasiado larga.');
    final tokens = <String>[];
    final out = StringBuffer();
    var quoted = false, escape = false;
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (escape) {
        out.write(char);
        escape = false;
        continue;
      }
      if (char == '\\' && quoted) {
        escape = true;
        continue;
      }
      if (char == '"') {
        quoted = !quoted;
        continue;
      }
      if (RegExp(r'\s').hasMatch(char) && !quoted) {
        if (out.isNotEmpty) {
          tokens.add(out.toString());
          out.clear();
        }
      } else {
        out.write(char);
      }
    }
    if (quoted || escape)
      throw const FormatException('Falta cerrar una comilla en la búsqueda.');
    if (out.isNotEmpty) tokens.add(out.toString());
    if (tokens.length > 32)
      throw const FormatException('Máximo 32 condiciones de búsqueda.');
    final predicates = <bool Function(ItemEntry)>[];
    for (final token in tokens) {
      final match = RegExp(
        r'^([a-zA-Z_][a-zA-Z_0-9]*)(>=|<=|!=|=|>|<|~)(.*)$',
      ).firstMatch(token);
      if (match == null) {
        final folded = foldedSearch(token);
        predicates.add((item) => item.searchText.contains(folded));
        continue;
      }
      final field = match[1]!.toLowerCase(), op = match[2]!, wanted = match[3]!;
      if (!fields.contains(field) &&
          !const {
            'name',
            'nombre',
            'description',
            'descripcion',
            'id',
          }.contains(field)) {
        throw FormatException(
          'Campo desconocido: $field. Usa el nombre nativo visible en Propiedades.',
        );
      }
      final text = const {
        'name',
        'nombre',
        'description',
        'descripcion',
        'id',
      }.contains(field);
      final number = BigInt.tryParse(wanted);
      if (!text && op != '~' && number == null) {
        throw FormatException('$field requiere un entero para $op.');
      }
      if (text && !const {'=', '!=', '~'}.contains(op)) {
        throw const FormatException('El texto admite =, != o ~ (contiene).');
      }
      predicates.add((item) {
        final value = switch (field) {
          'name' || 'nombre' => item.name,
          'description' || 'descripcion' => item.description,
          'id' => item.key,
          _ => item.values[field] ?? '',
        };
        if (!text && !item.values.containsKey(field)) return false;
        if (op == '~')
          return foldedSearch(value).contains(foldedSearch(wanted));
        if (!text && BigInt.tryParse(value) == null) return false;
        final comparison = text
            ? foldedSearch(value).compareTo(foldedSearch(wanted))
            : (BigInt.tryParse(value)?.compareTo(number!) ?? -2);
        return switch (op) {
          '=' => comparison == 0,
          '!=' => comparison != 0,
          '>' => comparison > 0,
          '>=' => comparison >= 0,
          '<' => comparison < 0,
          '<=' => comparison <= 0,
          _ => false,
        };
      });
    }
    return ItemQuery._(predicates);
  }
  bool matches(ItemEntry item) => _predicates.every((test) => test(item));
}
