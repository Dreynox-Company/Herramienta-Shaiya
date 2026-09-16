"""Codemod de una sola ejecución; se elimina del árbol tras pasar las pruebas.
No procesa ni publica DATA. Rechaza una base distinta, nunca fuerza un push.
"""
from pathlib import Path
import hashlib
root=Path.cwd()
expected={'lib/core/formats.dart':'a991dfdfbf53147277ee572691647d2ad27989a0e19ff1a418f3bcf60925be08','lib/core/combat.dart':'505d3492961c8de6b8226deb9671c8331622cd56151ef82e14f0f056e437b7fd','lib/data/catalog.dart':'0dd0ec58f858dc525f5b87515917785355faf3347d20b82ae900b3f930c3740e','lib/render/studio_scene.dart':'ebb62467b6132f2005437ce1d3729c5cf2e49ca0f2fc50a9bc41bdab50ff12f5','lib/main.dart':'e3626b2cb50699dbd1e36eecc1d30b9be01a58aa7fa4dfd1a14ab8d7e4d43e06','tool/audit_assets.dart':'f6f8b3aba75ab6f75bf73cd3cf88cb09829154d50e9ed2bec93af581a1b96596'}
for path,digest in expected.items():
    assert hashlib.sha256((root/path).read_bytes()).hexdigest()==digest, f'La base cambió: {path}. No se modifica.'

p=root/'lib/core/formats.dart';s=p.read_text()
s=s.replace("  double f32() { need(4); final x = data.getFloat32(offset, Endian.little); offset += 4; if (!x.isFinite) fail('Número no finito.'); return x; }", "  double rawFloat() { need(4); final x = data.getFloat32(offset, Endian.little); offset += 4; return x; }\n  double f32() { final x = rawFloat(); if (!x.isFinite) fail('Número no finito.'); return x; }")
s=s.replace('  v.Matrix4 matrix() => v.Matrix4.fromList(floats(16));','  v.Matrix4 matrix() => v.Matrix4.fromList(floats(16));\n  v.Matrix4 rawMatrix() => v.Matrix4.fromList(List.generate(16, (_) => rawFloat()));')
s=s.replace('  final String source;\n  MeshData(', '  final String source;\n  final List<String> repairs = [];\n  MeshData(',1)
s=s.replace('final inv=List.generate(nb,(_)=>r.matrix());','final inv=List.generate(nb,(_)=>r.rawMatrix());')
s=s.replace('normal[i*3+k]=r.f32();','normal[i*3+k]=r.rawFloat();')
s=s.replace('    return MeshData(p,normal,uv,readIndices(r,n),joints,weights,inv,r.source);', '''    final index=readIndices(r,n);
    final model=MeshData(p,normal,uv,index,joints,weights,inv,r.source);
    final used=<int>{};for(var i=0;i<weights.length;i++){if(weights[i]>1e-6)used.add(joints[i]);}
    for(var i=0;i<inv.length;i++){
      final valid=inv[i].storage.every((x)=>x.isFinite)&&inv[i].determinant().abs()>1e-12;
      if(!valid&&used.contains(i))r.fail('Matriz de enlace inválida en el hueso utilizado $i.');
      if(!valid){inv[i]=v.Matrix4.identity();model.repairs.add('Matriz auxiliar no utilizada $i omitida.');}
    }
    model.repairNormals();return model;''')
s=s.replace('no[3*i+k]=r.f32();','no[3*i+k]=r.rawFloat();')
s=s.replace('    return MeshData(p,no,uv,readIndices(r,n),Uint8List(0),Float32List(0),[],r.source);','    return MeshData(p,no,uv,readIndices(r,n),Uint8List(0),Float32List(0),[],r.source)..repairNormals();')
s=s.replace('  static Uint16List readIndices', '''  void repairNormals(){
    if(normals.every((n)=>n.isFinite))return;
    normals.fillRange(0,normals.length,0);
    for(var i=0;i<indices.length;i+=3){
      final a=indices[i]*3,b=indices[i+1]*3,c=indices[i+2]*3;
      final ax=positions[b]-positions[a],ay=positions[b+1]-positions[a+1],az=positions[b+2]-positions[a+2];
      final bx=positions[c]-positions[a],by=positions[c+1]-positions[a+1],bz=positions[c+2]-positions[a+2];
      final nx=ay*bz-az*by,ny=az*bx-ax*bz,nz=ax*by-ay*bx;
      for(final k in [a,b,c]){normals[k]+=nx;normals[k+1]+=ny;normals[k+2]+=nz;}
    }
    for(var i=0;i<normals.length;i+=3){
      final length=math.sqrt(normals[i]*normals[i]+normals[i+1]*normals[i+1]+normals[i+2]*normals[i+2]);
      if(length>1e-12){for(var k=0;k<3;k++){normals[i+k]/=length;}}else{normals[i+1]=1;}
    }
    repairs.add('Normales no finitas reconstruidas desde los triángulos; posiciones, UV y pesos originales conservados.');
  }
  static Uint16List readIndices''')
