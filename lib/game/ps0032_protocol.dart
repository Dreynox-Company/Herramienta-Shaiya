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
  static const selectCharacter=0x0104;
  static const characterDetails=0x0105;
  static const accountFaction=0x0109;
  static const characterMove=0x0501;
  static const mobEnter=0x0601;
  static const questList=0x0901;
  static const questFinishedList=0x0906;
  static const mapNpcEnter=0x0E01;
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

class PsConnection {
  final Socket socket;
  final List<int> _buffer=[];
  final List<PsPacket> _queued=[];
  final List<Completer<PsPacket>> _waiters=[];
  StreamSubscription<Uint8List>? _subscription;
  _AesCtrLe? _recv,_send;
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
      final data=_recv==null?encrypted:_recv!.apply(encrypted);
      if(data.length<2){_fail(StateError('Payload ps0032 truncado.'));return;}
      _emit(PsPacket(_u16(data,0),Uint8List.sublistView(data,2)));
    }
  }

  void _emit(PsPacket packet){
    if(_waiters.isNotEmpty)_waiters.removeAt(0).complete(packet);
    else _queued.add(packet);
  }
  void _onError(Object e)=>_fail(e);
  void _onDone()=>_fail(StateError('Socket ps0032 cerrado por el servidor.'));
  void _fail(Object e){
    if(_closed)return;
    _closed=true;
    for(final w in _waiters){if(!w.isCompleted)w.completeError(e);}
    _waiters.clear();
  }

  Future<void> close() async {
    if(_closed)return;
    _closed=true;
    await _subscription?.cancel();
    await socket.close();
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

class WorldBootstrap {
  final int faction,maxMode;
  final List<PsPacket> packets;
  const WorldBootstrap(this.faction,this.maxMode,this.packets);
  int get characterListPackets=>packets.where((p)=>p.type==PsPacketType.characterList).length;
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

  Future<WorldBootstrap> bootstrapWorld(LoginSession login) async {
    final c=await PsConnection.connect(host,worldPort);
    try{
      final worldIv=Uint8List.fromList(hash.sha256.convert(login.iv).bytes.sublist(0,16));
      c.useCipher(login.key,worldIv);
      await c.send(PsPacketType.gameHandshake,[..._i32Bytes(login.userId),...login.sessionId],true);
      final handshake=await c.nextType(PsPacketType.gameHandshake,timeout:const Duration(seconds:15));
      if(handshake.body.length<18||handshake.body[0]!=0)throw StateError('GAME_HANDSHAKE inválido.');
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
      return WorldBootstrap(faction,maxMode,packets);
    }finally{
      await c.close();
    }
  }
}
