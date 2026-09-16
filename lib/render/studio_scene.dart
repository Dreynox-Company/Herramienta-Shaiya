import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:three_js/three_js.dart' as t;
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../core/formats.dart';
import '../core/textures.dart';
import '../core/combat.dart';
import '../data/library.dart';
import '../data/catalog.dart';

class RenderPart {
  final MeshData data;
  final t.Mesh mesh;
  final t.Float32BufferAttribute position;
  final t.Texture texture;
  RenderPart(this.data,this.mesh,this.position,this.texture);
  void skin(List<v.Matrix4> world) {
    if(data.inverses.isEmpty)return;
    final palette=List.generate(math.min(world.length,data.inverses.length),(i)=>(world[i]*data.inverses[i]).storage);
    for(var i=0;i<data.vertices;i++) {
      final x=data.positions[i*3],y=data.positions[i*3+1],z=data.positions[i*3+2];var px=0.0,py=0.0,pz=0.0;
      for(var k=0;k<4;k++) {
        final w=data.weights[i*4+k];if(w<=1e-7)continue;final j=data.joints[i*4+k];if(j>=palette.length)continue;final m=palette[j];
        px+=w*(m[0]*x+m[4]*y+m[8]*z+m[12]);py+=w*(m[1]*x+m[5]*y+m[9]*z+m[13]);pz+=w*(m[2]*x+m[6]*y+m[10]*z+m[14]);
      }
      position.setXYZ(i,px,py,pz);
    }
    position.needsUpdate=true;
  }
  void dispose(){mesh.removeFromParent();mesh.geometry?.dispose();mesh.material?.dispose();texture.dispose();}
}
class Actor {
  final t.Group root=t.Group();
  final List<RenderPart> parts=[];
  ClipData? clip;
  double time=0,speed=1;
  bool playing=true,loop=true;
  List<v.Matrix4> world=[];
  final Map<String,ClipData> clips={};
  void pose(){if(clip==null)return;world=clip!.pose(time,loop:loop);for(final p in parts){p.skin(world);}}
  void tick(double dt){if(playing)time+=dt*speed;pose();}
  void play(ClipData c,{bool repeat=true}){clip=c;time=0;loop=repeat;playing=true;pose();}
  int get requiredBones=>parts.fold(0,(n,p)=>math.max(n,p.data.requiredBones));
  double get height=>parts.isEmpty?2:parts.map((p)=>p.data.maxY).reduce(math.max);
  void dispose(){root.removeFromParent();for(final p in parts){p.dispose();}parts.clear();}
}