s=s.replace('      final world=r.matrix();final local=parent<0?world:v.Matrix4.inverted(tracks[parent].bind)*world;\n      final p=v.Vector3.zero(),s=v.Vector3.zero();final q=v.Quaternion.identity();local.decompose(p,q,s);', '''      final world=r.rawMatrix();
      final p=v.Vector3.zero(),s=v.Vector3.zero();final q=v.Quaternion.identity();''')
s=s.replace('      tracks.add(BoneTrack(parent,world,rt.isEmpty?', '''      // Solo se usa el enlace como respaldo cuando falta un canal.
      if(rt.isEmpty||pt.isEmpty){
        if(!world.storage.every((x)=>x.isFinite)||world.determinant().abs()<1e-12)r.fail('Matriz inválida para un canal de animación sin claves.');
        v.Matrix4 local=world;
        if(parent>=0){final bind=tracks[parent].bind;if(!bind.storage.every((x)=>x.isFinite)||bind.determinant().abs()<1e-12)r.fail('Respaldo de animación singular.');local=v.Matrix4.inverted(bind)*world;}
        local.decompose(p,q,s);
        if(!p.storage.every((x)=>x.isFinite)||!q.storage.every((x)=>x.isFinite))r.fail('No se pudo recuperar el canal de animación.');
      }
      tracks.add(BoneTrack(parent,world,rt.isEmpty?''')
s=s.replace('  v.Matrix4 get matrix=>', '''  bool get defined=>bone>=0&&(bone!=0||position.length2>1e-12||rotation.x.abs()+rotation.y.abs()+rotation.z.abs()>1e-6);
  v.Matrix4 get matrix=>''')
p.write_text(s)
p=root/'tool/audit_assets.dart';s=p.read_text().replace('Pixels.dds(b,path)','Pixels.decode(b,path)');p.write_text(s)

