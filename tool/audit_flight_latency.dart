import 'dart:convert';
import 'package:herramienta_shaiya/core/flight_transition.dart';
import 'dart:io';

void main() {
  final results = <Map<String, Object>>[];
  for (final h in [0.12, 0.38, 1.0]) {
    for (final fps in [30, 60, 144]) {
      final state = FlightTransition()..height = h;
      state.queue('target');
      var frames = 0;
      while (!state.grounded && frames < fps * 4) {
        state.step(1 / fps, eligible: true, inCombat: false, hoverHeight: h);
        frames++;
      }
      results.add({
        'initialHeight': h,
        'fps': fps,
        'landingSeconds': frames / fps,
        'grounded': state.grounded,
        'scope': 'controller only, no renderer or weapon windup',
      });
    }
  }
  stdout.writeln(
    jsonEncode({
      'version': 'candidate manual-flight changes; not Windows compiled',
      'measurements': results,
    }),
  );
}
