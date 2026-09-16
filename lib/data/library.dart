import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

String baseName(String path)=>path.replaceAll('\\','/').split('/').last;
String directoryName(String path) {final x=path.replaceAll('\\','/');final i=x.lastIndexOf('/');return i<0?'':x.substring(0,i);}
String canon(String path) {
  final value=path.replaceAll('\\','/').replaceAll(RegExp(r'/+'),'/');
  if(value.startsWith('/')||value.contains(':')||value.split('/').contains('..'))throw FormatException('Ruta no relativa: $path');
  return value.replaceFirst(RegExp(r'^\./'),'').toLowerCase();
}
const supportedExtensions={'.3dc','.3do','.ani','.mlt','.alt','.itm','.mon','.dds','.png','.jpg','.jpeg','.tga','.bmp','.wav','.mp3','.ogg','.wld','.smod','.dg','.eft'};
bool supportedPath(String p) { final i=p.lastIndexOf('.'); return i>=0&&supportedExtensions.contains(p.substring(i).toLowerCase()); }

class Library {
  static const channel=MethodChannel('dreynox.shaiya/data');
  final String location;
  final bool saf;
  final Map<String,String> files;
  final Map<String,List<String>> _names={};
  Library(this.location,this.saf,this.files) {for(final p in files.keys) {_names.putIfAbsent(baseName(p),()=>[]).add(p);}}
  static Future<Library?> choose(void Function(String) progress) async {
    if(Platform.isAndroid) {
      final uri=await channel.invokeMethod<String>('chooseTree');if(uri==null)return null;
      progress('Indexando DATA con acceso de solo lectura…');
      final rows=await channel.invokeMethod<Map>('index',{'tree':uri});
      if(rows==null)throw const FormatException('No se pudo leer la carpeta seleccionada.');
      return _normalise(uri,true,rows.map((k,v)=>MapEntry(k.toString(),v.toString())));
    }
    final dir=await getDirectoryPath(confirmButtonText:'Usar carpeta DATA');if(dir==null)return null;
    return fromDirectory(dir,progress);
  }
  static Future<Library> fromDirectory(String dir,void Function(String) progress) async {
    var root=Directory(dir);
    if(!await root.exists())throw const FormatException('La carpeta DATA no existe.');
    final child=await root.list(followLinks:false).where((e)=>e is Directory&&baseName(e.path).toLowerCase()=='data').toList();
    if(child.length==1)root=Directory(child.first.path);
    final map=<String,String>{};var n=0;
    await for(final entry in root.list(recursive:true,followLinks:false)) {
      if(entry is! File||!supportedPath(entry.path))continue;
      final rel=entry.path.substring(root.path.length+1).replaceAll('\\','/');
      if(map.containsKey(canon(rel)))throw FormatException('Hay dos archivos que solo difieren en mayúsculas: $rel');
      map[canon(rel)]=entry.path;
      if(++n%1000==0)progress('Indexando… $n recursos');
      if(n>200000)throw const FormatException('La carpeta supera el límite de 200.000 recursos.');
    }
    return _normalise(root.path,false,map);
  }
  static Library _normalise(String location,bool saf,Map<String,String> source) {
    final map=<String,String>{};
    for(final entry in source.entries) {if(supportedPath(entry.key))map[canon(entry.key)]=entry.value;}
    final hasCharacter=map.keys.any((p)=>p.startsWith('character/'));
    if(!hasCharacter) {
      final nested=map.keys.where((p)=>p.contains('/character/')).toList();
      if(nested.isEmpty)throw const FormatException('Selecciona DATA: no se encuentra Character.');
      final prefixes=nested.map((p)=>p.substring(0,p.indexOf('/character/')+1)).toSet();
      if(prefixes.length!=1)throw const FormatException('Hay varias bibliotecas DATA. Selecciona una sola.');
      final prefix=prefixes.single,trimmed=<String,String>{};for(final e in map.entries) {if(e.key.startsWith(prefix))trimmed[e.key.substring(prefix.length)]=e.value;}
      return Library(location,saf,trimmed);
    }
    return Library(location,saf,map);
  }
  String? resolve(String name,List<String> directories,{bool uniqueFallback=false}) {
    if(name.isEmpty||baseName(name).toLowerCase().startsWith('null.'))return null;
    final n=canon(name);final variants={n};if(n.endsWith('.tga'))variants.add('${n.substring(0,n.length-4)}.dds');
    for(final root in directories) {for(final v in variants) {final key=canon(root.isEmpty?v:'$root/$v');if(files.containsKey(key))return key;}}
    for(final v in variants) {if(files.containsKey(v))return v;}
    if(uniqueFallback) {for(final v in variants) {final hits=_names[baseName(v)]??[];if(hits.length==1)return hits.single;if(hits.length>1)throw FormatException('Nombre ambiguo: $name (${hits.length} rutas).');}}
    return null;
  }
  Future<Uint8List> read(String path,{int limit=64*1024*1024}) async {
    final id=files[canon(path)];if(id==null)throw FormatException('Recurso ausente: $path');
    if(saf) {
      final b=await channel.invokeMethod<Uint8List>('read',{'tree':location,'uri':id,'limit':limit});if(b==null)throw FormatException('No se pudo leer $path');return b;
    }
    final f=File(id);if(await f.length()>limit)throw FormatException('$path supera el límite de lectura.');return f.readAsBytes();
  }
}
