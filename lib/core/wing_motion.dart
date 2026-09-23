/// State-driven wing animation selection for Shaiya Studio.
///
/// The MON file remains authoritative: this layer never fabricates ANI paths.
/// It only chooses among semantic slots that were decoded from the wing's
/// original MO2/MO4 record.
enum WingMotionPhase { grounded, hover, cruise, landing }

WingMotionPhase wingMotionPhase({
  required bool flightEnabled,
  required bool grounded,
  required bool landing,
  required bool moving,
}) {
  if (!flightEnabled || grounded) return WingMotionPhase.grounded;
  if (landing) return WingMotionPhase.landing;
  return moving ? WingMotionPhase.cruise : WingMotionPhase.hover;
}

/// Priority is deliberately conservative. Missing roles fall back to another
/// original MON slot; a made-up animation is never substituted.
List<String> wingMotionCandidates(WingMotionPhase phase) => switch (phase) {
  WingMotionPhase.grounded => const ['Reposo', 'Respirar'],
  WingMotionPhase.hover => const ['Respirar', 'Reposo'],
  WingMotionPhase.cruise => const ['Correr', 'Caminar', 'Respirar', 'Reposo'],
  WingMotionPhase.landing => const ['Caminar', 'Reposo', 'Respirar'],
};

T? selectWingMotion<T>(Map<String, T> clips, WingMotionPhase phase) {
  for (final key in wingMotionCandidates(phase)) {
    final clip = clips[key];
    if (clip != null) return clip;
  }
  return clips.values.firstOrNull;
}

String wingMotionLabel(WingMotionPhase phase) => switch (phase) {
  WingMotionPhase.grounded => 'Reposo terrestre',
  WingMotionPhase.hover => 'Flotación',
  WingMotionPhase.cruise => 'Vuelo en movimiento',
  WingMotionPhase.landing => 'Aterrizaje',
};
