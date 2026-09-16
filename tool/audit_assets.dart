import 'dart:convert';
import 'dart:io';
import '../lib/core/formats.dart';
import '../lib/core/textures.dart';

/// Auditor de solo lectura. No requiere Flutter ni acceso a internet al ejecutarse.
void main(List<String> args) async {
  if(args.isEmpty){stderr.writeln('Uso: audit_assets_linux RUTA_DATA [informe.json]');exitCode=64;return;}
  final root=Directory(args.first);if(!await root.exists()){stderr.writeln('No existe DATA.');exitCode=66;return;}
  final verified=<String,int>{},errors=<Map<String,String>>[];var files=0;
  await for(final e in root.list(recursive:true,followLinks:false)){
    if(e is! File)continue;final path=e.path.substring(root.path.length+1).replaceAll('\\','/'),ext=path.split('.').last.toLowerCase();
    if(!['3dc','ani','mlt','itm','mon','dds','wld'].contains(ext))continue;
    try{
      final b=await e.readAsBytes();
      switch(ext){
        case '3dc':MeshData.skinned(b,path);break;
        case 'ani':ClipData.parse(b,path);break;
        case 'mlt':readMlt(b,path);break;
        case 'itm':readItm(b,path);break;
        case 'mon':readMon(b,path);break;
        case 'dds':Pixels.dds(b,path);break;
        case 'wld':WorldData.parse(b,path);break;
      }
      verified.update(ext,(n)=>n+1,ifAbsent:()=>1);
    }catch(error){errors.add({'file':path,'error':error.toString()});}
    files++;if(files%1000==0)stderr.writeln('$files recursos comprobados');
  }
  final report=const JsonEncoder.withIndent('  ').convert({'files':files,'verified':verified,'errors':errors});
  if(args.length>1){await File(args[1]).writeAsString(report);}else{stdout.writeln(report);}
  stderr.writeln('Completado: $files archivos, ${errors.length} incompatibilidades.');
}
