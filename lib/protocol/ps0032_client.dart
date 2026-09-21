import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ps0032_crypto.dart';
import 'ps0032_packet.dart';

class Ps0032WorldInfo {
  final int id,status,connected,maxUsers;
  final String name;
  const Ps0032WorldInfo(this.id,this.status,this.connected,this.maxUsers,this.name);
}

class Ps0032LoginIdentity {
  final int userId;
  final Uint8List sessionIdBytes;
  const Ps0032LoginIdentity(this.userId,this.sessionIdBytes);
}

class Ps0032Bootstrap {
  final Ps0032LoginIdentity identity;
  final List<Ps0032WorldInfo> worlds;
  final int faction,maxMode;
  final List<Ps0032Packet> initialWorldPackets;
  const Ps0032Bootstrap(
    this.identity,this.worlds,this.faction,this.maxMode,this.initialWorldPackets,
  );
}

class _Wire {
  final Socket socket;
  final Ps0032StreamDecoder decoder=Ps0032StreamDecoder();
  final Queue<Uint8List> pending=Queue<Uint8List>();
  late final StreamIterator<Uint8List> iterator=StreamIterator<Uint8List>(socket);
  _Wire(this.socket);

  static Future<_Wire> connect(String host,int port) async {
    final socket=await Socket.connect(host,port,timeout:const Duration(seconds:10));
    socket.setOption(SocketOption.tcpNoDelay,true);
    return _Wire(socket);
  }

  Future<Uint8List> readFrame({Duration timeout=const Duration(seconds:10)}) async {
    return _readFrame().timeout(timeout,onTimeout:(){
      throw TimeoutException('Timeout esperando paquete ps0032.');
    });
  }

  Future<Uint8List> _readFrame() async {
    while(pending.isEmpty){
      if(!await iterator.moveNext())throw const SocketException('Servidor ps0032 cerró la conexión.');
      pending.addAll(decoder.add(iterator.current));
    }
    return pending.removeFirst();
  }

  Future<void> write(Uint8List bytes) async {
    socket.add(bytes);
    await socket.flush();
  }

  Future<void> close() async {
    try{await iterator.cancel();}catch(_){}
    socket.destroy();
  }
}

class Ps0032ClientSession {
  final _Wire login,world;
  final Ps0032LoginCrypto loginCrypto;
  final Ps0032WorldCrypto worldCrypto;
  final Ps0032Bootstrap bootstrap;
  Ps0032ClientSession._(
    this.login,this.world,this.loginCrypto,this.worldCrypto,this.bootstrap,
  );

  Future<Ps0032Packet> readWorld() async =>
      worldCrypto.decryptFrame(await world.readFrame());

  Future<void> sendWorld(Ps0032Packet packet) =>
      world.write(worldCrypto.encryptPacket(packet));

  Future<void> close() async {
    await world.close();
    await login.close();
  }
}

class Ps0032Client {
  final String host;
  final int loginPort,worldPort;
  const Ps0032Client({
    this.host='127.0.0.1',
    this.loginPort=30800,
    this.worldPort=30810,
  });

