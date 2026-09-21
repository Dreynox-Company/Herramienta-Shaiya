import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/textures.dart';
import '../data/library.dart';

Uint8List _decodeUi(Map<String,Object> args)=>
    Pixels.decode(args['bytes'] as Uint8List,args['path'] as String).png();

class UiAssetCache {
  final Library library;
  final Map<String,Future<Uint8List?>> _cache={};
  UiAssetCache(this.library);

  Future<Uint8List?> load(String path)=>_cache.putIfAbsent(path,() async {
    try {
      final key=canon(path);
      if(!library.files.containsKey(key))return null;
      final bytes=await library.read(key,limit:32*1024*1024);
      return compute(_decodeUi,{'bytes':bytes,'path':key});
    } catch (_) {
      return null;
    }
  });
}

class DataImage extends StatelessWidget {
  final UiAssetCache cache;
  final String path;
  final BoxFit fit;
  final Alignment alignment;
  final double? width,height;
  final Widget? fallback;
  final FilterQuality filterQuality;
  const DataImage({
    super.key,
    required this.cache,
    required this.path,
    this.fit=BoxFit.contain,
    this.alignment=Alignment.center,
    this.width,
    this.height,
    this.fallback,
    this.filterQuality=FilterQuality.medium,
  });

  @override Widget build(BuildContext context)=>FutureBuilder<Uint8List?>(
    future:cache.load(path),
    builder:(context,snapshot){
      final data=snapshot.data;
      if(data==null){
        return fallback??SizedBox(width:width,height:height);
      }
      return Image.memory(data,width:width,height:height,fit:fit,alignment:alignment,filterQuality:filterQuality,gaplessPlayback:true);
    },
  );
}


class DataSprite extends StatelessWidget {
  final UiAssetCache cache;
  final String path;
  final int columns,rows,column,row;
  final double width,height;
  final Widget? fallback;
  final FilterQuality filterQuality;
  const DataSprite({
    super.key,
    required this.cache,
    required this.path,
    required this.columns,
    required this.rows,
    required this.column,
    required this.row,
    required this.width,
    required this.height,
    this.fallback,
    this.filterQuality=FilterQuality.medium,
  });

  @override Widget build(BuildContext context)=>FutureBuilder<Uint8List?>(
    future:cache.load(path),
    builder:(context,snapshot){
      final data=snapshot.data;
      if(data==null)return fallback??SizedBox(width:width,height:height);
      return SizedBox(
        width:width,
        height:height,
        child:ClipRect(
          child:OverflowBox(
            alignment:Alignment.topLeft,
            minWidth:width*columns,
            maxWidth:width*columns,
            minHeight:height*rows,
            maxHeight:height*rows,
            child:Transform.translate(
              offset:Offset(-column*width,-row*height),
              child:Image.memory(
                data,
                width:width*columns,
                height:height*rows,
                fit:BoxFit.fill,
                filterQuality:filterQuality,
                gaplessPlayback:true,
              ),
            ),
          ),
        ),
      );
    },
  );
}


class DataRegion extends StatelessWidget {
  final UiAssetCache cache;
  final String path;
  final double sheetWidth,sheetHeight;
  final Rect source;
  final double width,height;
  final Widget? fallback;
  final FilterQuality filterQuality;
  const DataRegion({
    super.key,
    required this.cache,
    required this.path,
    required this.sheetWidth,
    required this.sheetHeight,
    required this.source,
    required this.width,
    required this.height,
    this.fallback,
    this.filterQuality=FilterQuality.medium,
  });

  @override Widget build(BuildContext context)=>FutureBuilder<Uint8List?>(
    future:cache.load(path),
    builder:(context,snapshot){
      final data=snapshot.data;
      if(data==null)return fallback??SizedBox(width:width,height:height);
      final sx=width/source.width;
      final sy=height/source.height;
      return SizedBox(
        width:width,
        height:height,
        child:ClipRect(
          child:OverflowBox(
            alignment:Alignment.topLeft,
            minWidth:sheetWidth*sx,
            maxWidth:sheetWidth*sx,
            minHeight:sheetHeight*sy,
            maxHeight:sheetHeight*sy,
            child:Transform.translate(
              offset:Offset(-source.left*sx,-source.top*sy),
              child:Image.memory(
                data,
                width:sheetWidth*sx,
                height:sheetHeight*sy,
                fit:BoxFit.fill,
                filterQuality:filterQuality,
                gaplessPlayback:true,
              ),
            ),
          ),
        ),
      );
    },
  );
}
