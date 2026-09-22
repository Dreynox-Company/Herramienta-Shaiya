import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

class PsPacketType {
  static const loginHandshake=0xA101;
  static const loginRequest=0xA102;
  static const oauthLoginRequest=0xA110;
  static const serverList=0xA201;
  static const selectServer=0xA202;
  static const gameHandshake=0xA301;
  static const characterList=0x0101;
  static const createCharacter=0x0102;
  static const deleteCharacter=0x0103;
  static const selectCharacter=0x0104;
  static const characterDetails=0x0105;
  static const characterItems=0x0106;
  static const characterSkills=0x0108;
  static const characterSkillBar=0x010B;
  static const accountFaction=0x0109;
  static const characterEnteredMap=0x0201;
  static const inventoryMoveItem=0x0204;
  static const addItem=0x0205;
  static const removeItem=0x0206;
  static const characterMove=0x0501;
  static const useMobTargetSkill=0x0517;
  static const characterCurrentHitpoints=0x0521;
  static const characterAdditionalStats=0x0526;
  static const mobEnter=0x0601;
  static const mobLeave=0x0602;
  static const mobMove=0x0603;
  static const mobDeath=0x0606;
  static const questList=0x0901;
  static const questStart=0x0902;
  static const questEnd=0x0903;
  static const questUpdateCount=0x0905;
  static const questFinishedList=0x0906;
  static const questEndSelect=0x0907;
  static const questQuit=0x0908;
  static const mapNpcEnter=0x0E01;
  static const mapNpcLeave=0x0E02;
  static const mapNpcMove=0x0E03;
}

class PsPacket {
  final int type;
  final Uint8List body;
  const PsPacket(this.type,this.body);
  @override String toString()=> '0x${type.toRadixString(16).padLeft(4,'0')} (${body.length} B)';
}

int _u16(Uint8List b,int o)=>b[o]|(b[o+1]<<8);
int _i32(Uint8List b,int o)=>ByteData.sublistView(b).getInt32(o,Endian.little);

Uint8List _u16Bytes(int value){
  final b=ByteData(2)..setUint16(0,value,Endian.little);
  return b.buffer.asUint8List();
}
Uint8List _i32Bytes(int value){
  final b=ByteData(4)..setInt32(0,value,Endian.little);
  return b.buffer.asUint8List();
}
Uint8List _u32Bytes(int value){
  final b=ByteData(4)..setUint32(0,value,Endian.little);
  return b.buffer.asUint8List();
}
Uint8List _i16Bytes(int value){
  final b=ByteData(2)..setInt16(0,value,Endian.little);
  return b.buffer.asUint8List();
}
Uint8List _f32Bytes(double value){
  final b=ByteData(4)..setFloat32(0,value,Endian.little);
  return b.buffer.asUint8List();
}

BigInt _bigIntLe(Uint8List bytes){
  var n=BigInt.zero;
  for(var i=0;i<bytes.length;i++)n|=BigInt.from(bytes[i])<<(8*i);
  return n;
}
Uint8List _bigIntLeBytes(BigInt value){
  if(value==BigInt.zero)return Uint8List.fromList([0]);
  final out=<int>[];
  var n=value;
  while(n>BigInt.zero){
    out.add((n&BigInt.from(0xff)).toInt());
    n>>=8;
  }
  return Uint8List.fromList(out);
}

class _AesCtrLe {
  final AESEngine _aes=AESEngine();
  final Uint8List _counter;
  Uint8List _mask=Uint8List(0);
  int _maskOffset=0;

  _AesCtrLe(Uint8List key,Uint8List counter):_counter=Uint8List.fromList(counter){
    if(key.length!=16||counter.length!=16)throw ArgumentError('AES-CTR ps0032 requiere key/counter de 16 bytes.');
    _aes.init(true,KeyParameter(key));
  }

  Uint8List apply(Uint8List input){
    final out=Uint8List(input.length);
    for(var i=0;i<input.length;i++){
      if(_maskOffset>=_mask.length)_nextMask();
      out[i]=input[i]^_mask[_maskOffset++];
    }
    return out;
  }

  void _nextMask(){
    final block=Uint8List(16);
    _aes.processBlock(_counter,0,block,0);
    _mask=block;_maskOffset=0;
    for(var i=0;i<_counter.length;i++){
      _counter[i]=(_counter[i]+1)&0xff;
      if(_counter[i]!=0)break;
    }
  }
}


class _ExpandedXor {
  final Uint8List table;
  _ExpandedXor(Uint8List key):table=_expand(key);

  static Uint8List _expand(Uint8List key){
    if(key.length!=16)throw ArgumentError('XOR ps0032 requiere 16 bytes.');
    final out=<int>[];
    var digest=hash.sha256.convert(key).bytes;
    out.addAll(digest);
    for(var i=0;i<127;i++){
      final nextKey=Uint8List.fromList(out.sublist(out.length-16));
      digest=hash.sha256.convert(nextKey).bytes;
      out.addAll(digest);
    }
    return Uint8List.fromList(out);
  }

