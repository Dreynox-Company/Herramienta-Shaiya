/// State-driven Wing.MON animation selection for Shaiya Studio.
///
/// The MON record remains authoritative: this layer never fabricates ANI paths.
/// It only maps locomotion/flight states onto the nine semantic slots decoded
/// from MO2/MO4. Attack, damage and death one-shots are triggered by combat
/// events in StudioScene and are intentionally not selected by this loop.
enum WingMotionPhase {
  groundedIdle,
  groundedWalk,
  groundedRun,
  hover,
  cruise,
  landing,
}

WingMotionPhase wingMotionPhase({
  required bool flightEnabled,
  required bool grounded,
  required bool landing,
  required bool moving,
  bool running = false,
}) {
  if (!flightEnabled || grounded) {
    if (!moving) return WingMotionPhase.groundedIdle;
    return running ? WingMotionPhase.groundedRun : WingMotionPhase.groundedWalk;
  }
  if (landing) return WingMotionPhase.landing;
  return moving ? WingMotionPhase.cruise : WingMotionPhase.hover;
}

/// Priority is deliberately conservative. Missing roles fall back only to
/// another slot declared by the same MON; Studio never synthesizes an ANI.
List<String> wingMotionCandidates(WingMotionPhase phase) => switch (phase) {
  WingMotionPhase.groundedIdle => const ['Reposo', 'Respirar'],
  WingMotionPhase.groundedWalk => const ['Caminar', 'Reposo', 'Respirar'],
  WingMotionPhase.groundedRun => const [
    'Correr',
    'Caminar',
    'Reposo',
    'Respirar',
  ],
  WingMotionPhase.hover => const ['Respirar', 'Reposo'],
  WingMotionPhase.cruise => const ['Correr', 'Caminar', 'Respirar', 'Reposo'],
  WingMotionPhase.landing => const ['Caída', 'Respirar', 'Reposo'],
};

T? selectWingMotion<T>(Map<String, T> clips, WingMotionPhase phase) {
  for (final key in wingMotionCandidates(phase)) {
    final clip = clips[key];
    if (clip != null) return clip;
  }
  return clips.isEmpty ? null : clips.values.first;
}

String wingMotionLabel(WingMotionPhase phase) => switch (phase) {
  WingMotionPhase.groundedIdle => 'Reposo terrestre',
  WingMotionPhase.groundedWalk => 'Marcha terrestre',
  WingMotionPhase.groundedRun => 'Carrera terrestre',
  WingMotionPhase.hover => 'Flotación',
  WingMotionPhase.cruise => 'Vuelo en movimiento',
  WingMotionPhase.landing => 'Caída / aterrizaje',
};
