import 'dart:convert';
import 'dart:io';

import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/world_resources.dart';
import 'package:herramienta_shaiya/core/game_metadata.dart';

void main(List<String> args) async {
  final root = Directory(args.first),
      worlds = [],
      effects = [],
      errors = <String>[];
  var meshes = 0, dg = 0;
  await for (final f in root.list(recursive: true)) {
    if (f is! File) continue;
    final name = f.path.toLowerCase();
    try {
      if (name.endsWith('.3do')) {
        MeshData.object(await f.readAsBytes(), name);
        meshes++;
      }
      if (name.endsWith('.dg')) {
        DungeonResource.parse(await f.readAsBytes(), name);
        dg++;
      }
      if (name.endsWith('.wld')) {
        final w = WorldResource.parse(await f.readAsBytes(), name);
        worlds.add({
          'file': f.uri.pathSegments.last,
          'layout': w.terrain.layout,
          'size': w.terrain.size,
          'objects': w.terrain.objects.length,
          'sky': w.sky,
          'spawn': w.spawn().storage.toList(),
          'areas': w.areas
              .map(
                (a) => {
                  'name': a.name,
                  'comment': a.comment,
                  'center': a.center.storage.toList(),
                },
              )
              .toList(),
        });
      }
      if (name.endsWith('.seff')) {
        final records = readSeff(await f.readAsBytes(), name);
        effects.add({
          'file': name,
          'records': records
              .map(
                (e) => {
                  'id': e.id,
                  'parts': e.particles
                      .map(
                        (p) => {
                          'tex': p.texture,
                          'count': p.count,
                          'color': p.color,
                          'visible': p.visible,
                        },
                      )
                      .toList(),
                },
              )
              .toList(),
        });
      }
    } catch (e) {
      errors.add(e.toString());
    }
  }
  final itemData = DataTable.open(
    await File('${root.path}/BinarySData/DBItemData.SData').readAsBytes(),
    'items',
  ).integers();
  final itemNames = readItemNames(
    await File('${root.path}/BinarySData/DBItemText_CHN.SData').readAsBytes(),
    'names',
  );
  final monsterNames = readMonsterNames(
    await File(
      '${root.path}/BinarySData/DBMonsterText_CHN.SData',
    ).readAsBytes(),
    'monster names',
  );
  final result = {
    'meshes3do': meshes,
    'dungeons': dg,
    'worlds': worlds,
    'effects': effects,
    'errors': errors,
    'items': itemData.length,
    'itemNames': itemNames.length,
    'monsterNames': monsterNames.length,
  };
  await File(
    args[1],
  ).writeAsString(const JsonEncoder.withIndent(' ').convert(result));
  stdout.writeln(
    '3DO: $meshes; DG: $dg; WLD: ${worlds.length}; items: ${itemData.length}; errors: ${errors.length}',
  );
  for (final e in errors.take(10)) {
    stdout.writeln(e);
  }
}