  Uint8List apply(Uint8List input){
    final n=input.length;
    if(n*2>table.length)throw StateError('Paquete XOR ps0032 excede tabla expandida: $n');
    final out=Uint8List(n);
    for(var i=0;i<n;i++)out[i]=input[i]^table[i+n];
    return out;
  }
}

class PsConnection {
  final Socket socket;
  final List<int> _buffer=[];
  final List<PsPacket> _queued=[];
  final List<Completer<PsPacket>> _waiters=[];
  final StreamController<PsPacket> _packets=StreamController<PsPacket>.broadcast(sync:true);
  StreamSubscription<Uint8List>? _subscription;
  _AesCtrLe? _recv,_send;
  _ExpandedXor? _expandedRecv;
  bool _closed=false;

  PsConnection._(this.socket){
    _subscription=socket.listen(_onData,onError:_onError,onDone:_onDone,cancelOnError:false);
  }

  static Future<PsConnection> connect(String host,int port,{Duration timeout=const Duration(seconds:8)}) async {
    final socket=await Socket.connect(host,port,timeout:timeout);
    socket.setOption(SocketOption.tcpNoDelay,true);
    return PsConnection._(socket);
  }

  void useCipher(Uint8List key,Uint8List counter){
    _recv=_AesCtrLe(key,counter);
    _send=_AesCtrLe(key,counter);
    _expandedRecv=null;
  }

  void switchIncomingToExpanded(Uint8List xorKey){
    _expandedRecv=_ExpandedXor(xorKey);
  }

  Future<void> send(int type,[List<int> body=const [],bool plain=false]) async {
    if(_closed)throw StateError('Conexión ps0032 cerrada.');
    final raw=Uint8List(2+body.length);
    raw.setRange(0,2,_u16Bytes(type));
    raw.setRange(2,raw.length,body);
    final payload=plain||_send==null?raw:_send!.apply(raw);
    final length=payload.length+2;
    if(length>0xffff)throw StateError('Paquete ps0032 demasiado grande: $length');
    socket.add([..._u16Bytes(length),...payload]);
    await socket.flush();
  }

  Future<PsPacket> next({Duration timeout=const Duration(seconds:8)}) {
    if(_queued.isNotEmpty)return Future.value(_queued.removeAt(0));
    if(_closed)return Future.error(StateError('Conexión ps0032 cerrada.'));
    final c=Completer<PsPacket>();_waiters.add(c);
    return c.future.timeout(timeout,onTimeout:(){
      _waiters.remove(c);
      throw TimeoutException('Timeout esperando paquete ps0032.');
    });
  }

  Future<PsPacket> nextType(int type,{Duration timeout=const Duration(seconds:12)}) async {
    final deadline=DateTime.now().add(timeout);
    while(DateTime.now().isBefore(deadline)){
      final left=deadline.difference(DateTime.now());
      final p=await next(timeout:left);
      if(p.type==type)return p;
    }
    throw TimeoutException('Timeout esperando 0x${type.toRadixString(16)}');
  }

  void _onData(Uint8List chunk){
    _buffer.addAll(chunk);
    while(_buffer.length>=2){
      final length=_buffer[0]|(_buffer[1]<<8);
      if(length<4){_fail(StateError('Longitud ps0032 inválida: $length'));return;}
      if(_buffer.length<length)return;
      final encrypted=Uint8List.fromList(_buffer.sublist(2,length));
      _buffer.removeRange(0,length);
      final data=_expandedRecv!=null?_expandedRecv!.apply(encrypted):(_recv==null?encrypted:_recv!.apply(encrypted));
      if(data.length<2){_fail(StateError('Payload ps0032 truncado.'));return;}
      _emit(PsPacket(_u16(data,0),Uint8List.sublistView(data,2)));
    }
  }

  Stream<PsPacket> get packets=>_packets.stream;

  void _emit(PsPacket packet){
    if(!_packets.isClosed)_packets.add(packet);
    if(_waiters.isNotEmpty)_waiters.removeAt(0).complete(packet);
    else if(!_packets.hasListener)_queued.add(packet);
  }
  void _onError(Object e)=>_fail(e);
  void _onDone()=>_fail(StateError('Socket ps0032 cerrado por el servidor.'));
  void _fail(Object e){
    if(_closed)return;
    _closed=true;
    for(final w in _waiters){if(!w.isCompleted)w.completeError(e);}
    _waiters.clear();
    if(!_packets.isClosed)_packets.addError(e);
  }

  Future<void> close() async {
    if(_closed)return;
    _closed=true;
    await _subscription?.cancel();
    await socket.close();
    if(!_packets.isClosed)await _packets.close();
  }
}


