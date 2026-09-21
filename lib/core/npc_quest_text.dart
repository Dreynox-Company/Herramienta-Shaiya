import 'dart:convert';
import 'dart:typed_data';

class NpcLocalizedText {
  final String name,welcome;
  final List<String> destinations;
  const NpcLocalizedText(this.name,this.welcome,[this.destinations=const []]);
}

class QuestLocalizedText {
  final String name,summary,completion,initialDescription,welcome,reminder,alternate;
  final List<String> completionVariants;
  const QuestLocalizedText({required this.name,required this.summary,required this.completion,required this.initialDescription,required this.welcome,required this.reminder,required this.alternate,required this.completionVariants});
}

class SpanishNpcQuestText {
  final Map<int,List<NpcLocalizedText>> npcByType;
  final List<QuestLocalizedText> quests;
  const SpanishNpcQuestText(this.npcByType,this.quests);

  NpcLocalizedText? npc(int type,int typeId){
    final list=npcByType[type];
    if(list==null||typeId<=0||typeId>list.length)return null;
    return list[typeId-1];
  }
  QuestLocalizedText? quest(int questId){
    if(questId<=0||questId>quests.length)return null;
    return quests[questId-1];
  }

  static SpanishNpcQuestText parse(Uint8List bytes,String source){
    final r=_TextReader(bytes,source),types=<int,List<NpcLocalizedText>>{};
    for(var type=1;type<=13;type++){
      final n=r.count(100000),rows=<NpcLocalizedText>[];
      for(var i=0;i<n;i++){
        final name=r.string(),welcome=r.string();
        if(type==2){rows.add(NpcLocalizedText(name,welcome,[r.string(),r.string(),r.string()]));}
        else{rows.add(NpcLocalizedText(name,welcome));}
      }
      types[type]=rows;
    }
    final count=r.count(100000),quests=<QuestLocalizedText>[];
    for(var i=0;i<count;i++){
      final fields=List.generate(12,(_)=>r.string());
      quests.add(QuestLocalizedText(
        name:fields[0],summary:fields[1],completion:fields[2],
        completionVariants:fields.sublist(2,8),
        initialDescription:fields[8],welcome:fields[9],reminder:fields[10],alternate:fields[11]));
    }
    if(!r.done)throw FormatException('$source · quedan ${bytes.length-r.offset} bytes sin interpretar.');
    return SpanishNpcQuestText(types,quests);
  }
}

class _TextReader {
  final Uint8List bytes;final String source;late final ByteData data=ByteData.sublistView(bytes);int offset=0;
  _TextReader(this.bytes,this.source);
  bool get done=>offset==bytes.length;
  int i32(){if(offset+4>bytes.length)throw FormatException('$source · texto truncado en $offset');final v=data.getInt32(offset,Endian.little);offset+=4;return v;}
  int count(int max){final n=i32();if(n<0||n>max)throw FormatException('$source · recuento inválido $n en $offset');return n;}
  String string(){final n=count(16*1024*1024);if(offset+n>bytes.length)throw FormatException('$source · cadena truncada en $offset');var raw=bytes.sublist(offset,offset+n);offset+=n;if(raw.isNotEmpty&&raw.last==0)raw=raw.sublist(0,raw.length-1);return latin1.decode(raw,allowInvalid:true).replaceAll('\u0000','').trimRight();}
}
