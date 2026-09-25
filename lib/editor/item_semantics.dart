import '../core/native_item_icons.dart';
import 'field_semantics.dart';

/// Presentation metadata only. Unknown native fields are never removed from
/// the editor, relabeled as an invented mechanic, or normalized on save.
class ItemSemantics {
  static String category(int type) {
    final family = NativeItemIcons.family(type);
    final base = const {
      1: 'Espadas de una mano',
      2: 'Espadas de dos manos',
      3: 'Hachas de una mano',
      4: 'Hachas de dos manos',
      5: 'Armas dobles',
      6: 'Lanzas',
      7: 'Mazas',
      8: 'Martillos',
      9: 'Cuchillas',
      10: 'Dagas',
      11: 'Jabalinas',
      12: 'Bastones',
      13: 'Arcos',
      14: 'Ballestas',
      15: 'Garras',
      16: 'Cascos de Luz',
      17: 'Torsos de Luz',
      18: 'Piernas de Luz',
      19: 'Escudos de Luz',
      20: 'Guantes de Luz',
      21: 'Botas de Luz',
      22: 'Anillos',
      23: 'Amuletos',
      24: 'Capas de Luz',
      25: 'Consumibles y materiales',
      27: 'Misiones y materiales',
      28: 'Misiones y materiales',
      29: 'Misiones y materiales',
      30: 'Lapis',
      31: 'Cascos de Furia',
      32: 'Torsos de Furia',
      33: 'Piernas de Furia',
      34: 'Escudos de Furia',
      35: 'Guantes de Furia',
      36: 'Botas de Furia',
      39: 'Capas de Furia',
      40: 'Brazaletes',
      42: 'Monturas',
      95: 'Lapisia',
      100: 'Consumibles y servicios',
      120: 'Mascotas',
      121: 'Alas',
      150: 'Trajes',
    }[family];
    return base == null ? 'Otros · tipo $type' : '$base · tipo $type';
  }

  static String kind(int type) {
    final f = NativeItemIcons.family(type);
    if (f >= 1 && f <= 15) return 'Armas';
    if ((f >= 16 && f <= 21) || (f >= 31 && f <= 36)) return 'Armaduras';
    if (const {22, 23, 24, 39, 40}.contains(f)) return 'Accesorios';
    return switch (f) {
      121 => 'Alas',
      42 => 'Monturas',
      120 => 'Mascotas',
      150 => 'Trajes',
      30 => 'Lapis',
      95 => 'Lapisia',
      27 || 28 || 29 => 'Misiones y materiales',
      25 || 100 => 'Consumibles y servicios',
      _ => 'Otros',
    };
  }