class PsNpcEnter {
  final int globalId,type,typeId,angle;
  final double x,y,z;
  const PsNpcEnter(this.globalId,this.type,this.typeId,this.x,this.y,this.z,this.angle);
  static PsNpcEnter parse(PsPacket p){
    if(p.type!=PsPacketType.mapNpcEnter||p.body.length<21){
      throw FormatException('MAP_NPC_ENTER truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsNpcEnter(
      d.getUint32(0,Endian.little),
      p.body[4],
      d.getInt16(5,Endian.little),
      d.getFloat32(7,Endian.little),
      d.getFloat32(11,Endian.little),
      d.getFloat32(15,Endian.little),
      d.getUint16(19,Endian.little),
    );
  }
}

class PsMobEnter {
  final int globalId,mobId;
  final bool isNew;
  final double x,z;
  const PsMobEnter(this.globalId,this.isNew,this.mobId,this.x,this.z);
  static PsMobEnter parse(PsPacket p){
    if(p.type!=PsPacketType.mobEnter||p.body.length<15){
      throw FormatException('MOB_ENTER truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsMobEnter(
      d.getUint32(0,Endian.little),
      p.body[4]!=0,
      d.getUint16(5,Endian.little),
      d.getFloat32(7,Endian.little),
      d.getFloat32(11,Endian.little),
    );
  }
}

class PsEnteredMap {
  final int characterId,isAdmin,angle,guildId,vehicleId;
  final double x,y,z;
  const PsEnteredMap(this.characterId,this.isAdmin,this.angle,this.x,this.y,this.z,this.guildId,this.vehicleId);
  static PsEnteredMap parse(PsPacket p){
    if(p.type!=PsPacketType.characterEnteredMap||p.body.length<27){
      throw FormatException('CHARACTER_ENTERED_MAP truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsEnteredMap(
      d.getUint32(0,Endian.little),
      p.body[4],
      d.getUint16(5,Endian.little),
      d.getFloat32(7,Endian.little),
      d.getFloat32(11,Endian.little),
      d.getFloat32(15,Endian.little),
      d.getUint32(19,Endian.little),
      d.getUint32(23,Endian.little),
    );
  }
}

class PsQuestProgress {
  final int questId,remaining,count1,count2,count3;
  const PsQuestProgress(this.questId,this.remaining,this.count1,this.count2,this.count3);
}
class PsFinishedQuest {
  final int questId;
  final bool success;
  const PsFinishedQuest(this.questId,this.success);
}

List<PsQuestProgress> parseQuestList(PsPacket p){
  if(p.type!=PsPacketType.questList||p.body.isEmpty)return const [];
  final count=p.body[0];
  if(p.body.length<1+count*7)throw FormatException('QUEST_LIST truncado.');
  final d=ByteData.sublistView(p.body),out=<PsQuestProgress>[];
  var o=1;
  for(var i=0;i<count;i++,o+=7){
    out.add(PsQuestProgress(
      d.getInt16(o,Endian.little),
      d.getUint16(o+2,Endian.little),
      p.body[o+4],p.body[o+5],p.body[o+6],
    ));
  }
  return out;
}

List<PsFinishedQuest> parseFinishedQuests(PsPacket p){
  if(p.type!=PsPacketType.questFinishedList||p.body.isEmpty)return const [];
  final count=p.body[0];
  if(p.body.length<1+count*3)throw FormatException('QUEST_FINISHED_LIST truncado.');
  final d=ByteData.sublistView(p.body),out=<PsFinishedQuest>[];
  var o=1;
  for(var i=0;i<count;i++,o+=3){
    out.add(PsFinishedQuest(d.getInt16(o,Endian.little),p.body[o+2]!=0));
  }
  return out;
}

class PsWorldSnapshot {
  final PsEnteredMap? self;
  final List<PsNpcEnter> npcs;
  final List<PsMobEnter> mobs;
  final List<PsQuestProgress> quests;
  final List<PsFinishedQuest> finishedQuests;
  const PsWorldSnapshot({
    required this.self,required this.npcs,required this.mobs,
    required this.quests,required this.finishedQuests,
  });

  factory PsWorldSnapshot.fromPackets(Iterable<PsPacket> packets){
    PsEnteredMap? self;
    final npcs=<PsNpcEnter>[],mobs=<PsMobEnter>[],quests=<PsQuestProgress>[],finished=<PsFinishedQuest>[];
    for(final p in packets){
      if(p.type==PsPacketType.characterEnteredMap)self=PsEnteredMap.parse(p);
      else if(p.type==PsPacketType.mapNpcEnter)npcs.add(PsNpcEnter.parse(p));
      else if(p.type==PsPacketType.mobEnter)mobs.add(PsMobEnter.parse(p));
      else if(p.type==PsPacketType.questList)quests.addAll(parseQuestList(p));
      else if(p.type==PsPacketType.questFinishedList)finished.addAll(parseFinishedQuests(p));
    }
    return PsWorldSnapshot(
      self:self,npcs:List.unmodifiable(npcs),mobs:List.unmodifiable(mobs),
      quests:List.unmodifiable(quests),finishedQuests:List.unmodifiable(finished),
    );
  }
}

class LoginSession {
  final int userId;
  final Uint8List sessionId,key,iv;
  final int worldId;
  const LoginSession({
    required this.userId,required this.sessionId,required this.key,required this.iv,required this.worldId,
  });
}

class PsCharacterSlot {
  final int slot,id,mapId;
  final int level,race,mode,hair,face,height,profession,gender;
  final String name;
  final bool isDelete,isRename;
  const PsCharacterSlot({
    required this.slot,required this.id,required this.mapId,
    required this.level,required this.race,required this.mode,
    required this.hair,required this.face,required this.height,
    required this.profession,required this.gender,
    required this.name,required this.isDelete,required this.isRename,
  });
  bool get exists=>id!=0;

