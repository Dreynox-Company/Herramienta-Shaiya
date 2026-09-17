import 'dart:io';
import 'dart:convert';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/core/formats.dart';

/// Reads the user-owned DATA only. Does not embed or upload original resources.
Future<void> main(List<String> args) async {
  final data =
      Platform.environment['SHAIYA_BODY_DATA'] ?? (args.isEmpty ? '' : args[0]);
  final output =
      Platform.environment['SHAIYA_BODY_REPORT'] ??
      (args.length < 2 ? 'body-audit.json' : args[1]);
  final lib = await Library.fromDirectory(data, (_) {});
  final c = Catalog(lib);
  await c.load((_) {});
  final results = <Map<String, Object?>>[];
  for (final a in c.archetypes) {
    final initial = Appearance.initial(a),
        base = Appearance.forSet(a, originalBodySet, previous: initial);
    final checks = <Map<String, Object?>>[];
    for (final look in [initial, base]) {
      final parts = look.effective;
      final regions = parts.expand((p) => [p.slot, ...p.coveredSlots]).toSet();
      final complete = [
        Slot.upper,
        Slot.lower,
        Slot.hand,
        Slot.foot,
      ].every(regions.contains);
      final meshes = <MeshData>[];
      final errors = <String>[];
      for (final p in parts) {
        try {
          meshes.add(MeshData.skinned(await lib.read(p.meshPath), p.meshPath));
        } catch (e) {
          errors.add(e.toString());
        }
      }
      checks.add({
        'preset': look.selectedSetKey,
        'complete': complete,
        'slots': parts.map((p) => p.slot.name).toList(),
        'meshes': meshes.length,
        'errors': errors,
      });
    }
    final incomplete = <String>[];
    for (final key in a.sets.keys) {
      final look = Appearance.forSet(a, key, previous: initial);
      final occupied = look.effective
          .expand((p) => [p.slot, ...p.coveredSlots])
          .toSet();
      if (![
        Slot.upper,
        Slot.lower,
        Slot.hand,
        Slot.foot,
      ].every(occupied.contains)) {
        incomplete.add(key);
      }
    }
    results.add({
      'id': a.id,
      'race': a.race,
      'sets': a.sets.length,
      'initialAndBase': checks,
      'incompleteCompositionKeys': incomplete,
      'nudeAvailable': a.hasNude,
      'nudeDetail': a.nudeUnavailableReason,
    });
  }
  final result = {
    'archetypes': results.length,
    'results': results,
    'warnings': c.warnings,
  };
  await File(
    output,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln(
    'Original archetypes checked: ${results.length}; report: $output',
  );
  exit(0);
}
