import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'ps0032_packet.dart';

class Ps0032AesCtr {
  final Uint8List _counter;
  final AESEngine _aes=AESEngine();
  final Uint8List _mask=Uint8List(16);
  int _maskOffset=16;

  Ps0032AesCtr(Uint8List key,Uint8List counter)
      :_counter=Uint8List.fromList(counter){
    if(key.length!=16||counter.length!=16){
      throw const FormatException('AES ps0032 requiere key/counter de 16 bytes.');
    }
    _aes.init(true,KeyParameter(Uint8List.fromList(key)));
  }

  Uint8List process(Uint8List input){
    final out=Uint8List(input.length);
    for(var i=0;i<input.length;i++){
      if(_maskOffset>=16)_refill();
      out[i]=input[i]^_mask[_maskOffset++];
    }
    return out;
  }

  void _refill(){
    _aes.processBlock(_counter,0,_mask,0);
    _incrementLittleEndian();
    _maskOffset=0;
  }

  void _incrementLittleEndian(){
    for(var i=0;i<_counter.length;i++){
      _counter[i]=(_counter[i]+1)&0xff;
      if(_counter[i]!=0)break;
    }
  }

  Uint8List get counter=>Uint8List.fromList(_counter);
}

Uint8List _hmacSha256(Uint8List key,Uint8List data){
  final h=HMac(SHA256Digest(),64)..init(KeyParameter(key));
  final out=Uint8List(h.macSize);
  h.update(data,0,data.length);
  h.doFinal(out,0);
  return out;
}

Uint8List sha256Bytes(Uint8List data)=>SHA256Digest().process(data);

class Ps0032LoginCrypto {
  final Uint8List key,iv,secretBytes;
  final Ps0032AesCtr send,receive;
  final BigInt encryptedSecret;

  Ps0032LoginCrypto._(
    this.key,this.iv,this.secretBytes,this.encryptedSecret,
    this.send,this.receive,
  );

  factory Ps0032LoginCrypto.fromHello(
    LoginHandshakeHello hello,{
    Uint8List? secretBytes,
  }){
    final secret=secretBytes??_securePositiveBytes(32);
    if(secret.isEmpty||secret.last==0||secret.last>=0x80){
      throw const FormatException('El secreto RSA debe ser positivo y canónico.');
    }
    final secretNumber=littleEndianBigInt(secret);
    if(secretNumber<=BigInt.zero||secretNumber>=hello.modulus){
      throw const FormatException('Secreto RSA fuera del módulo.');
    }
    final encrypted=secretNumber.modPow(hello.exponent,hello.modulus);
    final digest=_hmacSha256(secret,hello.modulusLittleEndian);
    final key=Uint8List.fromList(digest.sublist(0,16));
    final iv=Uint8List.fromList(digest.sublist(16,32));
    return Ps0032LoginCrypto._(
      key,iv,Uint8List.fromList(secret),encrypted,
      Ps0032AesCtr(key,iv),Ps0032AesCtr(key,iv),
    );
  }

  Ps0032Packet handshakePacket(){
    final encrypted=littleEndianBytes(encryptedSecret);
    if(encrypted.length>255)throw const FormatException('RSA cifrado excede 255 bytes.');
    return Ps0032Packet(
      Ps0032Types.loginHandshake,
      Uint8List.fromList([encrypted.length,...encrypted]),
    );
  }

  Uint8List encryptPacket(Ps0032Packet packet)=>packet.encodeEncrypted(send.process);
  Ps0032Packet decryptFrame(Uint8List frame)=>Ps0032Packet.decodeEncrypted(frame,receive.process);

  Ps0032WorldCrypto worldCrypto(){
    final hashed=sha256Bytes(iv);
    final counter=Uint8List.fromList(hashed.sublist(0,16));
    return Ps0032WorldCrypto._(
      Uint8List.fromList(key),
      counter,
      Ps0032AesCtr(key,counter),
      Ps0032AesCtr(key,counter),
    );
  }
}

class Ps0032WorldCrypto {
  final Uint8List key,counter;
  final Ps0032AesCtr send,receive;
  Ps0032WorldCrypto._(this.key,this.counter,this.send,this.receive);

  Uint8List encryptPacket(Ps0032Packet packet)=>packet.encodeEncrypted(send.process);
  Ps0032Packet decryptFrame(Uint8List frame)=>Ps0032Packet.decodeEncrypted(frame,receive.process);
}

Uint8List _securePositiveBytes(int length){
  final r=Random.secure(),out=Uint8List(length);
  for(var i=0;i<length-1;i++)out[i]=r.nextInt(256);
  out[length-1]=1+r.nextInt(0x7f);
  return out;
}