  static PsCharacterSlot parse(PsPacket packet){
    if(packet.type!=PsPacketType.characterList||packet.body.length<5){
      throw FormatException('CHARACTER_LIST inválido.');
    }
    final b=packet.body,slot=b[0],id=ByteData.sublistView(b).getUint32(1,Endian.little);
    if(id==0){
      return PsCharacterSlot(
        slot:slot,id:0,mapId:0,level:0,race:0,mode:0,hair:0,face:0,height:0,profession:0,gender:0,
        name:'',isDelete:false,isRename:false,
      );
    }
    if(b.length<657)throw FormatException('CHARACTER_LIST existente truncado: ${b.length}');
    final rawName=b.sublist(612,631);
    final zero=rawName.indexOf(0);
    final name=utf8.decode(zero<0?rawName:rawName.sublist(0,zero),allowMalformed:true);
    return PsCharacterSlot(
      slot:slot,id:id,level:_u16(b,9),race:b[11],mode:b[12],hair:b[13],
      face:b[14],height:b[15],profession:b[16],gender:b[17],mapId:_u16(b,18),
      name:name,isDelete:b[631]!=0,isRename:b[632]!=0,
    );
  }
}

class PsCharacterDetails {
  final int strength,dexterity,reaction,intelligence,wisdom,luck;
  final int statPoint,skillPoint,maxHp,maxMp,maxSp,angle;
  final int startExp,endExp,currentExp,gold,kills,deaths,victories,defeats;
  final double x,y,z;
  final String guildName;
  const PsCharacterDetails({
    required this.strength,required this.dexterity,required this.reaction,
    required this.intelligence,required this.wisdom,required this.luck,
    required this.statPoint,required this.skillPoint,
    required this.maxHp,required this.maxMp,required this.maxSp,required this.angle,
    required this.startExp,required this.endExp,required this.currentExp,required this.gold,
    required this.x,required this.y,required this.z,
    required this.kills,required this.deaths,required this.victories,required this.defeats,
    required this.guildName,
  });
  double get experienceRatio {
    final span=endExp-startExp;
    if(span<=0)return 0;
    return ((currentExp-startExp)/span).clamp(0.0,1.0);
  }
  static PsCharacterDetails parse(PsPacket p){
    if(p.type!=PsPacketType.characterDetails||p.body.length<74){
      throw FormatException('CHARACTER_DETAILS truncado: ${p.body.length}');
    }
    final b=p.body,d=ByteData.sublistView(b);
    String guild='';
    if(b.length>=99){
      final raw=b.sublist(74,99),zero=raw.indexOf(0);
      guild=utf8.decode(zero<0?raw:raw.sublist(0,zero),allowMalformed:true);
    }
    return PsCharacterDetails(
      strength:d.getUint16(0,Endian.little),
      dexterity:d.getUint16(2,Endian.little),
      reaction:d.getUint16(4,Endian.little),
      intelligence:d.getUint16(6,Endian.little),
      wisdom:d.getUint16(8,Endian.little),
      luck:d.getUint16(10,Endian.little),
      statPoint:d.getUint16(12,Endian.little),
      skillPoint:d.getUint16(14,Endian.little),
      maxHp:d.getInt32(16,Endian.little),
      maxMp:d.getInt32(20,Endian.little),
      maxSp:d.getInt32(24,Endian.little),
      angle:d.getUint16(28,Endian.little),
      startExp:d.getUint32(30,Endian.little),
      endExp:d.getUint32(34,Endian.little),
      currentExp:d.getUint32(38,Endian.little),
      gold:d.getUint32(42,Endian.little),
      x:d.getFloat32(46,Endian.little),
      y:d.getFloat32(50,Endian.little),
      z:d.getFloat32(54,Endian.little),
      kills:d.getUint32(58,Endian.little),
      deaths:d.getUint32(62,Endian.little),
      victories:d.getUint32(66,Endian.little),
      defeats:d.getUint32(70,Endian.little),
      guildName:guild,
    );
  }
}

class PsHitpoints {
  final int hp,mp,sp;
  const PsHitpoints(this.hp,this.mp,this.sp);
  static PsHitpoints parse(PsPacket p){
    if(p.type!=PsPacketType.characterCurrentHitpoints||p.body.length<12){
      throw FormatException('CHARACTER_CURRENT_HITPOINTS truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsHitpoints(
      d.getInt32(0,Endian.little),
      d.getInt32(4,Endian.little),
      d.getInt32(8,Endian.little),
    );
  }
}

class PsAdditionalStats {
  final int strength,reaction,intelligence,wisdom,dexterity,luck;
  final int minAttack,maxAttack,minMagicAttack,maxMagicAttack,defense,resistance;
  const PsAdditionalStats(
    this.strength,this.reaction,this.intelligence,this.wisdom,this.dexterity,this.luck,
    this.minAttack,this.maxAttack,this.minMagicAttack,this.maxMagicAttack,this.defense,this.resistance,
  );
  static PsAdditionalStats parse(PsPacket p){
    if(p.type!=PsPacketType.characterAdditionalStats||p.body.length<48){
      throw FormatException('CHARACTER_ADDITIONAL_STATS truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    final values=List<int>.generate(12,(i)=>d.getInt32(i*4,Endian.little));
    return PsAdditionalStats(
      values[0],values[1],values[2],values[3],values[4],values[5],
      values[6],values[7],values[8],values[9],values[10],values[11],
    );
  }
}

class PsInventoryItem {
  final int bag,slot,type,typeId,quality,count;
  final List<int> gems;
  final String craftName;
  final bool dyed;
  const PsInventoryItem({
    required this.bag,required this.slot,required this.type,required this.typeId,
    required this.quality,required this.count,required this.gems,required this.craftName,required this.dyed,
  });
  String get key=>'${type}:${typeId}';
}

List<PsInventoryItem> parseInventoryItems(PsPacket p){
  if(p.type!=PsPacketType.characterItems||p.body.isEmpty)return const [];
  final b=p.body,d=ByteData.sublistView(b),count=b[0],out=<PsInventoryItem>[];
  const size=102;
  if(b.length<1+count*size)throw FormatException('CHARACTER_ITEMS truncado: count=$count bytes=${b.length}.');
  var o=1;
  for(var i=0;i<count;i++,o+=size){
    final gems=List<int>.generate(6,(j)=>d.getInt32(o+6+j*4,Endian.little));
    final rawName=b.sublist(o+31,o+51),zero=rawName.indexOf(0);
    final craft=utf8.decode(zero<0?rawName:rawName.sublist(0,zero),allowMalformed:true);
    out.add(PsInventoryItem(
      bag:b[o],slot:b[o+1],type:b[o+2],typeId:b[o+3],
      quality:d.getUint16(o+4,Endian.little),gems:List.unmodifiable(gems),
      count:b[o+30],craftName:craft,dyed:b[o+74]!=0,
    ));
  }
  return out;
}

class PsInventoryRemoval {
  final int bag,slot,type,typeId,count;
  const PsInventoryRemoval(this.bag,this.slot,this.type,this.typeId,this.count);
  bool get fullRemove=>type==0&&typeId==0&&count==0;
  static PsInventoryRemoval parse(PsPacket p){
    if(p.type!=PsPacketType.removeItem||p.body.length<5){
      throw FormatException('REMOVE_ITEM truncado: ${p.body.length}');
    }
    return PsInventoryRemoval(p.body[0],p.body[1],p.body[2],p.body[3],p.body[4]);
  }
}

PsInventoryItem _inventory102(Uint8List b,int o){
  if(o<0||o+102>b.length)throw FormatException('Inventory item 102 truncado en $o/${b.length}.');
  final d=ByteData.sublistView(b),gems=List<int>.generate(6,(j)=>d.getInt32(o+57+j*4,Endian.little));
  final rawName=b.sublist(o+81,o+101),zero=rawName.indexOf(0);
  final craft=utf8.decode(zero<0?rawName:rawName.sublist(0,zero),allowMalformed:true);
  return PsInventoryItem(
    bag:b[o],slot:b[o+1],type:b[o+2],typeId:b[o+3],
    count:b[o+4],quality:d.getUint16(o+5,Endian.little),
    gems:List.unmodifiable(gems),craftName:craft,dyed:b[o+30]!=0,
  );
}

PsInventoryItem parseAddedInventoryItem(PsPacket p){
  if(p.type!=PsPacketType.addItem||p.body.length<106){
    throw FormatException('ADD_ITEM truncado/no-item: ${p.body.length}');
  }
  final b=p.body,d=ByteData.sublistView(b),gems=List<int>.generate(6,(j)=>d.getInt32(11+j*4,Endian.little));
  final rawName=b.sublist(85,105),zero=rawName.indexOf(0);
  final craft=utf8.decode(zero<0?rawName:rawName.sublist(0,zero),allowMalformed:true);
  return PsInventoryItem(
    bag:b[0],slot:b[1],type:b[2],typeId:b[3],count:b[4],
    quality:d.getUint16(5,Endian.little),gems:List.unmodifiable(gems),
    craftName:craft,dyed:b[58]!=0,
  );
}

class PsInventoryMove {
  final PsInventoryItem source,destination;
  final int gold;
  const PsInventoryMove(this.source,this.destination,this.gold);
  static PsInventoryMove parse(PsPacket p){
    if(p.type!=PsPacketType.inventoryMoveItem){
      throw FormatException('No es INVENTORY_MOVE_ITEM.');
    }
    final b=p.body;
    final prefix=b.length>=212?4:0;
    if(b.length<prefix+208)throw FormatException('INVENTORY_MOVE_ITEM truncado: ${b.length}');
    final source=_inventory102(b,prefix),destination=_inventory102(b,prefix+102);
    final gold=ByteData.sublistView(b).getUint32(prefix+204,Endian.little);
    return PsInventoryMove(source,destination,gold);
  }
}

class PsLearnedSkill {
  final int skillId,level,number,cooldownSeconds;
  const PsLearnedSkill(this.skillId,this.level,this.number,this.cooldownSeconds);
}

class PsSkillBook {
  final int skillPoints;
  final List<PsLearnedSkill> skills;
  const PsSkillBook(this.skillPoints,this.skills);
  PsLearnedSkill? byNumber(int number)=>skills.where((s)=>s.number==number).firstOrNull;
  PsLearnedSkill? bySkillId(int skillId)=>skills.where((s)=>s.skillId==skillId).firstOrNull;
  static PsSkillBook parse(PsPacket p){
    if(p.type!=PsPacketType.characterSkills||p.body.length<3){
      throw FormatException('CHARACTER_SKILLS truncado: ${p.body.length}');
    }
    final b=p.body,d=ByteData.sublistView(b);
    final points=d.getUint16(0,Endian.little),count=b[2];
    if(b.length<3+count*8)throw FormatException('CHARACTER_SKILLS count truncado: $count.');
    final skills=<PsLearnedSkill>[];
    var o=3;
    for(var i=0;i<count;i++,o+=8){
      skills.add(PsLearnedSkill(
        d.getUint16(o,Endian.little),b[o+2],b[o+3],d.getInt32(o+4,Endian.little),
      ));
    }
    return PsSkillBook(points,List.unmodifiable(skills));
  }
}

class PsQuickSlot {
  final int bar,slot,bag,number,cooldown;
  const PsQuickSlot(this.bar,this.slot,this.bag,this.number,this.cooldown);
  bool get isSkill=>bag==100;
}

class PsSkillBar {
  final List<PsQuickSlot> slots;
  const PsSkillBar(this.slots);
  static PsSkillBar parse(PsPacket p){
    if(p.type!=PsPacketType.characterSkillBar||p.body.length<5){
      throw FormatException('CHARACTER_SKILL_BAR truncado: ${p.body.length}');
    }
    final b=p.body,d=ByteData.sublistView(b);
    final count=b[0],items=count==0?0:count-1;
    if(b.length<5+items*9)throw FormatException('CHARACTER_SKILL_BAR count truncado: $count.');
    final out=<PsQuickSlot>[];
    var o=5;
    for(var i=0;i<items;i++,o+=9){
      out.add(PsQuickSlot(b[o],b[o+1],b[o+2],d.getUint16(o+3,Endian.little),d.getInt32(o+5,Endian.little)));
    }
    out.sort((a,b){final byBar=a.bar.compareTo(b.bar);return byBar!=0?byBar:a.slot.compareTo(b.slot);});
    return PsSkillBar(List.unmodifiable(out));
  }
}

class WorldBootstrap {
  final int faction,maxMode;
  final List<PsPacket> packets;
  const WorldBootstrap(this.faction,this.maxMode,this.packets);
  int get characterListPackets=>packets.where((p)=>p.type==PsPacketType.characterList).length;
  List<PsCharacterSlot> get characters=>packets
    .where((p)=>p.type==PsPacketType.characterList)
    .map(PsCharacterSlot.parse)
    .toList()
    ..sort((a,b)=>a.slot.compareTo(b.slot));
}


class PsWorldSession {
  final PsConnection connection;
  final int faction,maxMode;
  final Uint8List xorKey;
  final List<PsPacket> initialPackets;
  bool _expanded=false;

  PsWorldSession(this.connection,this.faction,this.maxMode,this.xorKey,this.initialPackets);

  List<PsCharacterSlot> get characters=>initialPackets
    .where((p)=>p.type==PsPacketType.characterList)
    .map(PsCharacterSlot.parse)
    .toList()
    ..sort((a,b)=>a.slot.compareTo(b.slot));

  Future<({int faction,int maxMode})> setFaction(int value) async {
    if(value<0||value>1)throw ArgumentError('Facción ps0032 inválida: $value');
    await connection.send(PsPacketType.accountFaction,[value]);
    final result=await connection.nextType(PsPacketType.accountFaction);
    if(result.body.length<2)throw FormatException('ACCOUNT_FACTION response truncado.');
    return (faction:result.body[0],maxMode:result.body[1]);
  }

  Future<void> deleteCharacter(int characterId) async {
    await connection.send(PsPacketType.deleteCharacter,_u32Bytes(characterId));
    final result=await connection.nextType(PsPacketType.deleteCharacter);
    if(result.body.length<5||result.body[0]!=0){
      throw StateError('DELETE_CHARACTER falló.');
    }
    final returned=ByteData.sublistView(result.body).getUint32(1,Endian.little);
    if(returned!=characterId)throw StateError('DELETE_CHARACTER devolvió id inesperado: $returned');
  }

  Future<List<PsCharacterSlot>> createCharacter({
    int slot=0,int race=0,int mode=2,int hair=0,int face=0,
    int height=2,int profession=0,int gender=0,String name='FlutterLocal',
  }) async {
    final rawName=utf8.encode(name);
    if(rawName.length>20)throw ArgumentError('Nombre de personaje demasiado largo.');
    final fixedName=Uint8List(21)..setRange(0,rawName.length,rawName);
    await connection.send(PsPacketType.createCharacter,[
      slot,race,mode,hair,face,height,profession,gender,...fixedName,
    ]);
    final result=await connection.nextType(PsPacketType.createCharacter);
    if(result.body.isEmpty||result.body[0]!=0){
      throw StateError('CREATE_CHARACTER falló: ${result.body.isEmpty?-1:result.body[0]}');
    }
    final slots=<PsCharacterSlot>[];
    final deadline=DateTime.now().add(const Duration(seconds:10));
    while(slots.length<5&&DateTime.now().isBefore(deadline)){
      final p=await connection.next(timeout:deadline.difference(DateTime.now()));
      if(p.type==PsPacketType.characterList)slots.add(PsCharacterSlot.parse(p));
    }
    if(slots.length<5)throw StateError('El servidor no devolvió los 5 CHARACTER_LIST después de crear.');
    slots.sort((a,b)=>a.slot.compareTo(b.slot));
    return slots;
  }

  Future<({PsCharacterDetails details,List<PsPacket> packets})> selectCharacter(int characterId) async {
    await connection.send(PsPacketType.selectCharacter,_u32Bytes(characterId));
    final packets=<PsPacket>[];
    PsCharacterDetails? details;
    final deadline=DateTime.now().add(const Duration(seconds:20));
    while(DateTime.now().isBefore(deadline)){
      final p=await connection.next(timeout:deadline.difference(DateTime.now()));
      packets.add(p);
      if(p.type==PsPacketType.selectCharacter){
        if(p.body.length<5||p.body[0]!=0)throw StateError('SELECT_CHARACTER rechazado.');
      }else if(p.type==PsPacketType.characterDetails){
        details=PsCharacterDetails.parse(p);
      }else if(p.type==PsPacketType.characterSkillBar){
        connection.switchIncomingToExpanded(xorKey);
        _expanded=true;
        break;
      }
    }
    if(details==null)throw StateError('No llegó CHARACTER_DETAILS.');
    if(!_expanded)throw StateError('No llegó CHARACTER_SKILL_BAR/cambio de cifrado.');
    return (details:details,packets:packets);
  }

  Future<List<PsPacket>> enterMap({Duration collect=const Duration(seconds:6)}) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de entrar al mapa.');
    // Client -> server remains AES-CTR. The server only changes outgoing crypto.
    await connection.send(PsPacketType.characterEnteredMap);
    final packets=<PsPacket>[];
    final deadline=DateTime.now().add(collect);
    while(DateTime.now().isBefore(deadline)){
      try{
        packets.add(await connection.next(timeout:const Duration(milliseconds:500)));
      }on TimeoutException{}
    }
    return packets;
  }

  Stream<PsPacket> get packets=>connection.packets;

  Future<void> moveCharacter({
    required double x,
    required double y,
    required double z,
    required double yawRadians,
    required bool run,
  }) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de moverlo.');
    var yaw=yawRadians%(2*pi);
    if(yaw<0)yaw+=2*pi;
    final angle=((yaw/(2*pi))*65536.0).round()&0xffff;
    await connection.send(PsPacketType.characterMove,[
      ..._u16Bytes(angle),
      run?1:0,
      ..._f32Bytes(x),
      ..._f32Bytes(y),
      ..._f32Bytes(z),
    ]);
  }

