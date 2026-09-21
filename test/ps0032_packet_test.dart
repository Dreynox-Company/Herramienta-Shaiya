import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/protocol/ps0032_packet.dart';

void main(){
  test('framing ps0032 conserva longitud y tipo little endian',(){
    final p=Ps0032Packet(0xA110,Uint8List.fromList([1,2,3]));
    final frame=p.encodePlain();
    expect(frame,[7,0,0x10,0xA1,1,2,3]);
    final parsed=Ps0032Packet.decodePlain(frame);
    expect(parsed.type,0xA110);
    expect(parsed.payload,[1,2,3]);
  });

  test('stream decoder conserva fragmentos TCP y entrega dos tramas',(){
    final a=Ps0032Packet(0x0101,Uint8List.fromList([7])).encodePlain();
    final b=Ps0032Packet(0x0901,Uint8List.fromList([8,9])).encodePlain();
    final all=Uint8List.fromList([...a,...b]);
    final d=Ps0032StreamDecoder();
    expect(d.add(all.sublist(0,3)),isEmpty);
    final frames=d.add(all.sublist(3));
    expect(frames.length,2);
    expect(Ps0032Packet.decodePlain(frames[0]).type,0x0101);
    expect(Ps0032Packet.decodePlain(frames[1]).type,0x0901);
    expect(d.bufferedBytes,0);
  });

  test('OAuth A110 usa exactamente 40 bytes de payload',(){
    final p=oauthPacket('localplayer:abc123');
    expect(p.type,Ps0032Types.oauthLoginRequest);
    expect(p.payload.length,40);
    expect(String.fromCharCodes(p.payload.take(18)),'localplayer:abc123');
  });

  test('SELECT_SERVER A202 serializa world y build -1',(){
    final p=selectServerPacket(1).encodePlain();
    expect(p.length,9);
    expect(ByteData.sublistView(p).getUint16(2,Endian.little),0xA202);
    expect(p[4],1);
    expect(ByteData.sublistView(p).getInt32(5,Endian.little),-1);
  });

  test('LOGIN_HANDSHAKE A101 lee exponent/modulus little endian',(){
    final payload=Uint8List(3+64+128);
    payload[0]=0;payload[1]=2;payload[2]=3;
    payload[3]=0x03;payload[4]=0x01;
    payload[67]=0x05;payload[68]=0x01;payload[69]=0x01;
    final hello=LoginHandshakeHello.fromPacket(
      Ps0032Packet(Ps0032Types.loginHandshake,payload),
    );
    expect(hello.exponent,BigInt.from(0x0103));
    expect(hello.modulus,BigInt.from(0x010105));
  });

  test('BigInt helper roundtrips little endian',(){
    final n=BigInt.parse('123456789abcdef',radix:16);
    expect(littleEndianBigInt(littleEndianBytes(n)),n);
  });
}
