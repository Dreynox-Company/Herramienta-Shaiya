/// Authored local playtest rules, deliberately versioned independently of the
/// original game's/server's balance. These values are not reverse-engineered.
class LocalRules {
  final int killExperience, goldReward, healCost;
  final double healAmount;
  const LocalRules({
    this.killExperience = 25,
    this.goldReward = 5,
    this.healCost = 10,
    this.healAmount = 250,
  });
  factory LocalRules.parse(Map<String, dynamic> json) {
    int value(String key, int fallback, int max) {
      final x = json[key] ?? fallback;
      if (x is! int || x < 0 || x > max) {
        throw FormatException('Regla local inválida: $key');
      }
      return x;
    }

    if (json['schema'] != 1) {
      throw const FormatException('Esquema de reglas desconocido.');
    }
    return LocalRules(
      killExperience: value('killExperience', 25, 100000),
      goldReward: value('goldReward', 5, 100000),
      healCost: value('healCost', 10, 100000),
      healAmount: value('healAmount', 250, 1000).toDouble(),
    );
  }
  Map<String, Object?> toJson() => {
    'schema': 1,
    'killExperience': killExperience,
    'goldReward': goldReward,
    'healCost': healCost,
    'healAmount': healAmount.toInt(),
  };
}

class LocalProgress {
  int level = 1,
      experience = 0,
      gold = 0,
      victories = 0,
      deaths = 0,
      potions = 3;
  double seconds = 0;
  final Set<String> _credited = {};
  int get requiredExperience => 100 + 50 * (level - 1);
  LocalProgress();
  factory LocalProgress.parse(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Partida de otro motor/esquema.');
    }
    int read(String key, int min, int max) {
      final n = json[key];
      if (n is! int || n < min || n > max) {
        throw FormatException('Partida inválida: $key');
      }
      return n;
    }

    final p = LocalProgress()
      ..level = read('level', 1, 1000)
      ..experience = read('experience', 0, 1000000000)
      ..gold = read('gold', 0, 2000000000)
      ..victories = read('victories', 0, 1000000000)
      ..deaths = read('deaths', 0, 1000000000)
      ..potions = read('potions', 0, 9999);
    final time = json['seconds'];
    if (time is! num || !time.isFinite || time < 0 || time > 1e10) {
      throw const FormatException('Tiempo inválido.');
    }
    p.seconds = time.toDouble();
    if (p.experience >= p.requiredExperience && p.level < 1000) {
      throw const FormatException('Experiencia no normalizada.');
    }
    return p;
  }
  bool defeat(String encounterId, LocalRules rules) {
    if (encounterId.isEmpty || _credited.contains(encounterId)) return false;
    _credited.add(encounterId);
    if (_credited.length > 4096) _credited.remove(_credited.first);
    victories++;
    gold = (gold + rules.goldReward).clamp(0, 2000000000);
    experience += rules.killExperience;
    while (level < 1000 && experience >= requiredExperience) {
      experience -= requiredExperience;
      level++;
    }
    if (level == 1000) experience = experience.clamp(0, requiredExperience - 1);
    return true;
  }

  bool buyPotion(LocalRules rules) {
    if (gold < rules.healCost || potions >= 9999) return false;
    gold -= rules.healCost;
    potions++;
    return true;
  }

  double consumePotion(double health, LocalRules rules) {
    if (!health.isFinite || health <= 0 || health >= 1000 || potions == 0) {
      return health;
    }
    potions--;
    return (health + rules.healAmount).clamp(0, 1000);
  }

  void advance(double dt) {
    if (dt.isFinite && dt > 0) seconds += dt.clamp(0, .25);
  }

  Map<String, Object?> toJson() => {
    'schema': 1,
    'level': level,
    'experience': experience,
    'gold': gold,
    'victories': victories,
    'deaths': deaths,
    'potions': potions,
    'seconds': seconds,
  };
}
