import 'formats.dart';

// Identificadores contrastados con ItemType/MotionType del cliente EP6.
int weaponFamily(WeaponRecord? weapon) {
  if (weapon == null) return 0;
  final name = weapon.source.replaceAll('\\', '/').split('/').last;
  return int.tryParse(RegExp(r'^\d+').stringMatch(name) ?? '') ?? 0;
}

const weaponNames = {
  1: 'Espada de una mano',
  2: 'Espada de dos manos',
  3: 'Hacha de una mano',
  4: 'Hacha de dos manos',
  5: 'Armas dobles',
  6: 'Lanza',
  7: 'Maza de una mano',
  8: 'Maza de dos manos',
  9: 'Daga invertida',
  10: 'Daga',
  11: 'Jabalina',
  12: 'Bastón',
  13: 'Arco',
  14: 'Ballesta',
  15: 'Garras',
  19: 'Escudo de la Luz',
  34: 'Escudo de la Furia',
};
String weaponLabel(WeaponRecord w) =>
    '${weaponNames[weaponFamily(w)] ?? 'Equipo'} · ${w.id}';
int? motionIndex(String path) {
  final match = RegExp(r'_(\d{3})_').firstMatch(path);
  return match == null ? null : int.tryParse(match.group(1)!);
}

int? readyMotion(int family) => switch (family) {
  1 || 3 || 7 => 34,
  2 || 4 || 8 => 23,
  5 => 41,
  6 => 48,
  9 => 64,
  10 => 78,
  11 => 55,
  12 => 59,
  13 || 14 => 30,
  15 => 71,
  _ => null,
};
List<int> attackMotions(int family) {
  final ready = readyMotion(family);
  if (ready == null) return [];
  final count = [11, 13, 14].contains(family)
      ? 1
      : family == 12
      ? 2
      : 4;
  return List.generate(count, (i) => ready + 1 + i);
}

int? damageMotion(int family) {
  final ready = readyMotion(family);
  if (ready == null) return null;
  return ready +
      ([11, 13, 14].contains(family)
          ? 2
          : family == 12
          ? 3
          : 5);
}

const motionNames = {
  0: 'Reposo',
  1: 'Caminar',
  2: 'Correr',
  3: 'Paso atrás',
  4: 'Paso lateral izquierdo',
  5: 'Paso lateral derecho',
  6: 'Reposo en el agua',
  7: 'Nadar',
  8: 'Saltar',
  9: 'Caída',
  10: 'Sentarse',
  11: 'Levantarse',
  12: 'Descansar sentado',
  13: 'Esquiva hacia atrás',
  14: 'Esquiva izquierda',
  15: 'Esquiva derecha',
  16: 'Gesto de reposo 1',
  17: 'Gesto de reposo 2',
  18: 'Escalar',
  19: 'Presentación',
  20: 'Montura en movimiento',
  21: 'Reposo en montura',
  22: 'Tabla de nieve',
  23: 'Guardia · dos manos',
  30: 'Guardia · arco',
  34: 'Guardia · una mano',
  41: 'Guardia · armas dobles',
  48: 'Guardia · lanza',
  55: 'Guardia · jabalina',
  59: 'Guardia · bastón',
  64: 'Guardia · daga invertida',
  71: 'Guardia · garras',
  78: 'Guardia · daga',
  116: 'Súplica',
  117: 'Victoria',
  118: 'Risa',
  119: 'Amor',
  120: 'Saludo',
  121: 'Aplauso',
  122: 'Derrota',
  123: 'Inicio',
  124: 'Insulto',
  125: 'Provocación',
};
String translatedMotion(String path) {
  final index = motionIndex(path), name = path.toLowerCase();
  if (motionNames.containsKey(index)) return motionNames[index]!;
  if (index != null && index >= 100 && index <= 115) {
    return 'Habilidad · $index';
  }
  for (final type in [1, 2, 5, 6, 9, 10, 11, 12, 13, 15]) {
    if (attackMotions(type).contains(index)) {
      return 'Ataque ${attackMotions(type).indexOf(index!) + 1} · ${weaponNames[type]}';
    }
    if (damageMotion(type) == index) return 'Daño · ${weaponNames[type]}';
  }
  if (name.contains('run')) return 'Correr con equipo';
  if (name.contains('attack')) return 'Acción de ataque';
  if (name.contains('ready') || name.contains('roop')) {
    return 'Canalización de habilidad';
  }
  return 'Animación ${index ?? ''}';
}

int? runningMotion(int family) => switch (family) {
  1 || 3 || 7 => 40,
  2 || 4 || 8 => 29,
  5 => 47,
  6 => 54,
  9 => 70,
  10 => 84,
  11 => 58,
  12 => 63,
  13 || 14 => 33,
  15 => 77,
  _ => null,
};
