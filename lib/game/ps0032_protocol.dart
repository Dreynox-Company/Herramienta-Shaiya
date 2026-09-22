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
  static const characterLeftMap=0x0202;
  static const experienceGain=0x0207;
  static const runMode=0x0210;
  static const autoAttackStop=0x0212;
  static const setMoney=0x0213;
  static const inventorySort=0x021F;
  static const useVehicle=0x0216;
  static const useVehicleReady=0x0217;
  static const useVehicle2=0x021C;
  static const vehicleRequest=0x021D;
  static const vehicleResponse=0x021E;
  static const characterEnteredPortal=0x020A;
  static const characterMapTeleport=0x020B;
  static const characterTeleportViaNpc=0x020C;
  static const targetCharacterHpUpdate=0x0301;
  static const targetCharacterMaxHp=0x0302;
  static const characterShape=0x0303;
  static const targetMobGetState=0x0304;
  static const targetMobHpUpdate=0x0305;
  static const targetGetCharacterBuffs=0x0308;
  static const targetGetMobBuffs=0x0309;
  static const targetClear=0x030A;
  static const targetBuffs=0x030B;
  static const targetBuffAdd=0x030C;
  static const targetBuffRemove=0x030D;
  static const mapWeather=0x0451;
  static const inventoryMoveItem=0x0204;
  static const updateStats=0x0208;
  static const learnNewSkill=0x0209;
  static const addItem=0x0205;
  static const removeItem=0x0206;
  static const mapAddItem=0x0401;
  static const mapRemoveItem=0x0402;
  static const worldDay=0x0404;
  static const characterMove=0x0501;
  static const characterCharacterAutoAttack=0x0502;
  static const characterMobAutoAttack=0x0503;
  static const characterRecover=0x0505;
  static const characterMotion=0x0506;
  static const characterLevelUpMyself=0x0508;
  static const characterMaxHitpoints=0x050B;
  static const sendEquipment=0x0507;
  static const useItem=0x050A;
  static const characterSkillKeep=0x050F;
  static const characterSkillCasting=0x0510;
  static const useCharacterTargetSkill=0x0511;
  static const useCharacterRangeSkill=0x0513;
  static const characterSkillMirror=0x0515;
  static const mobSkillCasting=0x0516;
  static const useMobTargetSkill=0x0517;
  static const useMobRangeSkill=0x0519;
  static const mobSkillMirror=0x051B;
  static const characterAttackMovementSpeed=0x051C;
  static const characterShapeUpdate=0x051D;
  static const characterLevelUpOther=0x051E;
  static const characterMaxHpMpSp=0x051F;
  static const characterKillInfo=0x0522;
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
  static const mobSkillKeep=0x0607;
  static const mobSkillUse=0x060B;
  static const mobRangeSkillUse=0x060D;
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
  static const tradeRequest=0x0A01;
  static const tradeResponse=0x0A02;
  static const tradeStart=0x0A03;
  static const tradeStop=0x0A04;
  static const tradeFinish=0x0A05;
  static const tradeOwnerAddItem=0x0A06;
  static const tradeRemoveItem=0x0A07;
  static const tradeAddMoney=0x0A08;
  static const tradeReceiverAddItem=0x0A09;
  static const tradeDecide=0x0A0A;
  static const guildDismantle=0x0D03;
  static const guildJoinRequest=0x0D07;
  static const guildJoinResultUser=0x0D08;
  static const guildLeave=0x0D09;
  static const guildKick=0x0D0A;
  static const guildUserState=0x0D0C;
  static const guildListLoadingStart=0x0D0D;
  static const guildListLoadingEnd=0x0D0E;
  static const guildListRemove=0x0D11;
  static const guildUserListOnline=0x0D12;
  static const guildUserListNotOnline=0x0D13;
  static const guildUserListAdd=0x0D14;
  static const guildJoinList=0x0D16;
  static const guildJoinListAdd=0x0D17;
  static const guildJoinListRemove=0x0D18;
  static const guildCreate=0x0D21;
  static const guildCreateAgree=0x0D22;
  static const guildList=0x0D2F;
  static const guildListAdd=0x0D30;
  static const guildWarehouseItemList=0x0D29;
  static const guildWarehouseItemAdd=0x0D31;
  static const guildWarehouseItemRemove=0x0D32;
  static const guildRankUpdate=0x0D37;
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
  static const raidList=0x0B0B;
  static const raidEnter=0x0B0C;
  static const raidLeave=0x0B0D;
  static const raidCreate=0x0B0E;
  static const raidChangeLoot=0x0B0F;
  static const raidChangeAutoInvite=0x0B10;
  static const raidJoin=0x0B11;
  static const raidMovePlayer=0x0B12;
  static const raidChangeSubLeader=0x0B13;
  static const raidInvite=0x0B14;
  static const raidResponse=0x0B15;
  static const raidDismantle=0x0B16;
  static const raidChangeLeader=0x0B17;
  static const raidPartyError=0x0B19;
  static const raidKick=0x0B1A;
  static const raidCharacterSpMp=0x0C0A;
  static const raidSetMax=0x0C0B;
  static const raidAddedBuff=0x0C0E;
  static const raidRemovedBuff=0x0C10;
  static const raidMemberGetItem=0x0C14;
  static const friendList=0x2201;
  static const friendRequest=0x2202;
  static const friendResponse=0x2203;
  static const friendAdd=0x2204;
  static const friendDelete=0x2205;
  static const friendOnline=0x2207;
  static const duelRequest=0x2401;
  static const duelResponse=0x2402;
  static const duelReady=0x2403;
  static const duelStart=0x2404;
  static const duelWinLose=0x2405;
  static const duelCancel=0x2406;
  static const duelTrade=0x2407;
  static const duelCloseTrade=0x2408;
  static const duelTradeOk=0x2409;
  static const duelTradeAddItem=0x240A;
  static const duelTradeRemoveItem=0x240B;
  static const duelTradeAddMoney=0x240C;
  static const duelTradeOpponentAddItem=0x240D;
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
  static const mapNpcAttackPlayer=0x0E05;
  static const mapNpcAttackMob=0x0E06;
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

class PsShapeEquipment {
  final int slot,type,typeId,enhancement;
  final bool dyed;
  final int alpha,r,g,b;
  const PsShapeEquipment(this.slot,this.type,this.typeId,this.enhancement,this.dyed,this.alpha,this.r,this.g,this.b);
  bool get empty=>type==0||typeId==0;
}

class PsPlayerShape {
  final int characterId,motion,country,race,hair,face,height,profession,gender,partyDefinition,mode,kills;
  final bool dead;
  final List<PsShapeEquipment> equipment;
  final String name,guildName;
  final int guildFrame;
  const PsPlayerShape({
    required this.characterId,required this.dead,required this.motion,required this.country,required this.race,
    required this.hair,required this.face,required this.height,required this.profession,required this.gender,
    required this.partyDefinition,required this.mode,required this.kills,required this.equipment,
    required this.name,required this.guildFrame,required this.guildName,
  });
  static PsPlayerShape parse(PsPacket p){
    if(p.type!=PsPacketType.characterShape||p.body.length<685){
      throw FormatException('CHARACTER_SHAPE US truncado: ${p.body.length}.');
    }
    final b=p.body,d=ByteData.sublistView(b),s=4;
    final equipment=<PsShapeEquipment>[];
    for(var i=0;i<17;i++){
      final eo=s+15+i*3,hasColor=b[s+66+i]!=0,co=s+86+i*4;
      equipment.add(PsShapeEquipment(
        i,b[eo],b[eo+1],b[eo+2],hasColor,b[co],b[co+1],b[co+2],b[co+3],
      ));
    }
    return PsPlayerShape(
      characterId:d.getUint32(0,Endian.little),dead:b[s]!=0,motion:b[s+1],country:b[s+2],race:b[s+3],
      hair:b[s+4],face:b[s+5],height:b[s+6],profession:b[s+7],gender:b[s+8],
      partyDefinition:b[s+9],mode:b[s+10],kills:d.getUint32(s+11,Endian.little),
      equipment:List.unmodifiable(equipment),
      name:_fixedString(b,s+606,21),guildFrame:b[s+627],guildName:_fixedString(b,s+656,25),
    );
  }
}

