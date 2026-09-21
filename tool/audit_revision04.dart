import 'dart:convert';
import 'dart:io';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/core/extra_motion.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/locomotion.dart';
import 'package:herramienta_shaiya/core/archive_index.dart';
import 'package:herramienta_shaiya/data/archive_source.dart';
import 'package:crypto/crypto.dart';

Future<void> main() async {
  final root = Platform.environment['SHAIYA_AUDIT_DATA']!;
  final output = Platform.environment['SHAIYA_AUDIT_OUTPUT']!;
  final lib = await Library.fromDirectory(root, (_) {});
  final catalog = Catalog(lib);
  await catalog.load((m) => stdout.writeln(m));
  final extraFile = Platform.environment['SHAIYA_MOTION_PACK'];
  final extras = extraFile == null
      ? ExtraMotionLibrary({})
      : ExtraMotionLibrary.decode(await File(extraFile).readAsBytes());
  final actors = <Map<String, Object?>>[], failures = <Map<String, Object?>>[];
  for (final a in catalog.archetypes) {
    try {
      final initial = await catalog.resolveAppearance(Appearance.initial(a));
      final idle = groundMotionCandidates(
        a.animations,
        GroundMotion.idle,
      ).firstOrNull;
      final normal = idle == null
          ? null
          : ClipData.parse(await lib.read(idle), idle);
      final profile = extras.profiles[a.id];
      final mapped =
          profile != null &&
          normal != null &&
          profile.matches(a.id, a.female, normal);
      if (profile != null && !mapped) {
        throw StateError('Supplemental skeleton or gender mismatch ${a.id}');
      }
      final sets = <String, Object?>{};
      for (final key in a.sets.keys.where(
        (k) => k.contains('2015') && k.contains('christ'),
      )) {
        final look = await catalog.resolveAppearance(
          Appearance.forSet(a, key, previous: initial),
        );
        sets[key] = {
          'embedded': look.embeddedSlots.map((s) => s.name).toList(),
          'rendered': {for (final p in look.effective) p.slot.name: p.raw.mesh},
        };
      }
      actors.add({
        'archetype': a.id,
        'baseComplete':
            initial.embeddedSlots.contains(Slot.lower) ||
            initial.effective.any((p) => p.slot == Slot.lower),
        'faceVariants': (a.parts[Slot.face] ?? []).length,
        'hairVariants': (a.parts[Slot.hair] ?? []).length,
        'hoverFlyMatched': mapped,
        'gender': a.female ? 'Femenino' : 'Masculino',
        'nativeBones': normal?.bones.length,
        'christmas': sets,
      });
    } catch (e) {
      failures.add({'archetype': a.id, 'error': e.toString()});
    }
  }
  final faceDetails = <Map<String, Object?>>[];
  for (final a in catalog.archetypes.where((a) => a.race == 'human')) {
    for (final p in a.parts[Slot.face] ?? <PartRecord>[]) {
      if (RegExp(r'face(?:001_2|009|010)').hasMatch(p.texturePath)) {
        final mesh = await catalog.appearanceMesh(p.meshPath);
        faceDetails.add({
          'archetype': a.id,
          'texture': p.texturePath,
          'mesh': p.meshPath,
          'vertices': mesh.vertices,
          'triangles': mesh.triangles,
        });
      }
    }
  }
  final archiveTests = <Map<String, Object?>>[];
  final dir = Platform.environment['SHAIYA_ARCHIVE_FIXTURES'];
  if (dir != null) {
    await for (final f in Directory(dir).list()) {
      if (f is! File || !f.path.endsWith('.sah')) continue;
      final saf = File('${f.path.substring(0, f.path.length - 4)}.saf');
      if (!await saf.exists()) continue;
      try {
        final b = await f.readAsBytes(),
            index = ArchiveIndex.decode(b, await saf.length());
        final source = await ArchiveSource.fromFiles(f.path, saf.path);
        final hashes = <String, String>{};
        for (final entry in index.entries.values) {
          hashes[entry.path] = sha256
              .convert(await source.read(entry.path))
              .toString();
        }
        source.close();
        archiveTests.add({
          'sah': baseName(f.path),
          'entries': index.entries.length,
          'profile': index.report['profile'],
          'allPayloadsRead': true,
          'hashes': hashes,
        });
      } catch (e) {
        failures.add({'archive': baseName(f.path), 'error': e.toString()});
      }
    }
  }
  final report = {
    'version': '0.4.0+6',
    'files': lib.files.length,
    'ddsTotal': lib.files.keys.where((s) => s.endsWith('.dds')).length,
    'inventoryCount': catalog.textureInventory.length,
    'archetypes': actors,
    'verifiedFaces': faceDetails,
    'archivalReferenceTests': archiveTests,
    'failures': failures,
    'scope':
        'Binary, geometry coverage, skeletal and catalogue validation; not a visual approval of every texture.',
  };
  await File(
    output,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(
    'AUDIT_DONE ${actors.length} actors, ${archiveTests.length} archives, ${failures.length} errors',
  );
  if (failures.isNotEmpty) exitCode = 1;
}
