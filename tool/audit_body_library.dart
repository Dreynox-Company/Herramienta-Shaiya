// Run with Flutter's Dart runtime; DATA is only read, never modified.
import 'dart:convert';
import 'dart:io';

import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/catalog.dart';

Future<void> main() async {
  final path = Platform.environment['SHAIYA_AUDIT_DATA'];
  final output = Platform.environment['SHAIYA_AUDIT_OUTPUT'];
  if (path == null || output == null) {
    throw StateError('Define SHAIYA_AUDIT_DATA y SHAIYA_AUDIT_OUTPUT.');
  }
  final lib = await Library.fromDirectory(path, (_) {});
  final catalog = Catalog(lib);
  await catalog.load((_) {});
  final rows = <Map<String, Object?>>[], errors = <Map<String, Object?>>[];
  int sets = 0, restored = 0, protected = 0;
  for (final a in catalog.archetypes) {
    final base = await catalog.resolveAppearance(Appearance.base(a));
    final initial = await catalog.resolveAppearance(Appearance.initial(a));
    final baseSlots = base.effective.map((p) => p.slot).toSet();
    if (![
      Slot.upper,
      Slot.lower,
      Slot.hand,
      Slot.foot,
    ].every(baseSlots.contains)) {
      throw StateError('Base incompleta: ${a.id}');
    }
    if (!initial.embeddedSlots.contains(Slot.lower) &&
        !initial.effective.any((p) => p.slot == Slot.lower)) {
      throw StateError('Inicio incompleto: ${a.id}');
    }
    var good = 0, failed = 0, recovered = 0;
    for (final key in a.sets.keys) {
      try {
        final look = await catalog.resolveAppearance(
          Appearance.forSet(a, key, previous: base),
        );
        if (!look.embeddedSlots.contains(Slot.lower) &&
            !look.effective.any((p) => p.slot == Slot.lower)) {
          throw StateError('Piernas ausentes tras resolver.');
        }
        if (look.selected[Slot.lower] == null &&
            look.effective.any((p) => p.slot == Slot.lower)) {
          recovered++;
          restored++;
        }
        for (final identity in [Slot.face, Slot.hair]) {
          if (!identical(look.selected[identity], base.selected[identity])) {
            throw StateError('Cambió ${identity.name}');
          }
          protected++;
        }
        sets++;
        good++;
      } catch (e) {
        errors.add({'archetype': a.id, 'set': key, 'error': e.toString()});
        failed++;
      }
    }
    rows.add({
      'archetype': a.id,
      'race': a.race,
      'base_parts': {for (final p in base.effective) p.slot.name: p.raw.mesh},
      'original_nude_complete': a.hasOriginalNude,
      'initial_preset': initial.preset,
      'initial_complete': true,
      'sets_resolved': good,
      'sets_rejected_with_diagnostic': failed,
      'missing_lower_restored': recovered,
    });
  }
  final report = {
    'version': '0.3.1+5',
    'archetypes': rows.length,
    'sets_resolved': sets,
    'identity_checks': protected,
    'missing_lower_restored': restored,
    'method': 'Lectura y resolución de la selección con las mallas originales. No es homologación visual de todos los trajes.',
    'rows': rows,
    'rejected_resources': errors,
  };
  await File(output)
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(
    'AUDITORIA: ${rows.length} arquetipos, $sets conjuntos resueltos, ${errors.length} rechazados con diagnóstico.',
  );
}