(root/'lib/core/motion_catalog.dart').write_text(r'''import 'formats.dart';

// Identificadores contrastados con ItemType/MotionType del cliente EP6.
int weaponFamily(WeaponRecord? weapon){if(weapon==null)return 0;final name=weapon.source.replaceAll('\\','/').split('/').last;return int.tryParse(RegExp(r'^\d+').stringMatch(name)??'')??0;}
const weaponNames={1:'Espada de una mano',2:'Espada de dos manos',3:'Hacha de una mano',4:'Hacha de dos manos',5:'Armas dobles',6:'Lanza',7:'Maza de una mano',8:'Maza de dos manos',9:'Daga invertida',10:'Daga',11:'Jabalina',12:'Bastón',13:'Arco',14:'Ballesta',15:'Garras',19:'Escudo de la Luz',34:'Escudo de la Furia'};
String weaponLabel(WeaponRecord w)=>'${weaponNames[weaponFamily(w)]??'Equipo'} · ${w.id}';
int? motionIndex(String path){final match=RegExp(r'_(\d{3})_').firstMatch(path);return match==null?null:int.tryParse(match.group(1)!);}
int? readyMotion(int family)=>switch(family){1||3||7=>34,2||4||8=>23,5=>41,6=>48,9=>63,10=>77,11=>55,12=>59,13||14=>30,15=>70,_=>null};
List<int> attackMotions(int family){final ready=readyMotion(family);if(ready==null)return [];final count=[11,13,14].contains(family)?1:family==12?2:4;return List.generate(count,(i)=>ready+1+i);}
int? damageMotion(int family){final ready=readyMotion(family);if(ready==null)return null;return ready+([11,13,14].contains(family)?2:family==12?3:5);}
const motionNames={0:'Reposo',1:'Caminar',2:'Correr',3:'Paso atrás',4:'Paso lateral izquierdo',5:'Paso lateral derecho',6:'Reposo en el agua',7:'Nadar',8:'Saltar',9:'Caída',10:'Sentarse',11:'Levantarse',12:'Descansar sentado',13:'Esquiva hacia atrás',14:'Esquiva izquierda',15:'Esquiva derecha',16:'Gesto de reposo 1',17:'Gesto de reposo 2',18:'Escalar',19:'Presentación',20:'Montura en movimiento',21:'Reposo en montura',22:'Tabla de nieve',23:'Guardia · dos manos',30:'Guardia · arco',34:'Guardia · una mano',41:'Guardia · armas dobles',48:'Guardia · lanza',55:'Guardia · jabalina',59:'Guardia · bastón',63:'Guardia · daga invertida',70:'Guardia · garras',77:'Guardia · daga',116:'Súplica',117:'Victoria',118:'Risa',119:'Amor',120:'Saludo',121:'Aplauso',122:'Derrota',123:'Inicio',124:'Insulto',125:'Provocación'};
String translatedMotion(String path){
  final index=motionIndex(path),name=path.toLowerCase();
  if(motionNames.containsKey(index))return motionNames[index]!;
  if(index!=null&&index>=100&&index<=115)return 'Habilidad · $index';
  for(final type in [1,2,5,6,9,10,11,12,13,15]){if(attackMotions(type).contains(index))return 'Ataque ${attackMotions(type).indexOf(index!)+1} · ${weaponNames[type]}';if(damageMotion(type)==index)return 'Daño · ${weaponNames[type]}';}
  if(name.contains('run'))return 'Correr con equipo';
  if(name.contains('attack'))return 'Acción de ataque';
  if(name.contains('ready')||name.contains('roop'))return 'Canalización de habilidad';
  return 'Animación ${index??''}';
}
''')
p=root/'lib/data/catalog.dart';s=p.read_text();s="export '../core/motion_catalog.dart';\nimport '../core/motion_catalog.dart';\n"+s
start=s.index('String animationLabel(');end=s.index('String setIdentity',start);s=s[:start]+"String animationLabel(String source)=>translatedMotion(source);\n"+s[end:];p.write_text(s)
p=root/'lib/main.dart';s=p.read_text().replace("'${scene.weaponRecord!.source} · ${scene.weaponRecord!.id}'",'weaponLabel(scene.weaponRecord!)').replace("(w)=>'Arma ${w.id} · familia ${baseName(w.source).replaceFirst('.itm','')}'",'weaponLabel')
s=s.replace('final keys=HardwareKeyboard.instance.logicalKeysPressed;scene.walkX=', 'final keys=HardwareKeyboard.instance.logicalKeysPressed;scene.running=keys.contains(LogicalKeyboardKey.shiftLeft)||keys.contains(LogicalKeyboardKey.shiftRight);scene.walkX=')
s=s.replace('WASD: mover','WASD: mover · Shift: correr');p.write_text(s)
p=root/'lib/core/combat.dart';s=p.read_text().replace('double _clock=0,','double attackDuration=1;\n  double _clock=0,').replace('bool attack(double distance,{double duration=1.0}) {','bool attack(double distance,{double? duration}) {\n    final time=duration??attackDuration;').replace('math.max(cooldown,duration)','math.max(cooldown,time)').replace('_clock+duration*.45','_clock+time*.45');p.write_text(s)
p=root/'lib/render/studio_scene.dart';s=p.read_text()
s=s.replace('  ClipData? clip,idle;', '  ClipData? clip,idle,normal;\n  int? wingBone;\n  v.Matrix4? wingReference;')
s=s.replace('  RenderPart? weapon;', '  RenderPart? weapon,secondWeapon;')
s=s.replace('  Attachment? weaponAttachment;', '  Attachment? weaponAttachment,secondAttachment;\n  List<ClipData> attackClips=[];\n  int attackCounter=0,_locomotionRevision=0;\n  bool running=false,_wasMoving=false,_wasRunning=false;')
s=s.replace('final data=MeshData.skinned(await catalog!.library.read(mesh),mesh);return makePart', "final data=MeshData.skinned(await catalog!.library.read(mesh),mesh);for(final repair in data.repairs){report('$mesh · $repair');}return makePart")
s=s.replace('if(c!=null){staged.idle=c;staged.play(c);}', '''if(c!=null){
        staged.idle=c;staged.normal=c;staged.play(c);
        var score=double.infinity;
        for(var i=1;i<math.min(staged.world.length,12);i++){
          final m=staged.world[i].storage;final d=(m[13]-staged.height*.74).abs()+m[12].abs()*.7+m[14].abs()*.3;
          if(d<score&&staged.world[i].determinant().abs()>1e-12){score=d;staged.wingBone=i;staged.wingReference=v.Matrix4.inverted(staged.world[i]);}
        }
        if(mount!=null){final ride=await firstCompatible(staged,next.archetype.animations.where((p)=>motionIndex(p)==21).toList());if(ride!=null)staged.play(ride);}
      }''')
