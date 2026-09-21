import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/npc_quest_text.dart';

class W {
  final BytesBuilder b=BytesBuilder();
  void i32(int v){final d=ByteData(4)..setInt32(0,v,Endian.little);b.add(d.buffer.asUint8List());}
  void s(String value){final raw=latin1.encode(value);i32(raw.length);b.add(raw);}
  Uint8List done()=>b.takeBytes();
}

void main(){
  test('NpcQuestTrans Spain maps one-based NPC ids and quest text',(){
    final w=W();
    for(var type=1;type<=13;type++){
      w.i32(type==8?1:0);
      if(type==8){w.s('Guardia de Erina');w.s('Mantén los ojos abiertos.');}
    }
    w.i32(1);
    final fields=[
      'Operación básica','Aprende la interfaz','Completada','','','','','',
      'Habla con el guardia.','Bienvenido.','Sigue practicando.','Más tarde.',
    ];
    for(final f in fields){w.s(f);}
    final parsed=SpanishNpcQuestText.parse(w.done(),'fixture');
    expect(parsed.npc(8,1)?.name,'Guardia de Erina');
    expect(parsed.npc(8,0),isNull);
    expect(parsed.quest(1)?.name,'Operación básica');
    expect(parsed.quest(1)?.initialDescription,'Habla con el guardia.');
  });
}
