import 'document.dart';

/// Display metadata never changes the binary schema. Keep original captions
/// visible beside translated ones, including fields with unknown semantics.
class FieldMeaning {
  final String label, group, help;
  const FieldMeaning(this.label, this.group, this.help);
  static const groups = [
    'Todos',
    'Identidad',
    'Botín y oro',
    'Precios y tienda',
    'Combate',
    'Habilidades',
    'Requisitos',
    'Coordenadas',
    'Texto',
    'Otros',
  ];
  static FieldMeaning of(String name) {
    final n = name.toLowerCase().replaceAll('_', '');
    final drop = RegExp(r'^itemdroprate(\d+)$').firstMatch(n);
    if (drop != null) {
      return FieldMeaning(
        'Tasa de botín · espacio ${drop[1]}',
        'Botín y oro',
        'Unidad entera original. No se convierte automáticamente a porcentaje. El servidor debe usar una regla compatible.',
      );
    }
    final slot = RegExp(r'^item(\d+)$').firstMatch(n);
    if (slot != null) {
      return FieldMeaning(
        'Referencia de botín · espacio ${slot[1]}',
        'Botín y oro',
        'Referencia original del espacio de botín. Puede identificar un grupo/Grade, no necesariamente un ItemID. Verifica la tabla de drops del servidor.',
      );
    }
    if (n == 'money1' || n == 'money2') {
      return FieldMeaning(
        n == 'money1' ? 'Oro mínimo (Money1)' : 'Oro máximo (Money2)',
        'Botín y oro',
        'Valor original de la tabla. Esta edición de DATA no instala ni cambia automáticamente la base de datos del servidor.',
      );
    }
    if (n == 'buy' ||
        n == 'sell' ||
        n.contains('price') ||
        n.contains('cost') ||
        n == 'money' ||
        n.contains('productcount') ||
        n.startsWith('inventory') ||
        n.startsWith('itemid') ||
        n.startsWith('itemcount') ||
        n.startsWith('product')) {
      return FieldMeaning(
        _labels[n] ?? name,
        'Precios y tienda',
        'Distingue compra, venta al NPC y tienda premium. Se conserva el tipo numérico original y se requiere coherencia con el servidor.',
      );
    }
    if (n == 'name' ||
        n == 'text' ||
        n.contains('message') ||
        n.contains('description') ||
        n.contains('summary')) {
      return FieldMeaning(
        _labels[n] ?? name,
        'Texto',
        'La codificación debe corresponder al archivo y al cliente. La interfaz admite Unicode; al guardar se rechazan caracteres que el formato elegido no puede representar.',
      );
    }
    if (n.contains('position') ||
        n.startsWith('min.') ||
        n.startsWith('max.') ||
        n == 'factionorportalid' ||
        n.contains('mapid') ||
        n.endsWith('.yaw')) {
      return FieldMeaning(
        _labels[n] ?? name,
        'Coordenadas',
        'Coordenadas originales; SVMAP se instala en el servidor correspondiente. Los cambios se guardan en una copia.',
      );
    }
    if (n.contains('skill') ||
        n.contains('ability') ||
        n == 'cooltime' ||
        n == 'keep' ||
        n == 'skillpoint') {
      return FieldMeaning(
        _labels[n] ?? name,
        'Habilidades',
        'Parámetro de habilidad en su unidad original. No se inventan conversiones de tiempo, distancia o porcentaje.',
      );
    }
    if (const {
      'attackfighter',
      'defensefighter',
      'patrolrogue',
      'shootrogue',
      'attackmage',
      'defensemage',
    }.contains(n)) {
      return FieldMeaning(
        _labels[n] ?? name,
        'Requisitos',
        'Restricción de clase original del cliente.',
      );
    }
    if (n.contains('attack') ||
        n.contains('defense') ||
        n.contains('damage') ||
        [
          'hp',
          'sp',
          'mp',
          'exp',
          'dex',
          'wis',
          'luc',
          'str',
          'rec',
          'int',
          'magic',
          'ai',
          'normaltime',
          'chaserange',
          'chasetime',
          'chasestep',
        ].contains(n)) {
      return FieldMeaning(
        _labels[n] ?? name,
        'Combate',
        'Dato original de combate. Los valores efectivos online pueden ser validados o calculados por el servidor.',
      );
    }
    if (n.contains('level') ||
        n.contains('req') ||
        [
          'fighter',
          'defender',
          'ranger',
          'archer',
          'mage',
          'priest',
          'country',
          'faction',
          'grow',
          'mode',
          'mal esex',
          'malesex',
          'femalesex',
        ].contains(n)) {
      return FieldMeaning(
        _labels[n] ?? name,
        'Requisitos',
        'Se preservan códigos y restricciones originales. No se confunde clase con sexo del modelo.',
      );
    }
    if ([
      'id',
      'type',
      'typeid',
      'index',
      'model',
      'modelid',
      'image',
      'icon',
      'grade',
      'npctype',
      'npctypeid',
      'np cid',
      'mobid',
      'goodsid',
    ].contains(n)) {
      return FieldMeaning(
        _labels[n] ?? name,
        'Identidad',
        'Identificador o referencia. Comprueba relaciones con las otras tablas antes de cambiarlo.',
      );
    }
    return FieldMeaning(
      _labels[n] ?? name,
      'Otros',
      'Campo conservado con su nombre y tipo originales. Su significado depende de la versión del cliente; no se presupone.',
    );
  }