s=s.replace('      staged.root.scale.z=-1;weapon?.dispose();weapon=null;weaponRecord=null;weaponAttachment=null;++_weaponRevision;++_clipRevision;', '''      staged.root.scale.z=-1;
      final old=character;
      if(old!=null){staged.root.position.setValues(old.root.position.x,old.root.position.y,old.root.position.z);staged.root.rotation.y=old.root.rotation.y;}
      final keep=appearance?.archetype.id==next.archetype.id&&appearance?.archetype.race==next.archetype.race;
      if(keep){for(final part in [weapon,secondWeapon]){if(part!=null){part.mesh.removeFromParent();staged.root.add(part.mesh);}}}
      else{weapon?.dispose();secondWeapon?.dispose();weapon=null;secondWeapon=null;weaponRecord=null;weaponAttachment=null;secondAttachment=null;}
      ++_weaponRevision;++_clipRevision;++_locomotionRevision;_wasMoving=false;attackClips.clear();''')
s=s.replace('      combat.reset();updateAttachments();updateCamera();','      combat.reset();await prepareWeaponMotions();updateAttachments();updateCamera();',1)
s=s.replace('      if(idle!=null){a.idle=idle;a.play(idle);}','      if(idle!=null){a.idle=idle;a.normal=idle;a.play(idle);}')
s=s.replace('if(staged!=null)view!.scene.add(staged.root);', "if(staged!=null)view!.scene.add(staged.root);if(kind=='wing'&&staged!=null)staged.root.matrixAutoUpdate=false;")
s=s.replace('if(w==null){weapon?.dispose();weapon=null;weaponRecord=null;weaponAttachment=null;notifyListeners();return;}','if(w==null){weapon?.dispose();secondWeapon?.dispose();weapon=null;secondWeapon=null;weaponRecord=null;weaponAttachment=null;secondAttachment=null;await prepareWeaponMotions();notifyListeners();return;}')
s=s.replace('if(attachment==null||attachment.bone<0||attachment.bone>=a.world.length)','if(attachment==null||!attachment.defined||attachment.bone>=a.world.length)')
s=s.replace("    weapon?.dispose();weapon=part;weaponRecord=w;weaponAttachment=attachment;a.root.add(part.mesh);part.mesh.matrixAutoUpdate=false;updateAttachments();say('Arma equipada con el anclaje IT2 original.');", '''    RenderPart? other;Attachment? otherAttachment;
    if([5,15].contains(weaponFamily(w))&&w.transforms[code][1].defined){
      otherAttachment=w.transforms[code][1];
      if(otherAttachment.bone>=a.world.length){part.dispose();throw const FormatException('El segundo anclaje requiere otro esqueleto.');}
      try{other=await makePart(data,tex,opaque:w.alpha==1);}catch(_){part.dispose();rethrow;}
    }
    if(disposed||rev!=_weaponRevision||character!=a){part.dispose();other?.dispose();return;}
    weapon?.dispose();secondWeapon?.dispose();weapon=part;secondWeapon=other;weaponRecord=w;weaponAttachment=attachment;secondAttachment=otherAttachment;
    for(final p in [part,other]){if(p!=null){a.root.add(p.mesh);p.mesh.matrixAutoUpdate=false;}}
    await prepareWeaponMotions();updateAttachments();say('${weaponLabel(w)} equipado${other==null?'':' en ambas manos'} con anclajes IT2 originales.');''')
