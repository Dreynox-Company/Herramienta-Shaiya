import 'dart:math' as math;

/// Manual flight's vertical component. It never modifies horizontal velocity,
/// held keys or a route. Only the brief combat descent is time-compressed;
/// attack playback, damage timing and weapon cooldown remain unchanged.
class FlightTransition {
  double height = 0, velocity = 0;
  bool wantsFlight = false;
  String? pendingTarget;
  double _queuedAge = 0;
  double? _descentDuration;
  double _descentTime = 0, _startHeight = 0, _startVelocity = 0;
  bool get landing => !wantsFlight && height > .004;
  bool get grounded =>
      _descentDuration == null && height <= .004 && velocity.abs() < .035;
  bool get combatDescent => _descentDuration != null;

  void queue(String target) {
    if (target.isEmpty) throw ArgumentError.value(target, 'target');
    pendingTarget = target;
    _queuedAge = 0;
    wantsFlight = false;
    // Updating the target must not restart the descent on repeated attacks.
    if (_descentDuration == null && !grounded) _beginCombatDescent();
  }

  void _beginCombatDescent() {
    if (!height.isFinite || !velocity.isFinite || height <= .004) return;
    _startHeight = height;
    _startVelocity = velocity;
    _descentTime = 0;
    var duration = (.115 + height * .10).clamp(.115, .32);
    if (velocity < 0) {
      // Close to the floor, preserve incoming velocity without forcing an
      // artificial prolonged slowdown or a negative position.
      duration = math.min(
        duration,
        (2.5 * height / -velocity).clamp(.008, .32),
      );
    }
    _descentDuration = duration;
  }

  void reset() {
    height = 0;
    velocity = 0;
    pendingTarget = null;
    _queuedAge = 0;
    wantsFlight = false;
    _descentDuration = null;
    _descentTime = 0;
  }

  void cancel() {
    pendingTarget = null;
    _queuedAge = 0;
    // Finish contact even when the target disappears; then honour the manual
    // flight preference instead of reversing direction mid-landing.
  }

  void step(
    double dt, {
    required bool eligible,
    required bool inCombat,
    required double hoverHeight,
  }) {
    if (!dt.isFinite || dt <= 0 || !hoverHeight.isFinite) return;
    final delta = dt.clamp(0.0, .1);
    if (pendingTarget != null) {
      _queuedAge += delta;
      if (_queuedAge > 3) cancel();
    }
    if (inCombat && !grounded && _descentDuration == null) {
      _beginCombatDescent();
    }
    wantsFlight =
        eligible &&
        !inCombat &&
        pendingTarget == null &&
        _descentDuration == null;
    final duration = _descentDuration;
    if (duration != null) {
      _descentTime = math.min(_descentTime + delta, duration);
      final t = _descentTime / duration,
          h = _startHeight,
          v = _startVelocity * duration;
      // Quintic Hermite trajectory: original position/velocity at entry,
      // zero velocity and acceleration at floor contact. No teleport to zero.
      final a3 = -10 * h - 6 * v, a4 = 15 * h + 8 * v, a5 = -6 * h - 3 * v;
      height =
          h +
          v * t +
          a3 * t * t * t +
          a4 * t * t * t * t +
          a5 * t * t * t * t * t;
      velocity =
          (v + 3 * a3 * t * t + 4 * a4 * t * t * t + 5 * a5 * t * t * t * t) /
          duration;
      if (_descentTime >= duration || height < 0) {
        height = 0;
        velocity = 0;
        _descentDuration = null;
      }
      return;
    }
    final goal = wantsFlight ? hoverHeight.clamp(0.0, 2.0) : 0.0;
    var remaining = delta;
    while (remaining > 1e-9) {
      final h = math.min(remaining, .008);
      remaining -= h;
      final acceleration = ((goal - height) * 80 - velocity * 18).clamp(
        -12.0,
        12.0,
      );
      velocity = (velocity + acceleration * h).clamp(-1.5, 1.2);
      height += velocity * h;
      if (height < 0) {
        height = 0;
        velocity = 0;
      }
    }
    if ((height - goal).abs() < .003 && velocity.abs() < .03) {
      height = goal;
      velocity = 0;
    }
  }
}
