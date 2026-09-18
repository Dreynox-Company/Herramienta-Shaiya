/// Continuous height and velocity, with an acceleration-limited spring. Combat
/// may request descent at any point without snapping the character to ground.
class FlightTransition {
  double height = 0, velocity = 0;
  bool wantsFlight = false;
  String? pendingTarget;
  double _queuedAge = 0;
  bool get landing => !wantsFlight && height > .004;
  bool get grounded => height <= .004 && velocity.abs() < .035;
  void queue(String target) {
    pendingTarget = target;
    _queuedAge = 0;
    wantsFlight = false;
  }

  void reset() {
    height = 0;
    velocity = 0;
    pendingTarget = null;
    _queuedAge = 0;
    wantsFlight = false;
  }

  void cancel() {
    pendingTarget = null;
    _queuedAge = 0;
  }

  void step(
    double dt, {
    required bool eligible,
    required bool inCombat,
    required double hoverHeight,
  }) {
    if (!dt.isFinite || dt <= 0) return;
    final delta = dt.clamp(0.0, .1);
    if (pendingTarget != null) {
      _queuedAge += delta;
      if (_queuedAge > 3) cancel();
    }
    wantsFlight = eligible && !inCombat && pendingTarget == null;
    final goal = wantsFlight ? hoverHeight.clamp(0.0, 2.0) : 0.0;
    // Substeps keep the spring stable across 30/60/144 Hz and pauses.
    var remaining = delta;
    while (remaining > 1e-9) {
      final h = remaining > .008 ? .008 : remaining;
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
