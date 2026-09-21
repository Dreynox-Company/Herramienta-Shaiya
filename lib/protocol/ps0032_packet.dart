import 'dart:typed_data';

final class Ps0032Types {
  static const int characterList=0x0101,createCharacter=0x0102,selectCharacter=0x0104;
  static const int characterDetails=0x0105,accountFaction=0x0109,characterMove=0x0501;
  static const int mobEnter=0x0601,questList=0x0901,questFinishedList=0x0906,npcEnter=0x0E01;
  static const int loginHandshake=0xA101,loginRequest=0xA102,oauthLoginRequest=0xA110;
  static const int serverList=0xA201,selectServer=0xA202,gameHandshake=0xA301;
}

class Ps0032Packet {
  final int type;
  final Uint8List payload;
  const Ps0032Packet(this.type,this.payload);

  Uint8List encodePlain(){
    final total=4+payload.length;
    if(total>0xffff)throw const FormatException('Paquete ps0032 demasiado grande.');
    final out=Uint8List(total),d=ByteData.sublistView(out);
    d.setUint16(0,total,Endian.little);
    d.setUint16(2,type,Endian.little);
    out.setRange(4,total,payload);
    return out;
  }

  Uint8List encodeEncrypted(Uint8List Function(Uint8List) crypt){
    final plain=encodePlain(),body=crypt(Uint8List.sublistView(plain,2));
    if(body.length!=plain.length-2)throw const FormatException('El cifrador cambió la longitud del paquete.');
    return Uint8List(plain.length)..setRange(0,2,plain)..setRange(2,plain.length,body);
  }

  static Ps0032Packet decodePlain(Uint8List frame){
    if(frame.length<4)throw const FormatException('Trama ps0032 truncada.');
    final d=ByteData.sublistView(frame),declared=d.getUint16(0,Endian.little);
    if(declared!=frame.length)throw FormatException('Longitud ps0032 inválida: $declared != ${frame.length}.');
    return Ps0032Packet(d.getUint16(2,Endian.little),Uint8List.fromList(frame.sublist(4)));
  }

  static Ps0032Packet decodeEncrypted(Uint8List frame,Uint8List Function(Uint8List) crypt){
    if(frame.length<4)throw const FormatException('Trama ps0032 truncada.');
    final declared=ByteData.sublistView(frame).getUint16(0,Endian.little);
    if(declared!=frame.length)throw FormatException('Longitud ps0032 inválida: $declared != ${frame.length}.');
    final body=crypt(Uint8List.fromList(frame.sublist(2)));
    if(body.length!=frame.length-2)throw const FormatException('El descifrador cambió la longitud del paquete.');
    final plain=Uint8List(frame.length)..setRange(0,2,frame)..setRange(2,frame.length,body);
    return decodePlain(plain);
  }
}

class Ps0032StreamDecoder {
  final List<int> _buffer=[];
  final int maxFrame;
  Ps0032StreamDecoder({this.maxFrame=0xffff});

  List<Uint8List> add(List<int> chunk){
    _buffer.addAll(chunk);
    final frames=<Uint8List>[];
    while(_buffer.length>=2){
      final size=_buffer[0]|(_buffer[1]<<8);
      if(size<4||size>maxFrame)throw FormatException('Longitud de trama ps0032 inválida: $size.');
      if(_buffer.length<size)break;
      frames.add(Uint8List.fromList(_buffer.sublist(0,size)));
      _buffer.removeRange(0,size);
    }
    return frames;
  }
  int get bufferedBytes=>_buffer.length;
  void clear()=>_buffer.clear();
}

class LoginHandshakeHello {
  final Uint8List exponentLittleEndian,modulusLittleEndian;
  const LoginHandshakeHello(this.exponentLittleEndian,this.modulusLittleEndian);

  factory LoginHandshakeHello.fromPacket(Ps0032Packet packet){
    if(packet.type!=Ps0032Types.loginHandshake)throw const FormatException('No es LOGIN_HANDSHAKE.');
    final p=packet.payload;
    if(p.length<3+64+128)throw const FormatException('LOGIN_HANDSHAKE truncado.');
    final exponentLength=p[1],modulusLength=p[2];
    if(exponentLength==0||exponentLength>64||modulusLength==0||modulusLength>128){
      throw const FormatException('Longitudes RSA ps0032 inválidas.');
    }
    return LoginHandshakeHello(
      Uint8List.fromList(p.sublist(3,3+exponentLength)),
      Uint8List.fromList(p.sublist(3+64,3+64+modulusLength)),
    );
  }

  BigInt get exponent=>littleEndianBigInt(exponentLittleEndian);
  BigInt get modulus=>littleEndianBigInt(modulusLittleEndian);
}

BigInt littleEndianBigInt(List<int> bytes){
  var value=BigInt.zero;
  for(var i=bytes.length-1;i>=0;i--){value=(value<<8)|BigInt.from(bytes[i]);}
  return value;
}

Uint8List littleEndianBytes(BigInt value,{int? minLength}){
  if(value.isNegative)throw const FormatException('BigInt negativo no soportado.');
  final out=<int>[];
  var n=value;
  while(n>BigInt.zero){out.add((n&BigInt.from(0xff)).toInt());n>>=8;}
  if(out.isEmpty)out.add(0);
  while(minLength!=null&&out.length<minLength)out.add(0);
  return Uint8List.fromList(out);
}

Ps0032Packet oauthPacket(String key){
  final raw=Uint8List(40),bytes=Uint8List.fromList(key.codeUnits);
  if(bytes.length>40)throw const FormatException('OAuth key excede 40 bytes.');
  raw.setRange(0,bytes.length,bytes);
  return Ps0032Packet(Ps0032Types.oauthLoginRequest,raw);
}

Ps0032Packet selectServerPacket(int worldId,{int buildClient=-1}){
  if(worldId<0||worldId>255)throw const FormatException('WorldId inválido.');
  final p=Uint8List(5),d=ByteData.sublistView(p);
  p[0]=worldId;
  d.setInt32(1,buildClient,Endian.little);
  return Ps0032Packet(Ps0032Types.selectServer,p);
}
