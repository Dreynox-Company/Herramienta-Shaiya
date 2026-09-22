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
  static const characterActiveBuffs=0x010A;
  static const characterSkillBar=0x010B;
  static const accountFaction=0x0109;
  static const characterEnteredMap=0x0201;
  static const characterEnteredPortal=0x020A;
  static const characterMapTeleport=0x020B;
  static const characterTeleportViaNpc=0x020C;
  static const targetMobHpUpdate=0x0305;
  static const mapWeather=0x0451;
  static const inventoryMoveItem=0x0204;
  static const updateStats=0x0208;
  static const learnNewSkill=0x0209;
  static const addItem=0x0205;
  static const removeItem=0x0206;
  static const characterMove=0x0501;
  static const characterMobAutoAttack=0x0503;
  static const sendEquipment=0x0507;
  static const useItem=0x050A;
  static const useMobTargetSkill=0x0517;
  static const usedSpMp=0x050C;
  static const buffAdd=0x050D;
  static const buffRemove=0x050E;
  static const characterDeath=0x0504;
  static const deadRebirth=0x0551;
  static const useItem2=0x0557;
  static const rebirthNearestTown=0x0553;
  static const characterLeaveDead=0x0406;
  static const characterCurrentHitpoints=0x0521;
  static const characterAdditionalStats=0x0526;
  static const mobEnter=0x0601;
  static const mobLeave=0x0602;
  static const mobMove=0x0603;
  static const mobAttack=0x0605;
  static const mobDeath=0x0606;
  static const mobSkillUse=0x060B;
  static const chatNormal=0x1101;
  static const chatWhisper=0x1102;
  static const chatWorld=0x1103;
  static const chatGuild=0x1104;
  static const chatParty=0x1105;
  static const chatMap=0x1111;
  static const gemAdd=0x0801;
  static const gemRemove=0x0802;
  static const gemAddPossibility=0x0809;
  static const gemRemovePossibility=0x080A;
  static const npcBuyItem=0x0702;
  static const warehouseItemList=0x0711;
  static const npcSellItem=0x0703;
  static const partyList=0x0B01;
  static const partyRequest=0x0B02;
  static const partyResponse=0x0B03;
  static const partyEnter=0x0B04;
  static const partyLeave=0x0B05;
  static const partyKick=0x0B06;
  static const partyChangeLeader=0x0B07;
  static const partyMemberGetItem=0x0B08;
  static const partyCharacterSpMp=0x0C01;
  static const partySetMax=0x0C02;
  static const partyMemberHpSpMp=0x0C03;
  static const partyAddedBuff=0x0C04;
  static const partyRemovedBuff=0x0C05;
  static const partyMemberMaxHpSpMp=0x0C08;
  static const partyMemberLevel=0x0C09;
  static const friendList=0x2201;
  static const friendRequest=0x2202;
  static const friendResponse=0x2203;
  static const friendAdd=0x2204;
  static const friendDelete=0x2205;
  static const friendOnline=0x2207;
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
Uint8List _fixedStringBytes(String value,int length){
  final out=Uint8List(length),raw=utf8.encode(value);
  final n=min(length,raw.length);
  out.setRange(0,n,raw);
  return out;
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
  Future<PsPacket> waitStream(bool Function(PsPacket) test,{Duration timeout=const Duration(seconds:8)})=>
    packets.firstWhere(test).timeout(timeout,onTimeout:()=>throw TimeoutException('Timeout esperando paquete ps0032 en stream.'));


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

class PsMapTeleport {
  final int characterId,mapId;
  final double x,y,z;
  const PsMapTeleport(this.characterId,this.mapId,this.x,this.y,this.z);
  static PsMapTeleport parse(PsPacket p){
    if(p.type!=PsPacketType.characterMapTeleport||p.body.length<18){
      throw FormatException('CHARACTER_MAP_TELEPORT truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsMapTeleport(
      d.getUint32(0,Endian.little),d.getUint16(4,Endian.little),
      d.getFloat32(6,Endian.little),d.getFloat32(10,Endian.little),d.getFloat32(14,Endian.little),
    );
  }
}

class PsNpcTeleportResult {
  final int reason,gold;
  const PsNpcTeleportResult(this.reason,this.gold);
  bool get success=>reason==0;
  static PsNpcTeleportResult parse(PsPacket p){
    if(p.type!=PsPacketType.characterTeleportViaNpc||p.body.length<5){
      throw FormatException('CHARACTER_TELEPORT_VIA_NPC response truncado: ${p.body.length}');
    }
    return PsNpcTeleportResult(p.body[0],ByteData.sublistView(p.body).getUint32(1,Endian.little));
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
class PsCharacterDeath {
  final int characterId,killerType,killerId;
  const PsCharacterDeath(this.characterId,this.killerType,this.killerId);
  static PsCharacterDeath parse(PsPacket p){
    if(p.type!=PsPacketType.characterDeath||p.body.length<9){
      throw FormatException('CHARACTER_DEATH truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterDeath(
      d.getUint32(0,Endian.little),p.body[4],d.getUint32(5,Endian.little),
    );
  }
}

class PsDeadRebirth {
  final int characterId,rebirthType,expLoss;
  final double x,y,z;
  const PsDeadRebirth(this.characterId,this.rebirthType,this.expLoss,this.x,this.y,this.z);
  static PsDeadRebirth parse(PsPacket p){
    if(p.type!=PsPacketType.deadRebirth||p.body.length<21){
      throw FormatException('DEAD_REBIRTH truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsDeadRebirth(
      d.getUint32(0,Endian.little),p.body[4],d.getUint32(5,Endian.little),
      d.getFloat32(9,Endian.little),d.getFloat32(13,Endian.little),d.getFloat32(17,Endian.little),
    );
  }
}


class PsUsualHit {
  final int result,attackerId,targetId,hpDamage,spDamage,mpDamage;
  const PsUsualHit(this.result,this.attackerId,this.targetId,this.hpDamage,this.spDamage,this.mpDamage);
  bool get success=>result==0||result==1;
  static PsUsualHit parse(PsPacket p){
    if(p.type!=PsPacketType.characterMobAutoAttack||p.body.length<15){
      throw FormatException('CHARACTER_MOB_AUTO_ATTACK truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsUsualHit(
      p.body[0],d.getUint32(1,Endian.little),d.getUint32(5,Endian.little),
      d.getUint16(9,Endian.little),d.getUint16(11,Endian.little),d.getUint16(13,Endian.little),
    );
  }
}
class PsMapWeather {
  final bool setType;
  final int state,power;
  const PsMapWeather(this.setType,this.state,this.power);
  bool get rain=>state==1;
  bool get snow=>state==2;
  static PsMapWeather parse(PsPacket p){
    if(p.type!=PsPacketType.mapWeather||p.body.length<3){
      throw FormatException('MAP_WEATHER truncado: ${p.body.length}');
    }
    return PsMapWeather(p.body[0]!=0,p.body[1],p.body[2]);
  }
}


class PsEquipmentChange {
  final int characterId,slot,type,typeId,enchant;
  final bool hasColor;
  final int alpha,r,g,b;
  const PsEquipmentChange({
    required this.characterId,required this.slot,required this.type,required this.typeId,
    required this.enchant,required this.hasColor,required this.alpha,required this.r,required this.g,required this.b,
  });
  static PsEquipmentChange parse(PsPacket p){
    if(p.type!=PsPacketType.sendEquipment||p.body.length<13){
      throw FormatException('SEND_EQUIPMENT truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsEquipmentChange(
      characterId:d.getUint32(0,Endian.little),slot:p.body[4],type:p.body[5],typeId:p.body[6],
      enchant:p.body[7],hasColor:p.body[8]!=0,
      alpha:p.body[9],r:p.body[10],g:p.body[11],b:p.body[12],
    );
  }
}

class PsUsedItem {
  final int characterId,bag,slot,type,typeId,count;
  const PsUsedItem(this.characterId,this.bag,this.slot,this.type,this.typeId,this.count);
  static PsUsedItem parse(PsPacket p){
    if(p.type!=PsPacketType.useItem||p.body.length<9){
      throw FormatException('USE_ITEM event truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsUsedItem(d.getUint32(0,Endian.little),p.body[4],p.body[5],p.body[6],p.body[7],p.body[8]);
  }
}

class PsTargetMobHp {
  final int targetId,currentHp,attackSpeed,moveSpeed;
  const PsTargetMobHp(this.targetId,this.currentHp,this.attackSpeed,this.moveSpeed);
  static PsTargetMobHp parse(PsPacket p){
    if(p.type!=PsPacketType.targetMobHpUpdate||p.body.length<10){
      throw FormatException('TARGET_MOB_HP_UPDATE truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsTargetMobHp(
      d.getUint32(0,Endian.little),d.getInt32(4,Endian.little),p.body[8],p.body[9],
    );
  }
}

class PsSkillHit {
  final int result,attackerId,targetId,skillId,skillLevel,hpDamage,spDamage,mpDamage;
  final bool keepActivated;
  const PsSkillHit({
    required this.result,required this.attackerId,required this.targetId,
    required this.skillId,required this.skillLevel,required this.hpDamage,
    required this.spDamage,required this.mpDamage,required this.keepActivated,
  });
  bool get success=>result==0||result==1||result==4;
  static PsSkillHit parse(PsPacket p){
    if(p.type!=PsPacketType.useMobTargetSkill||p.body.length<19){
      throw FormatException('USE_MOB_TARGET_SKILL response truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsSkillHit(
      result:p.body[0],attackerId:d.getUint32(1,Endian.little),targetId:d.getUint32(5,Endian.little),
      skillId:d.getUint16(9,Endian.little),skillLevel:p.body[11],
      hpDamage:d.getUint16(12,Endian.little),spDamage:d.getUint16(14,Endian.little),
      mpDamage:d.getUint16(16,Endian.little),keepActivated:p.body[18]!=0,
    );
  }
}

class PsMobAttack {
  final int result,mobId,targetId,hpDamage,spDamage,mpDamage;
  const PsMobAttack(this.result,this.mobId,this.targetId,this.hpDamage,this.spDamage,this.mpDamage);
  bool get success=>result==0||result==1;
  static PsMobAttack parse(PsPacket p){
    if(p.type!=PsPacketType.mobAttack||p.body.length<15){
      throw FormatException('MOB_ATTACK truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsMobAttack(
      p.body[0],d.getUint32(1,Endian.little),d.getUint32(5,Endian.little),
      d.getUint16(9,Endian.little),d.getUint16(11,Endian.little),d.getUint16(13,Endian.little),
    );
  }
}

class PsMobSkillHit {
  final int result,mobId,targetId,attackType,skillId,skillLevel,hpDamage,spDamage,mpDamage;
  const PsMobSkillHit({
    required this.result,required this.mobId,required this.targetId,required this.attackType,
    required this.skillId,required this.skillLevel,required this.hpDamage,required this.spDamage,required this.mpDamage,
  });
  bool get success=>result==0||result==1;
  static PsMobSkillHit parse(PsPacket p){
    if(p.type!=PsPacketType.mobSkillUse||p.body.length<19){
      throw FormatException('MOB_SKILL_USE truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsMobSkillHit(
      result:p.body[0],mobId:d.getUint32(1,Endian.little),targetId:d.getUint32(5,Endian.little),
      attackType:p.body[9],skillId:d.getUint16(10,Endian.little),skillLevel:p.body[12],
      hpDamage:d.getUint16(13,Endian.little),spDamage:d.getUint16(15,Endian.little),mpDamage:d.getUint16(17,Endian.little),
    );
  }
}

Uint8List _utf16Le(String value){
  final units=value.codeUnits,out=Uint8List(units.length*2),d=ByteData.sublistView(out);
  for(var i=0;i<units.length;i++)d.setUint16(i*2,units[i],Endian.little);
  return out;
}

String _utf16LeDecode(Uint8List bytes,int offset,int chars){
  final end=offset+chars*2;
  if(offset<0||chars<0||end>bytes.length)throw FormatException('UTF-16LE chat truncado.');
  final d=ByteData.sublistView(bytes),codes=<int>[];
  for(var o=offset;o<end;o+=2)codes.add(d.getUint16(o,Endian.little));
  return String.fromCharCodes(codes).replaceAll('\u0000','');
}

class PsChatMessage {
  final int packetType;
  final int? senderId;
  final String? senderName;
  final String message;
  const PsChatMessage(this.packetType,this.senderId,this.senderName,this.message);
  static PsChatMessage parse(PsPacket p){
    final b=p.body,d=ByteData.sublistView(b);
    if(p.type==PsPacketType.chatNormal||p.type==PsPacketType.chatParty){
      if(b.length<5)throw FormatException('Chat normal/party truncado.');
      final id=d.getUint32(0,Endian.little),len=b[4];
      return PsChatMessage(p.type,id,null,_utf16LeDecode(b,5,len));
    }
    if(p.type==PsPacketType.chatWhisper){
      if(b.length<23)throw FormatException('Whisper truncado.');
      final raw=b.sublist(1,22),zero=raw.indexOf(0);
      final name=utf8.decode(zero<0?raw:raw.sublist(0,zero),allowMalformed:true);
      final len=b[22];
      return PsChatMessage(p.type,null,name,_utf16LeDecode(b,23,len));
    }
    if(p.type==PsPacketType.chatWorld||p.type==PsPacketType.chatGuild||p.type==PsPacketType.chatMap){
      if(b.length<22)throw FormatException('Chat con nombre truncado.');
      final raw=b.sublist(0,21),zero=raw.indexOf(0);
      final name=utf8.decode(zero<0?raw:raw.sublist(0,zero),allowMalformed:true);
      final len=b[21];
      return PsChatMessage(p.type,null,name,_utf16LeDecode(b,22,len));
    }
    throw FormatException('Tipo de chat no soportado: 0x${p.type.toRadixString(16)}');
  }
}

class PsFriend {
  final int id,job;
  final bool online;
  final String name;
  final Uint8List memo;
  const PsFriend(this.id,this.job,this.online,this.name,this.memo);
  PsFriend copyWith({bool? online})=>PsFriend(id,job,online??this.online,name,memo);
}

String _fixedString(Uint8List b,int offset,int length){
  if(offset<0||offset+length>b.length)throw FormatException('Cadena fija truncada en $offset/$length.');
  final raw=b.sublist(offset,offset+length),zero=raw.indexOf(0);
  return utf8.decode(zero<0?raw:raw.sublist(0,zero),allowMalformed:true);
}

List<PsFriend> parseFriendList(PsPacket p){
  if(p.type!=PsPacketType.friendList||p.body.isEmpty)return const [];
  final count=p.body[0],need=1+count*79;
  if(p.body.length<need)throw FormatException('FRIEND_LIST truncado: count=$count bytes=${p.body.length}.');
  final d=ByteData.sublistView(p.body),out=<PsFriend>[];
  var o=1;
  for(var i=0;i<count;i++,o+=79){
    out.add(PsFriend(
      d.getUint32(o,Endian.little),p.body[o+4],p.body[o+5]!=0,
      _fixedString(p.body,o+6,21),Uint8List.fromList(p.body.sublist(o+28,o+79)),
    ));
  }
  return List.unmodifiable(out);
}

PsFriend parseFriendAdd(PsPacket p){
  if(p.type!=PsPacketType.friendAdd||p.body.length<26)throw FormatException('FRIEND_ADD truncado: ${p.body.length}.');
  final d=ByteData.sublistView(p.body);
  return PsFriend(d.getUint32(0,Endian.little),p.body[4],true,_fixedString(p.body,5,21),Uint8List(0));
}

String parseFriendRequestName(PsPacket p){
  if(p.type!=PsPacketType.friendRequest||p.body.length<21)throw FormatException('FRIEND_REQUEST truncado: ${p.body.length}.');
  return _fixedString(p.body,0,21);
}

class PsPartyBuff {
  final int skillId,skillLevel,countdownSeconds;
  const PsPartyBuff(this.skillId,this.skillLevel,this.countdownSeconds);
}

class PsPartyMember {
  final int id,level,profession,maxHp,hp,maxSp,sp,maxMp,mp,mapId;
  final String name;
  final double x,y,z;
  final List<PsPartyBuff> buffs;
  const PsPartyMember({
    required this.id,required this.name,required this.level,required this.profession,
    required this.maxHp,required this.hp,required this.maxSp,required this.sp,
    required this.maxMp,required this.mp,required this.mapId,
    required this.x,required this.y,required this.z,required this.buffs,
  });
  PsPartyMember copyWith({
    int? level,int? maxHp,int? hp,int? maxSp,int? sp,int? maxMp,int? mp,
    List<PsPartyBuff>? buffs,double? x,double? y,double? z,int? mapId,
  })=>PsPartyMember(
    id:id,name:name,level:level??this.level,profession:profession,
    maxHp:maxHp??this.maxHp,hp:hp??this.hp,maxSp:maxSp??this.maxSp,sp:sp??this.sp,
    maxMp:maxMp??this.maxMp,mp:mp??this.mp,mapId:mapId??this.mapId,
    x:x??this.x,y:y??this.y,z:z??this.z,buffs:buffs??this.buffs,
  );
}

({PsPartyMember member,int next}) _parsePartyMember(Uint8List b,int offset){
  if(offset<0||offset+67>b.length)throw FormatException('PartyMember truncado en $offset/${b.length}.');
  final d=ByteData.sublistView(b);
  final count=b[offset+66],need=67+count*7;
  if(offset+need>b.length)throw FormatException('PartyMember buffs truncados: $count.');
  final buffs=<PsPartyBuff>[];
  var bo=offset+67;
  for(var i=0;i<count;i++,bo+=7){
    buffs.add(PsPartyBuff(
      d.getUint16(bo,Endian.little),b[bo+2],d.getInt32(bo+3,Endian.little),
    ));
  }
  return (
    member:PsPartyMember(
      id:d.getUint32(offset,Endian.little),name:_fixedString(b,offset+4,21),
      level:d.getUint16(offset+25,Endian.little),profession:b[offset+27],
      maxHp:d.getInt32(offset+28,Endian.little),hp:d.getInt32(offset+32,Endian.little),
      maxSp:d.getInt32(offset+36,Endian.little),sp:d.getInt32(offset+40,Endian.little),
      maxMp:d.getInt32(offset+44,Endian.little),mp:d.getInt32(offset+48,Endian.little),
      mapId:d.getUint16(offset+52,Endian.little),
      x:d.getFloat32(offset+54,Endian.little),y:d.getFloat32(offset+58,Endian.little),z:d.getFloat32(offset+62,Endian.little),
      buffs:List.unmodifiable(buffs),
    ),
    next:offset+need,
  );
}

class PsPartyList {
  final int leaderIndex;
  final List<PsPartyMember> members;
  const PsPartyList(this.leaderIndex,this.members);
  static PsPartyList parse(PsPacket p){
    if(p.type!=PsPacketType.partyList||p.body.length<2)throw FormatException('PARTY_LIST truncado: ${p.body.length}.');
    final leader=p.body[0],count=p.body[1],members=<PsPartyMember>[];
    var o=2;
    for(var i=0;i<count;i++){final row=_parsePartyMember(p.body,o);members.add(row.member);o=row.next;}
    return PsPartyList(leader,List.unmodifiable(members));
  }
}

PsPartyMember parsePartyEnter(PsPacket p){
  if(p.type!=PsPacketType.partyEnter)throw FormatException('No es PARTY_ENTER.');
  return _parsePartyMember(p.body,0).member;
}

class PsPartyVitals {
  final int id,hp,sp,mp;
  const PsPartyVitals(this.id,this.hp,this.sp,this.mp);
  static PsPartyVitals parse(PsPacket p,{required bool maximum}){
    final expected=maximum?PsPacketType.partyMemberMaxHpSpMp:PsPacketType.partyMemberHpSpMp;
    if(p.type!=expected||p.body.length<16)throw FormatException('PARTY vitals truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsPartyVitals(
      d.getUint32(0,Endian.little),d.getInt32(4,Endian.little),
      d.getInt32(8,Endian.little),d.getInt32(12,Endian.little),
    );
  }
}

class PsPartySingleValue {
  final int id,type,value;
  const PsPartySingleValue(this.id,this.type,this.value);
  static PsPartySingleValue parse(PsPacket p){
    if((p.type!=PsPacketType.partyCharacterSpMp&&p.type!=PsPacketType.partySetMax)||p.body.length<9){
      throw FormatException('PARTY single value truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsPartySingleValue(d.getUint32(0,Endian.little),p.body[4],d.getInt32(5,Endian.little));
  }
}

class PsPartyBuffChange {
  final int id,skillId,skillLevel;
  const PsPartyBuffChange(this.id,this.skillId,this.skillLevel);
  static PsPartyBuffChange parse(PsPacket p){
    if((p.type!=PsPacketType.partyAddedBuff&&p.type!=PsPacketType.partyRemovedBuff)||p.body.length<7){
      throw FormatException('PARTY buff change truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsPartyBuffChange(d.getUint32(0,Endian.little),d.getUint16(4,Endian.little),p.body[6]);
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

class PsActiveBuff {
  final int id,skillId,skillLevel,countdownSeconds;
  const PsActiveBuff(this.id,this.skillId,this.skillLevel,this.countdownSeconds);
  static PsActiveBuff parseRecord(Uint8List b,int offset){
    if(offset<0||offset+11>b.length)throw FormatException('Buff truncado en $offset/${b.length}.');
    final d=ByteData.sublistView(b);
    return PsActiveBuff(
      d.getUint32(offset,Endian.little),
      d.getUint16(offset+4,Endian.little),
      b[offset+6],
      d.getInt32(offset+7,Endian.little),
    );
  }
}

List<PsActiveBuff> parseActiveBuffs(PsPacket p){
  if(p.type!=PsPacketType.characterActiveBuffs||p.body.isEmpty)return const [];
  final count=p.body[0];
  if(p.body.length<1+count*11)throw FormatException('CHARACTER_ACTIVE_BUFFS truncado: count=$count bytes=${p.body.length}.');
  return List<PsActiveBuff>.generate(count,(i)=>PsActiveBuff.parseRecord(p.body,1+i*11),growable:false);
}

PsActiveBuff parseBuffAdd(PsPacket p){
  if(p.type!=PsPacketType.buffAdd||p.body.length<11)throw FormatException('BUFF_ADD truncado: ${p.body.length}.');
  return PsActiveBuff.parseRecord(p.body,0);
}

int parseBuffRemove(PsPacket p){
  if(p.type!=PsPacketType.buffRemove||p.body.length<4)throw FormatException('BUFF_REMOVE truncado: ${p.body.length}.');
  return ByteData.sublistView(p.body).getUint32(0,Endian.little);
}

class PsUsedSpMp {
  final int sp,mp;
  const PsUsedSpMp(this.sp,this.mp);
  static PsUsedSpMp parse(PsPacket p){
    if(p.type!=PsPacketType.usedSpMp||p.body.length<8)throw FormatException('USED_SP_MP truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsUsedSpMp(d.getUint32(0,Endian.little),d.getUint32(4,Endian.little));
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
      count:b[o+30],craftName:craft,dyed:b[o+75]!=0,
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

class PsGemRemoveResult {
  final bool success;
  final int itemBag,itemSlot,gemPosition,gold;
  final List<int> savedBags,savedSlots,savedTypeIds,savedCounts;
  const PsGemRemoveResult({
    required this.success,required this.itemBag,required this.itemSlot,required this.gemPosition,
    required this.savedBags,required this.savedSlots,required this.savedTypeIds,required this.savedCounts,required this.gold,
  });
  static PsGemRemoveResult parse(PsPacket p){
    if(p.type!=PsPacketType.gemRemove||p.body.length<50){
      throw FormatException('GEM_REMOVE truncado: ${p.body.length}.');
    }
    final b=p.body,d=ByteData.sublistView(b);
    final bags=List<int>.generate(6,(i)=>b[4+i]);
    final slots=List<int>.generate(6,(i)=>b[10+i]);
    final ids=List<int>.generate(6,(i)=>d.getInt32(16+i*4,Endian.little));
    final counts=List<int>.generate(6,(i)=>b[40+i]);
    return PsGemRemoveResult(
      success:b[0]!=0,itemBag:b[1],itemSlot:b[2],gemPosition:b[3],
      savedBags:List.unmodifiable(bags),savedSlots:List.unmodifiable(slots),
      savedTypeIds:List.unmodifiable(ids),savedCounts:List.unmodifiable(counts),
      gold:d.getUint32(46,Endian.little),
    );
  }
}
class PsGemAddResult {
  final bool success;
  final int gemBag,gemSlot,gemCount,itemBag,itemSlot,linkSlot,gemTypeId,gold,hammerBag,hammerSlot;
  const PsGemAddResult({
    required this.success,required this.gemBag,required this.gemSlot,required this.gemCount,
    required this.itemBag,required this.itemSlot,required this.linkSlot,required this.gemTypeId,
    required this.gold,required this.hammerBag,required this.hammerSlot,
  });
  static PsGemAddResult parse(PsPacket p){
    if(p.type!=PsPacketType.gemAdd||p.body.length<17){
      throw FormatException('GEM_ADD truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsGemAddResult(
      success:p.body[0]!=0,gemBag:p.body[1],gemSlot:p.body[2],gemCount:p.body[3],
      itemBag:p.body[4],itemSlot:p.body[5],linkSlot:p.body[6],gemTypeId:p.body[7],
      gold:d.getUint32(11,Endian.little),hammerBag:p.body[15],hammerSlot:p.body[16],
    );
  }
}
class PsLinkingPossibility {
  final bool available;
  final double rate;
  final int gold;
  const PsLinkingPossibility(this.available,this.rate,this.gold);
  static PsLinkingPossibility parse(PsPacket p){
    if(p.type!=PsPacketType.gemAddPossibility&&p.type!=PsPacketType.gemRemovePossibility){
      throw FormatException('No es un paquete de posibilidad de lapis.');
    }
    if(p.body.length<13)throw FormatException('Gem possibility truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsLinkingPossibility(p.body[0]!=0,d.getFloat64(1,Endian.little),d.getInt32(9,Endian.little));
  }
}

class PsNpcTradeResult {
  final int result,bag,slot,type,typeId,count,gold;
  const PsNpcTradeResult(this.result,this.bag,this.slot,this.type,this.typeId,this.count,this.gold);
  bool get success=>result==0;
  static PsNpcTradeResult parse(PsPacket p){
    if(p.type!=PsPacketType.npcBuyItem&&p.type!=PsPacketType.npcSellItem){
      throw FormatException('No es una respuesta de compra/venta NPC.');
    }
    if(p.body.length<10)throw FormatException('NPC trade truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsNpcTradeResult(
      p.body[0],p.body[1],p.body[2],p.body[3],p.body[4],p.body[5],
      d.getUint32(6,Endian.little),
    );
  }
}

class PsWarehouseItem {
  final int slot,type,typeId,quality,count;
  final List<int> gems;
  final String craftName;
  final bool dyed;
  const PsWarehouseItem({
    required this.slot,required this.type,required this.typeId,required this.quality,
    required this.count,required this.gems,required this.craftName,required this.dyed,
  });
  String get key=>'$type:$typeId';
}

List<PsWarehouseItem> parseWarehouseItems(PsPacket p){
  if(p.type!=PsPacketType.warehouseItemList||p.body.isEmpty)return const [];
  final b=p.body,d=ByteData.sublistView(b),count=b[0],out=<PsWarehouseItem>[];
  const size=108;
  if(b.length<1+count*size)throw FormatException('WAREHOUSE_ITEM_LIST truncado: count=$count bytes=${b.length}.');
  var o=1;
  for(var i=0;i<count;i++,o+=size){
    final gems=List<int>.generate(6,(j)=>d.getInt32(o+5+j*4,Endian.little));
    final rawName=b.sublist(o+87,o+107),zero=rawName.indexOf(0);
    final craft=utf8.decode(zero<0?rawName:rawName.sublist(0,zero),allowMalformed:true);
    out.add(PsWarehouseItem(
      slot:b[o],type:b[o+1],typeId:b[o+2],quality:d.getUint16(o+3,Endian.little),
      gems:List.unmodifiable(gems),count:b[o+29],dyed:b[o+60]!=0,craftName:craft,
    ));
  }
  return List.unmodifiable(out);
}

class PsLearnSkillResult {
  final bool success;
  final int number,skillId,level;
  const PsLearnSkillResult(this.success,this.number,this.skillId,this.level);
  static PsLearnSkillResult parse(PsPacket p){
    if(p.type!=PsPacketType.learnNewSkill||p.body.length<5){
      throw FormatException('LEARN_NEW_SKILL truncado: ${p.body.length}');
    }
    final d=ByteData.sublistView(p.body);
    return PsLearnSkillResult(
      p.body[0]==0,p.body[1],d.getUint16(2,Endian.little),p.body[4],
    );
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


class PsQuestFinishResult {
  final int npcId,questId,resultType,xp,gold;
  final bool success,requiresChoice;
  const PsQuestFinishResult({
    required this.npcId,required this.questId,required this.resultType,
    required this.xp,required this.gold,required this.success,required this.requiresChoice,
  });
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

  Future<void> confirmMapLoaded() async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de confirmar el mapa.');
    await connection.send(PsPacketType.characterEnteredMap);
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

  Future<PsTargetMobHp> selectMobTarget(int globalId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de seleccionar objetivo.');
    final responseFuture=connection.waitStream((p)=>p.type==PsPacketType.targetMobHpUpdate&&p.body.length>=4&&ByteData.sublistView(p.body).getUint32(0,Endian.little)==globalId);
    await connection.send(PsPacketType.targetMobHpUpdate,_u32Bytes(globalId));
    final response=await responseFuture;
    final hp=PsTargetMobHp.parse(response);
    if(hp.targetId!=globalId)throw StateError('World devolvió otro target: ${hp.targetId}.');
    return hp;
  }

  Future<List<int>> updateStats({int str=0,int dex=0,int rec=0,int intl=0,int wis=0,int luc=0}) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de actualizar atributos.');
    final values=[str,dex,rec,intl,wis,luc];
    if(values.any((v)=>v<0||v>65535))throw RangeError('Incremento de atributo fuera de ushort.');
    final response=connection.waitStream((p)=>p.type==PsPacketType.updateStats,timeout:const Duration(seconds:5));
    await connection.send(PsPacketType.updateStats,[
      for(final v in values)..._u16Bytes(v),
    ]);
    final packet=await response;
    if(packet.body.length<12)throw FormatException('UPDATE_STATS response truncado: ${packet.body.length}.');
    final d=ByteData.sublistView(packet.body);
    return List<int>.generate(6,(i)=>d.getUint16(i*2,Endian.little));
  }
  Future<PsLearnSkillResult> learnSkill(int skillId,int level) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de aprender habilidades.');
    if(skillId<=0||skillId>65535||level<=0||level>255)throw RangeError('Skill id/nivel inválido.');
    final response=connection.waitStream((p){
      if(p.type!=PsPacketType.learnNewSkill||p.body.length<5)return false;
      final d=ByteData.sublistView(p.body);
      final returned=d.getUint16(2,Endian.little);
      return returned==0||returned==skillId;
    },timeout:const Duration(seconds:5));
    await connection.send(PsPacketType.learnNewSkill,[..._u16Bytes(skillId),level]);
    return PsLearnSkillResult.parse(await response);
  }
  Future<void> saveSkillBar(List<PsQuickSlot> slots) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de guardar la barra rápida.');
    if(slots.length>254)throw RangeError('Demasiados elementos en la barra rápida.');
    final body=<int>[slots.length+1,..._i32Bytes(0)];
    for(final slot in slots){
      body.addAll([
        slot.bar&0xff,slot.slot&0xff,slot.bag&0xff,
        ..._u16Bytes(slot.number),..._i32Bytes(slot.cooldown),
      ]);
    }
    await connection.send(PsPacketType.characterSkillBar,body);
  }
  Future<void> enterPortal(int portalId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar portales.');
    if(portalId<0||portalId>255)throw RangeError('PortalId fuera de byte: $portalId');
    await connection.send(PsPacketType.characterEnteredPortal,[portalId]);
  }

  Future<PsNpcTeleportResult> teleportViaNpc(int npcGlobalId,int gateId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar gatekeepers.');
    if(gateId<0||gateId>255)throw RangeError('GateId fuera de byte: $gateId');
    final response=connection.waitStream((p)=>p.type==PsPacketType.characterTeleportViaNpc);
    await connection.send(PsPacketType.characterTeleportViaNpc,[..._u32Bytes(npcGlobalId),gateId]);
    return PsNpcTeleportResult.parse(await response);
  }
  Future<void> requestFriend(String name) async {
    final value=name.trim();
    if(value.isEmpty)throw ArgumentError('Nombre de amigo vacío.');
    await connection.send(PsPacketType.friendRequest,_fixedStringBytes(value,21));
  }

  Future<void> respondFriend(bool accepted) async {
    await connection.send(PsPacketType.friendResponse,[accepted?1:0]);
  }

  Future<void> deleteFriend(int characterId) async {
    await connection.send(PsPacketType.friendDelete,_u32Bytes(characterId));
  }

  Future<void> requestParty(int characterId) async {
    await connection.send(PsPacketType.partyRequest,_u32Bytes(characterId));
  }

  Future<void> respondParty(int requesterId,{required bool declined}) async {
    await connection.send(PsPacketType.partyResponse,[declined?1:0,..._u32Bytes(requesterId)]);
  }

  Future<void> leaveParty() async {
    await connection.send(PsPacketType.partyLeave);
  }

  Future<void> kickPartyMember(int characterId) async {
    await connection.send(PsPacketType.partyKick,_u32Bytes(characterId));
  }

  Future<void> changePartyLeader(int characterId) async {
    await connection.send(PsPacketType.partyChangeLeader,_u32Bytes(characterId));
  }
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
    final response=connection.waitStream((p){
      if(p.type!=PsPacketType.questStart||p.body.length<6)return false;
      final d=ByteData.sublistView(p.body);
      return d.getUint32(0,Endian.little)==npcGlobalId&&d.getInt16(4,Endian.little)==questId;
    });
    await connection.send(PsPacketType.questStart,[
      ..._u32Bytes(npcGlobalId),
      ..._i16Bytes(questId),
    ]);
    final result=await response;
    if(result.body.length<6)throw FormatException('QUEST_START response truncado.');
    final npc=ByteData.sublistView(result.body).getUint32(0,Endian.little);
    final quest=ByteData.sublistView(result.body).getInt16(4,Endian.little);
    if(npc!=npcGlobalId||quest!=questId)throw StateError('QUEST_START devolvió NPC/misión inesperados.');
  }

  Future<PsQuestFinishResult> finishQuest(int npcGlobalId,int questId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de finalizar una misión.');
    final response=connection.waitStream((p){
      if(p.type==PsPacketType.questEndSelect&&p.body.length>=2){
        return ByteData.sublistView(p.body).getInt16(0,Endian.little)==questId;
      }
      if(p.type==PsPacketType.questEnd&&p.body.length>=6){
        return ByteData.sublistView(p.body).getInt16(4,Endian.little)==questId;
      }
      return false;
    });
    await connection.send(PsPacketType.questEnd,[
      ..._u32Bytes(npcGlobalId),
      ..._i16Bytes(questId),
    ]);
    final deadline=DateTime.now().add(const Duration(seconds:8));
    var first=true;
    while(DateTime.now().isBefore(deadline)){
      final p=first?await response:await connection.waitStream((p)=>p.type==PsPacketType.questEnd||p.type==PsPacketType.questEndSelect,timeout:deadline.difference(DateTime.now()));
      first=false;
      if(p.type==PsPacketType.questEndSelect){
        if(p.body.length<6)throw FormatException('QUEST_END_SELECT truncado: '+p.body.length.toString()+'.');
        final d=ByteData.sublistView(p.body);
        final returnedQuest=d.getInt16(0,Endian.little);
        if(returnedQuest!=questId)continue;
        return PsQuestFinishResult(
          npcId:npcGlobalId,questId:questId,resultType:0,xp:0,gold:0,
          success:true,requiresChoice:true,
        );
      }
      if(p.type!=PsPacketType.questEnd)continue;
      if(p.body.length<20)throw FormatException('QUEST_END truncado: '+p.body.length.toString()+'.');
      final d=ByteData.sublistView(p.body);
      final returnedNpc=d.getUint32(0,Endian.little);
      final returnedQuest=d.getInt16(4,Endian.little);
      if(returnedQuest!=questId)continue;
      return PsQuestFinishResult(
        npcId:returnedNpc,questId:returnedQuest,
        success:p.body[6]!=0,resultType:p.body[7],
        xp:d.getUint32(8,Endian.little),gold:d.getUint32(12,Endian.little),
        requiresChoice:false,
      );
    }
    throw TimeoutException('World no respondió QUEST_END '+questId.toString()+'.');
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

  Future<void> rebirth({bool useRune=false}) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de renacer.');
    await connection.send(PsPacketType.rebirthNearestTown,[useRune?4:2]);
  }

  Future<void> sendNormalChat(String message) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar chat.');
    final text=message.trim();if(text.isEmpty)return;
    if(text.length>255)throw RangeError('El mensaje supera 255 caracteres.');
    await connection.send(PsPacketType.chatNormal,[text.length,..._utf16Le(text)]);
  }
  Future<PsInventoryMove> moveItem(int currentBag,int currentSlot,int destinationBag,int destinationSlot) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de mover objetos.');
    for(final value in [currentBag,currentSlot,destinationBag,destinationSlot]){
      if(value<0||value>255)throw RangeError('Bag/slot fuera de byte: $value');
    }
    final responseFuture=connection.waitStream((p)=>p.type==PsPacketType.inventoryMoveItem);
    await connection.send(PsPacketType.inventoryMoveItem,[currentBag,currentSlot,destinationBag,destinationSlot]);
    final response=await responseFuture;
    return PsInventoryMove.parse(response);
  }
  Future<PsGemRemoveResult> removeGem({
    required int itemBag,required int itemSlot,required int gemPosition,
    int hammerBag=0,int hammerSlot=0,
  }) async {
    if(gemPosition<0||gemPosition>5)throw RangeError('GemPosition inválida: $gemPosition');
    final response=connection.waitStream((p)=>p.type==PsPacketType.gemRemove);
    await connection.send(PsPacketType.gemRemove,[itemBag,itemSlot,1,gemPosition,hammerBag,hammerSlot]);
    return PsGemRemoveResult.parse(await response);
  }
  Future<PsGemAddResult> addGem({
    required int gemBag,required int gemSlot,required int itemBag,required int itemSlot,
    int hammerBag=0,int hammerSlot=0,
  }) async {
    final response=connection.waitStream((p)=>p.type==PsPacketType.gemAdd);
    await connection.send(PsPacketType.gemAdd,[gemBag,gemSlot,itemBag,itemSlot,hammerBag,hammerSlot]);
    return PsGemAddResult.parse(await response);
  }
  Future<PsLinkingPossibility> gemAddPossibility({
    required int gemBag,required int gemSlot,required int itemBag,required int itemSlot,
    int hammerBag=0,int hammerSlot=0,
  }) async {
    final response=connection.waitStream((p)=>p.type==PsPacketType.gemAddPossibility);
    await connection.send(PsPacketType.gemAddPossibility,[gemBag,gemSlot,itemBag,itemSlot,hammerBag,hammerSlot]);
    return PsLinkingPossibility.parse(await response);
  }

  Future<PsLinkingPossibility> gemRemovePossibility({
    required int itemBag,required int itemSlot,bool specific=false,int gemPosition=0,
    int hammerBag=0,int hammerSlot=0,
  }) async {
    final response=connection.waitStream((p)=>p.type==PsPacketType.gemRemovePossibility);
    await connection.send(PsPacketType.gemRemovePossibility,[itemBag,itemSlot,specific?1:0,gemPosition,hammerBag,hammerSlot]);
    return PsLinkingPossibility.parse(await response);
  }
  Future<PsNpcTradeResult> buyNpcItem(int npcGlobalId,int productIndex,int count) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de comprar.');
    if(productIndex<0||productIndex>255||count<=0||count>255)throw RangeError('Índice/cantidad de compra inválidos.');
    final response=connection.waitStream((p)=>p.type==PsPacketType.npcBuyItem);
    await connection.send(PsPacketType.npcBuyItem,[..._u32Bytes(npcGlobalId),productIndex,count]);
    return PsNpcTradeResult.parse(await response);
  }

  Future<PsNpcTradeResult> sellNpcItem(int bag,int slot,int count) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de vender.');
    if(bag<=0||bag>255||slot<0||slot>255||count<=0||count>255)throw RangeError('Bag/slot/cantidad de venta inválidos.');
    final response=connection.waitStream((p)=>p.type==PsPacketType.npcSellItem);
    await connection.send(PsPacketType.npcSellItem,[bag,slot,count]);
    return PsNpcTradeResult.parse(await response);
  }
  Future<void> useInventoryItem(int bag,int slot,{int? targetGlobalId}) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar objetos.');
    if(bag<0||bag>255||slot<0||slot>255)throw RangeError('Bag/slot fuera de byte.');
    if(targetGlobalId==null){
      await connection.send(PsPacketType.useItem,[bag,slot]);
    }else{
      await connection.send(PsPacketType.useItem2,[bag,slot,..._u32Bytes(targetGlobalId)]);
    }
  }
  Future<void> startMobAutoAttack(int targetGlobalId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de atacar.');
    await connection.send(PsPacketType.characterMobAutoAttack,_u32Bytes(targetGlobalId));
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
