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
    'Anclajes 3D',
    'Texto',
    'Otros',
  ];
  static FieldMeaning of(String name) {
    final n = name.toLowerCase().replaceAll('_', '');
    final socket = RegExp(
      r'^attachment\[(\d+)\]\[(\d+)\]\.(.+)$',
    ).firstMatch(n);
    if (socket != null) {
      return FieldMeaning(
        'Anclaje ${socket[1]} · mano ${socket[2]} · ${socket[3]}',
        'Anclajes 3D',
        'Transformación original IT2. La rotación se guarda como cuaternión X/Y/Z/W, no como grados. El índice de hueso pertenece al esqueleto del perfil.',
      );
    }
    if (n.startsWith('animation.')) {
      return FieldMeaning(
        'Animación · ${const {'walk': 'Caminar', 'run': 'Correr', 'attack1': 'Ataque 1', 'attack2': 'Ataque 2', 'attack3': 'Ataque 3', 'death': 'Muerte', 'breathe': 'Respirar', 'damage': 'Recibir daño', 'idle': 'Reposo'}[n.substring(10)] ?? n.substring(10)}',
        'Habilidades',
        'Ruta ANI original del catálogo MON, conservada sin reemplazar otro gesto.',
      );
    }
    if (n.startsWith('parts[') ||
        n == 'mesh' ||
        n == 'texture' ||
        n == 'meshindex' ||
        n == 'textureindex') {
      return FieldMeaning(
        const {
              'mesh': 'Geometría',
              'texture': 'Textura',
              'meshindex': 'Índice de geometría',
              'textureindex': 'Índice de textura',
            }[n] ??
            name,
        'Identidad',
        'Referencia exacta a la malla o textura del catálogo; no se reasigna por parecido del nombre.',
      );
    }
    if (n == 'reqog') {
      return const FieldMeaning(
        'Intercambio / vinculación (ReqOg)',
        'Requisitos',
        'Semántica observada en clientes Shaiya: 0 permite intercambio; 1 se usa '
            'para objetos no intercambiables y 2 se ha usado para vinculación '
            'al personaje. La compatibilidad del valor 2 depende del servidor; '
            'otros valores se conservan sin reinterpretarlos.',
      );
    }
    if (_extra.containsKey(n)) {
      return FieldMeaning(
        _extra[n]!.$1,
        _extra[n]!.$2,
        'Valor original de $name. Se conserva su tipo y unidad del archivo.',
      );
    }
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
        'Coordenadas originales; SVMAP se instala en el servidor correspondiente. Guardar actualiza el origen abierto; Guardar como crea una copia.',
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

  static const _extra = <String, (String, String)>{
    'itemtype': ('Tipo de objeto', 'Identidad'),
    'itemtypeid': ('ID dentro del tipo', 'Identidad'),
    'str': ('Fuerza (STR)', 'Combate'),
    'dex': ('Destreza (DEX)', 'Combate'),
    'rec': ('Resistencia (REC)', 'Combate'),
    'int': ('Inteligencia (INT)', 'Combate'),
    'wis': ('Sabiduría (WIS)', 'Combate'),
    'luc': ('Suerte (LUC)', 'Combate'),
    'consthp': ('Bonificación de vida', 'Combate'),
    'constmp': ('Bonificación de maná', 'Combate'),
    'constsp': ('Bonificación de resistencia', 'Combate'),
    'quality': ('Durabilidad', 'Combate'),
    'slot': ('Ranuras', 'Otros'),
    'attrib': ('Atributo elemental', 'Combate'),
    'range': ('Alcance', 'Combate'),
    'attacktime': ('Tiempo / velocidad de ataque', 'Combate'),
    'attackplus': ('Ataque adicional', 'Combate'),
    'attackadd': ('Ataque adicional', 'Combate'),
    'attack': ('Ataque base', 'Combate'),
    'def': ('Defensa física', 'Combate'),
    'resist': ('Resistencia mágica', 'Combate'),
    'magic': ('Resistencia mágica', 'Combate'),
    'speed': ('Velocidad', 'Combate'),
    'drops': ('Distribución de botín', 'Botín y oro'),
    'grade': ('Grupo / grado', 'Botín y oro'),
    'skillpoint': ('Puntos de habilidad necesarios', 'Habilidades'),
    'point': ('Puntos necesarios', 'Habilidades'),
    'resettime': ('Recarga', 'Habilidades'),
    'readytime': ('Preparación', 'Habilidades'),
    'keeptime': ('Duración de efecto', 'Habilidades'),
    'applyrange': ('Radio de aplicación', 'Habilidades'),
    'attackrange': ('Alcance de ataque', 'Habilidades'),
    'successtype': ('Tipo de éxito', 'Habilidades'),
    'successvalue': ('Valor de éxito', 'Habilidades'),
    'targettype': ('Tipo de objetivo', 'Habilidades'),
    'typeattack': ('Tipo de ataque', 'Habilidades'),
    'typeeffect': ('Tipo de efecto', 'Habilidades'),
    'typeshow': ('Aprendizaje / visibilidad', 'Habilidades'),
    'count': ('Cantidad máxima', 'Otros'),
    'grow': ('Modo requerido', 'Requisitos'),
    'droprate': ('Tasa original de botín', 'Botín y oro'),
    'movedistance': ('Distancia de movimiento', 'Coordenadas'),
    'movespeed': ('Velocidad de movimiento', 'Coordenadas'),
    'height': ('Altura del modelo', 'Identidad'),
    'size': ('Tamaño', 'Identidad'),
    'npcid': ('ID del NPC', 'Identidad'),
    'npcname': ('Nombre del NPC', 'Texto'),
    'mobname': ('Nombre del monstruo', 'Texto'),
    'itemname': ('Nombre del objeto', 'Texto'),
    'bag': ('Categoría de tienda', 'Precios y tienda'),
    'welcomemessage': ('Mensaje de bienvenida', 'Texto'),
    'description': ('Descripción', 'Texto'),
    'desc': ('Descripción', 'Texto'),
    'reqlevel': ('Nivel requerido', 'Requisitos'),
    'reqstr': ('Fuerza requerida', 'Requisitos'),
    'reqdex': ('Destreza requerida', 'Requisitos'),
    'reqrec': ('Resistencia requerida', 'Requisitos'),
    'reqint': ('Inteligencia requerida', 'Requisitos'),
    'reqwis': ('Sabiduría requerida', 'Requisitos'),
    'reqluc': ('Suerte requerida', 'Requisitos'),
    'sound0': ('Sonido 1', 'Otros'),
    'sound1': ('Sonido 2', 'Otros'),
    'sound2': ('Sonido 3', 'Otros'),
    'sound3': ('Sonido 4', 'Otros'),
    'conststr': ('Bonificación STR', 'Combate'),
    'constdex': ('Bonificación DEX', 'Combate'),
    'constrec': ('Bonificación REC', 'Combate'),
    'constint': ('Bonificación INT', 'Combate'),
    'constwis': ('Bonificación WIS', 'Combate'),
    'constluc': ('Bonificación LUC', 'Combate'),
    'damagehp': ('Daño de vida', 'Habilidades'),
    'damagemp': ('Daño de maná', 'Habilidades'),
    'damagesp': ('Daño de resistencia', 'Habilidades'),
    'damage1': ('Daño 1', 'Habilidades'),
    'damage2': ('Daño 2', 'Habilidades'),
    'damage3': ('Daño 3', 'Habilidades'),
    'timedamagehp': ('Daño periódico de vida', 'Habilidades'),
    'timedamagemp': ('Daño periódico de maná', 'Habilidades'),
    'timedamagesp': ('Daño periódico de resistencia', 'Habilidades'),
    'timedamage1': ('Daño periódico 1', 'Habilidades'),
    'timedamage2': ('Daño periódico 2', 'Habilidades'),
    'timedamage3': ('Daño periódico 3', 'Habilidades'),
    'adddamagehp': ('Daño adicional de vida', 'Habilidades'),
    'adddamagemp': ('Daño adicional de maná', 'Habilidades'),
    'adddamagesp': ('Daño adicional de resistencia', 'Habilidades'),
    'adddamage1': ('Daño adicional 1', 'Habilidades'),
    'adddamage2': ('Daño adicional 2', 'Habilidades'),
    'adddamage3': ('Daño adicional 3', 'Habilidades'),
    'healhp': ('Curación de vida', 'Habilidades'),
    'healmp': ('Curación de maná', 'Habilidades'),
    'healsp': ('Curación de resistencia', 'Habilidades'),
    'heal1': ('Curación 1', 'Habilidades'),
    'heal2': ('Curación 2', 'Habilidades'),
    'heal3': ('Curación 3', 'Habilidades'),
    'timehealhp': ('Curación periódica de vida', 'Habilidades'),
    'timehealmp': ('Curación periódica de maná', 'Habilidades'),
    'timehealsp': ('Curación periódica de resistencia', 'Habilidades'),
    'timeheal1': ('Curación periódica 1', 'Habilidades'),
    'timeheal2': ('Curación periódica 2', 'Habilidades'),
    'timeheal3': ('Curación periódica 3', 'Habilidades'),
    'abilitytype1': ('Tipo de efecto 1', 'Habilidades'),
    'abilityvalue1': ('Valor de efecto 1', 'Habilidades'),
    'abilitytype2': ('Tipo de efecto 2', 'Habilidades'),
    'abilityvalue2': ('Valor de efecto 2', 'Habilidades'),
    'abilitytype3': ('Tipo de efecto 3', 'Habilidades'),
    'abilityvalue3': ('Valor de efecto 3', 'Habilidades'),
    'abilitytype4': ('Tipo de efecto 4', 'Habilidades'),
    'abilityvalue4': ('Valor de efecto 4', 'Habilidades'),
    'abilitytype5': ('Tipo de efecto 5', 'Habilidades'),
    'abilityvalue5': ('Valor de efecto 5', 'Habilidades'),
    'abilitytype6': ('Tipo de efecto 6', 'Habilidades'),
    'abilityvalue6': ('Valor de efecto 6', 'Habilidades'),
    'abilitytype7': ('Tipo de efecto 7', 'Habilidades'),
    'abilityvalue7': ('Valor de efecto 7', 'Habilidades'),
    'abilitytype8': ('Tipo de efecto 8', 'Habilidades'),
    'abilityvalue8': ('Valor de efecto 8', 'Habilidades'),
    'abilitytype9': ('Tipo de efecto 9', 'Habilidades'),
    'abilityvalue9': ('Valor de efecto 9', 'Habilidades'),
    'abilitytype10': ('Tipo de efecto 10', 'Habilidades'),
    'abilityvalue10': ('Valor de efecto 10', 'Habilidades'),
  };
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
  if (values['npctype'] != null && values['npctypeid'] != null) {
    return '${values['npctype']}:${values['npctypeid']}';
  }
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