  static const _labels = <String, String>{
    'id': 'Identificador',
    'name': 'Nombre',
    'text': 'Descripción',
    'type': 'Tipo',
    'typeid': 'ID dentro del tipo',
    'index': 'Índice',
    'model': 'Modelo',
    'modelid': 'ID de modelo',
    'image': 'Modelo visual',
    'icon': 'Icono',
    'grade': 'Grupo / Grade',
    'buy': 'Precio de compra',
    'sell': 'Precio de venta al NPC',
    'attackfighter': 'Luchador / Guerrero',
    'defensefighter': 'Defensor / Guardián',
    'patrolrogue': 'Ranger / Asesino',
    'shootrogue': 'Arquero / Cazador',
    'attackmage': 'Mago / Pagano',
    'defensemage': 'Sacerdote / Oráculo',
    'buyprice': 'Precio de compra',
    'sellprice': 'Precio de venta al NPC',
    'buycost': 'Costo de compra',
    'cost': 'Costo',
    'money': 'Oro',
    'exp': 'Experiencia',
    'hp': 'Vida (HP)',
    'sp': 'Resistencia (SP)',
    'mp': 'Maná (MP)',
    'ai': 'Comportamiento (AI)',
    'level': 'Nivel',
    'minlevel': 'Nivel mínimo',
    'maxlevel': 'Nivel máximo',
    'faction': 'Facción',
    'country': 'Facción / país',
    'fighter': 'Luchador / Guerrero',
    'defender': 'Defensor / Guardián',
    'ranger': 'Ranger / Asesino',
    'archer': 'Arquero / Cazador',
    'mage': 'Mago / Pagano',
    'priest': 'Sacerdote / Oráculo',
    'cooltime': 'Recarga',
    'skillpoint': 'Costo de puntos',
    'productname': 'Nombre del producto',
    'productcode': 'Código del producto',
    'description': 'Descripción',
    'npctype': 'Tipo de NPC',
    'npctypeid': 'ID del NPC',
    'merchanttype': 'Tipo de comerciante',
    'blessvalue': 'Bendición de la diosa',
  };
}

List<String> rowWarnings(EditDocument doc, int row) {
  final fields = doc.fields(row), warnings = <String>[];
  final values = {
    for (final f in fields) f.spec.name.toLowerCase(): doc.read(f),
  };
  for (final f in fields) {
    if (f.spec.type == 'opaque') continue;
    final value = doc.read(f), n = f.spec.name.toLowerCase();
    if (value.startsWith('-') &&
        (n == 'buy' ||
            n == 'sell' ||
            n.contains('money') ||
            n.contains('price') ||
            n.contains('cost') ||
            n.contains('rate'))) {
      warnings.add(
        '${f.spec.name}: negativo representable en ${f.spec.type}, pero su significado en el juego debe verificarse (sentinela, penalización o dato no válido).',
      );
    }
  }
  final low = BigInt.tryParse(values['money1'] ?? ''),
      high = BigInt.tryParse(values['money2'] ?? '');
  if (low != null && high != null && low > high) {
    warnings.add(
      'Money1 es mayor que Money2. Revisa el intervalo de oro antes de exportar.',
    );
  }
  return warnings;
}

/// Classic and DB tables use different captions for the same six class flags.
/// Missing flags are not interpreted as universal permission.
bool editorMatchesClass(Map<String, String> values, String selected) {
  if (selected == 'Todas') return true;
  const aliases = {
    'fighter': ['fighter', 'attackfighter'],
    'defender': ['defender', 'defensefighter'],
    'ranger': ['ranger', 'patrolrogue'],
    'archer': ['archer', 'shootrogue'],
    'mage': ['mage', 'attackmage'],
    'priest': ['priest', 'defensemage'],
  };
  for (final key
      in aliases[selected.toLowerCase()] ?? [selected.toLowerCase()]) {
    final value = BigInt.tryParse(values[key] ?? '');
    if (value != null) return value > BigInt.zero;
  }
  return false;
}

String editorIdentityKey(Map<String, String> values, RecordRef record) {
  final type = values['itemtype'] ?? values['type'];
  final item = values['itemtypeid'] ?? values['typeid'];
  if (type != null && item != null) return '$type:$item';
  final id =
      values['id'] ??
      values['mobid'] ??
      values['index'] ??
      values['goods_id'] ??
      values['npctypeid'];
  final level = values['skilllevel'];
  if (level != null) return '${id ?? record.group + 1}:$level';
  if (id != null) return id;
  if (record.kind == 'Criatura') return '${record.ordinal + 1}';
  return '${record.group + 1}:${record.ordinal + 1}';
}
