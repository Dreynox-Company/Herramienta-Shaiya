import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/textures.dart';
import 'package:herramienta_shaiya/core/combat.dart';
import 'package:herramienta_shaiya/data/catalog.dart';
import 'package:herramienta_shaiya/data/library.dart';
import 'package:vector_math/vector_math_64.dart';

Matcher closeToList(List<double> expected,double epsilon)=>predicate<List<double>>(
  (actual)=>actual.length==expected.length&&List.generate(actual.length,(i)=>(actual[i]-expected[i]).abs()<=epsilon).every((x)=>x),
  'close to $expected ± $epsilon',
);

Uint8List dds(String code, int c0, int c1, {int selectors = 0}) {
  final data = Uint8List(code == 'DXT1' ? 136 : 144),
      v = ByteData.sublistView(data);
  v.setUint32(0, 0x20534444, Endian.little);
  v.setUint32(4, 124, Endian.little);
  v.setUint32(12, 4, Endian.little);
  v.setUint32(16, 4, Endian.little);
  for (var i = 0; i < 4; i++) {
    data[84 + i] = code.codeUnitAt(i);
  }
  final offset = code == 'DXT1' ? 128 : 136;
  if (code != 'DXT1') {
    for (var i = 128; i < 136; i++) {
      data[i] = 255;
    }
  }
  v.setUint16(offset, c0, Endian.little);
  v.setUint16(offset + 2, c1, Endian.little);
  v.setUint32(offset + 4, selectors, Endian.little);
  return data;
}