s=s.replace('  void updateAttachments() {', '''  Future<void> prepareWeaponMotions() async {
    final a=character;if(a==null)return;
    attackClips.clear();attackCounter=0;
    final family=weaponFamily(weaponRecord),wanted=attackMotions(family);
    final candidates=wanted.isEmpty?animations.where((p)=>p.contains('attack')).take(4):animations.where((p)=>wanted.contains(motionIndex(p)));
    for(final path in candidates){final c=await firstCompatible(a,[path]);if(c!=null&&a==character)attackClips.add(c);}
    if(a!=character)return;
    final ready=readyMotion(family),paths=animations.where((p)=>motionIndex(p)==ready).toList();
    final idle=paths.isEmpty?a.normal:await firstCompatible(a,paths);
    if(idle!=null){a.idle=idle;if(mount==null)a.play(idle);}
    if(attackClips.isNotEmpty)combat.attackDuration=attackClips.first.duration;
  }
  Future<void> locomotion(bool moving,bool fast) async {
    final revision=++_locomotionRevision,a=character;if(a==null)return;
    ClipData? desired;
    final index=mount!=null?(moving?20:21):(fast?2:1);
    if(!moving&&mount==null){desired=a.idle;}
    else{desired=await firstCompatible(a,animations.where((p)=>motionIndex(p)==index).toList());}
    if(disposed||a!=character||revision!=_locomotionRevision)return;
    if(desired!=null&&!sceneCombatLocked)a.play(desired);
    final vehicle=mount;if(vehicle!=null){final c=vehicle.clips[moving?(fast?'Correr':'Caminar'):'Respirar']??vehicle.clips[moving?'Correr':'Reposo'];if(c!=null)vehicle.play(c);}
  }
  bool get sceneCombatLocked=>combat.active||!combat.alive;
  void updateAttachments() {''')
s=s.replace('    if(mount!=null){mount!.root.position', '    if(secondWeapon!=null&&secondAttachment!=null&&secondAttachment!.bone<a.world.length){secondWeapon!.mesh.matrix.copyFromArray((a.world[secondAttachment!.bone]*secondAttachment!.matrix).storage);secondWeapon!.mesh.matrixWorldNeedsUpdate=true;}\n    if(mount!=null){mount!.root.position',1)
old='    if(wing!=null){wing!.root.position.setValues(x+math.sin(rotation)*wingDepth,groundY+wingHeight+(mount==null?0:riderHeight),z+math.cos(rotation)*wingDepth);wing!.root.scale.setValues(wingSize,wingSize,-wingSize);wing!.root.rotation.y=rotation;}'
new='''    if(wing!=null){
      final root=v.Matrix4.compose(v.Vector3(x,a.root.position.y,z),v.Quaternion.axisAngle(v.Vector3(0,1,0),rotation),v.Vector3(1,1,-1));
      final bone=a.wingBone;final delta=bone!=null&&bone<a.world.length&&a.wingReference!=null?a.world[bone]*a.wingReference!:v.Matrix4.identity();
      final offset=v.Matrix4.compose(v.Vector3(0,wingHeight,wingDepth),v.Quaternion.identity(),v.Vector3.all(wingSize));
      wing!.root.matrix.copyFromArray((root*delta*offset).storage);wing!.root.matrixWorldNeedsUpdate=true;
    }'''
assert old in s;s=s.replace(old,new)
old="""        final tokens=event=='attack'?['attack','_att']:event=='death'?['die','dead']:['damage','_dam'];
        final candidates=animations.where((p)=>tokens.any(p.contains)).toList();
        final c=await firstCompatible(a,candidates);if(c!=null&&a==character)a.play(c,repeat:false);"""
new="""        ClipData? c;
        if(event=='attack'&&attackClips.isNotEmpty){c=attackClips[attackCounter++%attackClips.length];combat.attackDuration=attackClips[attackCounter%attackClips.length].duration;}
        else {final index=event=='death'?9:damageMotion(weaponFamily(weaponRecord));final candidates=animations.where((p)=>index!=null?motionIndex(p)==index:p.contains('damage')).toList();c=await firstCompatible(a,candidates);}
        if(c!=null&&a==character)a.play(c,repeat:false);"""
