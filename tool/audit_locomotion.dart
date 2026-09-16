import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/locomotion.dart';
Future<void> main(List<String> args) async {
  if(args.isEmpty){stderr.writeln('Uso: auditor_movimiento RUTA_CARPETA [informe.json]');exitCode=64;return;}
  final root=Directory(args.first),groups=<String,List<String>>{};
  await for(final f in root.list(recursive:true,followLinks:false)){if(f is! File||!f.path.toLowerCase().endsWith('.ani'))continue;final name=f.path.replaceAll('\\','/').split('/').last;if(!RegExp(r'^[a-z]+_00[012]_',caseSensitive:false).hasMatch(name))continue;groups.putIfAbsent(name.split('_').first.toLowerCase(),()=>[]).add(f.path);}
  final result=<Map<String,Object>>[];var failed=0;
  for(final entry in groups.entries){final row=<String,Object>{'arquetipo':entry.key};for(final mode in GroundMotion.values){try{final paths=groundMotionCandidates(entry.value,mode);if(paths.isEmpty)throw const FormatException('Falta el clip terrestre.');final file=File(paths.first),clip=ClipData.parse(await file.readAsBytes(),paths.first);final pose0=clip.pose(0),pose1=clip.pose(clip.duration*.37);var delta=0.0;for(var b=0;b<pose0.length;b++){for(var k=0;k<16;k++){final a=pose0[b].storage[k],c=pose1[b].storage[k];if(!a.isFinite||!c.isFinite)throw const FormatException('Pose no finita.');delta=math.max(delta,(c-a).abs());}}if(mode!=GroundMotion.idle&&delta<1e-8)throw const FormatException('El clip no produce cambios de pose.');row[mode.name]={'archivo':file.uri.pathSegments.last,'huesos':clip.bones.length,'duracion':clip.duration,'cambio_maximo_pose':delta};}catch(e){row[mode.name]={'error':e.toString()};failed++;}}result.add(row);}
  final text=const JsonEncoder.withIndent('  ').convert({'arquetipos':groups.length,'clips_validos':groups.length*3-failed,'errores':failed,'resultados':result});if(args.length>1){await File(args[1]).writeAsString(text);}else{stdout.writeln(text);}stdout.writeln('Arquetipos: ${groups.length}; clips: ${groups.length*3-failed}; errores: $failed');if(failed>0||groups.isEmpty)exitCode=1;
}
