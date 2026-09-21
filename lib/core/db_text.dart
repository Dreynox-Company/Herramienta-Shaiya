import 'dart:convert';
import 'dart:typed_data';

class SkillTextRecord {
  final int id,level;
  final String name,text;
  const SkillTextRecord(this.id,this.level,this.name,this.text);
  String get key=>'${id}:${level}';
}

class ItemTextRecord {
  final int type,id;
  final String name,text;
  const ItemTextRecord(this.type,this.id,this.name,this.text);
  String get key=>'${type}:${id}';
}

class BinarySDataText {
  static ({Map<String,SkillTextRecord> skills,List<String> fields}) skills(Uint8List bytes,String source){
    final r=_Reader(bytes,source)..skip(128);
    final fields=r.fields();
    if(fields.length!=4)throw FormatException('$source · se esperaban 4 campos y hay ${fields.length}.');
    final count=r.i32Checked(1000000),out=<String,SkillTextRecord>{};
    for(var i=0;i<count;i++){
      final id=r.i64(),level=r.i64(),name=r.string(),text=r.string();
      final row=SkillTextRecord(id,level,name,text);out[row.key]=row;
    }
    r.end();return (skills:out,fields:fields);
  }

  static ({Map<String,ItemTextRecord> items,List<String> fields}) items(Uint8List bytes,String source){
    final r=_Reader(bytes,source)..skip(128);
    final fields=r.fields();
    if(fields.length!=4)throw FormatException('$source · se esperaban 4 campos y hay ${fields.length}.');
    final count=r.i32Checked(1000000),out=<String,ItemTextRecord>{};
    for(var i=0;i<count;i++){
      final type=r.i64(),id=r.i64(),name=r.string(),text=r.string();
      final row=ItemTextRecord(type,id,name,text);out[row.key]=row;
    }
    r.end();return (items:out,fields:fields);
  }
}

class _Reader {
  final Uint8List bytes;final String source;late final ByteData data=ByteData.sublistView(bytes);int offset=0;
  _Reader(this.bytes,this.source);
  void _need(int n){if(n<0||offset+n>bytes.length)throw FormatException('$source · truncado en $offset, requiere $n bytes.');}
  void skip(int n){_need(n);offset+=n;}
  int i32(){_need(4);final v=data.getInt32(offset,Endian.little);offset+=4;return v;}
  int i32Checked(int max){final n=i32();if(n<0||n>max)throw FormatException('$source · recuento inválido $n en $offset.');return n;}
  int i64(){_need(8);final v=data.getInt64(offset,Endian.little);offset+=8;return v;}
  int u8(){_need(1);return bytes[offset++];}
  String string(){
    final n=i32Checked(32*1024*1024);_need(n);var raw=bytes.sublist(offset,offset+n);offset+=n;
    if(raw.isNotEmpty&&raw.last==0)raw=raw.sublist(0,raw.length-1);
    return latin1.decode(raw,allowInvalid:true).replaceAll('\u0000','');
  }
  List<String> fields(){
    final n=i32Checked(1024),out=<String>[];
    for(var i=0;i<n;i++){
      final chars=u8();_need(chars*2);
      final raw=bytes.sublist(offset,offset+chars*2);offset+=chars*2;
      out.add(const Utf16LeDecoder().convert(raw));
    }
    return out;
  }
  void end(){if(offset!=bytes.length)throw FormatException('$source · quedan ${bytes.length-offset} bytes sin interpretar.');}
}

class Utf16LeDecoder {
  const Utf16LeDecoder();
  String convert(List<int> bytes){
    if(bytes.length.isOdd)throw const FormatException('UTF-16LE impar.');
    final codes=<int>[];
    for(var i=0;i<bytes.length;i+=2)codes.add(bytes[i]|(bytes[i+1]<<8));
    return String.fromCharCodes(codes);
  }
}
