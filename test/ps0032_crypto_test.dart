import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/protocol/ps0032_crypto.dart';
import 'package:herramienta_shaiya/protocol/ps0032_packet.dart';

Uint8List hex(String value)=>Uint8List.fromList([
  for(var i=0;i<value.length;i+=2)int.parse(value.substring(i,i+2),radix:16),
]);

void main(){
  test('AES CTR usa AES-ECB y contador little endian como Imgeneus',(){
    final ctr=Ps0032AesCtr(
      hex('000102030405060708090a0b0c0d0e0f'),
      hex('00112233445566778899aabbccddeeff'),
    );
    final out=ctr.process(Uint8List(32));
    expect(
      out,
      hex(
        '69c4e0d86a7b0430d8cdb78070b4c55a'
        'a556156c72876577f67f95a9d9e640a7',
      ),
    );
  });

  test('AES CTR send/receive independientes producen stream simetrico',(){
    final key=hex('00112233445566778899aabbccddeeff');
    final iv=hex('ffeeddccbbaa99887766554433221100');
    final enc=Ps0032AesCtr(key,iv),dec=Ps0032AesCtr(key,iv);
    final plain=Uint8List.fromList(List.generate(73,(i)=>(i*7)&0xff));
    final cipher=enc.process(plain);
    expect(cipher,isNot(plain));
    expect(dec.process(cipher),plain);
  });

  test('login deriva HMAC, RSA raw y handshake exactamente',(){
    final hello=LoginHandshakeHello(
      Uint8List.fromList([3]),
      Uint8List.fromList([1,1]), // modulus = 257.
    );
    final crypto=Ps0032LoginCrypto.fromHello(
      hello,
      secretBytes:Uint8List.fromList([5]),
    );
    expect(crypto.encryptedSecret,BigInt.from(125));
    expect(crypto.key,hex('4fd8d8851563739df92ae95d1ac4b4f3'));
    expect(crypto.iv,hex('ce3902215506d20b26c824cfed6d826f'));
    final handshake=crypto.handshakePacket();
    expect(handshake.type,Ps0032Types.loginHandshake);
    expect(handshake.payload,[1,125]);
  });

  test('World deriva counter SHA256 del IV de Login',(){
    final hello=LoginHandshakeHello(
      Uint8List.fromList([3]),
      Uint8List.fromList([1,1]),
    );
    final login=Ps0032LoginCrypto.fromHello(
      hello,
      secretBytes:Uint8List.fromList([5]),
    );
    expect(
      login.worldCrypto().counter,
      hex('b86c7b1e6fb00f0f36fa0325eed6576b'),
    );
  });

  test('cifrado de paquete conserva los dos bytes de longitud',(){
    final key=hex('000102030405060708090a0b0c0d0e0f');
    final iv=hex('00112233445566778899aabbccddeeff');
    final send=Ps0032AesCtr(key,iv),recv=Ps0032AesCtr(key,iv);
    final packet=Ps0032Packet(0xA110,Uint8List.fromList([1,2,3,4]));
    final wire=packet.encodeEncrypted(send.process);
    expect(wire.sublist(0,2),[8,0]);
    final parsed=Ps0032Packet.decodeEncrypted(wire,recv.process);
    expect(parsed.type,0xA110);
    expect(parsed.payload,[1,2,3,4]);
  });
}
