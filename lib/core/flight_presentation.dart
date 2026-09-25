/// Wall-clock budgets for presentation only. Locomotion, collision, damage,
/// weapon speed and cooldowns never depend on reaching a clip's last frame.
abstract final class FlightPresentation {
  static const takeoffSeconds = .20;
  static const landingSeconds = .16;
  static const airBlendSeconds = .09;
  static const contactSeconds = .14;
  static const entryBlendSeconds = .07;

  static double? budget(String kind, {bool combat = false}) => switch (kind) {
    'TAKEOFF' => takeoffSeconds,
    'LANDING' => combat ? contactSeconds : landingSeconds,
    'AIR_BLEND' => airBlendSeconds,
    // Long sequence clips are inspector demos, not interactive locomotion.
    _ => null,
  };
}