  Future<void> startQuest(int npcGlobalId,int questId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de iniciar una misión.');
    await connection.send(PsPacketType.questStart,[
      ..._u32Bytes(npcGlobalId),
      ..._i16Bytes(questId),
    ]);
    final result=await connection.nextType(PsPacketType.questStart);
    if(result.body.length<6)throw FormatException('QUEST_START response truncado.');
    final npc=ByteData.sublistView(result.body).getUint32(0,Endian.little);
    final quest=ByteData.sublistView(result.body).getInt16(4,Endian.little);
    if(npc!=npcGlobalId||quest!=questId)throw StateError('QUEST_START devolvió NPC/misión inesperados.');
  }

  Future<PsPacket> finishQuest(int npcGlobalId,int questId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de finalizar una misión.');
    await connection.send(PsPacketType.questEnd,[
      ..._u32Bytes(npcGlobalId),
      ..._i16Bytes(questId),
    ]);
    return connection.nextType(PsPacketType.questEnd);
  }

  Future<void> chooseQuestReward(int npcGlobalId,int questId,int index) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de elegir recompensa.');
    await connection.send(PsPacketType.questEndSelect,[
      ..._u32Bytes(npcGlobalId),
      ..._i16Bytes(questId),
      index&0xff,
    ]);
  }

