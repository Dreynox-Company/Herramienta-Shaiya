import 'dart:convert';
import 'dart:io';

import 'package:herramienta_shaiya/core/formats.dart';

Future<void> main(List<String> args) async {
  if(args.isEmpty){
    stderr.writeln('usage: dart run tool/audit_world_extras.dart <DATA> [report.json]');
    exitCode=2;
    return;
  }
  final root=Directory(args[0]);
  if(!await root.exists()){
    stderr.writeln('DATA directory does not exist: ${root.path}');
    exitCode=2;
    return;
  }

  final files=<File>[];
  await for(final entity in root.list(recursive:true,followLinks:false)){
    if(entity is! File)continue;
    final lower=entity.path.toLowerCase();
    if(lower.endsWith('.wld')||
       lower.endsWith('.wtr')||
       lower.endsWith('.mani')||
       lower.endsWith('.vani')){
      files.add(entity);
    }
  }
  files.sort((a,b)=>a.path.compareTo(b.path));

  final wlds=<Map<String,Object?>>[];
  final wtrs=<Map<String,Object?>>[];
  final manis=<Map<String,Object?>>[];
  final vanis=<Map<String,Object?>>[];
  final failures=<Map<String,Object?>>[];

  String relative(File file){
    var p=file.absolute.path.replaceAll('\\','/');
    var base=root.absolute.path.replaceAll('\\','/');
    if(!base.endsWith('/'))base+='/';
    if(p.startsWith(base))p=p.substring(base.length);
    return p;
  }

  for(final file in files){
    final path=relative(file),lower=path.toLowerCase();
    try{
      final bytes=await file.readAsBytes();
      if(lower.endsWith('.wld')){
        final w=WorldData.parse(bytes,path);
        wlds.add({
          'path':path,
          'bytes':bytes.length,
          'size':w.size,
          'layout':w.layout,
          'objects':w.objects.length,
          'categories':{
            for(final category in w.objects.map((o)=>o.category).toSet())
              category:w.objects.where((o)=>o.category==category).length,
          },
          'maniBindings':w.maniBindings.length,
          'musicNames':w.musicNames.length,
          'musicZones':w.musicZones.length,
          'soundNames':w.soundEffectNames.length,
          'soundEffects':w.soundEffects.length,
          'sky':w.skyFile,
          'cloud1':w.primaryCloudFile,
          'cloud2':w.secondaryCloudFile,
          'fogColor':[w.fogColor.x,w.fogColor.y,w.fogColor.z],
          'fogStart':w.fogStart,
          'fogEnd':w.fogEnd,
        });
      }else if(lower.endsWith('.wtr')){
        final w=readWtr(bytes,path);
        wtrs.add({
          'path':path,
          'bytes':bytes.length,
          'unknown1':w.unknown1,
          'unknown2':w.unknown2,
          'unknown3':w.unknown3,
          'textures':w.textures,
        });
      }else if(lower.endsWith('.mani')){
        final m=readMani(bytes,path);
        manis.add({
          'path':path,
          'bytes':bytes.length,
          'version':m.version,
          'rotationEnabled':m.rotationEnabled,
          'axis':[m.rotationAxis.x,m.rotationAxis.y,m.rotationAxis.z],
          'speed':m.animationSpeed,
        });
      }else if(lower.endsWith('.vani')){
        final v=readVani(bytes,path);
        vanis.add({
          'path':path,
          'bytes':bytes.length,
          'frames':v.frameCount,
          'meshes':v.meshes.length,
          'vertices':v.meshes.fold<int>(0,(n,m)=>n+m.vertices),
        });
      }
    }catch(e){
      failures.add({'path':path,'error':e.toString()});
    }
  }

  final layouts=<Map<String,Object?>>[];
  for(final w in wlds){
    final layout=(w['layout'] as String?)?.trim()??'';
    if(layout.isEmpty)continue;
    final stem=layout.replaceAll('\\','/').split('/').last.toLowerCase();
    final matches=wtrs.where((row){
      final p=(row['path'] as String).replaceAll('\\','/').split('/').last.toLowerCase();
      return p==stem;
    }).map((row)=>row['path']).toList();
    layouts.add({'world':w['path'],'layout':layout,'wtrMatches':matches});
  }

  final report=<String,Object?>{
    'root':root.absolute.path,
    'counts':{
      'worlds':wlds.length,
      'water':wtrs.length,
      'mani':manis.length,
      'vani':vanis.length,
      'failures':failures.length,
    },
    'layouts':layouts.take(200).toList(),
    'wld':wlds.take(200).toList(),
    'wtr':wtrs.take(200).toList(),
    'mani':manis.take(300).toList(),
    'vani':vanis.take(200).toList(),
    'failures':failures.take(200).toList(),
  };

  final json=const JsonEncoder.withIndent('  ').convert(report);
  stdout.writeln(json);
  if(args.length>1){
    final out=File(args[1]);
    await out.parent.create(recursive:true);
    await out.writeAsString(json,flush:true);
  }
  if(failures.isNotEmpty){
    stderr.writeln('world-extra parse failures: ${failures.length}');
  }
}
