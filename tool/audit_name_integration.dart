import 'dart:convert';
import 'dart:io';

import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/game_names.dart';

/// Run with Flutter's headless engine or through a Flutter test harness.
/// The supplied directory is only read. Missing heavy resources stay missing.
Future<void> main() async {
  final root = Platform.environment['SHAIYA_AUDIT_DATA'];
  final output = Platform.environment['SHAIYA_AUDIT_OUTPUT'];
  if (root == null || output == null) {
    stderr.writeln('Define SHAIYA_AUDIT_DATA y SHAIYA_AUDIT_OUTPUT.');
    exit(2);
  }
  try {
    final library = await Library.fromDirectory(root, stdout.writeln);
    final names = GameNames();
    await names.load(library, stdout.writeln);
    final report = {
      'sources': names.localeSources,
      'item_model_relations': names.itemCount,
      'monster_models': names.monsters.length,
      'skills': names.skills.length,
      'npc_skills': names.npcSkills.length,
      'worlds': names.maps.length,
      'localized_worlds': names.worldTexts.length,
      'system_messages': names.systemMessages.length,
      'secondary_system_messages': names.secondarySystemMessages.length,
      'locale_conflicts': {
        for (final path in names.localeConflicts.entries)
          path.key: {for (final e in path.value.entries) '${e.key}': e.value},
      },
      'warnings': names.warnings,
      'item_samples': names.itemByModel.values
          .expand((v) => v)
          .where((r) => RegExp('[ñÑáéíóú]').hasMatch(r.name))
          .take(10)
          .map((r) => r.name)
          .toList(),
      'skill_samples': names.skills.values
          .where((r) => RegExp('[ñÑáéíóú]').hasMatch(r.name))
          .take(5)
          .map((r) => r.name)
          .toList(),
      'source_modified': false,
    };
    await File(
      output,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    if (!names.localeSources['items']!.endsWith('_spn.sdata') ||
        names.skills.length != 12060 ||
        names.npcSkills.length != 774 ||
        names.itemCount == 0 ||
        names.worldTexts.isEmpty ||
        names.systemMessages.isEmpty) {
      throw StateError(
        'Los nombres no se integraron conforme a este cliente auditado.',
      );
    }
    await File(
      output,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    library.dispose();
    stdout.writeln('NAME_INTEGRATION_PASSED');
    exit(0);
  } catch (e, s) {
    stderr.writeln('$e\n$s');
    exit(1);
  }
}