  static const groups = [
    'Todos los campos',
    'Nombre y aspecto',
    'Requisitos',
    'Combate y estadísticas',
    'Uso y efectos',
    'Economía y obtención',
    'Parámetros de versión',
  ];
  static FieldMeaning field(int type, String name) {
    final n = name.toLowerCase();
    final kindName = kind(type);
    const original =
        'Se conserva el valor, tipo y unidad nativos. '
        'Cambiar DATA del cliente no cambia por sí solo el servidor.';
    if (const {
      'itemtype',
      'itemtypeid',
      'name',
      'itemname',
      'text',
      'description',
      'icon',
      'image',
      'dyeingtype',
      'weaponpart',
    }.contains(n)) {
      return FieldMeaning(
        const {
              'itemtype': 'Tipo',
              'itemtypeid': 'ID del objeto',
              'icon': 'Icono nativo (base 1)',
              'image': 'Modelo / entrada del catálogo',
              'itemname': 'Nombre dentro del juego',
              'name': 'Nombre',
              'text': 'Descripción dentro del juego',
              'description': 'Descripción',
              'dyeingtype': 'Tipo de teñido',
              'weaponpart': 'Parte de arma',
            }[n] ??
            name,
        'Nombre y aspecto',
        original,
      );
    }
    if (const {'effect1', 'effect2', 'effect3', 'effect4'}.contains(n) &&
        const {
          'Armas',
          'Armaduras',
          'Accesorios',
          'Lapis',
          'Alas',
        }.contains(kindName)) {
      return FieldMeaning(
        const {
          'effect1': 'Daño base mínimo',
          'effect2': 'Amplitud de daño (mínimo + amplitud = máximo base)',
          'effect3': 'Defensa',
          'effect4': 'Resistencia mágica',
        }[n]!,
        'Combate y estadísticas',
        'Correspondencia del backend offline 0.1.2 suministrado: '
            'Effect1=MinAttack, Effect2=PlusAttack, Effect3=Defense, Effect4=Resistance. '
            'No es una fórmula universal para cualquier Special o servidor. '
            'El backend convierte estos cuatro valores a ushort (0..65535). $original',
      );
    }
    if (n == 'rec' && kindName == 'Lapisia') {
      return FieldMeaning(
        'Tasa de encantamiento · Rec',
        'Uso y efectos',
        'En el backend 0.1.2, Rec se expone como EnchantRate; un valor positivo '
            'se multiplica por 100 antes del cálculo sobre 10000. Cero delega en '
            'la configuración de encantamiento. Otros servidores deben verificarse. $original',
      );
    }
    if (n.startsWith('const')) {
      final resource = const {
        'consthp': 'HP / vida',
        'constmp': 'MP / maná',
        'constsp': 'SP / resistencia',
      }[n];
      final label = resource == null
          ? (const {
                  'conststr': 'Fuerza',
                  'constdex': 'Destreza',
                  'constrec': 'Resistencia',
                  'constint': 'Inteligencia',
                  'constwis': 'Sabiduría',
                  'constluc': 'Suerte',
                }[n] ??
                name)
          : kindName == 'Consumibles y servicios'
          ? '$resource · valor de uso'
          : '$resource · bonificación';
      return FieldMeaning(label, 'Combate y estadísticas', original);
    }
    if (n.startsWith('req') ||
        const {
          'level',
          'maxlevel',
          'country',
          'grow',
          'attackfighter',
          'defensefighter',
          'patrolrogue',
          'shootrogue',
          'attackmage',
          'defensemage',
          'str',
          'dex',
          'rec',
          'int',
          'wis',
          'luc',
          'vg',
          'og',
          'ig',
        }.contains(n)) {
      return FieldMeaning(
        const {
              'level': 'Nivel requerido',
              'maxlevel': 'Nivel máximo',
              'country': 'Raza / facción',
              'grow': 'Modo',
              'attackfighter': 'Luchador / Guerrero',
              'defensefighter': 'Defensor / Guardián',
              'patrolrogue': 'Ranger / Asesino',
              'shootrogue': 'Arquero / Cazador',
              'attackmage': 'Mago / Pagano',
              'defensemage': 'Sacerdote / Oráculo',
            }[n] ??
            '$name · código nativo',
        'Requisitos',
        'Algunos requisitos se reutilizan para otras funciones '
            'según el tipo y la versión. No se interpretan todos como bonificaciones. $original',
      );
    }
    if (n.startsWith('effect') ||
        const {
          'range',
          'attacktime',
          'attrib',
          'slot',
          'quality',
          'speed',
          'attack',
          'attackplus',
          'def',
          'resist',
        }.contains(n)) {
      final effects = n.startsWith('effect');
      return FieldMeaning(
        effects
            ? '$name · ${kindName == 'Armas' ? 'parámetro de ataque' : 'efecto nativo'}'
            : FieldMeaning.of(name).label,
        kindName == 'Armas' || kindName == 'Armaduras'
            ? 'Combate y estadísticas'
            : 'Uso y efectos',
        effects
            ? 'Los campos Effect dependen del tipo. Se muestran completos, '
                  'sin inventar daño mínimo/máximo, probabilidades o efectos de misión. $original'
            : original,
      );
    }
    if (const {
      'buy',
      'sell',
      'grade',
      'drop',
      'server',
      'buymethod',
      'moneytype',
    }.contains(n)) {
      return FieldMeaning(
        FieldMeaning.of(name).label,
        'Economía y obtención',
        original,
      );
    }
    if (const {
      'count',
      'special',
      'exp',
      'duration',
      'extduration',
      'secoption',
      'optionrate',
      'usecontype',
      'useconvar',
      'itemskill',
      'itemupgrade',
      'casttime',
      'genecount',
      'spellbookexp',
      'spellbookdurability',
    }.contains(n)) {
      return FieldMeaning(
        const {
              'count': 'Cantidad máxima',
              'duration': 'Duración',
              'extduration': 'Duración adicional',
              'itemskill': 'Habilidad del objeto',
              'itemupgrade': 'Mejora del objeto',
              'casttime': 'Tiempo de uso / lanzamiento',
              'usecontype': 'Condición de uso · tipo',
              'useconvar': 'Condición de uso · valor',
              'special': 'Comportamiento especial',
              'exp': 'Experiencia',
              'spellbookexp': 'Experiencia del libro',
              'spellbookdurability': 'Durabilidad del libro',
            }[n] ??
            name,
        'Uso y efectos',
        original,
      );
    }
    return FieldMeaning(
      name,
      'Parámetros de versión',
      'Campo nativo sin semántica confirmada para este cliente. Editable según '
          'el tipo binario; no se le atribuye un significado inventado.',
    );
  }
}