  Future<Ps0032ClientSession> connect({
    required String oauthKey,
    int preferredWorld=1,
  }) async {
    final login=await _Wire.connect(host,loginPort);
    _Wire? world;
    try{
      final helloPacket=Ps0032Packet.decodePlain(await login.readFrame());
      final hello=LoginHandshakeHello.fromPacket(helloPacket);
      final crypto=Ps0032LoginCrypto.fromHello(hello);

      await login.write(crypto.handshakePacket().encodePlain());
      await login.write(crypto.encryptPacket(oauthPacket(oauthKey)));

      Ps0032LoginIdentity? identity;
      List<Ps0032WorldInfo>? worlds;
      for(var i=0;i<8&&(identity==null||worlds==null);i++){
        final packet=crypto.decryptFrame(await login.readFrame());
        if(packet.type==Ps0032Types.loginRequest){
          identity=_parseLogin(packet);
        }else if(packet.type==Ps0032Types.serverList){
          worlds=_parseWorlds(packet);
        }
      }
      if(identity==null)throw const FormatException('Login no devolvió identidad.');
      if(worlds==null||worlds.isEmpty)throw const FormatException('Login no devolvió mundos.');

      final selected=worlds.where((x)=>x.id==preferredWorld).firstOrNull??worlds.first;
      await login.write(crypto.encryptPacket(selectServerPacket(selected.id)));
      var accepted=false;
      for(var i=0;i<4&&!accepted;i++){
        final packet=crypto.decryptFrame(await login.readFrame());
        if(packet.type!=Ps0032Types.selectServer)continue;
        if(packet.payload.length<5)throw const FormatException('SELECT_SERVER truncado.');
        if(packet.payload[0]!=0)throw FormatException('SELECT_SERVER rechazado: ${packet.payload[0]}.');
        accepted=true;
      }
      if(!accepted)throw const FormatException('SELECT_SERVER sin respuesta.');

      world=await _Wire.connect(host,worldPort);
      final worldCrypto=crypto.worldCrypto();
      final handshakePayload=Uint8List(20),bd=ByteData.sublistView(handshakePayload);
      bd.setInt32(0,identity.userId,Endian.little);
      handshakePayload.setRange(4,20,identity.sessionIdBytes);
      await world.write(Ps0032Packet(Ps0032Types.gameHandshake,handshakePayload).encodePlain());

      final initial=<Ps0032Packet>[];
      int? faction,maxMode;
      var gotHandshake=false;
      for(var i=0;i<20&&(faction==null||!gotHandshake);i++){
        final packet=worldCrypto.decryptFrame(await world.readFrame());
        initial.add(packet);
        if(packet.type==Ps0032Types.gameHandshake){
          if(packet.payload.length<18||packet.payload[0]!=0){
            throw const FormatException('GAME_HANDSHAKE rechazado.');
          }
          gotHandshake=true;
        }else if(packet.type==Ps0032Types.accountFaction){
          if(packet.payload.length<2)throw const FormatException('ACCOUNT_FACTION truncado.');
          faction=packet.payload[0];
          maxMode=packet.payload[1];
        }
      }
      if(!gotHandshake)throw const FormatException('World no confirmó GAME_HANDSHAKE.');
      if(faction==null)throw const FormatException('World no devolvió ACCOUNT_FACTION.');

      return Ps0032ClientSession._(
        login,world,crypto,worldCrypto,
        Ps0032Bootstrap(identity,worlds,faction,maxMode??0,List.unmodifiable(initial)),
      );
    }catch(_){
      if(world!=null)await world.close();
      await login.close();
      rethrow;
    }
  }

  Ps0032LoginIdentity _parseLogin(Ps0032Packet packet){
    final p=packet.payload;
    if(p.length<22)throw const FormatException('LOGIN_REQUEST response truncado.');
    if(p[0]!=0)throw FormatException('Autenticación rechazada: ${p[0]}.');
    final userId=ByteData.sublistView(p).getInt32(1,Endian.little);
    return Ps0032LoginIdentity(userId,Uint8List.fromList(p.sublist(6,22)));
  }

  List<Ps0032WorldInfo> _parseWorlds(Ps0032Packet packet){
    final p=packet.payload;
    if(p.isEmpty)throw const FormatException('SERVER_LIST truncado.');
    var o=1;
    final out=<Ps0032WorldInfo>[];
    for(var i=0;i<p[0];i++){
      if(o+38>p.length)throw const FormatException('SERVER_LIST truncado.');
      final d=ByteData.sublistView(p);
      final id=p[o],status=p[o+1];
      final connected=d.getUint16(o+2,Endian.little);
      final maxUsers=d.getUint16(o+4,Endian.little);
      final raw=p.sublist(o+6,o+38);
      final zero=raw.indexOf(0);
      final name=utf8.decode(zero<0?raw:raw.sublist(0,zero),allowMalformed:true);
      out.add(Ps0032WorldInfo(id,status,connected,maxUsers,name));
      o+=38;
    }
    return out;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull=>isEmpty?null:first;
}