  Future<void> quitQuest(int questId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de abandonar una misión.');
    await connection.send(PsPacketType.questQuit,_i16Bytes(questId));
  }

  Future<void> useMobSkill(int skillNumber,int targetGlobalId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar skills.');
    await connection.send(PsPacketType.useMobTargetSkill,[
      skillNumber&0xff,..._u32Bytes(targetGlobalId),
    ]);
  }

  Future<void> close()=>connection.close();
}

class Ps0032Client {
  final String host;
  final int loginPort,worldPort;
  final void Function(String)? trace;
  Ps0032Client({this.host='127.0.0.1',this.loginPort=30800,this.worldPort=30810,this.trace});

  void _log(String value)=>trace?.call(value);

  Future<LoginSession> loginOffline(String password) async {
    final c=await PsConnection.connect(host,loginPort);
    try{
      final hello=await c.nextType(PsPacketType.loginHandshake);
      if(hello.body.length<195)throw FormatException('Handshake Login demasiado corto: ${hello.body.length}');
      final exponentLength=hello.body[1],modulusLength=hello.body[2];
      if(exponentLength<=0||exponentLength>64||modulusLength<=0||modulusLength>128){
        throw FormatException('RSA Login inválido: exp=$exponentLength mod=$modulusLength');
      }
      final exponent=Uint8List.fromList(hello.body.sublist(3,3+exponentLength));
      final modulus=Uint8List.fromList(hello.body.sublist(67,67+modulusLength));
      final random=Random.secure(),secret=Uint8List(16);
      for(var i=0;i<secret.length;i++)secret[i]=random.nextInt(256);
      secret[15]=(secret[15]&0x7f)|1;
      final plain=_bigIntLe(secret);
      final encrypted=plain.modPow(_bigIntLe(exponent),_bigIntLe(modulus));
      final encryptedBytes=_bigIntLeBytes(encrypted);
      if(encryptedBytes.length>255)throw StateError('RSA ciphertext excede 255 bytes.');
      await c.send(PsPacketType.loginHandshake,[encryptedBytes.length,...encryptedBytes],true);

      final digest=hash.Hmac(hash.sha256,secret).convert(modulus).bytes;
      final key=Uint8List.fromList(digest.sublist(0,16));
      final iv=Uint8List.fromList(digest.sublist(16,32));
      c.useCipher(key,iv);

      final oauth=utf8.encode('localplayer:$password');
      final oauthBody=Uint8List(40);
      oauthBody.setRange(0,min(oauth.length,oauthBody.length),oauth);
      await c.send(PsPacketType.oauthLoginRequest,oauthBody);

      final auth=await c.nextType(PsPacketType.loginRequest);
      if(auth.body.length<22)throw FormatException('LOGIN_REQUEST response truncado.');
      final result=auth.body[0];
      if(result!=0)throw StateError('Autenticación local rechazada: $result');
      final userId=_i32(auth.body,1);
      final sessionId=Uint8List.fromList(auth.body.sublist(6,22));
      _log('Login autenticado · user=$userId');

      final list=await c.nextType(PsPacketType.serverList);
      if(list.body.isEmpty||list.body[0]==0)throw StateError('SERVER_LIST vacío.');
      final worldId=list.body[1];
      _log('SERVER_LIST · world=$worldId');

      await c.send(PsPacketType.selectServer,[worldId,..._i32Bytes(-1)]);
      final selected=await c.nextType(PsPacketType.selectServer);
      if(selected.body.length<5)throw FormatException('SELECT_SERVER response truncado.');
      if(selected.body[0]!=0)throw StateError('SELECT_SERVER falló: ${selected.body[0]}');
      _log('Servidor local seleccionado.');

      return LoginSession(userId:userId,sessionId:sessionId,key:key,iv:iv,worldId:worldId);
    }finally{
      await c.close();
    }
  }