class PsTargetCharacterHp {
  final int targetId,currentHp,maxHp,attackSpeed,moveSpeed;
  const PsTargetCharacterHp(this.targetId,this.currentHp,this.maxHp,this.attackSpeed,this.moveSpeed);
  static PsTargetCharacterHp parse(PsPacket p){
    if(p.type!=PsPacketType.targetCharacterHpUpdate||p.body.length<14){
      throw FormatException('TARGET_CHARACTER_HP_UPDATE truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsTargetCharacterHp(
      d.getUint32(0,Endian.little),d.getInt32(4,Endian.little),d.getInt32(8,Endian.little),p.body[12],p.body[13],
    );
  }
}

class PsTargetCharacterSelection {
  final int targetId,maxHp,currentHp;
  const PsTargetCharacterSelection(this.targetId,this.maxHp,this.currentHp);
  static PsTargetCharacterSelection parse(PsPacket p){
    if(p.type!=PsPacketType.targetCharacterMaxHp||p.body.length<12){
      throw FormatException('TARGET_CHARACTER_MAX_HP truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsTargetCharacterSelection(
      d.getUint32(0,Endian.little),d.getInt32(4,Endian.little),d.getInt32(8,Endian.little),
    );
  }
}

class PsCharacterMove {
  final int characterId,angle,motion;
  final double x,y,z;
  const PsCharacterMove(this.characterId,this.angle,this.motion,this.x,this.y,this.z);
  bool get walking=>motion==0;
  bool get running=>motion==1;
  bool get immobilized=>motion==193;
  static PsCharacterMove parse(PsPacket p){
    if(p.type!=PsPacketType.characterMove||p.body.length<19){
      throw FormatException('CHARACTER_MOVE remoto truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterMove(
      d.getUint32(0,Endian.little),
      d.getUint16(4,Endian.little),
      p.body[6],
      d.getFloat32(7,Endian.little),
      d.getFloat32(11,Endian.little),
      d.getFloat32(15,Endian.little),
    );
  }
}

class PsCharacterLeftMap {
  final int characterId;
  const PsCharacterLeftMap(this.characterId);
  static PsCharacterLeftMap parse(PsPacket p){
    if(p.type!=PsPacketType.characterLeftMap||p.body.length<4){
      throw FormatException('CHARACTER_LEFT_MAP truncado: ${p.body.length}.');
    }
    return PsCharacterLeftMap(ByteData.sublistView(p.body).getUint32(0,Endian.little));
  }
}

class PsCharacterMotion {
  final int characterId,motion;
  const PsCharacterMotion(this.characterId,this.motion);
  static PsCharacterMotion parse(PsPacket p){
    if(p.type!=PsPacketType.characterMotion||p.body.length<5){
      throw FormatException('CHARACTER_MOTION truncado: ${p.body.length}.');
    }
    return PsCharacterMotion(ByteData.sublistView(p.body).getUint32(0,Endian.little),p.body[4]);
  }
}

class PsCharacterSpeed {
  final int characterId,attackSpeed,moveSpeed;
  const PsCharacterSpeed(this.characterId,this.attackSpeed,this.moveSpeed);
  static PsCharacterSpeed parse(PsPacket p){
    if(p.type!=PsPacketType.characterAttackMovementSpeed||p.body.length<6){
      throw FormatException('CHARACTER_ATTACK_MOVEMENT_SPEED truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterSpeed(d.getUint32(0,Endian.little),p.body[4],p.body[5]);
  }
}

class PsShapeUpdate {
  final int characterId,shape,param1,param2;
  const PsShapeUpdate(this.characterId,this.shape,this.param1,this.param2);
  bool get mounted=>const <int>{14,15,16,17,24,25,26,27,29,30,32,34,222}.contains(shape);
  static PsShapeUpdate parse(PsPacket p){
    if(p.type!=PsPacketType.characterShapeUpdate||p.body.length<13){
      throw FormatException('CHARACTER_SHAPE_UPDATE truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsShapeUpdate(
      d.getUint32(0,Endian.little),p.body[4],
      d.getUint32(5,Endian.little),d.getUint32(9,Endian.little),
    );
  }
}

class PsUseVehicleState {
  final bool success,mounted;
  const PsUseVehicleState(this.success,this.mounted);
  static PsUseVehicleState parse(PsPacket p){
    if(p.type!=PsPacketType.useVehicle||p.body.length<2){
      throw FormatException('USE_VEHICLE truncado: ${p.body.length}.');
    }
    return PsUseVehicleState(p.body[0]!=0,p.body[1]!=0);
  }
}

class PsVehiclePassenger {
  final int passengerId,vehicleCharacterId;
  const PsVehiclePassenger(this.passengerId,this.vehicleCharacterId);
  static PsVehiclePassenger parse(PsPacket p){
    if(p.type!=PsPacketType.useVehicle2||p.body.length<8){
      throw FormatException('USE_VEHICLE_2 truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsVehiclePassenger(d.getUint32(0,Endian.little),d.getUint32(4,Endian.little));
  }
}

class PsCharacterUsualHit {
  final int result,attackerId,targetId,hpDamage,spDamage,mpDamage;
  const PsCharacterUsualHit(this.result,this.attackerId,this.targetId,this.hpDamage,this.spDamage,this.mpDamage);
  bool get success=>result==0||result==1;
  static PsCharacterUsualHit parse(PsPacket p){
    if(p.type!=PsPacketType.characterCharacterAutoAttack||p.body.length<15){
      throw FormatException('CHARACTER_CHARACTER_AUTO_ATTACK truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterUsualHit(
      p.body[0],d.getUint32(1,Endian.little),d.getUint32(5,Endian.little),
      d.getUint16(9,Endian.little),d.getUint16(11,Endian.little),d.getUint16(13,Endian.little),
    );
  }
}

class PsCharacterSkillHit {
  final int result,attackerId,targetId,skillId,skillLevel,hpDamage,spDamage,mpDamage;
  final bool keepActivated;
  const PsCharacterSkillHit({
    required this.result,required this.attackerId,required this.targetId,required this.skillId,required this.skillLevel,
    required this.hpDamage,required this.spDamage,required this.mpDamage,required this.keepActivated,
  });
  bool get success=>result==0||result==1||result==4;
  static PsCharacterSkillHit parse(PsPacket p){
    if(!const <int>{PsPacketType.useCharacterTargetSkill,PsPacketType.useCharacterRangeSkill}.contains(p.type)||p.body.length<19){
      throw FormatException('CHARACTER_SKILL_HIT truncado/tipo inválido: 0x${p.type.toRadixString(16)} · ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterSkillHit(
      result:p.body[0],attackerId:d.getUint32(1,Endian.little),targetId:d.getUint32(5,Endian.little),
      skillId:d.getUint16(9,Endian.little),skillLevel:p.body[11],hpDamage:d.getUint16(12,Endian.little),
      spDamage:d.getUint16(14,Endian.little),mpDamage:d.getUint16(16,Endian.little),keepActivated:p.body[18]!=0,
    );
  }
}

class PsSkillCasting {
  final int casterId,targetId,skillId,skillLevel;
  const PsSkillCasting(this.casterId,this.targetId,this.skillId,this.skillLevel);
  bool get hasExplicitTarget=>targetId!=0;
  static PsSkillCasting parse(PsPacket p){
    if(!const <int>{PsPacketType.characterSkillCasting,PsPacketType.mobSkillCasting}.contains(p.type)||p.body.length<11){
      throw FormatException('SKILL_CASTING truncado/tipo inválido: 0x${p.type.toRadixString(16)} · ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsSkillCasting(
      d.getUint32(0,Endian.little),d.getUint32(4,Endian.little),
      d.getUint16(8,Endian.little),p.body[10],
    );
  }
}

class PsSkillKeep {
  final int senderId,skillId,skillLevel,hpDamage,spDamage,mpDamage;
  const PsSkillKeep(this.senderId,this.skillId,this.skillLevel,this.hpDamage,this.spDamage,this.mpDamage);
  int get characterId=>senderId;
  bool get fromMobPacket=>false;
  static PsSkillKeep parse(PsPacket p){
    if(!const <int>{PsPacketType.characterSkillKeep,PsPacketType.mobSkillKeep}.contains(p.type)||p.body.length<13){
      throw FormatException('SKILL_KEEP truncado/tipo inválido: 0x${p.type.toRadixString(16)} · ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsSkillKeep(
      d.getUint32(0,Endian.little),d.getUint16(4,Endian.little),p.body[6],
      d.getUint16(7,Endian.little),d.getUint16(9,Endian.little),d.getUint16(11,Endian.little),
    );
  }
}

class PsSkillMirror {
  final int targetId,senderId,hpDamage,spDamage,mpDamage;
  const PsSkillMirror(this.targetId,this.senderId,this.hpDamage,this.spDamage,this.mpDamage);
  static PsSkillMirror parse(PsPacket p){
    if(!const <int>{PsPacketType.characterSkillMirror,PsPacketType.mobSkillMirror}.contains(p.type)||p.body.length<14){
      throw FormatException('SKILL_MIRROR truncado/tipo inválido: 0x${p.type.toRadixString(16)} · ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsSkillMirror(
      d.getUint32(0,Endian.little),d.getUint32(4,Endian.little),
      d.getUint16(8,Endian.little),d.getUint16(10,Endian.little),d.getUint16(12,Endian.little),
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
class PsExperienceGain {
  final int exp,unknown;
  const PsExperienceGain(this.exp,this.unknown);
  static PsExperienceGain parse(PsPacket p){
    if(p.type!=PsPacketType.experienceGain||p.body.length<8){
      throw FormatException('EXPERIENCE_GAIN truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsExperienceGain(
      d.getUint32(0,Endian.little),d.getUint32(4,Endian.little),
    );
  }
}

class PsCharacterLevelUp {
  final int characterId,level,statPoint,skillPoint,minLevelExp,nextLevelExp;
  const PsCharacterLevelUp(
    this.characterId,this.level,this.statPoint,this.skillPoint,
    this.minLevelExp,this.nextLevelExp,
  );
  static PsCharacterLevelUp parse(PsPacket p){
    if(!const <int>{
      PsPacketType.characterLevelUpMyself,PsPacketType.characterLevelUpOther,
    }.contains(p.type)||p.body.length<18){
      throw FormatException('CHARACTER_LEVEL_UP truncado/tipo inválido: 0x${p.type.toRadixString(16)} · ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterLevelUp(
      d.getUint32(0,Endian.little),
      d.getUint16(4,Endian.little),
      d.getUint16(6,Endian.little),
      d.getUint16(8,Endian.little),
      d.getUint32(10,Endian.little),
      d.getUint32(14,Endian.little),
    );
  }
}

class PsCharacterRecover {
  final int characterId,hp,mp,sp;
  const PsCharacterRecover(this.characterId,this.hp,this.mp,this.sp);
  static PsCharacterRecover parse(PsPacket p){
    if(p.type!=PsPacketType.characterRecover||p.body.length<16){
      throw FormatException('CHARACTER_RECOVER truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterRecover(
      d.getUint32(0,Endian.little),d.getInt32(4,Endian.little),
      d.getInt32(8,Endian.little),d.getInt32(12,Endian.little),
    );
  }
}

class PsCharacterMaxVitals {
  final int characterId,maxHp,maxMp,maxSp;
  const PsCharacterMaxVitals(this.characterId,this.maxHp,this.maxMp,this.maxSp);
  static PsCharacterMaxVitals parse(PsPacket p){
    if(p.type!=PsPacketType.characterMaxHpMpSp||p.body.length<16){
      throw FormatException('CHARACTER_MAX_HP_MP_SP truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterMaxVitals(
      d.getUint32(0,Endian.little),d.getInt32(4,Endian.little),
      d.getInt32(8,Endian.little),d.getInt32(12,Endian.little),
    );
  }
}

class PsCharacterMaxHitpoint {
  final int characterId,type,value;
  const PsCharacterMaxHitpoint(this.characterId,this.type,this.value);
  static PsCharacterMaxHitpoint parse(PsPacket p){
    if(p.type!=PsPacketType.characterMaxHitpoints||p.body.length<9){
      throw FormatException('CHARACTER_MAX_HITPOINTS truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsCharacterMaxHitpoint(
      d.getUint32(0,Endian.little),p.body[4],d.getInt32(5,Endian.little),
    );
  }
}

class PsMoneyUpdate {
  final int gold;
  const PsMoneyUpdate(this.gold);
  static PsMoneyUpdate parse(PsPacket p){
    if(p.type!=PsPacketType.setMoney||p.body.length<4){
      throw FormatException('SET_MONEY truncado: ${p.body.length}.');
    }
    return PsMoneyUpdate(ByteData.sublistView(p.body).getUint32(0,Endian.little));
  }
}

class PsKillInfo {
  final int characterId,kills;
  const PsKillInfo(this.characterId,this.kills);
  static PsKillInfo parse(PsPacket p){
    if(p.type!=PsPacketType.characterKillInfo||p.body.length<8){
      throw FormatException('CHARACTER_KILLINFO truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsKillInfo(d.getUint32(0,Endian.little),d.getUint32(4,Endian.little));
  }
}

class PsTargetBuff {
  final int skillId,skillLevel,countdownSeconds;
  const PsTargetBuff(this.skillId,this.skillLevel,this.countdownSeconds);
}

class PsTargetBuffState {
  final int targetType,targetId;
  final List<PsTargetBuff> buffs;
  const PsTargetBuffState(this.targetType,this.targetId,this.buffs);
  static PsTargetBuffState parse(PsPacket p){
    if(p.type!=PsPacketType.targetBuffs||p.body.length<6){
      throw FormatException('TARGET_BUFFS truncado: ${p.body.length}.');
    }
    final b=p.body,d=ByteData.sublistView(b),count=b[5];
    if(b.length<6+count*7){
      throw FormatException('TARGET_BUFFS records truncados: count=$count bytes=${b.length}.');
    }
    final rows=<PsTargetBuff>[];
    var o=6;
    for(var i=0;i<count;i++,o+=7){
      rows.add(PsTargetBuff(
        d.getUint16(o,Endian.little),b[o+2],d.getInt32(o+3,Endian.little),
      ));
    }
    return PsTargetBuffState(b[0],d.getUint32(1,Endian.little),List.unmodifiable(rows));
  }
}

class PsTargetBuffChange {
  final int targetType,targetId,skillId,skillLevel;
  const PsTargetBuffChange(this.targetType,this.targetId,this.skillId,this.skillLevel);
  static PsTargetBuffChange parse(PsPacket p){
    if(!const <int>{PsPacketType.targetBuffAdd,PsPacketType.targetBuffRemove}.contains(p.type)||p.body.length<8){
      throw FormatException('TARGET_BUFF_CHANGE truncado/tipo inválido: 0x${p.type.toRadixString(16)} · ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsTargetBuffChange(
      p.body[0],d.getUint32(1,Endian.little),d.getUint16(5,Endian.little),p.body[7],
    );
  }
}

class PsMapItem {
  final int globalId,kind,type,typeId,count,ownerId;
  final double x,y,z;
  const PsMapItem(
    this.globalId,this.kind,this.type,this.typeId,this.count,
    this.x,this.y,this.z,this.ownerId,
  );
  static PsMapItem parse(PsPacket p){
    if(p.type!=PsPacketType.mapAddItem||p.body.length<24){
      throw FormatException('MAP_ADD_ITEM truncado: ${p.body.length}.');
    }
    final b=p.body,d=ByteData.sublistView(b);
    return PsMapItem(
      d.getUint32(0,Endian.little),b[4],b[5],b[6],b[7],
      d.getFloat32(8,Endian.little),d.getFloat32(12,Endian.little),
      d.getFloat32(16,Endian.little),d.getUint32(20,Endian.little),
    );
  }
}

int parseMapRemoveItem(PsPacket p){
  if(p.type!=PsPacketType.mapRemoveItem||p.body.length<4){
    throw FormatException('MAP_REMOVE_ITEM truncado: ${p.body.length}.');
  }
  return ByteData.sublistView(p.body).getUint32(0,Endian.little);
}

class PsNpcAttack {
  final int result,npcId,targetId,hpDamage;
  const PsNpcAttack(this.result,this.npcId,this.targetId,this.hpDamage);
  bool get success=>result==0||result==1;
  static PsNpcAttack parse(PsPacket p){
    if(!const <int>{PsPacketType.mapNpcAttackPlayer,PsPacketType.mapNpcAttackMob}.contains(p.type)||p.body.length<11){
      throw FormatException('MAP_NPC_ATTACK truncado/tipo inválido: 0x${p.type.toRadixString(16)} · ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsNpcAttack(
      p.body[0],d.getUint32(1,Endian.little),
      d.getUint32(5,Endian.little),d.getUint16(9,Endian.little),
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
    if(!const <int>{PsPacketType.useMobTargetSkill,PsPacketType.useMobRangeSkill}.contains(p.type)||p.body.length<19){
      throw FormatException('MOB_SKILL_HIT truncado/tipo inválido: 0x${p.type.toRadixString(16)} · ${p.body.length}.');
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

class PsMobRangeSkillHit {
  final int result,mobId,targetId,skillId,skillLevel,hpDamage,spDamage,mpDamage;
  final bool keepActivated;
  const PsMobRangeSkillHit({
    required this.result,required this.mobId,required this.targetId,
    required this.skillId,required this.skillLevel,required this.hpDamage,
    required this.spDamage,required this.mpDamage,required this.keepActivated,
  });
  bool get success=>result==0||result==1||result==4;
  static PsMobRangeSkillHit parse(PsPacket p){
    if(p.type!=PsPacketType.mobRangeSkillUse||p.body.length<19){
      throw FormatException('MOB_RANGE_SKILL_USE truncado: ${p.body.length}.');
    }
    final d=ByteData.sublistView(p.body);
    return PsMobRangeSkillHit(
      result:p.body[0],mobId:d.getUint32(1,Endian.little),targetId:d.getUint32(5,Endian.little),
      skillId:d.getUint16(9,Endian.little),skillLevel:p.body[11],
      hpDamage:d.getUint16(12,Endian.little),spDamage:d.getUint16(14,Endian.little),
      mpDamage:d.getUint16(16,Endian.little),keepActivated:p.body[18]!=0,
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

String _fixedUtf16Le(Uint8List b,int offset,int byteLength){
  if(offset<0||offset+byteLength>b.length)throw FormatException('UTF16 fijo truncado en $offset/$byteLength.');
  final codes=<int>[];
  for(var i=0;i+1<byteLength;i+=2){
    final code=b[offset+i]|(b[offset+i+1]<<8);
    if(code==0)break;
    codes.add(code);
  }
  return String.fromCharCodes(codes);
}

Uint8List _fixedUtf16LeBytes(String value,int chars){
  final out=Uint8List(chars*2),codes=value.runes.take(chars).toList();
  final d=ByteData.sublistView(out);
  for(var i=0;i<codes.length;i++)d.setUint16(i*2,codes[i],Endian.little);
  return out;
}

class PsTradeItem {
  final int tradeSlot,type,typeId,count,quality;
  final List<int> gems;
  final String craftName;
  final bool dyed;
  const PsTradeItem({
    required this.tradeSlot,required this.type,required this.typeId,required this.count,
    required this.quality,required this.gems,required this.craftName,required this.dyed,
  });
  String get key=>'$type:$typeId';
  static PsTradeItem parse(PsPacket p){
    if(p.type!=PsPacketType.tradeReceiverAddItem||p.body.length<108){
      throw FormatException('TRADE_RECEIVER_ADD_ITEM truncado: ${p.body.length}.');
    }
    final b=p.body,d=ByteData.sublistView(b);
    final gems=List<int>.generate(6,(i)=>d.getInt32(63+i*4,Endian.little));
    final raw=b.sublist(87,107),zero=raw.indexOf(0);
    final craft=utf8.decode(zero<0?raw:raw.sublist(0,zero),allowMalformed:true);
    return PsTradeItem(
      tradeSlot:b[0],type:b[1],typeId:b[2],count:b[3],quality:d.getUint16(4,Endian.little),
      gems:List.unmodifiable(gems),craftName:craft,dyed:b[36]!=0,
    );
  }
}

class PsTradeOwnerItemAck {
  final int bag,slot,count,tradeSlot;
  const PsTradeOwnerItemAck(this.bag,this.slot,this.count,this.tradeSlot);
  static PsTradeOwnerItemAck parse(PsPacket p){
    if(p.type!=PsPacketType.tradeOwnerAddItem||p.body.length<4){
      throw FormatException('TRADE_OWNER_ADD_ITEM truncado: ${p.body.length}.');
    }
    return PsTradeOwnerItemAck(p.body[0],p.body[1],p.body[2],p.body[3]);
  }
}

class PsTradeMoney {
  final int byWho,money;
  const PsTradeMoney(this.byWho,this.money);
  static PsTradeMoney parse(PsPacket p){
    if(p.type!=PsPacketType.tradeAddMoney||p.body.length<5)throw FormatException('TRADE_ADD_MONEY truncado: ${p.body.length}.');
    return PsTradeMoney(p.body[0],ByteData.sublistView(p.body).getUint32(1,Endian.little));
  }
}

class PsTradeDecision {
  final int byWho;
  final bool decided;
  const PsTradeDecision(this.byWho,this.decided);
  static PsTradeDecision parse(PsPacket p){
    if(p.type!=PsPacketType.tradeDecide||p.body.length<2)throw FormatException('TRADE_DECIDE truncado: ${p.body.length}.');
    return PsTradeDecision(p.body[0],p.body[1]!=0);
  }
}

class PsTradeConfirmation {
  final int byWho;
  final bool declined;
  const PsTradeConfirmation(this.byWho,this.declined);
  static PsTradeConfirmation parse(PsPacket p){
    if(p.type!=PsPacketType.tradeFinish||p.body.length<2)throw FormatException('TRADE_FINISH truncado: ${p.body.length}.');
    return PsTradeConfirmation(p.body[0],p.body[1]!=0);
  }
}

class PsDuelRequest {
  final int starterId,opponentId;
  const PsDuelRequest(this.starterId,this.opponentId);
  static PsDuelRequest parse(PsPacket p){
    if(p.type!=PsPacketType.duelRequest||p.body.length<8)throw FormatException('DUEL_REQUEST truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsDuelRequest(d.getUint32(0,Endian.little),d.getUint32(4,Endian.little));
  }
}

class PsDuelResponse {
  final int response,characterId;
  const PsDuelResponse(this.response,this.characterId);
  bool get accepted=>response==1;
  static PsDuelResponse parse(PsPacket p){
    if(p.type!=PsPacketType.duelResponse||p.body.length<5)throw FormatException('DUEL_RESPONSE truncado: ${p.body.length}.');
    return PsDuelResponse(p.body[0],ByteData.sublistView(p.body).getUint32(1,Endian.little));
  }
}

class PsDuelTradeOpen {
  final int characterId,unknown;
  const PsDuelTradeOpen(this.characterId,this.unknown);
  static PsDuelTradeOpen parse(PsPacket p){
    if(p.type!=PsPacketType.duelTrade||p.body.length<5)throw FormatException('DUEL_TRADE truncado: ${p.body.length}.');
    return PsDuelTradeOpen(ByteData.sublistView(p.body).getUint32(0,Endian.little),p.body[4]);
  }
}

class PsDuelTradeItem {
  final int tradeSlot,type,typeId,count,quality;
  final List<int> gems;
  final String craftName;
  final bool dyed;
  const PsDuelTradeItem({required this.tradeSlot,required this.type,required this.typeId,required this.count,required this.quality,required this.gems,required this.craftName,required this.dyed});
  String get key=>'$type:$typeId';
  static PsDuelTradeItem parse(PsPacket p){
    if(p.type!=PsPacketType.duelTradeOpponentAddItem||p.body.length<108)throw FormatException('DUEL_TRADE_OPPONENT_ADD_ITEM truncado: ${p.body.length}.');
    final b=p.body,d=ByteData.sublistView(b);
    final gems=List<int>.generate(6,(i)=>d.getInt32(63+i*4,Endian.little));
    final raw=b.sublist(87,107),zero=raw.indexOf(0);
    final craft=utf8.decode(zero<0?raw:raw.sublist(0,zero),allowMalformed:true);
    return PsDuelTradeItem(
      tradeSlot:b[0],type:b[1],typeId:b[2],count:b[3],quality:d.getUint16(4,Endian.little),
      gems:List.unmodifiable(gems),craftName:craft,dyed:b[36]!=0,
    );
  }
}

class PsDuelTradeItemAck {
  final int bag,slot,count,tradeSlot;
  const PsDuelTradeItemAck(this.bag,this.slot,this.count,this.tradeSlot);
  static PsDuelTradeItemAck parse(PsPacket p){
    if(p.type!=PsPacketType.duelTradeAddItem||p.body.length<4)throw FormatException('DUEL_TRADE_ADD_ITEM truncado: ${p.body.length}.');
    return PsDuelTradeItemAck(p.body[0],p.body[1],p.body[2],p.body[3]);
  }
}

class PsDuelTradeRemove {
  final int senderType,tradeSlot;
  const PsDuelTradeRemove(this.senderType,this.tradeSlot);
  static PsDuelTradeRemove parse(PsPacket p){
    if(p.type!=PsPacketType.duelTradeRemoveItem||p.body.length<2)throw FormatException('DUEL_TRADE_REMOVE_ITEM truncado: ${p.body.length}.');
    return PsDuelTradeRemove(p.body[0],p.body[1]);
  }
}

class PsDuelTradeMoney {
  final int senderType,money;
  const PsDuelTradeMoney(this.senderType,this.money);
  static PsDuelTradeMoney parse(PsPacket p){
    if(p.type!=PsPacketType.duelTradeAddMoney||p.body.length<5)throw FormatException('DUEL_TRADE_ADD_MONEY truncado: ${p.body.length}.');
    return PsDuelTradeMoney(p.body[0],ByteData.sublistView(p.body).getUint32(1,Endian.little));
  }
}

class PsDuelTradeApproval {
  final int senderType,result;
  const PsDuelTradeApproval(this.senderType,this.result);
  bool get approved=>result==0;
  static PsDuelTradeApproval parse(PsPacket p){
    if(p.type!=PsPacketType.duelTradeOk||p.body.length<2)throw FormatException('DUEL_TRADE_OK truncado: ${p.body.length}.');
    return PsDuelTradeApproval(p.body[0],p.body[1]);
  }
}

class PsDuelReady {
  final double x,z;
  const PsDuelReady(this.x,this.z);
  static PsDuelReady parse(PsPacket p){
    if(p.type!=PsPacketType.duelReady||p.body.length<8)throw FormatException('DUEL_READY truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsDuelReady(d.getFloat32(0,Endian.little),d.getFloat32(4,Endian.little));
  }
}

class PsDuelCancel {
  final int reason,playerId;
  const PsDuelCancel(this.reason,this.playerId);
  static PsDuelCancel parse(PsPacket p){
    if(p.type!=PsPacketType.duelCancel||p.body.length<5)throw FormatException('DUEL_CANCEL truncado: ${p.body.length}.');
    return PsDuelCancel(p.body[0],ByteData.sublistView(p.body).getUint32(1,Endian.little));
  }
}

class PsDuelResult {
  final int result;
  const PsDuelResult(this.result);
  bool get won=>result==1;
  bool get lost=>result==2;
  static PsDuelResult parse(PsPacket p){
    if(p.type!=PsPacketType.duelWinLose||p.body.isEmpty)throw FormatException('DUEL_WIN_LOSE truncado: ${p.body.length}.');
    return PsDuelResult(p.body[0]);
  }
}
class PsGuildSummary {
  final int id,rank,points;
  final String name,masterName,message;
  const PsGuildSummary(this.id,this.name,this.masterName,this.message,this.rank,this.points);
  static PsGuildSummary parseUnit(Uint8List b,int offset){
    if(offset<0||offset+185>b.length)throw FormatException('GuildUnit truncado en $offset/${b.length}.');
    final d=ByteData.sublistView(b);
    return PsGuildSummary(
      d.getUint32(offset,Endian.little),
      _fixedString(b,offset+4,25),_fixedString(b,offset+29,21),
      _fixedUtf16Le(b,offset+50,130),b[offset+180],d.getInt32(offset+181,Endian.little),
    );
  }
}

List<PsGuildSummary> parseGuildList(PsPacket p){
  if(p.type!=PsPacketType.guildList||p.body.isEmpty)return const [];
  final count=p.body[0],need=1+count*185;
  if(p.body.length<need)throw FormatException('GUILD_LIST truncado: count=$count bytes=${p.body.length}.');
  return List<PsGuildSummary>.generate(count,(i)=>PsGuildSummary.parseUnit(p.body,1+i*185),growable:false);
}

class PsGuildMember {
  final int id,rank,level,job;
  final String name;
  final bool online;
  const PsGuildMember(this.id,this.rank,this.level,this.job,this.name,this.online);
  PsGuildMember copyWith({int? rank,bool? online})=>PsGuildMember(id,rank??this.rank,level,job,name,online??this.online);
  static PsGuildMember parseUnit(Uint8List b,int offset,{required bool online}){
    if(offset<0||offset+29>b.length)throw FormatException('GuildUserUnit truncado en $offset/${b.length}.');
    final d=ByteData.sublistView(b);
    return PsGuildMember(
      d.getUint32(offset,Endian.little),b[offset+4],d.getUint16(offset+5,Endian.little),
      b[offset+7],_fixedString(b,offset+8,21),online,
    );
  }
}

List<PsGuildMember> parseGuildMembers(PsPacket p,{required bool online}){
  if((p.type!=PsPacketType.guildUserListOnline&&p.type!=PsPacketType.guildUserListNotOnline)||p.body.isEmpty)return const [];
  final count=p.body[0],need=1+count*29;
  if(p.body.length<need)throw FormatException('GUILD_USER_LIST truncado: count=$count bytes=${p.body.length}.');
  return List<PsGuildMember>.generate(count,(i)=>PsGuildMember.parseUnit(p.body,1+i*29,online:online),growable:false);
}

PsGuildMember parseGuildMemberAdd(PsPacket p){
  if(p.type!=PsPacketType.guildUserListAdd||p.body.length<30)throw FormatException('GUILD_USER_LIST_ADD truncado: ${p.body.length}.');
  return PsGuildMember.parseUnit(p.body,1,online:p.body[0]!=0);
}

class PsGuildJoinApplicant {
  final int id,level,job;
  final String name;
  const PsGuildJoinApplicant(this.id,this.level,this.job,this.name);
  static PsGuildJoinApplicant parseUnit(Uint8List b,int offset){
    if(offset<0||offset+28>b.length)throw FormatException('GuildJoinUserUnit truncado en $offset/${b.length}.');
    final d=ByteData.sublistView(b);
    return PsGuildJoinApplicant(
      d.getUint32(offset,Endian.little),d.getUint16(offset+4,Endian.little),
      b[offset+6],_fixedString(b,offset+7,21),
    );
  }
}

class PsGuildJoinResult {
  final bool ok;
  final int guildId,rank;
  final String name;
  const PsGuildJoinResult(this.ok,this.guildId,this.rank,this.name);
  static PsGuildJoinResult parse(PsPacket p){
    if(p.type!=PsPacketType.guildJoinResultUser||p.body.length<31)throw FormatException('GUILD_JOIN_RESULT_USER truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsGuildJoinResult(p.body[0]!=0,d.getUint32(1,Endian.little),p.body[5],_fixedString(p.body,6,25));
  }
}

class PsGuildCreateResult {
  final int reason,guildId,rank;
  final String name,message;
  const PsGuildCreateResult(this.reason,this.guildId,this.rank,this.name,this.message);
  bool get success=>reason==0;
  static PsGuildCreateResult parse(PsPacket p){
    if(p.type!=PsPacketType.guildCreate||p.body.isEmpty)throw FormatException('GUILD_CREATE vacío.');
    final reason=p.body[0];
    if(reason!=0)return PsGuildCreateResult(reason,0,0,'','');
    if(p.body.length<96)throw FormatException('GUILD_CREATE success truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsGuildCreateResult(reason,d.getUint32(1,Endian.little),p.body[5],_fixedString(p.body,6,25),_fixedString(p.body,31,65));
  }
}

class PsGuildCreateInvite {
  final int creatorId;
  final String name,message;
  const PsGuildCreateInvite(this.creatorId,this.name,this.message);
  static PsGuildCreateInvite parse(PsPacket p){
    if(p.type!=PsPacketType.guildCreateAgree||p.body.length<94)throw FormatException('GUILD_CREATE_AGREE truncado: ${p.body.length}.');
    final d=ByteData.sublistView(p.body);
    return PsGuildCreateInvite(d.getUint32(0,Endian.little),_fixedString(p.body,4,25),_fixedString(p.body,29,65));
  }
}

PsInventoryItem _guildWarehouseItem(Uint8List b,int offset){
  if(offset<0||offset+100>b.length)throw FormatException('GuildWarehouseItem truncado en '+offset.toString()+'/'+b.length.toString()+'.');
  final d=ByteData.sublistView(b);
  final gems=List<int>.generate(6,(i)=>d.getInt32(offset+5+i*4,Endian.little));
  final raw=b.sublist(offset+79,offset+99),zero=raw.indexOf(0);
  final craft=utf8.decode(zero<0?raw:raw.sublist(0,zero),allowMalformed:true);
  return PsInventoryItem(
    bag:255,slot:b[offset],type:b[offset+1],typeId:b[offset+2],
    quality:d.getUint16(offset+3,Endian.little),count:b[offset+29],
    gems:List.unmodifiable(gems),craftName:craft,dyed:b[offset+52]!=0,
  );
}

List<PsInventoryItem> parseGuildWarehouseItems(PsPacket p){
  if(p.type!=PsPacketType.guildWarehouseItemList||p.body.isEmpty)return const [];
  final count=p.body[0],need=1+count*100;
  if(p.body.length<need)throw FormatException('GUILD_WAREHOUSE_ITEM_LIST truncado: count='+count.toString()+' bytes='+p.body.length.toString()+'.');
  return List<PsInventoryItem>.generate(count,(i)=>_guildWarehouseItem(p.body,1+i*100),growable:false);
}

class PsGuildWarehouseMutation {
  final PsInventoryItem item;
  final int characterId;
  const PsGuildWarehouseMutation(this.item,this.characterId);
  static PsGuildWarehouseMutation parse(PsPacket p){
    if((p.type!=PsPacketType.guildWarehouseItemAdd&&p.type!=PsPacketType.guildWarehouseItemRemove)||p.body.length<104){
      throw FormatException('GUILD_WAREHOUSE mutation truncado: '+p.body.length.toString()+'.');
    }
    final item=_guildWarehouseItem(p.body,0);
    final characterId=ByteData.sublistView(p.body).getUint32(100,Endian.little);
    return PsGuildWarehouseMutation(item,characterId);
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

class PsRaidMember {
  final int index;
  final PsPartyMember member;
  const PsRaidMember(this.index,this.member);
  PsRaidMember copyWith({int? index,PsPartyMember? member})=>PsRaidMember(index??this.index,member??this.member);
}

({PsRaidMember member,int next}) _parseRaidMember(Uint8List b,int offset){
  if(offset<0||offset+69>b.length)throw FormatException('RaidMember truncado en '+offset.toString()+'/'+b.length.toString()+'.');
  final d=ByteData.sublistView(b),index=d.getUint16(offset,Endian.little);
  final count=b[offset+68],need=69+count*7;
  if(offset+need>b.length)throw FormatException('RaidMember buffs truncados: '+count.toString()+'.');
  final buffs=<PsPartyBuff>[];
  var bo=offset+69;
  for(var i=0;i<count;i++,bo+=7){
    buffs.add(PsPartyBuff(
      d.getUint16(bo,Endian.little),b[bo+2],d.getInt32(bo+3,Endian.little),
    ));
  }
  final member=PsPartyMember(
    id:d.getUint32(offset+2,Endian.little),
    name:_fixedString(b,offset+6,21),
    level:d.getUint16(offset+27,Endian.little),
    profession:b[offset+29],
    maxHp:d.getInt32(offset+30,Endian.little),hp:d.getInt32(offset+34,Endian.little),
    maxSp:d.getInt32(offset+38,Endian.little),sp:d.getInt32(offset+42,Endian.little),
    maxMp:d.getInt32(offset+46,Endian.little),mp:d.getInt32(offset+50,Endian.little),
    mapId:d.getUint16(offset+54,Endian.little),
    x:d.getFloat32(offset+56,Endian.little),y:d.getFloat32(offset+60,Endian.little),z:d.getFloat32(offset+64,Endian.little),
    buffs:List.unmodifiable(buffs),
  );
  return (member:PsRaidMember(index,member),next:offset+need);
}

class PsRaidState {
  final int leaderIndex,subLeaderIndex,dropType;
  final bool autoJoin;
  final List<PsRaidMember> members;
  const PsRaidState({
    required this.leaderIndex,required this.subLeaderIndex,required this.dropType,
    required this.autoJoin,required this.members,
  });
  PsRaidMember? get leader=>members.where((m)=>m.index==leaderIndex).firstOrNull;
  PsRaidMember? get subLeader=>members.where((m)=>m.index==subLeaderIndex).firstOrNull;

  static PsRaidState parse(PsPacket p){
    if(p.type!=PsPacketType.raidList||p.body.length<8)throw FormatException('RAID_LIST truncado: '+p.body.length.toString()+'.');
    final b=p.body,d=ByteData.sublistView(b);
    final count=b[7],members=<PsRaidMember>[];
    var o=8;
    for(var i=0;i<count;i++){final row=_parseRaidMember(b,o);members.add(row.member);o=row.next;}
    return PsRaidState(
      leaderIndex:b[1],subLeaderIndex:b[2],dropType:d.getUint16(3,Endian.little),
      autoJoin:b[6]!=0,members:List.unmodifiable(members),
    );
  }
}

PsRaidMember parseRaidEnter(PsPacket p){
  if(p.type!=PsPacketType.raidEnter)throw FormatException('No es RAID_ENTER.');
  return _parseRaidMember(p.body,0).member;
}

class PsRaidMove {
  final int sourceIndex,destinationIndex,leaderIndex,subLeaderIndex;
  const PsRaidMove(this.sourceIndex,this.destinationIndex,this.leaderIndex,this.subLeaderIndex);
  static PsRaidMove parse(PsPacket p){
    if(p.type!=PsPacketType.raidMovePlayer||p.body.length<16)throw FormatException('RAID_MOVE_PLAYER truncado: '+p.body.length.toString()+'.');
    final d=ByteData.sublistView(p.body);
    return PsRaidMove(
      d.getInt32(0,Endian.little),d.getInt32(4,Endian.little),
      d.getInt32(8,Endian.little),d.getInt32(12,Endian.little),
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
  final List<PsEnteredMap> players;
  final List<PsNpcEnter> npcs;
  final List<PsMobEnter> mobs;
  final List<PsQuestProgress> quests;
  final List<PsFinishedQuest> finishedQuests;
  const PsWorldSnapshot({
    required this.self,this.players=const <PsEnteredMap>[],required this.npcs,required this.mobs,
    required this.quests,required this.finishedQuests,
  });

  factory PsWorldSnapshot.fromPackets(Iterable<PsPacket> packets,{int? selfCharacterId}){
    PsEnteredMap? self;
    final playerById=<int,PsEnteredMap>{};
    final npcs=<PsNpcEnter>[],mobs=<PsMobEnter>[],quests=<PsQuestProgress>[],finished=<PsFinishedQuest>[];
    for(final p in packets){
      if(p.type==PsPacketType.characterEnteredMap){
        final entered=PsEnteredMap.parse(p);
        if(selfCharacterId==null){
          if(self==null)self=entered;
          else if(entered.characterId!=self!.characterId)playerById[entered.characterId]=entered;
        }else if(entered.characterId==selfCharacterId){
          self=entered;playerById.remove(entered.characterId);
        }else{
          playerById[entered.characterId]=entered;
        }
      }else if(p.type==PsPacketType.characterLeftMap){
        playerById.remove(PsCharacterLeftMap.parse(p).characterId);
      }else if(p.type==PsPacketType.mapNpcEnter)npcs.add(PsNpcEnter.parse(p));
      else if(p.type==PsPacketType.mobEnter)mobs.add(PsMobEnter.parse(p));
      else if(p.type==PsPacketType.questList)quests.addAll(parseQuestList(p));
      else if(p.type==PsPacketType.questFinishedList)finished.addAll(parseFinishedQuests(p));
    }
    return PsWorldSnapshot(
      self:self,players:List.unmodifiable(playerById.values),npcs:List.unmodifiable(npcs),mobs:List.unmodifiable(mobs),
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

  Future<PsPlayerShape> requestCharacterShape(int characterId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de solicitar CHARACTER_SHAPE.');
    final response=connection.waitStream((p)=>
      p.type==PsPacketType.characterShape&&p.body.length>=4&&
      ByteData.sublistView(p.body).getUint32(0,Endian.little)==characterId
    );
    await connection.send(PsPacketType.characterShape,_u32Bytes(characterId));
    return PsPlayerShape.parse(await response);
  }

  Future<void> clearTarget() async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de limpiar objetivo.');
    await connection.send(PsPacketType.targetClear);
  }

  Future<PsTargetBuffState> requestCharacterTargetBuffs(int characterId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de consultar buffs PvP.');
    final response=connection.waitStream((p)=>
      p.type==PsPacketType.targetBuffs&&p.body.length>=5&&
      ByteData.sublistView(p.body).getUint32(1,Endian.little)==characterId
    );
    await connection.send(PsPacketType.targetGetCharacterBuffs,_u32Bytes(characterId));
    return PsTargetBuffState.parse(await response);
  }

  Future<PsTargetBuffState> requestMobTargetBuffs(int globalId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de consultar buffs del mob.');
    final response=connection.waitStream((p)=>
      p.type==PsPacketType.targetBuffs&&p.body.length>=5&&
      ByteData.sublistView(p.body).getUint32(1,Endian.little)==globalId
    );
    await connection.send(PsPacketType.targetGetMobBuffs,_u32Bytes(globalId));
    return PsTargetBuffState.parse(await response);
  }

  Future<PsTargetCharacterSelection> selectCharacterTarget(int characterId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de seleccionar objetivo PvP.');
    final response=connection.waitStream((p)=>
      p.type==PsPacketType.targetCharacterMaxHp&&p.body.length>=4&&
      ByteData.sublistView(p.body).getUint32(0,Endian.little)==characterId
    );
    // 0x0302 is the authoritative target-selection request in ps0032.
    // 0x0301 only refreshes current HP/speed and does not set AttackManager.Target.
    await connection.send(PsPacketType.targetCharacterMaxHp,_u32Bytes(characterId));
    return PsTargetCharacterSelection.parse(await response);
  }

  Future<PsTargetCharacterHp> refreshCharacterTargetHp(int characterId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de consultar HP PvP.');
    final response=connection.waitStream((p)=>
      p.type==PsPacketType.targetCharacterHpUpdate&&p.body.length>=4&&
      ByteData.sublistView(p.body).getUint32(0,Endian.little)==characterId
    );
    await connection.send(PsPacketType.targetCharacterHpUpdate,_u32Bytes(characterId));
    return PsTargetCharacterHp.parse(await response);
  }

  Future<void> startCharacterAutoAttack(int targetId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de atacar en PvP.');
    await connection.send(PsPacketType.characterCharacterAutoAttack,_u32Bytes(targetId));
  }

  Future<void> useCharacterSkill(int skillNumber,int targetId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar skills PvP.');
    await connection.send(PsPacketType.useCharacterTargetSkill,[skillNumber&0xff,..._u32Bytes(targetId)]);
  }
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
  Future<void> toggleVehicle() async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar montura.');
    await connection.send(PsPacketType.useVehicle);
  }

  Future<void> requestVehiclePassenger(int characterId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de invitar a una montura.');
    await connection.send(PsPacketType.vehicleRequest,_u32Bytes(characterId));
  }

  Future<void> respondVehiclePassenger({required bool rejected}) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de responder la invitación de montura.');
    await connection.send(PsPacketType.vehicleResponse,[rejected?1:0]);
  }

  Future<void> leaveVehiclePassenger() async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de bajar de la montura compartida.');
    await connection.send(PsPacketType.useVehicle2);
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
  Future<void> requestTrade(int characterId) async {
    await connection.send(PsPacketType.tradeRequest,_u32Bytes(characterId));
  }

  Future<void> respondTrade({required bool declined}) async {
    await connection.send(PsPacketType.tradeResponse,[declined?1:0]);
  }

  Future<void> addTradeItem(int bag,int slot,int count,int tradeSlot) async {
    for(final v in [bag,slot,count,tradeSlot]){if(v<0||v>255)throw RangeError('Trade byte fuera de rango: $v');}
    await connection.send(PsPacketType.tradeOwnerAddItem,[bag,slot,count,tradeSlot]);
  }

  Future<void> removeTradeItem(int tradeSlot) async {
    if(tradeSlot<0||tradeSlot>255)throw RangeError('Trade slot fuera de rango: $tradeSlot');
    await connection.send(PsPacketType.tradeRemoveItem,[tradeSlot]);
  }

  Future<void> addTradeMoney(int money) async {
    if(money<0||money>0xffffffff)throw RangeError('Oro de trade fuera de uint32.');
    await connection.send(PsPacketType.tradeAddMoney,_u32Bytes(money));
  }

  Future<void> decideTrade(bool decided) async {
    await connection.send(PsPacketType.tradeDecide,[decided?1:0]);
  }

  Future<void> finishTrade(int result) async {
    if(result<0||result>2)throw RangeError('Resultado de trade inválido: $result');
    await connection.send(PsPacketType.tradeFinish,[result]);
  }
  Future<void> requestDuel(int characterId) async {
    await connection.send(PsPacketType.duelRequest,_u32Bytes(characterId));
  }

  Future<void> respondDuel(bool accepted) async {
    await connection.send(PsPacketType.duelResponse,[accepted?1:0]);
  }

  Future<void> addDuelItem(int bag,int slot,int count,int tradeSlot) async {
    for(final v in [bag,slot,count,tradeSlot]){if(v<0||v>255)throw RangeError('Duel trade byte fuera de rango: $v');}
    await connection.send(PsPacketType.duelTradeAddItem,[bag,slot,count,tradeSlot]);
  }

  Future<void> removeDuelItem(int tradeSlot) async {
    if(tradeSlot<0||tradeSlot>255)throw RangeError('Duel trade slot fuera de rango: $tradeSlot');
    await connection.send(PsPacketType.duelTradeRemoveItem,[tradeSlot]);
  }

  Future<void> addDuelMoney(int money) async {
    if(money<0||money>0xffffffff)throw RangeError('Oro de duelo fuera de uint32.');
    await connection.send(PsPacketType.duelTradeAddMoney,_u32Bytes(money));
  }

  Future<void> decideDuelTrade(int result) async {
    if(result<0||result>2)throw RangeError('Resultado de ventana de duelo inválido: $result');
    await connection.send(PsPacketType.duelTradeOk,[result]);
  }

  Future<void> admitDuelDefeat() async {
    await connection.send(PsPacketType.duelCancel);
  }
  Future<void> requestGuildJoin(int guildId) async {
    await connection.send(PsPacketType.guildJoinRequest,_u32Bytes(guildId));
  }

  Future<void> respondGuildJoin(int characterId,{required bool accepted}) async {
    await connection.send(PsPacketType.guildJoinResultUser,[accepted?1:0,..._u32Bytes(characterId)]);
  }

  Future<void> leaveGuild() async {
    await connection.send(PsPacketType.guildLeave);
  }

  Future<void> kickGuildMember(int characterId) async {
    await connection.send(PsPacketType.guildKick,_u32Bytes(characterId));
  }

  Future<void> changeGuildRank(int characterId,{required bool demote}) async {
    await connection.send(PsPacketType.guildUserState,[demote?1:0,..._u32Bytes(characterId)]);
  }

  Future<void> createGuild(String name,String message) async {
    final guild=name.trim(),msg=message.trim();
    if(guild.isEmpty)throw ArgumentError('Nombre de guild vacío.');
    await connection.send(PsPacketType.guildCreate,[..._fixedStringBytes(guild,25),..._fixedUtf16LeBytes(msg,25)]);
  }

  Future<void> respondGuildCreate(bool accepted) async {
    await connection.send(PsPacketType.guildCreateAgree,[accepted?1:0]);
  }

  Future<void> dismantleGuild() async {
    await connection.send(PsPacketType.guildDismantle);
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

  Future<void> createRaid({bool autoJoin=false,int dropType=0}) async {
    await connection.send(PsPacketType.raidCreate,[1,autoJoin?1:0,..._i32Bytes(dropType)]);
  }

  Future<void> joinRaid(String characterName) async {
    await connection.send(PsPacketType.raidJoin,_fixedStringBytes(characterName,21));
  }

  Future<void> inviteRaid(int characterId) async {
    await connection.send(PsPacketType.raidInvite,_u32Bytes(characterId));
  }

  Future<void> respondRaid(int requesterId,{required bool declined}) async {
    await connection.send(PsPacketType.raidResponse,[declined?1:0,..._i32Bytes(requesterId)]);
  }

  Future<void> leaveRaid() async {await connection.send(PsPacketType.raidLeave);}
  Future<void> dismantleRaid() async {await connection.send(PsPacketType.raidDismantle);}
  Future<void> kickRaidMember(int characterId) async {await connection.send(PsPacketType.raidKick,_u32Bytes(characterId));}
  Future<void> changeRaidLeader(int characterId) async {await connection.send(PsPacketType.raidChangeLeader,_u32Bytes(characterId));}
  Future<void> changeRaidSubLeader(int characterId) async {await connection.send(PsPacketType.raidChangeSubLeader,_u32Bytes(characterId));}
  Future<void> changeRaidLoot(int dropType) async {await connection.send(PsPacketType.raidChangeLoot,_i32Bytes(dropType));}
  Future<void> changeRaidAutoJoin(bool enabled) async {await connection.send(PsPacketType.raidChangeAutoInvite,[enabled?1:0]);}
  Future<void> moveRaidMember(int sourceIndex,int destinationIndex) async {
    await connection.send(PsPacketType.raidMovePlayer,[..._i32Bytes(sourceIndex),..._i32Bytes(destinationIndex)]);
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

  Future<void> _sendChatMessage(int type,String message) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar chat.');
    final text=message.trim();if(text.isEmpty)return;
    if(text.length>255)throw RangeError('El mensaje supera 255 caracteres.');
    await connection.send(type,[text.length,..._utf16Le(text)]);
  }

  Future<void> sendNormalChat(String message)=>_sendChatMessage(PsPacketType.chatNormal,message);
  Future<void> sendPartyChat(String message)=>_sendChatMessage(PsPacketType.chatParty,message);
  Future<void> sendGuildChat(String message)=>_sendChatMessage(PsPacketType.chatGuild,message);
  Future<void> sendMapChat(String message)=>_sendChatMessage(PsPacketType.chatMap,message);
  Future<void> sendWorldChat(String message)=>_sendChatMessage(PsPacketType.chatWorld,message);

  Future<void> sendWhisper(String targetName,String message) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de usar whisper.');
    final target=targetName.trim(),text=message.trim();
    if(target.isEmpty||target.length>20)throw RangeError('Nombre de whisper inválido.');
    if(text.isEmpty)return;
    if(text.length>255)throw RangeError('El mensaje supera 255 caracteres.');
    await connection.send(PsPacketType.chatWhisper,[
      ..._fixedStringBytes(target,21),
      text.length,
      ..._utf16Le(text),
    ]);
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
  Future<void> pickupMapItem(int globalId) async {
    if(!_expanded)throw StateError('Selecciona un personaje antes de recoger objetos.');
    if(globalId<=0)throw RangeError('Id de objeto de mapa inválido.');
    await connection.send(PsPacketType.addItem,_u32Bytes(globalId));
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