Uint8List ep6SkinFixture() {
  final bytes=BytesBuilder(),out=ByteData(4);
  void u32(int x){out.setUint32(0,x,Endian.little);bytes.add(out.buffer.asUint8List());}
  void f32(double x){out.setFloat32(0,x,Endian.little);bytes.add(out.buffer.asUint8List());}
  void u16(int x){final b=ByteData(2)..setUint16(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  u32(444);
  u32(1);
  for(var i=0;i<16;i++)f32(i%5==0?1:0);
  u32(3);
  for(var vertex=0;vertex<3;vertex++){
    f32(vertex==1?1:0);f32(vertex==2?1:0);f32(0);
    f32(.2);f32(.3);f32(.1);
    bytes.add([0,0,0,0]);
    f32(0);f32(1);f32(0);
    f32(vertex==1?1:0);f32(vertex==2?1:0);
  }
  u32(1);u16(0);u16(1);u16(2);
  return bytes.takeBytes();
}


Uint8List svmapNpcRouteFixture() {
  final bytes=BytesBuilder();
  void i32(int x){final b=ByteData(4)..setInt32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void f32(double x){final b=ByteData(4)..setFloat32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}
  i32(8); // map size
  bytes.add(List<int>.filled(8,0)); // 8*8 / 8 collision mask bytes
  i32(0); // cell size
  i32(0); // ladders
  i32(0); // mob areas
  i32(1); // one NPC group
  i32(9);i32(2);i32(2); // Animal 2, two patrol points
  vec(10,20,30);f32(.25);
  vec(40,50,60);f32(.75);
  i32(0); // portals
  i32(0); // rebirth/spawn areas
  i32(0); // named areas
  return bytes.takeBytes();
}


Uint8List dgFixture() {
  final bytes=BytesBuilder();
  void i32(int x){final b=ByteData(4)..setInt32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void u16(int x){final b=ByteData(2)..setUint16(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void f32(double x){final b=ByteData(4)..setFloat32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}
  void str256(String value){
    final out=Uint8List(256),raw=Uint8List.fromList(value.codeUnits);
    out.setRange(0,raw.length.clamp(0,255),raw);
    bytes.add(out);
  }

  vec(0,0,0);vec(10,5,10); // DG bbox.
  i32(1);str256('DUN_LOGIN01.tga');
  i32(0); // lightmap count.
  i32(1); // root node present.

  vec(5,2.5,5); // node center.
  vec(0,0,0);vec(10,5,10); // view box.
  vec(0,0,0);vec(10,5,10); // collision box.
  i32(1); // mesh groups.
  i32(0); // texture index.
  i32(1); // meshes.
  i32(-1); // lightmap index.
  i32(3); // vertices.
  for(final p in <List<double>>[[0,1,0],[1,1,0],[0,1,1]]){
    vec(p[0],p[1],p[2]);
    vec(0,1,0);
    i32(-1);
    f32(p[0]);f32(p[2]);
    f32(0);f32(0);
  }
  i32(1);u16(0);u16(1);u16(2);
  i32(1); // native collision mesh.
  i32(3);
  vec(4,0,4);vec(4,2,4);vec(4,0,6);
  i32(1);u16(0);u16(1);u16(2);
  for(var i=0;i<8;i++)i32(0);
  return bytes.takeBytes();
}


Uint8List worldAudioFixture(){
  final bytes=BytesBuilder();
  void u32(int x){final b=ByteData(4)..setUint32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void i32(int x){final b=ByteData(4)..setInt32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void u16(int x){final b=ByteData(2)..setUint16(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void f32(double x){final b=ByteData(4)..setFloat32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}
  void str256(String value){
    final out=Uint8List(256),raw=Uint8List.fromList(value.codeUnits);
    out.setRange(0,raw.length.clamp(0,255),raw);bytes.add(out);
  }
  void emptyCategory(){u32(0);u32(0);}
  bytes.add([70,76,68,0]); // FLD\0
  u32(2);
  for(var i=0;i<4;i++)u16(10000+i);
  bytes.add(List<int>.filled(4,0));
  u32(0); // terrain layers
  str256(''); // water/layout
  for(var i=0;i<7;i++)emptyCategory();
  u32(0); // MAni names
  u32(0); // MAni instances
  str256(''); // EFT
  u32(0); // effect instances
  i32(0);i32(0);i32(0);
  emptyCategory(); // Entity/Object
  u32(1);str256('field_theme.wav');
  u32(1);
  vec(0,0,0);vec(100,100,100);f32(50);i32(0);i32(0);
  u32(1);str256('birds.wav');
  u32(0); // WLD zones
  u32(1);i32(0);vec(10,0,20);f32(30);
  u32(0); // restricted zones
  u32(0); // portals
  u32(0); // spawns
  u32(0); // named areas
  i32(0); // NPC rows
  str256('sky.bmp');str256('cloud1.bmp');str256('cloud2.bmp');
  for(var i=0;i<6;i++)f32(0); // two unused colors
  vec(.1,.2,.3);f32(40);f32(80);
  return bytes.takeBytes();
}

Uint8List smodCollisionFixture(){
  final bytes=BytesBuilder();
  void u32(int x){final b=ByteData(4)..setUint32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void u16(int x){final b=ByteData(2)..setUint16(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void f32(double x){final b=ByteData(4)..setFloat32(0,x,Endian.little);bytes.add(b.buffer.asUint8List());}
  void vec(double x,double y,double z){f32(x);f32(y);f32(z);}
  vec(0,1,0);f32(5); // center + radius
  vec(-2,0,-2);vec(2,4,2); // view box
  u32(0); // textured objects
  vec(-1,0,-1);vec(1,3,1); // collision box
  u32(1); // collision meshes
  u32(3);
  vec(0,0,0);vec(0,2,0);vec(0,0,2);
  u32(1);u16(0);u16(1);u16(2);
  return bytes.takeBytes();
}

PartRecord part(Slot s, int id, String texture) => PartRecord(
  s,
  MaterialRecord(id, 'm.3dc', texture, 1),
  'm.3dc',
  texture,
  'a.mlt',
);
Archetype archetype() {
  final slots = {for (final s in Slot.values) s: <PartRecord>[]};
  slots[Slot.upper]!.addAll([
    part(Slot.upper, 0, 'humf_upper016.dds'),
    part(Slot.upper, 1, 'humf_wedding_upper.dds'),
  ]);
  slots[Slot.lower]!.add(part(Slot.lower, 0, 'humf_lower016.dds'));
  slots[Slot.hand]!.add(part(Slot.hand, 0, 'humf_hand016.dds'));
  return Archetype('humf', 'human', 'character/human', slots, []);
}

void main() {
  group('Lectura defensiva', () {
    test('rechaza lectura fuera del archivo', () {
      expect(() => Bin(Uint8List(2)).u32(), throwsFormatException);
    });
    test('rechaza recuentos excesivos', () {
      expect(
        () => Bin(Uint8List.fromList([255, 255, 255, 255])).count(),
        throwsFormatException,
      );
    });
    test('rechaza flotantes no finitos', () {
      final b = Uint8List(4);
      ByteData.sublistView(b).setFloat32(0, double.nan, Endian.little);
      expect(() => Bin(b).f32(), throwsFormatException);
    });
    test('rechaza rutas que escapan de DATA', () {
      expect(() => canon('../secreto'), throwsFormatException);
      expect(() => canon('C:\\datos'), throwsFormatException);
    });
    test('normaliza mayusculas y separadores', () {
      expect(
        canon('Character\\Human/3DC/Test.3DC'),
        'character/human/3dc/test.3dc',
      );
    });
    test('resolucion evita basename ambiguo', () {
      final lib = Library('', false, {'a/t.dds': '1', 'b/t.dds': '2'});
      expect(
        () => lib.resolve('t.dds', [], uniqueFallback: true),
        throwsFormatException,
      );
      expect(lib.resolve('t.dds', ['b']), 'b/t.dds');
    });
  });
  group('DDS', () {
    test('DXT1 decodifica rojo real y opaco', () {
      final p = Pixels.dds(dds('DXT1', 0xf800, 0), 'test');
      expect(p.rgba.sublist(0, 4), [255, 0, 0, 255]);
      expect(p.width, 4);
    });
    test('DXT1 conserva pixel transparente', () {
      final p = Pixels.dds(
        dds('DXT1', 0, 65535, selectors: 0xffffffff),
        'test',
      );
      expect(p.rgba[3], 0);
    });
    test('DXT3 decodifica verde', () {
      final p = Pixels.dds(dds('DXT3', 0x07e0, 0), 'test');
      expect(p.rgba.sublist(0, 4), [0, 255, 0, 255]);
    });
    test('canal brillo no produce cuerpo invisible al hacerlo opaco', () {
      final b = dds('DXT3', 0xf800, 0);
      for (var i = 128; i < 136; i++) {
        b[i] = 0;
      }
      final p = Pixels.dds(b, 'test');
      expect(p.rgba[3], 0);
      final png = p.png(opaque: true);
      final decoded = Pixels.decode(png, 'test.png');
      expect(decoded.rgba.sublist(0, 4), [255, 0, 0, 255]);
    });
    test('bloque truncado produce error explicito', () {
      expect(
        () => Pixels.dds(dds('DXT1', 0, 0).sublist(0, 130), 'test'),
        throwsFormatException,
      );
    });
  });
  group('3DC EP6', () {
    test('usa tres grupos de hueso y deja el byte unknown sin peso', () {
      final mesh=MeshData.skinned(ep6SkinFixture(),'fixture.3dc');
      expect(mesh.weights.sublist(0,4),closeToList([1/3,.5,1/6,0],1e-6));
      expect(mesh.joints.sublist(0,4),[0,0,0,0]);
      expect(mesh.weights.sublist(0,4).reduce((a,b)=>a+b),closeTo(1,1e-6));
    });
  });

  group('Conjunto inicial nativo', () {
    test('prefiere el set 001 de la primera fila MLT', () {
      final slots={for(final s in Slot.values)s:<PartRecord>[]};
      slots[Slot.upper]!.addAll([
        part(Slot.upper,0,'humf_torso001.dds'),
        part(Slot.upper,15,'humf_upper016.dds'),
      ]);
      slots[Slot.lower]!.addAll([
        part(Slot.lower,0,'humf_lower001.dds'),
        part(Slot.lower,15,'humf_lower016.dds'),
      ]);
      slots[Slot.hand]!.addAll([
        part(Slot.hand,0,'humf_hand001.dds'),
        part(Slot.hand,15,'humf_hand016.dds'),
      ]);
      slots[Slot.foot]!.addAll([
        part(Slot.foot,0,'humf_boots001.dds'),
        part(Slot.foot,15,'humf_boots016.dds'),
      ]);
      final a=Archetype('humf','human','character/human',slots,[]);
      final look=Appearance.initial(a);
      expect(look.selected[Slot.upper]!.key,'001');
      expect(look.selected[Slot.lower]!.key,'001');
    });
  });

  group('DG dungeon', () {
    test('lee nodos, textura y malla de Login.wld', () {
      final dg=DgData.parse(dgFixture(),'DUN_LOGIN.dg');
      expect(dg.parts.length,1);
      expect(dg.parts.single.texture,'DUN_LOGIN01.tga');
      expect(dg.parts.single.mesh.vertices,3);
      expect(dg.parts.single.mesh.triangles,1);
      expect(dg.collisions.length,1);
      expect(dg.collisions.single.vertices.length,3);
      expect(dg.collisions.single.indices,[0,1,2]);
      expect(dg.center.x,closeTo(5,1e-6));
      expect(dg.center.z,closeTo(5,1e-6));
      expect(dg.floorAt(5,5),closeTo(1,1e-6));
    });
  });

  group('SVMAP NPC', () {
    test('un grupo conserva su ruta y solo crea un NPC lógico', () {
      final map=SvmapData.parse(svmapNpcRouteFixture(),'fixture.svmap');
      expect(map.npcs.length,1);
      expect(map.npcs.single.type,9);
      expect(map.npcs.single.id,2);
      expect(map.npcs.single.route.length,2);
      expect(map.npcs.single.position.x,closeTo(10,1e-6));
      expect(map.npcs.single.position.z,closeTo(30,1e-6));
      expect(map.npcs.single.route[1].position.x,closeTo(40,1e-6));
      expect(map.npcs.single.route[1].yaw,closeTo(.75,1e-6));
    });
  });

  group('Transformación WLD', () {
    test('preserva basis completo y convierte LH a RH', () {
      final obj=WorldInstance(
        'Building',
        'test.smod',
        Vector3(10,2,20),
        Vector3(0,0,1),
        Vector3(0,1,0),
      );
      final m=worldInstanceMatrix(obj,5,15).storage;
      expect(m[0],closeTo(1,1e-6));
      expect(m[5],closeTo(1,1e-6));
      expect(m[10],closeTo(-1,1e-6));
      expect(m[12],closeTo(5,1e-6));
      expect(m[13],closeTo(2,1e-6));
      expect(m[14],closeTo(-5,1e-6));
    });
  });


  group('WLD audio zones',(){
    test('decodifica música y efectos ambientales nativos',(){
      final w=WorldData.parse(worldAudioFixture(),'audio.wld');
      expect(w.musicAssets,['field_theme.wav']);
      expect(w.musicZones.length,1);
      expect(w.musicZones.single.assetId,0);
      expect(w.musicZones.single.bounds.contains(50,10,50),isTrue);
      expect(w.musicZones.single.bounds.contains(120,10,50),isFalse);
      expect(w.soundEffectAssets,['birds.wav']);
      expect(w.soundEffects.length,1);
      expect(w.soundEffects.single.contains(10,0,20),isTrue);
      expect(w.soundEffects.single.contains(100,0,20),isFalse);
      expect(w.skyFile,'sky.bmp');
      expect(w.fogStart,closeTo(40,1e-6));
      expect(w.fogEnd,closeTo(80,1e-6));
    });
  });

  group('SMOD collision',(){
    test('decodifica la malla de colisión nativa además de la geometría visual',(){
      final smod=readSmodData(smodCollisionFixture(),'collision.smod');
      expect(smod.parts,isEmpty);
      expect(smod.radius,closeTo(5,1e-6));
      expect(smod.collisions.length,1);
      expect(smod.collisions.single.vertices.length,3);
      expect(smod.collisions.single.indices,[0,1,2]);
      expect(smod.collisionUpper.y,closeTo(3,1e-6));
    });
  });

  group('Cambio de conjunto', () {
    test('identidad liga torso y piernas por recurso, no indice de tabla', () {
      expect(
        setIdentity('humf_upper016.dds'),
        setIdentity('humf_lower016.dds'),
      );
      expect(
        setIdentity('humf_wedding_upper.dds'),
        setIdentity('humf_wedding_lower.dds'),
      );
    });
    test('conjunto integral elimina la seleccion de pantalon anterior', () {
      final a = archetype(), first = Appearance.forSet(a, '016');
      expect(first.selected[Slot.lower], isNotNull);
      final next = Appearance.forSet(a, 'wedding', previous: first);
      expect(next.selected[Slot.lower], isNull);
      expect(next.fullCostume, isTrue);
      expect(next.effective.any((p) => p.slot == Slot.lower), isFalse);
    });
    test('selecciones son inmutables', () {
      final a = Appearance.forSet(archetype(), '016');
      expect(() => a.selected[Slot.upper] = null, throwsUnsupportedError);
    });
    test('rechaza pieza de otro arquetipo', () {
      final a = Appearance.forSet(archetype(), '016');
      expect(
        () => a.withPart(Slot.upper, part(Slot.upper, 10, 'otra.dds')),
        throwsFormatException,
      );
    });
    test('body001 no se etiqueta como desnudo', () {
      final p = PartRecord(
        Slot.upper,
        const MaterialRecord(1, 'human_m_fighter_body001.3dc', 'a.dds', 0),
        'a',
        'b',
        'c',
      );
      expect(p.explicitNude, isFalse);
    });
  });
  group('Combate simulado', () {
    test('no hay dano fuera de alcance', () {
      final c = Combat();
      expect(c.attack(20), isFalse);
      expect(c.enemyHealth, 1000);
    });
    test('impacto exactamente una vez y cooldown', () {
      final c = Combat()..counterattack = false;
      expect(c.attack(1), isTrue);
      expect(c.attack(1), isFalse);
      for (var i = 0; i < 20; i++) {
        c.step(.05, 1);
      }
      expect(c.enemyHealth, 910);
    });
    test('reiniciar cancela golpes pendientes', () {
      final c = Combat();
      c.attack(1);
      c.reset();
      for (var i = 0; i < 30; i++) {
        c.step(.05, 1);
      }
      expect(c.enemyHealth, 1000);
      expect(c.playerHealth, 1000);
    });
    test('muerte detiene acciones posteriores', () {
      final c = Combat()
        ..counterattack = false
        ..damage = 1000;
      c.attack(1);
      for (var i = 0; i < 20; i++) {
        c.step(.05, 1);
      }
      expect(c.alive, isFalse);
      expect(c.active, isFalse);
      expect(c.attack(1), isFalse);
    });
  });
}
