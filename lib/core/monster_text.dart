import 'dart:convert';
import 'dart:typed_data';

class MonsterTextData {
  final Map<int,String> names;
  const MonsterTextData(this.names);

  static MonsterTextData parse(Uint8List bytes,String source){
    final r=_Reader(bytes,source);
    r.skip(128);
    final fields=r.i32();
    if(fields<0||fields>128)throw FormatException('$source · campos inválidos: $fields');
    for(var i=0;i<fields;i++){
      final chars=r.u8();
      r.skip(chars*2);
    }
    final count=r.i32();
    if(count<0||count>1000000)throw FormatException('$source · registros inválidos: $count');
    final out=<int,String>{};
    for(var i=0;i<count;i++){
      final id=r.i64();
      final n=r.i32();
      if(n<0||n>1024*1024)throw FormatException('$source · nombre inválido en $i');
      final raw=r.take(n);
      out[id]=latin1.decode(raw,allowInvalid:true).replaceAll('\u0000','').trim();
    }
    return MonsterTextData(out);
  }
}

class _Reader {
  final Uint8List b;final String source;late final ByteData d=ByteData.sublistView(b);int o=0;
  _Reader(this.b,this.source);
  void need(int n){if(n<0||o+n>b.length)throw FormatException('$source · truncado en $o (+$n)');}
  void skip(int n){need(n);o+=n;}
  int u8(){need(1);return b[o++];}
  int i32(){need(4);final v=d.getInt32(o,Endian.little);o+=4;return v;}
  int i64(){need(8);final v=d.getInt64(o,Endian.little);o+=8;return v;}
  Uint8List take(int n){need(n);final v=Uint8List.sublistView(b,o,o+n);o+=n;return v;}
}