/// Cada cambio se prepara fuera de la escena. Solo se publica la revisión
/// vigente y completa; las cargas tardías se destruyen en vez de mezclarse.
class StudioScene extends ChangeNotifier {
  final void Function(String) report;
  StudioScene(this.report);
  t.ThreeJS? view;
  Catalog? catalog;
  Actor? character,enemy,mount,wing;
  Appearance? appearance;
  CreatureRecord? enemyRecord,mountRecord,wingRecord;
  RenderPart? weapon;
  WeaponRecord? weaponRecord;
  Attachment? weaponAttachment;
  t.Group environment=t.Group();
  final List<RenderPart> environmentParts=[];
  WorldData? world;
  String? worldPath,effectPath;
  t.Sprite? hitSprite;
  t.Texture? effectTexture;
  double hitLife=0;
  final Combat combat=Combat();
  final AudioPlayer audio=AudioPlayer();
  bool sound=false,wireframe=false,ready=false,disposed=false,busy=false;
  int _appearanceRevision=0,_creatureRevision=0,_mountRevision=0,_wingRevision=0,_worldRevision=0,_weaponRevision=0,_clipRevision=0;
  double yaw=.25,pitch=.18,distance=5.2,targetY=1.05,panX=0,panZ=0;
  double riderHeight=1.0,riderForward=0,wingHeight=1.3,wingDepth=.25,wingSize=1;
  double originX=0,originZ=0,groundY=0;
  double walkX=0,walkZ=0,_frameAccumulator=0,_uiAccumulator=0;
  String status='Selecciona la carpeta DATA.';
  List<String> get animations=>appearance?.archetype.animations??[];
  Future<void> setup(t.ThreeJS three) async {
    view=three;three.scene=t.Scene();three.camera=t.PerspectiveCamera(45,three.width/three.height,.02,2500);
    three.scene.background=t.Color.fromHex32(0x11151e);three.scene.add(environment);
    final grid=t.GridHelper(30,30,0x41485c,0x242b3b);three.scene.add(grid);
    combat.onEvent=(actor,event){unawaited(_combatEvent(actor,event));};
    three.addAnimationEvent(tick);ready=true;updateCamera();notifyListeners();
  }
  void say(String value){status=value;report(value);if(!disposed)notifyListeners();}
  Future<RenderPart> makePart(MeshData data,String texturePath,{bool opaque=false}) async {
    final lib=catalog!.library,bytes=await lib.read(texturePath);
    final png=await compute(_decodeTexture,{'bytes':bytes,'path':texturePath,'opaque':opaque});
    final texture=await t.TextureLoader(flipY:false).fromBytes(png);
    if(texture==null)throw FormatException('El motor no pudo cargar $texturePath');
    texture.colorSpace=t.ColorSpace.srgb;texture.wrapS=t.RepeatWrapping;texture.wrapT=t.RepeatWrapping;
    final geometry=t.BufferGeometry();
    final positions=t.Float32BufferAttribute.fromList(data.positions.toList(),3);
    geometry.setAttributeFromString('position',positions);
    geometry.setAttributeFromString('normal',t.Float32BufferAttribute.fromList(data.normals.toList(),3));
    geometry.setAttributeFromString('uv',t.Float32BufferAttribute.fromList(data.uv.toList(),2));
    geometry.setIndex(data.indices.toList());
    final material=t.MeshBasicMaterial.fromMap({'map':texture,'color':0xffffff,'side':t.DoubleSide,'alphaTest':opaque?0.0:.35,'wireframe':wireframe,'toneMapped':false});
    final mesh=t.Mesh(geometry,material);mesh.frustumCulled=false;
    return RenderPart(data,mesh,positions,texture);
  }
  Future<RenderPart> skinned(String mesh,String texture,{int alpha=0}) async {
    final data=MeshData.skinned(await catalog!.library.read(mesh),mesh);return makePart(data,texture,opaque:alpha==1);
  }
  Future<ClipData> clip(String path)=>catalog!.library.read(path).then((b)=>ClipData.parse(b,path));
  bool compatible(Actor actor,ClipData clip)=>actor.requiredBones<=clip.bones.length;
  Future<ClipData?> firstCompatible(Actor actor,List<String> paths) async {
    final sorted=List<String>.from(paths)..sort((a,b){int rank(String x)=>x.contains('normal')?0:x.contains('_br')?1:x.contains('idle')?2:3;return rank(a).compareTo(rank(b));});
    for(final path in sorted) {
      try{final c=await clip(path);if(compatible(actor,c))return c;}catch(e){report(e.toString());}
    }
    return null;
  }
  Future<void> setAppearance(Appearance next) async {
    final revision=++_appearanceRevision;busy=true;notifyListeners();final staged=Actor();
    try {
      for(final p in next.effective) {
        final part=await skinned(p.meshPath,p.texturePath,alpha:p.raw.alpha);staged.parts.add(part);staged.root.add(part.mesh);
        if(disposed||revision!=_appearanceRevision){staged.dispose();return;}
      }
      final c=await firstCompatible(staged,next.archetype.animations);if(c!=null)staged.play(c);
      if(disposed||revision!=_appearanceRevision){staged.dispose();return;}
      staged.root.scale.z=-1;character?.dispose();character=staged;appearance=next;view!.scene.add(staged.root);
      weapon?.dispose();weapon=null;weaponRecord=null;weaponAttachment=null;++_weaponRevision;
      combat.reset();updateAttachments();updateCamera();
      say('Apariencia aplicada · ${staged.parts.fold(0,(n,p)=>n+p.data.triangles)} triángulos${c==null?' · sin animación compatible':''}.');
    }catch(e){staged.dispose();say('Se conserva la apariencia anterior. $e');rethrow;}
    finally{if(revision==_appearanceRevision){busy=false;if(!disposed)notifyListeners();}}
  }
  Future<void> selectAnimation(String path) async {
    final a=character;if(a==null)return;final revision=++_clipRevision,c=await clip(path);
    if(disposed||revision!=_clipRevision||a!=character)return;
    if(!compatible(a,c))throw FormatException('Animación incompatible: necesita ${a.requiredBones} huesos y contiene ${c.bones.length}.');
    a.play(c);say('${animationLabel(path)} · ${c.duration.toStringAsFixed(2)} s');
  }
  Future<Actor> loadCreature(CreatureRecord c) async {
    final lib=catalog!.library,root=directoryName(c.source),a=Actor();
    try {
      for(final p in c.parts.where((p)=>!p.isNull)) {
        final m=lib.resolve(p.mesh,['$root/3dc',root]),tex=lib.resolve(p.texture,['$root/dds',root]);
        if(m==null||tex==null)throw FormatException('Falta una pieza de ${c.name}: ${m==null?p.mesh:p.texture}');
        final part=await skinned(m,tex);a.parts.add(part);a.root.add(part.mesh);
      }
      for(final entry in c.animations.entries) {
        final p=lib.resolve(entry.value,['$root/ani',root]);if(p==null)continue;
        try{final animation=await clip(p);if(compatible(a,animation))a.clips[entry.key]=animation;}catch(e){report(e.toString());}
      }
      final idle=a.clips['Respirar']??a.clips['Reposo']??(a.clips.isEmpty?null:a.clips.values.first);
      if(idle!=null)a.play(idle);a.root.scale.z=-1;return a;
    }catch(_){a.dispose();rethrow;}
  }
  Future<void> selectCreature(CreatureRecord? c,String kind) async {
    final revision=kind=='enemy'?++_creatureRevision:kind=='mount'?++_mountRevision:++_wingRevision;
    final staged=c==null?null:await loadCreature(c);
    final current=kind=='enemy'?_creatureRevision:kind=='mount'?_mountRevision:_wingRevision;
    if(disposed||revision!=current){staged?.dispose();return;}
    if(kind=='enemy'){enemy?.dispose();enemy=staged;enemyRecord=c;combat.reset();if(staged!=null){staged.root.position.x=1.8;staged.root.rotation.y=-math.pi/2;}}
    else if(kind=='mount'){mount?.dispose();mount=staged;mountRecord=c;if(staged!=null){riderHeight=(staged.height*.58).clamp(.2,5.0);await riderPose();}}
    else{wing?.dispose();wing=staged;wingRecord=c;}
    if(staged!=null)view!.scene.add(staged.root);
    updateAttachments();distance=mount!=null?math.max(7,mount!.height*2.5):5.2;updateCamera();say(c==null?'Elemento retirado.':'${catalog!.creatureLabel(c)} cargado.');
  }
  Future<void> riderPose() async {
    final a=character;if(a==null)return;
    final choices=animations.where((p)=>p.contains('veh')||p.contains('ride')||p.contains('sit')).toList();
    final c=await firstCompatible(a,choices);if(c!=null&&a==character)a.play(c);
  }
  Future<void> equip(WeaponRecord? w) async {
    final a=character;if(a==null)return;final rev=++_weaponRevision;
    if(w==null){weapon?.dispose();weapon=null;weaponRecord=null;return;}
    final lib=catalog!.library,root=directoryName(w.source),m=lib.resolve(w.mesh,['$root/3do',root]),tex=lib.resolve(w.texture,['$root/dds',root]);
    if(m==null||tex==null)throw FormatException('Faltan recursos del arma ${w.id}.');
    final r=Bin(await lib.read(m),m);r.str();final data=MeshData.rigid(r);r.end();
    final part=await makePart(data,tex,opaque:w.alpha==1);
    if(disposed||rev!=_weaponRevision||character!=a){part.dispose();return;}
    final code=archetypeCodes.indexOf(appearance!.archetype.id);
    Attachment? attachment;
    if(code>=0&&code<w.transforms.length)attachment=w.transforms[code][0];
    if(attachment==null||attachment.bone<0||attachment.bone>=a.world.length){part.dispose();throw const FormatException('Esta arma no define un anclaje válido para el arquetipo actual.');}
    weapon?.dispose();weapon=part;weaponRecord=w;weaponAttachment=attachment;a.root.add(part.mesh);part.mesh.matrixAutoUpdate=false;updateAttachments();say('Arma equipada con el anclaje IT2 original.');
  }
  void updateAttachments() {
    final a=character;if(a==null)return;
    final x=a.root.position.x,z=a.root.position.z;
    a.root.position.y=groundY+(mount==null?0:riderHeight);
    if(weapon!=null&&weaponAttachment!=null&&weaponAttachment!.bone<a.world.length){weapon!.mesh.matrix.copyFromArray((a.world[weaponAttachment!.bone]*weaponAttachment!.matrix).storage);weapon!.mesh.matrixWorldNeedsUpdate=true;}
    if(mount!=null){mount!.root.position.setValues(x,groundY,z+riderForward);mount!.root.rotation.y=a.root.rotation.y;}
    if(wing!=null){wing!.root.position.setValues(x,groundY+wingHeight+(mount==null?0:riderHeight),z+wingDepth);wing!.root.scale.setValues(wingSize,wingSize,-wingSize);wing!.root.rotation.y=a.root.rotation.y;}
  }
  Future<void> previewActorAnimation(String target,String name) async {final a=target=='enemy'?enemy:target=='mount'?mount:wing;final c=a?.clips[name];if(a!=null&&c!=null)a.play(c);notifyListeners();}
  Future<void> playSound(String path) async {
    if(!sound||catalog==null)return;
    try {
      final bytes=await catalog!.library.read(path,limit:32*1024*1024),dir=await getTemporaryDirectory();
      final f=File('${dir.path}/shaiya_${path.hashCode.toUnsigned(32)}_${baseName(path)}');
      if(!await f.exists())await f.writeAsBytes(bytes,flush:true);
      await audio.play(DeviceFileSource(f.path));
    }catch(e){report('Audio: $e');}
  }
  Future<void> setEffect(String path) async {
    final lib=catalog!.library;final png=await compute(_decodeTexture,{'bytes':await lib.read(path),'path':path,'opaque':false});
    final texture=await t.TextureLoader(flipY:false).fromBytes(png);if(texture==null)return;
    hitSprite?.removeFromParent();hitSprite?.material?.dispose();effectTexture?.dispose();effectTexture=texture;
    hitSprite=t.Sprite(t.SpriteMaterial.fromMap({'map':texture,'transparent':true,'depthWrite':false,'blending':t.AdditiveBlending,'color':0xffffff}));
    hitSprite!.visible=false;view!.scene.add(hitSprite!);effectPath=path;say('Textura de efecto seleccionada. La secuencia del laboratorio es una simulación.');
  }
  Future<void> _combatEvent(String who,String event) async {
    final a=who=='enemy'?enemy:character;if(a==null)return;
    if(who=='enemy') {
      final key=event=='attack'?'Ataque 1':event=='death'?'Caída':'Daño';final c=a.clips[key];if(c!=null)a.play(c,repeat:false);
      final raw=enemyRecord?.sounds[key]??'';final s=catalog?.library.resolve(raw,['sound/monster','sound'],uniqueFallback:true);if(s!=null)unawaited(playSound(s));
    }else {
      final tokens=event=='attack'?['attack','_att']:event=='death'?['die','dead']:['damage','_dam'];
      final candidates=animations.where((p)=>tokens.any(p.contains)).toList();
      if(candidates.isNotEmpty){final c=await firstCompatible(a,candidates);if(c!=null&&a==character)a.play(c,repeat:false);}
    }
    if(event=='hit'&&hitSprite!=null){hitLife=.45;hitSprite!.visible=true;hitSprite!.position.setValues(a.root.position.x,a.root.position.y+1,-.1+a.root.position.z);}
  }
  Future<void> attack() async {
    if(character==null||enemy==null)throw const FormatException('Carga un personaje y una criatura antes de combatir.');
    if(mount!=null)throw const FormatException('Desmonta antes de iniciar la prueba de combate.');
    combat.attack(enemyDistance);notifyListeners();
  }
  double get enemyDistance {if(enemy==null||character==null)return double.infinity;final dx=enemy!.root.position.x-character!.root.position.x,dz=enemy!.root.position.z-character!.root.position.z;return math.sqrt(dx*dx+dz*dz);}
  void resetCombat(){combat.reset();for(final a in [character,enemy]){if(a==null)continue;final c=a.clips['Respirar']??a.clips['Reposo']??a.clip;if(c!=null)a.play(c);}notifyListeners();}
  void setWireframe(bool value){wireframe=value;for(final a in [character,enemy,mount,wing]){for(final p in a?.parts??<RenderPart>[]){p.mesh.material?.wireframe=value;}}weapon?.mesh.material?.wireframe=value;notifyListeners();}
  void tick(double dt) {
    if(disposed)return;_frameAccumulator+=dt;_uiAccumulator+=dt;if(_frameAccumulator<1/30)return;final delta=_frameAccumulator.clamp(0.0,.1);_frameAccumulator=0;
    for(final a in [character,enemy,mount,wing]){a?.tick(delta);}
    if(character!=null&&(walkX!=0||walkZ!=0)){
      final x=character!.root.position.x+walkX*delta*2,z=character!.root.position.z+walkZ*delta*2;
      if(world==null||(x.abs()<55&&z.abs()<55)){character!.root.position.x=x;character!.root.position.z=z;if(world!=null)groundY=world!.heightAt(originX+x,originZ-z,scale:.02,offset:-200);}
      character!.root.rotation.y=math.atan2(walkX,walkZ);
    }
    updateAttachments();combat.step(delta,enemyDistance);
    if(hitLife>0&&hitSprite!=null){hitLife-=delta;hitSprite!.scale.setValues(1.5-hitLife,1.5-hitLife,1);hitSprite!.visible=hitLife>0;}
    updateCamera();if(_uiAccumulator>.2){_uiAccumulator=0;notifyListeners();}
  }
  void orbit(double dx,double dy){yaw-=dx*.006;pitch=(pitch+dy*.006).clamp(-1.2,1.2);updateCamera();}
  void zoom(double amount){distance=(distance*amount).clamp(.4,250);updateCamera();}
  void updateCamera(){if(!ready||view==null)return;final a=character;final x=(a?.root.position.x??0)+panX,z=(a?.root.position.z??0)+panZ,y=groundY+targetY+(mount==null?0:riderHeight*.6);view!.camera.position.setValues(x+math.sin(yaw)*math.cos(pitch)*distance,y+math.sin(pitch)*distance,z+math.cos(yaw)*math.cos(pitch)*distance);view!.camera.lookAt(t.Vector3(x,y,z));}
  Future<void> setWorld(String? path,{double? x,double? z}) async {
    final rev=++_worldRevision;
    if(path==null){for(final p in environmentParts){p.dispose();}environmentParts.clear();environment.removeFromParent();environment=t.Group();view!.scene.add(environment);world=null;worldPath=null;groundY=0;originX=originZ=0;updateCamera();notifyListeners();return;}
    final lib=catalog!.library,w=WorldData.parse(await lib.read(path),path);
    if(w.size==0)throw const FormatException('Este WLD es una mazmorra DG; su geometría aún no se interpreta. Selecciona un mapa exterior FLD.');
    final ox=(x??w.size/2).clamp(64.0,w.size-64.0),oz=(z??w.size/2).clamp(64.0,w.size-64.0);
    final stage=t.Group(),parts=<RenderPart>[];
    try {
      final grouped=<int,List<double>>{};final uv=<int,List<double>>{};
      final width=w.size~/2+1;
      for(var dz=-64;dz<64;dz+=2){for(var dx=-64;dx<64;dx+=2){final xx=ox+dx,zz=oz+dz;final type=w.types[(zz~/2)*width+xx~/2];final layer=type<w.layers.length?type:0;
        final verts=grouped.putIfAbsent(layer,()=>[]),tex=uv.putIfAbsent(layer,()=>[]);final tiling=w.layers.isEmpty?4.0:math.max(.1,w.layers[layer].tile.abs());
        for(final point in [[0,0],[2,0],[0,2],[2,0],[2,2],[0,2]]){final px=xx+point[0],pz=zz+point[1];verts.addAll([px-ox,w.heightAt(px,pz,scale:.02,offset:-200),-(pz-oz)]);tex.addAll([px/tiling,pz/tiling]);}
      }}
      for(final entry in grouped.entries){if(w.layers.isEmpty)break;final layer=w.layers[entry.key];final tex=lib.resolve(layer.texture,['terrain','terrain/texture','terrain/dds'],uniqueFallback:true);if(tex==null){report('Textura de terreno ausente: ${layer.texture}');continue;}final n=entry.value.length~/3,no=Float32List(n*3);for(var i=0;i<n;i++){no[i*3+1]=1;}final data=MeshData(Float32List.fromList(entry.value),no,Float32List.fromList(uv[entry.key]!),Uint16List.fromList(List.generate(n,(i)=>i)),Uint8List(0),Float32List(0),[],path);final part=await makePart(data,tex,opaque:true);parts.add(part);stage.add(part.mesh);}
      var loaded=0;
      final nearby=w.objects.where((o)=>(o.position.x-ox).abs()<78&&(o.position.z-oz).abs()<78&&['Building','Shape','Tree'].contains(o.category)).toList()..sort((a,b)=>((a.position.x-ox).abs()+(a.position.z-oz).abs()).compareTo((b.position.x-ox).abs()+(b.position.z-oz).abs()));
      for(final obj in nearby.take(80)){
        final model=lib.resolve(obj.asset,['entity/${obj.category}']);if(model==null||!model.endsWith('.smod'))continue;
        try{final objects=readSmod(await lib.read(model),model);final group=t.Group();
          for(final piece in objects){final tex=lib.resolve(piece.texture,['entity/${obj.category}','entity/${obj.category}/texture','entity/${obj.category}/textures'],uniqueFallback:true);if(tex==null)continue;final p=await makePart(piece.mesh,tex);parts.add(p);group.add(p.mesh);}
          group.scale.z=-1;group.position.setValues(obj.position.x-ox,obj.position.y,-(obj.position.z-oz));group.rotation.y=-math.atan2(obj.forward.x,obj.forward.z);stage.add(group);loaded++;
        }catch(e){report('Objeto $model: $e');}
        if(disposed||rev!=_worldRevision){for(final p in parts){p.dispose();}return;}
      }
      if(disposed||rev!=_worldRevision){for(final p in parts){p.dispose();}return;}
      for(final p in environmentParts){p.dispose();}environmentParts..clear()..addAll(parts);environment.removeFromParent();environment=stage;view!.scene.add(stage);world=w;worldPath=path;originX=ox;originZ=oz;groundY=w.heightAt(ox,oz,scale:.02,offset:-200);character?.root.position.setValues(0,groundY,0);enemy?.root.position.setValues(1.8,groundY,0);distance=8;updateCamera();say('Sector de 128 × 128 m · $loaded objetos · altura original. Sin colisión con edificios.');
    }catch(_){for(final p in parts){p.dispose();}rethrow;}
  }
  @override void dispose(){disposed=true;++_appearanceRevision;++_creatureRevision;++_mountRevision;++_wingRevision;++_worldRevision;++_weaponRevision;for(final a in [character,enemy,mount,wing]){a?.dispose();}weapon?.dispose();for(final p in environmentParts){p.dispose();}effectTexture?.dispose();audio.dispose();super.dispose();}
}
Uint8List _decodeTexture(Map<String,Object> args)=>Pixels.decode(args['bytes'] as Uint8List,args['path'] as String).png(opaque:args['opaque'] as bool);