assert old in s;s=s.replace(old,new)
s=s.replace('    character!.root.rotation.y=math.atan2', "    if(attackClips.isEmpty)await prepareWeaponMotions();\n    if(attackClips.isEmpty)throw const FormatException('No existe un ataque compatible con el equipo y arquetipo seleccionados.');\n    character!.root.rotation.y=math.atan2",1)
s=s.replace("final c=a.clips['Respirar']??a.clips['Reposo']??a.clips.values.where((c)=>c.source.contains('normal')||c.source.contains('_br')).firstOrNull;", "final c=a.clips['Respirar']??a.clips['Reposo']??a.normal;")
s=s.replace('weapon?.mesh.material?.wireframe=value;notifyListeners();','weapon?.mesh.material?.wireframe=value;secondWeapon?.mesh.material?.wireframe=value;notifyListeners();')
s=s.replace('    for(final a in [character,enemy,mount,wing]){a?.tick(delta);}', '    final moving=walkX!=0||walkZ!=0;\n    if(moving!=_wasMoving||(moving&&running!=_wasRunning)){_wasMoving=moving;_wasRunning=running;unawaited(locomotion(moving,running));}\n    for(final a in [character,enemy,mount,wing]){a?.tick(delta);}')
s=s.replace('walkX/norm*delta*2,z=character!.root.position.z+walkZ/norm*delta*2', 'walkX/norm*delta*(running?4:2),z=character!.root.position.z+walkZ/norm*delta*(running?4:2)')
s=s.replace('weapon?.dispose();for(final p in environmentParts)', 'weapon?.dispose();secondWeapon?.dispose();for(final p in environmentParts)')
p.write_text(s)

(root/'test/recovery_test.dart').write_text('''import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/motion_catalog.dart';
class Writer {
  final BytesBuilder data=BytesBuilder();
  void u(int n){final b=ByteData(4)..setUint32(0,n,Endian.little);data.add(b.buffer.asUint8List());}
  void i(int n){final b=ByteData(4)..setInt32(0,n,Endian.little);data.add(b.buffer.asUint8List());}
  void f(double n){final b=ByteData(4)..setFloat32(0,n,Endian.little);data.add(b.buffer.asUint8List());}
  void short(int n){final b=ByteData(2)..setUint16(0,n,Endian.little);data.add(b.buffer.asUint8List());}
  void mat({bool bad=false}){for(var k=0;k<16;k++){f(bad?double.nan:(k%5==0?1:0));}}
}
Uint8List mesh({bool usedInvalid=false,bool invalidPosition=false}){
 final b=Writer();b.u(0);b.u(2);b.mat(bad:usedInvalid);b.mat(bad:true);b.u(3);
 for(final p in [[0.0,0.0,0.0],[1.0,0.0,0.0],[0.0,1.0,0.0]]){
  b.f(invalidPosition?double.nan:p[0]);b.f(p[1]);b.f(p[2]);b.f(1);b.data.add([0,1,0,0]);b.f(double.nan);b.f(0);b.f(1);b.f(0);b.f(0);
 }
 b.u(1);b.short(0);b.short(1);b.short(2);return b.data.toBytes();
}
void main(){
 test('normales dañadas se derivan de geometría válida, sin inventar posiciones',(){final m=MeshData.skinned(mesh(),'prueba.3dc');expect(m.positions,[0,0,0,1,0,0,0,1,0]);expect(m.normals,[0,0,1,0,0,1,0,0,1]);expect(m.repairs.length,2);});
 test('una matriz inválida utilizada por vértices no se acepta',(){expect(()=>MeshData.skinned(mesh(usedInvalid:true),'mala.3dc'),throwsFormatException);});
 test('las posiciones inválidas no se reparan arbitrariamente',(){expect(()=>MeshData.skinned(mesh(invalidPosition:true),'mala.3dc'),throwsFormatException);});
 test('ANI con claves completas no depende de una matriz auxiliar singular',(){final b=Writer();b.i(0);b.i(30);b.short(1);b.i(-1);for(var i=0;i<16;i++){b.f(0);}b.u(1);b.i(0);b.f(0);b.f(0);b.f(0);b.f(1);b.u(1);b.i(0);b.f(0);b.f(2);b.f(0);final clip=ClipData.parse(b.data.toBytes(),'con_claves.ani');expect(clip.pose(0).first.storage[13],2);});
 test('el anclaje vacío no se coloca en la raíz del personaje',(){expect(Attachment(0,v.Vector3.zero(),v.Quaternion.identity()).defined,isFalse);expect(Attachment(21,v.Vector3.zero(),v.Quaternion.identity()).defined,isTrue);});
 test('las familias eligen ataques propios, no el primer ANI del catálogo',(){expect(attackMotions(1),[35,36,37,38]);expect(attackMotions(5),[42,43,44,45]);expect(attackMotions(13),[31]);expect(attackMotions(12),[60,61]);expect(damageMotion(5),46);expect(motionIndex('humf_001_walk.ani'),1);});
}
''')
print('Fuentes actualizadas. La publicación queda condicionada al análisis y a las pruebas.')
