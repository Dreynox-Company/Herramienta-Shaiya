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