  Future<PsWorldSession> openWorld(LoginSession login) async {
    final c=await PsConnection.connect(host,worldPort);
    try{
      final worldIv=Uint8List.fromList(hash.sha256.convert(login.iv).bytes.sublist(0,16));
      c.useCipher(login.key,worldIv);
      await c.send(PsPacketType.gameHandshake,[..._i32Bytes(login.userId),...login.sessionId],true);
      final handshake=await c.nextType(PsPacketType.gameHandshake,timeout:const Duration(seconds:15));
      if(handshake.body.length<18||handshake.body[0]!=0)throw StateError('GAME_HANDSHAKE inválido.');
      final xorKey=Uint8List.fromList(handshake.body.sublist(2,18));
      _log('World handshake completado.');

      var faction=-1,maxMode=-1;
      final packets=<PsPacket>[handshake];
      final deadline=DateTime.now().add(const Duration(seconds:4));
      while(DateTime.now().isBefore(deadline)){
        try{
          final p=await c.next(timeout:const Duration(milliseconds:500));
          packets.add(p);
          if(p.type==PsPacketType.accountFaction&&p.body.length>=2){
            faction=p.body[0];maxMode=p.body[1];
          }
          if(faction>=0&&packets.where((x)=>x.type==PsPacketType.characterList).length>=5)break;
        }on TimeoutException{
          if(faction>=0)break;
        }
      }
      if(faction<0)throw StateError('World no envió ACCOUNT_FACTION.');
      _log('ACCOUNT_FACTION · faction=$faction mode=$maxMode · packets=${packets.length}');
      return PsWorldSession(c,faction,maxMode,xorKey,packets);
    }catch(_){
      await c.close();
      rethrow;
    }
  }

  Future<WorldBootstrap> bootstrapWorld(LoginSession login) async {
    final world=await openWorld(login);
    try{
      return WorldBootstrap(world.faction,world.maxMode,world.initialPackets);
    }finally{
      await world.close();
    }
  }

}
