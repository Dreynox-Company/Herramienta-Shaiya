import 'dart:math' as math;

/// Each pending impact captures a target ID. Switching selection never transfers
/// damage to a different creature, and removing an actor cancels its hits.
class Combat {
  double playerHealth = 1000, maxHealth = 1000;
  double damage = 90,
      enemyDamage = 45,
      range = 2.5,
      cooldown = 1.1,
      attackDuration = 1;
  bool active = false, automatic = false, counterattack = true;
  String target = 'default';
  final Map<String, double> health = {'default': 1000};
  final Map<String, double> _enemyCooldown = {};
  final Set<String> _engaged = {};
  double _clock = 0, _nextPlayer = 0;
  final List<_Hit> _pending = [];
  void Function(String actor, String event)? onEvent;
  void Function(String id, String actor, String event)? onTargetEvent;
  double Function(String id)? distanceToTarget;
  final List<String> log = [];
  double get enemyHealth => health[target] ?? 0;
  set enemyHealth(double value) => health[target] = value;
  double get cooldownRemaining => math.max(0, _nextPlayer - _clock);
  bool get alive => playerHealth > 0 && enemyHealth > 0;
  void addTarget(String id) {
    health.putIfAbsent(id, () => maxHealth);
  }

  void selectTarget(String id) {
    if (!health.containsKey(id)) {
      throw ArgumentError('Objetivo no registrado: $id');
    }
    target = id;
    automatic = false;
  }

  void removeTarget(String id) {
    health.remove(id);
    _engaged.remove(id);
    _enemyCooldown.remove(id);
    _pending.removeWhere((h) => h.target == id);
    if (target == id) target = health.keys.firstOrNull ?? '';
  }

  void reset() {
    playerHealth = maxHealth;
    for (final id in health.keys.toList()) {
      health[id] = maxHealth;
    }
    active = false;
    automatic = false;
    _clock = 0;
    _nextPlayer = 0;
    _enemyCooldown.clear();
    _engaged.clear();
    _pending.clear();
    log.clear();
  }

  void cancelActions() {
    automatic = false;
    active = false;
    _pending.clear();
    _engaged.clear();
  }

  void _event(String id, String actor, String event) {
    onTargetEvent?.call(id, actor, event);
    onEvent?.call(actor, event);
  }

  bool attack(double distance, {double? duration}) {
    final time = duration ?? attackDuration;
    if (!alive || _clock < _nextPlayer) return false;
    if (!distance.isFinite || distance > range) {
      record('Fuera de alcance (${distance.toStringAsFixed(1)} m).');
      return false;
    }
    active = true;
    _engaged.add(target);
    _nextPlayer = _clock + math.max(cooldown, time);
    _pending.add(_Hit(_clock + time * .45, true, target, damage));
    _event(target, 'player', 'attack');
    return true;
  }

  void step(double dt, double distance) {
    if (!dt.isFinite || dt < 0) return;
    _clock += math.min(dt, .25);
    if (!active || playerHealth <= 0) return;
    double separation(String id) =>
        distanceToTarget?.call(id) ??
        (id == target ? distance : double.infinity);
    if (automatic && alive) attack(separation(target));
    if (counterattack) {
      for (final id in _engaged.toList()) {
        if ((health[id] ?? 0) <= 0 ||
            separation(id) > range ||
            _clock < (_enemyCooldown[id] ?? 0)) {
          continue;
        }
        _enemyCooldown[id] = _clock + 1.8;
        _pending.add(_Hit(_clock + .55, false, id, enemyDamage));
        _event(id, 'enemy', 'attack');
      }
    }
    for (final hit in List<_Hit>.from(_pending)) {
      if (hit.at > _clock) continue;
      _pending.remove(hit);
      if ((health[hit.target] ?? 0) <= 0 ||
          playerHealth <= 0 ||
          separation(hit.target) > range) {
        continue;
      }
      if (hit.player) {
        health[hit.target] = math.max(0, health[hit.target]! - hit.damage);
        record('Impacto: ${hit.damage.round()} de daño.');
        _event(hit.target, 'enemy', health[hit.target] == 0 ? 'death' : 'hit');
      } else {
        playerHealth = math.max(0, playerHealth - hit.damage);
        record('Recibido: ${hit.damage.round()} de daño.');
        _event(hit.target, 'player', playerHealth == 0 ? 'death' : 'hit');
      }
      if ((health[hit.target] ?? 0) <= 0) {
        _engaged.remove(hit.target);
        _pending.removeWhere((h) => h.target == hit.target);
        if (hit.target == target) automatic = false;
        record('Criatura derrotada.');
      }
      if (playerHealth <= 0) {
        cancelActions();
        record('Personaje derrotado.');
        break;
      }
    }
    if (_engaged.isEmpty && _pending.isEmpty) {
      active = false;
      automatic = false;
    }
  }

  void record(String text) {
    log.insert(0, text);
    if (log.length > 80) log.removeLast();
  }
}

class _Hit {
  final double at, damage;
  final bool player;
  final String target;
  _Hit(this.at, this.player, this.target, this.damage);
}
