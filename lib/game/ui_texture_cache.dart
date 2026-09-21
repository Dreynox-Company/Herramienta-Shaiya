import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/textures.dart';
import '../data/library.dart';

class GameUiTextureCache {
  final Library library;
  final Map<String,Future<Uint8List?>> _cache={};
  GameUiTextureCache(this.library);

  Future<Uint8List?> load(String path,{bool opaque=false}) =>
      _cache.putIfAbsent('$path#$opaque',() async {
        try {
          final key=library.resolve(path,[directoryName(path),'interface','interface/loading','interface/mainbottom','interface/quest','interface/countryselect'],uniqueFallback:true)??canon(path);
          if(!library.files.containsKey(key))return null;
          final bytes=await library.read(key,limit:32*1024*1024);
          return Pixels.decode(bytes,key).png(opaque:opaque);
        } catch (_) {
          return null;
        }
      });

  Widget image(String path,{BoxFit fit=BoxFit.contain,Alignment alignment=Alignment.center,bool opaque=false,Widget? fallback}) =>
      FutureBuilder<Uint8List?>(
        future:load(path,opaque:opaque),
        builder:(context,snapshot){
          final bytes=snapshot.data;
          if(bytes==null)return fallback??const SizedBox.shrink();
          return Image.memory(bytes,fit:fit,alignment:alignment,gaplessPlayback:true,filterQuality:FilterQuality.medium);
        },
      );
}
