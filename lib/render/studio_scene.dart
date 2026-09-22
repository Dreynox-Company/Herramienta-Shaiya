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
import '../core/locomotion.dart';
import '../core/attachment_pose.dart';
import 'world_collision.dart';
import '../data/library.dart';
import '../data/catalog.dart';

class RenderPart {
  final MeshData data;final t.Mesh mesh;
  final t.Float32BufferAttribute position,normal,uvAttribute;
  final t.Texture texture;
  RenderPart(this.data,this.mesh,this.position,this.normal,this.uvAttribute,this.texture);
  void skin(List<v.Matrix4> world){
    if(data.inverses.isEmpty)return;
    final palette=List.generate(math.min(world.length,data.inverses.length),(i)=>(world[i]*data.inverses[i]).storage);
    for(var i=0;i<data.vertices;i++){
      final x=data.positions[i*3],y=data.positions[i*3+1],z=data.positions[i*3+2];var px=0.0,py=0.0,pz=0.0;
      for(var k=0;k<4;k++){final w=data.weights[i*4+k];if(w<=1e-7)continue;final j=data.joints[i*4+k];if(j>=palette.length)continue;final m=palette[j];px+=w*(m[0]*x+m[4]*y+m[8]*z+m[12]);py+=w*(m[1]*x+m[5]*y+m[9]*z+m[13]);pz+=w*(m[2]*x+m[6]*y+m[10]*z+m[14]);}
      position.setXYZ(i,px,py,pz);
    }
    position.needsUpdate=true;
  }
  void applyVaniFrame(VaniMeshData source,int frame){
    if(source.frameCount==0)return;
    final i=frame%source.frameCount,p=source.positions[i],n=source.normals[i],uv=source.uv[i];
    if(p.length!=data.positions.length||n.length!=data.normals.length||uv.length!=data.uv.length)return;
    for(var vertex=0;vertex<data.vertices;vertex++){
      position.setXYZ(vertex,p[vertex*3],p[vertex*3+1],p[vertex*3+2]);
      normal.setXYZ(vertex,n[vertex*3],n[vertex*3+1],n[vertex*3+2]);
      uvAttribute.setXY(vertex,uv[vertex*2],uv[vertex*2+1]);
    }
    position.needsUpdate=true;normal.needsUpdate=true;uvAttribute.needsUpdate=true;
  }
  void dispose(){mesh.removeFromParent();mesh.geometry?.dispose();mesh.material?.dispose();texture.dispose();}
}
class VaniBinding {
  final RenderPart part;
  final VaniMeshData mesh;
  const VaniBinding(this.part,this.mesh);
}
class VaniActor {
  final t.Group root;
  final List<VaniBinding> bindings;
  final int frameCount;
  double time=0;
  int frame=-1;
  VaniActor(this.root,this.bindings,this.frameCount);
  void tick(double dt){
    if(frameCount<=1)return;
    time+=dt;
    final next=(time*15).floor()%frameCount;
    if(next==frame)return;
    frame=next;
    for(final binding in bindings)binding.part.applyVaniFrame(binding.mesh,next);
  }
  void dispose(){root.removeFromParent();for(final binding in bindings)binding.part.dispose();}
}
class WaterSurface {
  final t.Mesh mesh;
  final List<t.Texture> frames;
  final double framesPerSecond;
  double time=0;
  int frame=0;
  WaterSurface(this.mesh,this.frames,{this.framesPerSecond=15});
  void tick(double dt){
    if(frames.length<=1||framesPerSecond<=0)return;
    time+=dt;
    final next=(time*framesPerSecond).floor()%frames.length;
    if(next==frame)return;
    frame=next;
    final material=mesh.material;
    if(material!=null){
      material.map=frames[next];
      material.needsUpdate=true;
    }
  }
  void dispose(){
    mesh.removeFromParent();
    mesh.geometry?.dispose();
    mesh.material?.dispose();
    for(final texture in frames){texture.dispose();}
  }
}
class ManiActor {
  final t.Group root,pivot;
  final List<RenderPart> parts;
  final ManiData animation;
  const ManiActor(this.root,this.pivot,this.parts,this.animation);
  void tick(double dt){
    if(animation.enableRotation==0||!animation.animationSpeed.isFinite)return;
    final delta=animation.animationSpeed*dt;
    if(delta.abs()<1e-9)return;
    pivot.rotation.x+=animation.rotation.x*delta;
    pivot.rotation.y+=animation.rotation.y*delta;
    pivot.rotation.z+=animation.rotation.z*delta;
  }
  void dispose(){root.removeFromParent();for(final part in parts){part.dispose();}}
}
class Actor {
  final t.Group root=t.Group();final List<RenderPart> parts=[];
  ClipData? clip,idle,normal,walk,run,riderIdle,riderMoving;
  int? wingBone;v.Matrix4? wingReference;
  double time=0,speed=1;bool playing=true,loop=true;
  List<v.Matrix4> world=[];final Map<String,ClipData> clips={};
  void pose(){if(clip==null)return;world=clip!.pose(time,loop:loop);for(final p in parts){p.skin(world);}}
  void tick(double dt){if(playing)time+=dt*speed;if(!loop&&clip!=null&&time>clip!.duration&&idle!=null)play(idle!);pose();}
  void play(ClipData c,{bool repeat=true}){clip=c;time=0;loop=repeat;playing=true;pose();}
  int get requiredBones=>parts.fold(0,(n,p)=>math.max(n,p.data.requiredBones));
  double get height=>parts.isEmpty?2:parts.map((p)=>p.data.maxY).reduce(math.max);
  void dispose(){root.removeFromParent();for(final p in parts){p.dispose();}parts.clear();}
}

class RuntimeNpcSpawn {
  final int type,typeId,angle,globalId;
  final double x,y,z;
  const RuntimeNpcSpawn(this.type,this.typeId,this.x,this.y,this.z,this.angle,[this.globalId=0]);
}
class RuntimeMobSpawn {
  final int mobId,globalId;
  final double x,z;
  const RuntimeMobSpawn(this.mobId,this.x,this.z,[this.globalId=0]);
}

class GameActorLabel {
  final Actor actor;
  final String text;
  final bool quest,mob,player;
  final int globalId;
  const GameActorLabel(this.actor,this.text,{this.quest=false,this.mob=false,this.player=false,this.globalId=0});
}

class ProjectedGameLabel {
  final double x,y;
  final String text;
  final bool quest,mob,player;
  final int globalId;
  const ProjectedGameLabel(this.x,this.y,this.text,this.quest,this.mob,this.player,this.globalId);
}
class StudioScene extends ChangeNotifier {
  final void Function(String) report;StudioScene(this.report);
  t.ThreeJS? view;Catalog? catalog;
  t.LineSegments? grid;
  bool gridVisible=true;
  Actor? character,enemy,mount,wing;final List<Actor> gameActors=[];final List<GameActorLabel> gameLabels=[];
  final Map<int,Actor> networkNpcActors={},networkMobActors={},networkPlayerActors={},networkPlayerMountActors={};
  final Map<int,List<String>> networkPlayerAnimations={};
  final Map<int,double> networkPlayerGroundY={},networkPlayerRiderHeight={};
  Appearance? appearance;
  CreatureRecord? enemyRecord,mountRecord,wingRecord;
  RenderPart? weapon,secondWeapon,sky,primaryCloud,secondaryCloud;t.Texture? backdropTexture;WeaponRecord? weaponRecord;Attachment? weaponAttachment,secondAttachment;
  List<ClipData> attackClips=[];int attackCounter=0;
  bool running=false,touchRun=false;
  final movementTransitions=LocomotionTransitions();final Set<String> _missingMovementWarnings={};
  t.Group environment=t.Group();final List<RenderPart> environmentParts=[];final List<VaniActor> animatedWorldActors=[];final List<ManiActor> maniWorldActors=[];
  WorldData? world;DgData? dungeon;WtrData? waterAnimation;
  WaterSurface? waterSurface;
  String? worldPath,effectPath,skyPath,primaryCloudPath,secondaryCloudPath,waterPath;
  final List<String> waterTexturePaths=[];
  final List<String> loadedWorldAssets=[];
  final List<String> missingWorldAssets=[];
  final WorldCollisionIndex worldCollision=WorldCollisionIndex();
  final Map<String,({double height,double forward})> _seats={};
  String lastImpact='';t.Sprite? hitSprite;t.Texture? effectTexture;double hitLife=0;
  final Combat combat=Combat();
  AudioPlayer? _audio,_musicAudio,_ambientAudio,_footstepAudio;
  AudioPlayer get audio=>_audio??=AudioPlayer();
  AudioPlayer get musicAudio=>_musicAudio??=AudioPlayer();
  AudioPlayer get ambientAudio=>_ambientAudio??=AudioPlayer();
  AudioPlayer get footstepAudio=>_footstepAudio??=AudioPlayer();
  final Map<String,String> _materializedAudio=<String,String>{};
  String? _worldMusicPath,_worldAmbientPath;
  bool _worldAudioSyncing=false;
  bool sound=false,wireframe=false,ready=false,disposed=false,busy=false;
  int _appearanceRevision=0,_creatureRevision=0,_mountRevision=0,_wingRevision=0,_worldRevision=0,_weaponRevision=0,_clipRevision=0,_effectRevision=0,_skyRevision=0;
  double yaw=.25,pitch=.18,distance=5.2,targetY=1.05,panX=0,panZ=0;
  double riderHeight=1.0,riderForward=0,wingHeight=1.3,wingDepth=.25,wingSize=1;
  double originX=0,originZ=0,groundY=0,walkX=0,walkZ=0,_frameAccumulator=0,_uiAccumulator=0,_worldAudioAccumulator=0,_footstepAccumulator=0;
  String status='Selecciona la carpeta DATA.';
  List<String> get animations=>appearance?.archetype.animations??[];
  Future<void> setup(t.ThreeJS three) async {
    view=three;three.scene=t.Scene();three.camera=t.PerspectiveCamera(45,three.width/three.height,.02,2500);three.scene.background=t.Color.fromHex32(0x11151e);three.scene.add(environment);
    final ambient=t.AmbientLight(0xb8b8b8,1.0);
    three.scene.add(ambient);
    final sun=t.DirectionalLight(0xfff4e6,.82);
    sun.position.setValues(-7,14,9);
    three.scene.add(sun);
    final points=<double>[];for(var i=-15;i<=15;i++){points.addAll([i.toDouble(),-.02,-15,i.toDouble(),-.02,15,-15,-.02,i.toDouble(),15,-.02,i.toDouble()]);}
    final gridGeometry=t.BufferGeometry()..setAttributeFromString('position',t.Float32BufferAttribute.fromList(points,3));grid=t.LineSegments(gridGeometry,t.LineBasicMaterial.fromMap({'color':0x323b4d}));grid!.visible=gridVisible;three.scene.add(grid!);
    combat.onEvent=(actor,event){unawaited(_combatEvent(actor,event));};three.addAnimationEvent(tick);ready=true;updateCamera();notifyListeners();
  }
  int _fogColor(WorldData data){
    int channel(double value){
      final scaled=value<=1.0001?value*255:value;
      return scaled.round().clamp(0,255);
    }
    final r=channel(data.fogColor.x),g=channel(data.fogColor.y),b=channel(data.fogColor.z);
    return (r<<16)|(g<<8)|b;
  }
  void _applyWorldFog(WorldData? data){
    final scene=view?.scene;
    if(scene==null)return;
    if(data==null||!data.fogStart.isFinite||!data.fogEnd.isFinite||
      data.fogEnd<=data.fogStart||data.fogEnd<=0){
      scene.fog=null;
      return;
    }
    final near=math.max(.1,data.fogStart),far=math.max(near+.1,data.fogEnd);
    scene.fog=t.Fog(_fogColor(data),near,far);
  }

  void say(String value){status=value;report(value);if(!disposed)notifyListeners();}
  void setGridVisible(bool value){gridVisible=value;if(grid!=null)grid!.visible=value;notifyListeners();}
  Future<RenderPart> makePart(MeshData data,String texturePath,{bool opaque=false}) async {
    final bytes=await catalog!.library.read(texturePath);final png=await compute(_decodeTexture,{'bytes':bytes,'path':texturePath,'opaque':opaque});
    // Shaiya meshes were authored for Direct3D UVs (V=0 at the top).  Do not
    // apply Three/OpenGL's image flip here; doing so maps skin/face regions to
    // the wrong polygons.  2D scene backdrops use their own loading path.
    final texture=await t.TextureLoader(flipY:false).fromBytes(png);if(texture==null)throw FormatException('El motor no pudo cargar $texturePath');
    texture.colorSpace=t.SRGBColorSpace;texture.wrapS=t.RepeatWrapping;texture.wrapT=t.RepeatWrapping;
    final geometry=t.BufferGeometry(),positions=t.Float32BufferAttribute.fromList(data.positions.toList(),3),normals=t.Float32BufferAttribute.fromList(data.normals.toList(),3),uv=t.Float32BufferAttribute.fromList(data.uv.toList(),2);
    geometry.setAttributeFromString('position',positions);geometry.setAttributeFromString('normal',normals);geometry.setAttributeFromString('uv',uv);geometry.setIndex(data.indices.toList());
    final material=t.MeshLambertMaterial.fromMap({'map':texture,'color':0xffffff,'side':t.DoubleSide,'alphaTest':opaque?0.0:.35,'wireframe':wireframe,'toneMapped':false});final mesh=t.Mesh(geometry,material);mesh.frustumCulled=false;return RenderPart(data,mesh,positions,normals,uv,texture);
  }
  Future<RenderPart> _makeSkyLayer(
    MeshData data,
    String texturePath,{
    required double radius,
    required double opacity,
    required int renderOrder,
  }) async {
    final bytes=await catalog!.library.read(texturePath);
    final png=await compute(_decodeTexture,{'bytes':bytes,'path':texturePath,'opaque':opacity>=.999});
    final texture=await t.TextureLoader(flipY:false).fromBytes(png);
    if(texture==null)throw FormatException('El motor no pudo cargar $texturePath');
    texture.colorSpace=t.SRGBColorSpace;
    texture.wrapS=t.RepeatWrapping;texture.wrapT=t.RepeatWrapping;
    final geometry=t.BufferGeometry(),
      positions=t.Float32BufferAttribute.fromList(data.positions.toList(),3),
      normals=t.Float32BufferAttribute.fromList(data.normals.toList(),3),
      uv=t.Float32BufferAttribute.fromList(data.uv.toList(),2);
    geometry.setAttributeFromString('position',positions);
    geometry.setAttributeFromString('normal',normals);
    geometry.setAttributeFromString('uv',uv);
    geometry.setIndex(data.indices.toList());
    final material=t.MeshBasicMaterial.fromMap({
      'map':texture,'color':0xffffff,'side':t.DoubleSide,
      'transparent':opacity<.999,'opacity':opacity,
      'alphaTest':opacity<.999 ? .02 : 0.0,
      'depthWrite':false,'depthTest':false,'toneMapped':false,
    });
    final mesh=t.Mesh(geometry,material)..frustumCulled=false;
    var sourceRadius=0.0;
    for(final coordinate in data.positions){sourceRadius=math.max(sourceRadius,coordinate.abs());}
    if(sourceRadius<1e-6){
      texture.dispose();geometry.dispose();material.dispose();
      throw const FormatException('Cúpula de cielo vacía.');
    }
    mesh.scale.setValues(radius/sourceRadius,radius/sourceRadius,-radius/sourceRadius);
    mesh.renderOrder=renderOrder;
    return RenderPart(data,mesh,positions,normals,uv,texture);
  }
  Future<RenderPart> skinned(String mesh,String texture,{int alpha=0}) async {final data=MeshData.skinned(await catalog!.library.read(mesh),mesh);for(final repair in data.repairs){report('$mesh · $repair');}return makePart(data,texture,opaque:alpha==1);}
  Future<ClipData> clip(String path)=>catalog!.library.read(path).then((b)=>ClipData.parse(b,path));
  bool compatible(Actor actor,ClipData clip)=>actor.requiredBones<=clip.bones.length;
  Future<ClipData?> firstCompatible(Actor actor,List<String> paths) async {
    // Priority is supplied by the caller. Never rank by a substring of normal.
    for(final path in paths){try{final c=actor.clips[path]??await clip(path);if(compatible(actor,c)){actor.clips[path]=c;return c;}}catch(e){report(e.toString());}}
    return null;
  }
  Future<void> setAppearance(Appearance next) async {
    final revision=++_appearanceRevision;busy=true;notifyListeners();final staged=Actor();
    try{
      for(final p in next.effective){final part=await skinned(p.meshPath,p.texturePath,alpha:p.raw.alpha);staged.parts.add(part);staged.root.add(part.mesh);if(disposed||revision!=_appearanceRevision){staged.dispose();return;}}
      final c=await firstCompatible(staged,groundMotionCandidates(next.archetype.animations,GroundMotion.idle));
      if(c==null)throw FormatException('No hay reposo terrestre compatible para ${next.archetype.id}. No se sustituye por natación.');
      staged.walk=await firstCompatible(staged,groundMotionCandidates(next.archetype.animations,GroundMotion.walk));staged.run=await firstCompatible(staged,groundMotionCandidates(next.archetype.animations,GroundMotion.run));
      staged.riderIdle=await firstCompatible(staged,next.archetype.animations.where((p)=>p.toLowerCase().endsWith('_021_veh_br.ani')).toList());staged.riderMoving=await firstCompatible(staged,next.archetype.animations.where((p)=>p.toLowerCase().endsWith('_020_veh_run.ani')).toList());
      staged.idle=c;staged.normal=c;staged.play(c);
      var score=double.infinity;
      for(var i=1;i<math.min(staged.world.length,12);i++){final m=staged.world[i].storage;final d=(m[13]-staged.height*.74).abs()+m[12].abs()*.7+m[14].abs()*.3;if(d<score&&staged.world[i].determinant().abs()>1e-12){score=d;staged.wingBone=i;staged.wingReference=v.Matrix4.inverted(staged.world[i]);}}
      if(mount!=null&&staged.riderIdle!=null)staged.play(staged.riderIdle!);
      if(disposed||revision!=_appearanceRevision){staged.dispose();return;}
      staged.root.scale.z=-1;final old=character;
      if(old!=null){staged.root.position.setValues(old.root.position.x,old.root.position.y,old.root.position.z);staged.root.rotation.y=old.root.rotation.y;}
      final keep=appearance?.archetype.id==next.archetype.id&&appearance?.archetype.race==next.archetype.race;
      if(keep){for(final part in [weapon,secondWeapon]){if(part!=null){part.mesh.removeFromParent();staged.root.add(part.mesh);}}}
      else{weapon?.dispose();secondWeapon?.dispose();weapon=null;secondWeapon=null;weaponRecord=null;weaponAttachment=null;secondAttachment=null;}
      ++_weaponRevision;++_clipRevision;movementTransitions.invalidate();_missingMovementWarnings.clear();attackClips.clear();character?.dispose();character=staged;appearance=next;view!.scene.add(staged.root);
      combat.reset();await prepareWeaponMotions();updateAttachments();updateCamera();say('Apariencia aplicada · ${staged.parts.fold(0,(n,p)=>n+p.data.triangles)} triángulos.');
    }catch(e){staged.dispose();say('Se conserva la apariencia anterior. $e');rethrow;}
    finally{if(revision==_appearanceRevision){busy=false;if(!disposed)notifyListeners();}}
  }
  Future<void> selectAnimation(String path) async {final a=character;if(a==null)return;final revision=++_clipRevision,c=a.clips[path]??await clip(path);if(disposed||revision!=_clipRevision||a!=character)return;if(!compatible(a,c))throw FormatException('Animación incompatible: necesita ${a.requiredBones} huesos y contiene ${c.bones.length}.');a.clips[path]=c;a.play(c);say('${animationLabel(path)} · ${c.duration.toStringAsFixed(2)} s');}
  Future<Actor> loadAppearanceActor(Appearance next) async {
    final staged=Actor();
    try{
      for(final p in next.effective){
        final part=await skinned(p.meshPath,p.texturePath,alpha:p.raw.alpha);
        staged.parts.add(part);staged.root.add(part.mesh);
      }
      final idle=await firstCompatible(staged,groundMotionCandidates(next.archetype.animations,GroundMotion.idle));
      if(idle==null)throw FormatException('No hay reposo compatible para jugador remoto ${next.archetype.id}.');
      staged.walk=await firstCompatible(staged,groundMotionCandidates(next.archetype.animations,GroundMotion.walk));
      staged.run=await firstCompatible(staged,groundMotionCandidates(next.archetype.animations,GroundMotion.run));
      staged.riderIdle=await firstCompatible(staged,next.archetype.animations.where((p)=>p.toLowerCase().endsWith('_021_veh_br.ani')).toList());
      staged.riderMoving=await firstCompatible(staged,next.archetype.animations.where((p)=>p.toLowerCase().endsWith('_020_veh_run.ani')).toList());
      staged.idle=idle;staged.normal=idle;staged.play(idle);
      staged.root.scale.z=-1;
      return staged;
    }catch(_){staged.dispose();rethrow;}
  }
  Future<Actor> loadCreature(CreatureRecord c) async {
    final lib=catalog!.library,root=directoryName(c.source),a=Actor();
    try{
      for(final p in c.parts.where((p)=>!p.isNull)){final m=lib.resolve(p.mesh,['$root/3dc',root]),tex=lib.resolve(p.texture,['$root/dds',root]);if(m==null||tex==null)throw FormatException('Falta una pieza de ${c.name}: ${m==null?p.mesh:p.texture}');final part=await skinned(m,tex);a.parts.add(part);a.root.add(part.mesh);}
      for(final entry in c.animations.entries){final p=lib.resolve(entry.value,['$root/ani',root]);if(p==null)continue;try{final animation=await clip(p);if(compatible(a,animation))a.clips[entry.key]=animation;}catch(e){report(e.toString());}}
      final idle=a.clips['Respirar']??a.clips['Reposo']??(a.clips.isEmpty?null:a.clips.values.first);if(idle!=null){a.idle=idle;a.normal=idle;a.play(idle);}a.root.scale.z=-1;return a;
    }catch(_){a.dispose();rethrow;}
  }
  Future<void> spawnGameNpcs({int count=8}) async {
    for(final a in gameActors){a.dispose();}
    gameActors.clear();networkNpcActors.clear();networkMobActors.clear();gameLabels.clear();
    final source=(catalog?.npcs.isNotEmpty??false)?catalog!.npcs:catalog?.creatures??const <CreatureRecord>[];
    if(source.isEmpty||view==null)return;
    final limit=math.min(count,source.length);
    for(var i=0;i<limit;i++){
      try{
        final a=await loadCreature(source[i]);
        final angle=(i/math.max(1,limit))*math.pi*2;
        final radius=6.0+(i%3)*2.2;
        final x=math.cos(angle)*radius,z=math.sin(angle)*radius;
        a.root.position.setValues(x,world==null?0:world!.heightAt(originX+x,originZ-z,scale:.02,offset:-200),z);
        a.root.rotation.y=-angle+math.pi/2;
        gameActors.add(a);view!.scene.add(a.root);
        final name=catalog!.creatureLabel(source[i]);
        gameLabels.add(GameActorLabel(a,name,mob:!source[i].source.startsWith('npc/')));
      }catch(e){report('NPC ${source[i].id}: $e');}
    }
    say('${gameActors.length} NPC/criaturas locales cargados.');
  }

  Future<void> spawnGameActorsFromNetwork({
    required List<RuntimeNpcSpawn> npcs,
    required List<RuntimeMobSpawn> mobs,
    Map<String,int>? npcModels,
    Map<int,int>? mobModels,
    Set<String>? questNpcKeys,
    String locale='spn',
    int npcLimit=60,
    int mobLimit=80,
  }) async {
    for(final a in gameActors){a.dispose();}
    gameActors.clear();gameLabels.clear();networkNpcActors.clear();networkMobActors.clear();networkPlayerActors.clear();networkPlayerMountActors.clear();networkPlayerAnimations.clear();networkPlayerGroundY.clear();networkPlayerRiderHeight.clear();
    if(view==null||catalog==null)return;

    final npcRecords={for(final n in catalog!.npcs)n.id:n};
    final sortedNpcs=[...npcs]..sort((a,b){
      final adx=a.x-originX,adz=a.z-originZ;
      final bdx=b.x-originX,bdz=b.z-originZ;
      return (adx*adx+adz*adz).compareTo(bdx*bdx+bdz*bdz);
    });
    var npcsLoaded=0;
    for(final p in sortedNpcs){
      if(npcsLoaded>=npcLimit)break;
      final x=p.x-originX,z=-(p.z-originZ);
      if(x.abs()>85||z.abs()>85)continue;
      final model=npcModels?[p.type.toString()+':'+p.typeId.toString()]??p.typeId;
      final record=npcRecords[model];
      if(record==null){report('LIVE NPC ${p.type}:${p.typeId}: modelo $model no existe en npc MON.');continue;}
      try{
        final a=await loadCreature(record);
        a.root.position.setValues(x,p.y,z);
        a.root.rotation.y=-p.angle*(math.pi*2/65536.0);
        gameActors.add(a);view!.scene.add(a.root);npcsLoaded++;
        if(p.globalId!=0)networkNpcActors[p.globalId]=a;
        final key='${p.type}:${p.typeId}';
        final localized=catalog!.questText(locale)?.npc(p.type,p.typeId);
        gameLabels.add(GameActorLabel(
          a,
          (localized?.name.isNotEmpty??false)?localized!.name:'NPC $key',
          quest:questNpcKeys?.contains(key)??false,
          globalId:p.globalId,
        ));
      }catch(e){report('LIVE NPC ${p.type}:${p.typeId}: $e');}
    }

    final mobRecords={for(final m in catalog!.creatures)m.id:m};
    final sortedMobs=[...mobs]..sort((a,b){
      final adx=a.x-originX,adz=a.z-originZ;
      final bdx=b.x-originX,bdz=b.z-originZ;
      return (adx*adx+adz*adz).compareTo(bdx*bdx+bdz*bdz);
    });
    var mobsLoaded=0;
    for(final p in sortedMobs){
      if(mobsLoaded>=mobLimit)break;
      final x=p.x-originX,z=-(p.z-originZ);
      if(x.abs()>90||z.abs()>90)continue;
      final model=mobModels?[p.mobId]??p.mobId;
      final record=mobRecords[model];
      if(record==null){report('LIVE mob ${p.mobId}: modelo $model no existe en monster.mon.');continue;}
      try{
        final a=await loadCreature(record);
        final y=world==null?groundY:world!.heightAt(originX+x,originZ-z,scale:.02,offset:-200);
        a.root.position.setValues(x,y,z);
        a.root.rotation.y=math.atan2(-x,-z);
        gameActors.add(a);view!.scene.add(a.root);mobsLoaded++;
        if(p.globalId!=0)networkMobActors[p.globalId]=a;
        gameLabels.add(GameActorLabel(a,catalog!.monsterName(p.mobId,locale),mob:true,globalId:p.globalId));
      }catch(e){report('LIVE mob ${p.mobId}: $e');}
    }
    say('$npcsLoaded NPC y $mobsLoaded criaturas renderizados desde paquetes ps0032.');
  }

  Future<void> addNetworkNpc(
    RuntimeNpcSpawn p,{Map<String,int>? npcModels,Set<String>? questNpcKeys,String locale='spn'}
  ) async {
    if(view==null||catalog==null)return;
    if(p.globalId!=0)removeNetworkActor(p.globalId,mob:false);
    final x=p.x-originX,z=-(p.z-originZ);
    if(x.abs()>100||z.abs()>100)return;
    final model=npcModels?[p.type.toString()+':'+p.typeId.toString()]??p.typeId;
    final record=catalog!.npcs.where((n)=>n.id==model).firstOrNull;
    if(record==null){report('LIVE NPC ${p.type}:${p.typeId}: modelo $model no existe en npc MON.');return;}
    try{
      final a=await loadCreature(record);
      a.root.position.setValues(x,p.y,z);
      a.root.rotation.y=-p.angle*(math.pi*2/65536.0);
      gameActors.add(a);view!.scene.add(a.root);
      if(p.globalId!=0)networkNpcActors[p.globalId]=a;
      final key='${p.type}:${p.typeId}',localized=catalog!.questText(locale)?.npc(p.type,p.typeId);
      gameLabels.add(GameActorLabel(
        a,(localized?.name.isNotEmpty??false)?localized!.name:'NPC $key',
        quest:questNpcKeys?.contains(key)??false,globalId:p.globalId,
      ));
      notifyListeners();
    }catch(e){report('LIVE NPC ${p.type}:${p.typeId}: $e');}
  }

  Future<void> addNetworkMob(
    RuntimeMobSpawn p,{Map<int,int>? mobModels,String locale='spn'}
  ) async {
    if(view==null||catalog==null)return;
    if(p.globalId!=0)removeNetworkActor(p.globalId,mob:true);
    final x=p.x-originX,z=-(p.z-originZ);
    if(x.abs()>105||z.abs()>105)return;
    final model=mobModels?[p.mobId]??p.mobId;
    final record=catalog!.creatures.where((m)=>m.id==model).firstOrNull;
    if(record==null){report('LIVE mob ${p.mobId}: modelo $model no existe en monster.mon.');return;}
    try{
      final a=await loadCreature(record);
      final y=world==null?groundY:world!.heightAt(p.x,p.z,scale:.02,offset:-200);
      a.root.position.setValues(x,y,z);
      a.root.rotation.y=math.atan2(-x,-z);
      gameActors.add(a);view!.scene.add(a.root);
      if(p.globalId!=0)networkMobActors[p.globalId]=a;
      gameLabels.add(GameActorLabel(a,catalog!.monsterName(p.mobId,locale),mob:true,globalId:p.globalId));
      notifyListeners();
    }catch(e){report('LIVE mob ${p.mobId}: $e');}
  }
  Future<void> addNetworkPlayer({
    required int characterId,required Appearance appearance,required String name,
    required double x,required double y,required double z,required int angle,
  }) async {
    if(view==null||catalog==null)return;
    removeNetworkPlayer(characterId);
    final lx=x-originX,lz=-(z-originZ);
    if(lx.abs()>110||lz.abs()>110)return;
    try{
      final a=await loadAppearanceActor(appearance);
      a.root.position.setValues(lx,y,lz);
      a.root.rotation.y=-angle*(math.pi*2/65536.0);
      networkPlayerGroundY[characterId]=y;
      gameActors.add(a);networkPlayerActors[characterId]=a;networkPlayerAnimations[characterId]=appearance.archetype.animations;view!.scene.add(a.root);
      gameLabels.add(GameActorLabel(a,name,player:true,globalId:characterId));
      notifyListeners();
    }catch(e){report('LIVE player $characterId: $e');}
  }

  void moveNetworkPlayer(int characterId,double worldX,double worldY,double worldZ,int angle,int motion){
    final a=networkPlayerActors[characterId];if(a==null)return;
    final nx=worldX-originX,nz=-(worldZ-originZ),vehicle=networkPlayerMountActors[characterId];
    networkPlayerGroundY[characterId]=worldY;
    final seat=networkPlayerRiderHeight[characterId]??0;
    a.root.position.setValues(nx,worldY+(vehicle==null?0:seat),nz);
    a.root.rotation.y=-angle*(math.pi*2/65536.0);
    if(vehicle!=null){
      vehicle.root.position.setValues(nx,worldY,nz);
      vehicle.root.rotation.y=a.root.rotation.y;
      final moving=motion==0||motion==1;
      final rider=moving?(a.riderMoving??a.run??a.walk):(a.riderIdle??a.idle??a.normal);
      if(rider!=null&&a.clip!=rider)a.play(rider);
      final vehicleClip=moving
        ?(vehicle.clips[motion==1?'Correr':'Caminar']??vehicle.clips['Correr']??vehicle.clips['Caminar'])
        :(vehicle.clips['Respirar']??vehicle.clips['Reposo']??vehicle.normal);
      if(vehicleClip!=null&&vehicle.clip!=vehicleClip)vehicle.play(vehicleClip);
    }else{
      final clip=motion==1
        ?(a.run??a.walk)
        :motion==0
          ?(a.walk??a.run)
          :(a.idle??a.normal);
      if(clip!=null&&a.clip!=clip)a.play(clip);
    }
    notifyListeners();
  }

  Future<void> setNetworkPlayerMount(int characterId,CreatureRecord? record) async {
    final rider=networkPlayerActors[characterId];if(rider==null)return;
    final old=networkPlayerMountActors.remove(characterId);
    if(old!=null){gameActors.remove(old);old.dispose();}
    networkPlayerRiderHeight.remove(characterId);
    final ground=networkPlayerGroundY[characterId]??rider.root.position.y;
    if(record==null){
      rider.root.position.y=ground;
      final idle=rider.idle??rider.normal;
      if(idle!=null)rider.play(idle);
      notifyListeners();return;
    }
    try{
      final vehicle=await loadCreature(record);
      if(networkPlayerActors[characterId]!=rider){vehicle.dispose();return;}
      final seat=(vehicle.height*.58).clamp(.2,5.0);
      networkPlayerRiderHeight[characterId]=seat;
      vehicle.root.position.setValues(rider.root.position.x,ground,rider.root.position.z);
      vehicle.root.rotation.y=rider.root.rotation.y;
      rider.root.position.y=ground+seat;
      final riderIdle=rider.riderIdle??rider.idle??rider.normal;
      if(riderIdle!=null)rider.play(riderIdle);
      gameActors.add(vehicle);networkPlayerMountActors[characterId]=vehicle;view!.scene.add(vehicle.root);
      notifyListeners();
    }catch(e){report('LIVE mount $characterId: $e');}
  }

  Future<void> applyNetworkPlayerMotion(int characterId,int motion) async {
    final a=networkPlayerActors[characterId];if(a==null)return;
    final paths=networkPlayerAnimations[characterId]??const <String>[];
    final candidates=paths.where((p)=>motionIndex(p)==motion).toList();
    final clip=await firstCompatible(a,candidates);
    if(clip!=null&&networkPlayerActors[characterId]==a)a.play(clip,repeat:motion!=9);
    notifyListeners();
  }

  void removeNetworkPlayer(int characterId){
    final a=networkPlayerActors.remove(characterId),vehicle=networkPlayerMountActors.remove(characterId);
    networkPlayerAnimations.remove(characterId);networkPlayerGroundY.remove(characterId);networkPlayerRiderHeight.remove(characterId);
    if(vehicle!=null){gameActors.remove(vehicle);vehicle.dispose();}
    if(a==null)return;
    gameActors.remove(a);gameLabels.removeWhere((x)=>identical(x.actor,a));a.dispose();
    notifyListeners();
  }

  int? pickNetworkPlayer(double screenX,double screenY,double width,double height,{double radius=34}){
    int? bestId;var best=radius*radius;
    for(final p in projectGameLabels(width,height)){
      if(!p.player||p.globalId==0)continue;
      final dx=p.x-screenX,dy=p.y-screenY,d=dx*dx+dy*dy;
      if(d<best){best=d;bestId=p.globalId;}
    }
    return bestId;
  }

  ({int id,bool player})? pickNetworkCombatTarget(
    double screenX,double screenY,double width,double height,{double radius=34}
  ){
    ({int id,bool player})? result;
    var best=radius*radius;
    for(final p in projectGameLabels(width,height)){
      if(p.globalId==0||(!p.player&&!p.mob))continue;
      final dx=p.x-screenX,dy=p.y-screenY,d=dx*dx+dy*dy;
      if(d<best){best=d;result=(id:p.globalId,player:p.player);}
    }
    return result;
  }

  Future<void> networkPlayerAttackCharacter(int characterId) async {
    final a=character,target=networkPlayerActors[characterId];
    if(a==null||target==null)return;
    final dx=target.root.position.x-a.root.position.x,dz=target.root.position.z-a.root.position.z;
    if(dx.abs()+dz.abs()>1e-5)a.root.rotation.y=math.atan2(dx,dz);
    if(attackClips.isEmpty)await prepareWeaponMotions();
    if(attackClips.isNotEmpty)a.play(attackClips[attackCounter++%attackClips.length],repeat:false);
    notifyListeners();
  }

  Future<void> networkRemotePlayerHit(int characterId,int damage) async {
    final a=networkPlayerActors[characterId];if(a==null)return;
    final paths=networkPlayerAnimations[characterId]??const <String>[];
    final damageIndices=<int>{
      for(final family in const [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15])
        if(damageMotion(family)!=null)damageMotion(family)!,
    };
    final candidates=paths.where((p)=>damageIndices.contains(motionIndex(p))||p.toLowerCase().contains('damage')).toList();
    final clip=await firstCompatible(a,candidates);
    if(clip!=null&&networkPlayerActors[characterId]==a)a.play(clip,repeat:false);
    lastImpact='PvP −'+damage.toString();hitLife=.65;
    if(hitSprite!=null){
      hitSprite!.visible=true;hitSprite!.position.setValues(a.root.position.x,a.root.position.y+1,-.1+a.root.position.z);
    }
    notifyListeners();
  }

  Future<void> networkRemotePlayerDeath(int characterId) async {
    final a=networkPlayerActors[characterId];if(a==null)return;
    final paths=networkPlayerAnimations[characterId]??const <String>[];
    final clip=await firstCompatible(a,paths.where((p)=>motionIndex(p)==9||p.toLowerCase().contains('death')||p.toLowerCase().contains('dead')).toList());
    a.idle=null;
    if(clip!=null&&networkPlayerActors[characterId]==a)a.play(clip,repeat:false);else a.playing=false;
    notifyListeners();
  }

  Future<void> networkRemotePlayerRebirth(int characterId,double worldX,double worldY,double worldZ,int angle) async {
    final a=networkPlayerActors[characterId];if(a==null)return;
    a.root.position.setValues(worldX-originX,worldY,-(worldZ-originZ));
    a.root.rotation.y=-angle*(math.pi*2/65536.0);
    final idle=a.normal??a.idle;
    if(idle!=null){a.idle=idle;a.play(idle);}else{a.playing=true;}
    notifyListeners();
  }
  int? pickNetworkMob(double screenX,double screenY,double width,double height,{double radius=34}){
    int? bestId;var best=radius*radius;
    for(final p in projectGameLabels(width,height)){
      if(!p.mob||p.globalId==0)continue;
      final dx=p.x-screenX,dy=p.y-screenY,d=dx*dx+dy*dy;
      if(d<best){best=d;bestId=p.globalId;}
    }
    return bestId;
  }

  int? nearestNetworkNpcId({double maxDistance=4.5}){
    final me=character;
    if(me==null||networkNpcActors.isEmpty)return null;
    int? bestId;var best=maxDistance*maxDistance;
    for(final entry in networkNpcActors.entries){
      final dx=entry.value.root.position.x-me.root.position.x;
      final dz=entry.value.root.position.z-me.root.position.z;
      final d=dx*dx+dz*dz;
      if(d<best){best=d;bestId=entry.key;}
    }
    return bestId;
  }

  int? nearestNetworkMobId({double maxDistance=12}){
    final me=character;
    if(me==null||networkMobActors.isEmpty)return null;
    int? bestId;var best=maxDistance*maxDistance;
    for(final entry in networkMobActors.entries){
      final dx=entry.value.root.position.x-me.root.position.x;
      final dz=entry.value.root.position.z-me.root.position.z;
      final d=dx*dx+dz*dz;
      if(d<best){best=d;bestId=entry.key;}
    }
    return bestId;
  }
  void moveNetworkNpc(int globalId,double worldX,double worldY,double worldZ,int motion){
    final a=networkNpcActors[globalId];if(a==null)return;
    final nx=worldX-originX,nz=-(worldZ-originZ);
    final dx=nx-a.root.position.x,dz=nz-a.root.position.z;
    if(dx.abs()+dz.abs()>1e-5)a.root.rotation.y=math.atan2(dx,dz);
    a.root.position.setValues(nx,worldY,nz);
    final clip=motion==1?(a.clips['Correr']??a.clips['Caminar']):(a.clips['Caminar']??a.clips['Correr']);
    if(clip!=null&&a.clip!=clip)a.play(clip);
  }

  void moveNetworkMob(int globalId,double worldX,double worldZ,int motion){
    final a=networkMobActors[globalId];if(a==null)return;
    final nx=worldX-originX,nz=-(worldZ-originZ);
    final dx=nx-a.root.position.x,dz=nz-a.root.position.z;
    if(dx.abs()+dz.abs()>1e-5)a.root.rotation.y=math.atan2(dx,dz);
    final y=world==null?a.root.position.y:world!.heightAt(worldX,worldZ,scale:.02,offset:-200);
    a.root.position.setValues(nx,y,nz);
    final clip=motion==1?(a.clips['Correr']??a.clips['Caminar']):(a.clips['Caminar']??a.clips['Correr']);
    if(clip!=null&&a.clip!=clip)a.play(clip);
  }

  void removeNetworkActor(int globalId,{required bool mob}){
    final map=mob?networkMobActors:networkNpcActors;
    final a=map.remove(globalId);if(a==null)return;
    gameActors.remove(a);gameLabels.removeWhere((x)=>identical(x.actor,a));a.dispose();
    notifyListeners();
  }

  Future<void> networkPlayerAttack(int targetGlobalId) async {
    final a=character,target=networkMobActors[targetGlobalId];
    if(a==null||target==null)return;
    final dx=target.root.position.x-a.root.position.x;
    final dz=target.root.position.z-a.root.position.z;
    if(dx.abs()+dz.abs()>1e-5)a.root.rotation.y=math.atan2(dx,dz);
    if(attackClips.isEmpty)await prepareWeaponMotions();
    if(attackClips.isNotEmpty){
      final clip=attackClips[attackCounter++%attackClips.length];
      a.play(clip,repeat:false);
    }
    notifyListeners();
  }
  Future<void> networkMobHit(int globalId,int damage) async {
    final a=networkMobActors[globalId];if(a==null)return;
    final clip=a.clips['Daño']??a.clips['Damage']??a.clips['Golpe'];
    if(clip!=null)a.play(clip,repeat:false);
    lastImpact='Impacto −'+damage.toString();
    hitLife=.65;
    if(hitSprite!=null){
      hitSprite!.visible=true;
      hitSprite!.position.setValues(a.root.position.x,a.root.position.y+1,-.1+a.root.position.z);
    }
    notifyListeners();
  }

  Future<void> networkPlayerDeath() async {
    final a=character;if(a==null)return;
    clearMovement();
    final candidates=animations.where((p)=>motionIndex(p)==9||p.toLowerCase().contains('death')||p.toLowerCase().contains('dead')).toList();
    final clip=await firstCompatible(a,candidates);
    if(clip!=null){
      a.idle=null;
      a.play(clip,repeat:false);
    }else{
      a.playing=false;
    }
    lastImpact='Has muerto';
    hitLife=0;
    if(hitSprite!=null)hitSprite!.visible=false;
    notifyListeners();
  }

  Future<void> networkPlayerRebirth(double worldX,double worldY,double worldZ) async {
    final a=character;if(a==null)return;
    a.root.position.setValues(worldX-originX,worldY,-(worldZ-originZ));
    groundY=worldY;
    movementTransitions.invalidate();
    final idle=a.clips['Respirar']??a.clips['Reposo']??a.normal;
    if(idle!=null){
      a.idle=idle;
      a.play(idle);
    }else{
      a.playing=true;
    }
    updateAttachments();
    updateCamera();
    notifyListeners();
  }

  Future<void> networkPlayerHit(int damage) async {
    final a=character;if(a==null)return;
    final index=damageMotion(weaponFamily(weaponRecord));
    final candidates=animations.where((p)=>index!=null?motionIndex(p)==index:p.toLowerCase().contains('damage')).toList();
    final clip=await firstCompatible(a,candidates);
    if(clip!=null&&a==character)a.play(clip,repeat:false);
    lastImpact='Recibido −'+damage.toString();
    hitLife=.65;
    if(hitSprite!=null){
      hitSprite!.visible=true;
      hitSprite!.position.setValues(a.root.position.x,a.root.position.y+1,-.1+a.root.position.z);
    }
    notifyListeners();
  }
  Future<void> killNetworkMob(int globalId) async {
    final a=networkMobActors[globalId];if(a==null)return;
    final death=a.clips['Caída']??a.clips['Muerte'];
    if(death!=null)a.play(death,repeat:false);
    await Future<void>.delayed(Duration(milliseconds:death==null?250:math.max(250,(death.duration*1000).round())));
    if(networkMobActors[globalId]==a)removeNetworkActor(globalId,mob:true);
  }
  Future<void> spawnGameActorsFromSvmap(SvmapData map,{Map<String,int>? npcModels,Map<int,int>? mobModels,Set<String>? questNpcKeys,String locale='spn',int npcLimit=28,int mobLimit=18}) async {
    for(final a in gameActors){a.dispose();}
    gameActors.clear();gameLabels.clear();
    if(view==null||catalog==null)return;
    final npcRecords={for(final n in catalog!.npcs)n.id:n};
    final orderedNpcs=[...map.npcs]..sort((a,b){
      final adx=a.position.x-originX,adz=a.position.z-originZ;
      final bdx=b.position.x-originX,bdz=b.position.z-originZ;
      return (adx*adx+adz*adz).compareTo(bdx*bdx+bdz*bdz);
    });
    var npcsLoaded=0;
    for(final p in orderedNpcs){
      if(npcsLoaded>=npcLimit)break;
      final x=p.position.x-originX,z=-(p.position.z-originZ);
      if(x.abs()>60||z.abs()>60)continue;
      final model=npcModels?[p.type.toString()+':'+p.id.toString()]??p.id;
      final record=npcRecords[model];
      if(record==null)continue;
      try{
        final a=await loadCreature(record);
        a.root.position.setValues(x,p.position.y,z);
        a.root.rotation.y=-p.yaw;
        gameActors.add(a);view!.scene.add(a.root);npcsLoaded++;
        final key='${p.type}:${p.id}';
        final localized=catalog!.questText(locale)?.npc(p.type,p.id);
        gameLabels.add(GameActorLabel(
          a,
          (localized?.name.isNotEmpty??false)?localized!.name:'NPC ${p.type}:${p.id}',
          quest:questNpcKeys?.contains(key)??false,
        ));
      }catch(e){report('SVMAP NPC ${p.type}:${p.id}: $e');}
    }
    final mobRecords={for(final m in catalog!.creatures)m.id:m};
    var mobsLoaded=0;
    for(final area in map.mobAreas){
      if(mobsLoaded>=mobLimit)break;
      final center=area.center;
      final baseX=center.x-originX,baseZ=-(center.z-originZ);
      if(baseX.abs()>68||baseZ.abs()>68)continue;
      for(final spawn in area.mobs){
        if(mobsLoaded>=mobLimit)break;
        final model=mobModels?[spawn.id]??spawn.id;
        final record=mobRecords[model];
        if(record==null){report('SVMAP mob ${spawn.id}: modelo $model no existe en monster.mon.');continue;}
        try{
          final a=await loadCreature(record);
          final ring=mobsLoaded%6,rad=2.5+(mobsLoaded%3);
          final angle=ring/6*math.pi*2;
          final x=baseX+math.cos(angle)*rad,z=baseZ+math.sin(angle)*rad;
          a.root.position.setValues(x,world==null?center.y:world!.heightAt(originX+x,originZ-z,scale:.02,offset:-200),z);
          a.root.rotation.y=-angle;
          gameActors.add(a);view!.scene.add(a.root);mobsLoaded++;
          final mobName=catalog!.monsterName(spawn.id,locale);
          gameLabels.add(GameActorLabel(a,mobName,mob:true));
        }catch(e){report('SVMAP mob ${spawn.id}: $e');}
      }
    }
    say('$npcsLoaded NPC y $mobsLoaded criaturas colocados desde SVMAP.');
  }
  t.Vector2? projectWorldPosition(double worldX,double worldY,double worldZ,double width,double height){
    final camera=view?.camera;
    if(camera==null||width<=0||height<=0)return null;
    final p=t.Vector3(worldX-originX,worldY,-(worldZ-originZ));
    p.project(camera);
    if(p.z<-1||p.z>1||p.x<-1.25||p.x>1.25||p.y<-1.25||p.y>1.25)return null;
    return t.Vector2((p.x+1)*.5*width,(1-p.y)*.5*height);
  }

  List<ProjectedGameLabel> projectGameLabels(double width,double height){
    final camera=view?.camera;
    if(camera==null||width<=0||height<=0)return const [];
    final out=<ProjectedGameLabel>[];
    for(final label in gameLabels){
      final a=label.actor;
      final p=t.Vector3(a.root.position.x,a.root.position.y+a.height+0.28,a.root.position.z);
      p.project(camera);
      if(p.z<-1||p.z>1||p.x<-1.25||p.x>1.25||p.y<-1.25||p.y>1.25)continue;
      out.add(ProjectedGameLabel((p.x+1)*.5*width,(1-p.y)*.5*height,label.text,label.quest,label.mob,label.player,label.globalId));
    }
    return out;
  }
  Future<void> selectCreature(CreatureRecord? c,String kind) async {
    final revision=kind=='enemy'?++_creatureRevision:kind=='mount'?++_mountRevision:++_wingRevision;
    if(kind=='mount'&&mountRecord!=null){_seats['${mountRecord!.source}#${mountRecord!.id}']=(height:riderHeight,forward:riderForward);}
    final staged=c==null?null:await loadCreature(c);final current=kind=='enemy'?_creatureRevision:kind=='mount'?_mountRevision:_wingRevision;
    if(disposed||revision!=current){staged?.dispose();return;}
    if(kind=='enemy'){enemy?.dispose();enemy=staged;enemyRecord=c;combat.reset();if(staged!=null){staged.root.position.setValues(1.8,groundY,0);staged.root.rotation.y=-math.pi/2;}}
    else if(kind=='mount'){mount?.dispose();mount=staged;mountRecord=c;combat.reset();if(staged!=null){final seat=_seats['${c!.source}#${c.id}'];riderHeight=seat?.height??(staged.height*.58).clamp(.2,5.0);riderForward=seat?.forward??0;await riderPose();}else if(character?.idle!=null){character!.play(character!.idle!);}}
    else{wing?.dispose();wing=staged;wingRecord=c;}
    if(staged!=null)view!.scene.add(staged.root);if(kind=='wing'&&staged!=null)staged.root.matrixAutoUpdate=false;if(kind=='mount')movementTransitions.invalidate();
    updateAttachments();distance=mount!=null?math.max(7,mount!.height*2.5):5.2;updateCamera();say(c==null?'Elemento retirado.':'${catalog!.creatureLabel(c)} cargado.');
  }
  Future<void> riderPose() async {final a=character;if(a==null)return;if(a.riderIdle!=null)a.play(a.riderIdle!);movementTransitions.invalidate();}
  Future<void> equip(WeaponRecord? w) async {
    final a=character;if(a==null)return;final rev=++_weaponRevision;
    if(w==null){weapon?.dispose();secondWeapon?.dispose();weapon=null;secondWeapon=null;weaponRecord=null;weaponAttachment=null;secondAttachment=null;await prepareWeaponMotions();notifyListeners();return;}
    final lib=catalog!.library,root=directoryName(w.source),m=lib.resolve(w.mesh,['$root/3do',root]),tex=lib.resolve(w.texture,['$root/dds',root]);if(m==null||tex==null)throw FormatException('Faltan recursos del arma ${w.id}.');
    final r=Bin(await lib.read(m),m);r.str();final data=MeshData.rigid(r);r.end();final part=await makePart(data,tex,opaque:w.alpha==1);
    if(disposed||rev!=_weaponRevision||character!=a){part.dispose();return;}
    final code=archetypeCodes.indexOf(appearance!.archetype.id);Attachment? attachment;
    if(code>=0&&code<w.transforms.length)attachment=w.transforms[code][0];
    if(attachment==null||!attachment.defined||attachment.bone>=a.world.length){part.dispose();throw const FormatException('Esta arma no define un anclaje válido para el arquetipo actual.');}
    RenderPart? other;Attachment? otherAttachment;
    if([5,15].contains(weaponFamily(w))&&w.transforms[code][1].defined){otherAttachment=w.transforms[code][1];if(otherAttachment.bone>=a.world.length){part.dispose();throw const FormatException('El segundo anclaje requiere otro esqueleto.');}try{other=await makePart(data,tex,opaque:w.alpha==1);}catch(_){part.dispose();rethrow;}}
    if(disposed||rev!=_weaponRevision||character!=a){part.dispose();other?.dispose();return;}
    weapon?.dispose();secondWeapon?.dispose();weapon=part;secondWeapon=other;weaponRecord=w;weaponAttachment=attachment;secondAttachment=otherAttachment;
    for(final p in [part,other]){if(p!=null){a.root.add(p.mesh);p.mesh.matrixAutoUpdate=false;}}
    await prepareWeaponMotions();updateAttachments();say('${weaponLabel(w)} equipado${other==null?'':' en ambas manos'} con anclajes IT2 originales.');
  }
  Future<void> prepareWeaponMotions() async {
    final a=character;if(a==null)return;attackClips.clear();attackCounter=0;
    final family=weaponFamily(weaponRecord),wanted=attackMotions(family);
    final candidates=wanted.isEmpty?animations.where((p)=>p.contains('attack')).take(4):animations.where((p)=>wanted.contains(motionIndex(p)));
    for(final path in candidates){final c=await firstCompatible(a,[path]);if(c!=null&&a==character)attackClips.add(c);}if(a!=character)return;
    final ready=readyMotion(family);final paths=ready==null?<String>[]:animations.where((p)=>motionIndex(p)==ready).toList();
    final idle=paths.isEmpty?a.normal:await firstCompatible(a,paths);if(idle!=null){a.idle=idle;if(mount==null&&walkX==0&&walkZ==0)a.play(idle);}movementTransitions.invalidate();if(attackClips.isNotEmpty)combat.attackDuration=attackClips.first.duration;
  }
  void setMovement(double x,double z,{bool run=false}){if(disposed)return;walkX=x.isFinite?x.clamp(-1.0,1.0):0;walkZ=z.isFinite?z.clamp(-1.0,1.0):0;running=run;}
  void clearMovement()=>setMovement(0,0);
  bool get sceneCombatLocked{final a=character;return busy||combat.playerHealth<=0||(combat.active&&a!=null&&!a.loop&&a.clip!=null&&a.time<a.clip!.duration);}
  ClipData? movementClip(GroundMotion mode){
    final a=character;if(a==null)return null;
    if(mount!=null){if(mode!=GroundMotion.idle&&mount!.clips['Caminar']==null&&mount!.clips['Correr']==null)return null;return mode==GroundMotion.idle?a.riderIdle:a.riderMoving;}
    return switch(mode){GroundMotion.idle=>a.idle??a.normal,GroundMotion.walk=>a.walk,GroundMotion.run=>a.run};
  }
  bool applyLocomotion(GroundMotion mode){
    final a=character;if(a==null||sceneCombatLocked)return false;final desired=movementClip(mode),vehicle=mount;
    if(vehicle!=null&&mode!=GroundMotion.idle){final movement=vehicle.clips[mode==GroundMotion.run?'Correr':'Caminar']??vehicle.clips['Correr']??vehicle.clips['Caminar'];if(movement==null)return false;}
    if(desired==null){final key='${appearance?.archetype.id}:${mode.name}:${mount!=null}';if(_missingMovementWarnings.add(key))report('No hay animación compatible de ${mode==GroundMotion.run?'correr':mode==GroundMotion.walk?'caminar':'reposo'}. Se impide el desplazamiento sin animación.');return false;}
    a.play(desired);
    if(vehicle!=null){final key=mode==GroundMotion.idle?'Respirar':mode==GroundMotion.run?'Correr':'Caminar';final c=vehicle.clips[key]??vehicle.clips[mode==GroundMotion.idle?'Reposo':'Correr']??(mode==GroundMotion.idle?vehicle.normal:vehicle.clips['Caminar']);if(c!=null)vehicle.play(c);}
    return true;
  }
  void updateAttachments(){
    final a=character;if(a==null)return;final x=a.root.position.x,z=a.root.position.z,rotation=a.root.rotation.y;
    a.root.position.y=groundY+(mount==null?0:riderHeight);
    if(weapon!=null&&weaponAttachment!=null&&weaponAttachment!.bone<a.world.length){weapon!.mesh.matrix.copyFromArray((a.world[weaponAttachment!.bone]*weaponAttachment!.matrix).storage);weapon!.mesh.matrixWorldNeedsUpdate=true;}
    if(secondWeapon!=null&&secondAttachment!=null&&secondAttachment!.bone<a.world.length){secondWeapon!.mesh.matrix.copyFromArray((a.world[secondAttachment!.bone]*secondAttachment!.matrix).storage);secondWeapon!.mesh.matrixWorldNeedsUpdate=true;}
    if(mount!=null){mount!.root.position.setValues(x+math.sin(rotation)*riderForward,groundY,z+math.cos(rotation)*riderForward);mount!.root.rotation.y=rotation;}
    if(wing!=null){final bone=a.wingBone;final valid=bone!=null&&bone<a.world.length&&a.wingReference!=null;final matrix=backAttachmentPose(position:v.Vector3(x,a.root.position.y,z),yaw:rotation,bone:valid?a.world[bone]:v.Matrix4.identity(),referenceInverse:valid?a.wingReference!:v.Matrix4.identity(),offset:v.Vector3(0,wingHeight,wingDepth),scale:wingSize);wing!.root.matrix.copyFromArray(matrix.storage);wing!.root.matrixWorldNeedsUpdate=true;}
  }
  Future<void> previewActorAnimation(String target,String name) async {final a=target=='enemy'?enemy:target=='mount'?mount:wing;final c=a?.clips[name];if(a!=null&&c!=null)a.play(c);notifyListeners();}
  Future<String> _materializeAudio(String path) async {
    final cached=_materializedAudio[path];
    if(cached!=null&&await File(cached).exists())return cached;
    final bytes=await catalog!.library.read(path,limit:32*1024*1024),dir=await getTemporaryDirectory();
    final safeName=baseName(path).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
    final f=File('${dir.path}/shaiya_${path.hashCode.toUnsigned(32)}_$safeName');
    if(!await f.exists()||await f.length()!=bytes.length)await f.writeAsBytes(bytes,flush:true);
    _materializedAudio[path]=f.path;
    return f.path;
  }
  Future<void> playSound(String path) async {
    if(!sound||catalog==null)return;
    try{await audio.play(DeviceFileSource(await _materializeAudio(path)));}catch(e){report('Audio: $e');}
  }
  String? _resolveWorldAudioAsset(String name,{required bool music}){
    final lib=catalog?.library;if(lib==null||name.trim().isEmpty)return null;
    final roots=music?const ['sound/music','sound']:const ['sound'];
    return lib.resolve(name,roots)??lib.resolve(name,roots,uniqueFallback:true);
  }
  Future<void> _setLoopingChannel(AudioPlayer player,String? next,{required bool music}) async {
    final current=music?_worldMusicPath:_worldAmbientPath;
    if(current==next)return;
    if(music)_worldMusicPath=next;else _worldAmbientPath=next;
    await player.stop();
    if(next==null||!sound)return;
    try{
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(DeviceFileSource(await _materializeAudio(next)));
    }catch(e){report((music?'Música':'Ambiente')+': '+e.toString());}
  }
  Future<WaterSurface?> _buildWaterSurface(
    WorldData w,double ox,double oz,t.Group stage,
  ) async {
    if(waterTexturePaths.isEmpty||waterAnimation==null)return null;
    final tile=waterAnimation!.tileSize.abs()<1e-6?64.0:waterAnimation!.tileSize.abs();
    const extent=82.0;
    final positions=Float32List.fromList(<double>[
      -extent,0,-extent,
       extent,0,-extent,
      -extent,0, extent,
       extent,0, extent,
    ]);
    final normals=Float32List.fromList(<double>[
      0,1,0, 0,1,0, 0,1,0, 0,1,0,
    ]);
    double u(double localX)=>(ox+localX)/tile;
    double vv(double localZ)=>(oz-localZ)/tile;
    final uv=Float32List.fromList(<double>[
      u(-extent),vv(-extent),
      u(extent),vv(-extent),
      u(-extent),vv(extent),
      u(extent),vv(extent),
    ]);
    final geometry=t.BufferGeometry();
    geometry.setAttributeFromString(
      'position',t.Float32BufferAttribute.fromList(positions.toList(),3),
    );
    geometry.setAttributeFromString(
      'normal',t.Float32BufferAttribute.fromList(normals.toList(),3),
    );
    geometry.setAttributeFromString(
      'uv',t.Float32BufferAttribute.fromList(uv.toList(),2),
    );
    geometry.setIndex(<int>[0,2,1,1,2,3]);

    final textures=<t.Texture>[];
    try{
      for(final path in waterTexturePaths.take(48)){
        final bytes=await catalog!.library.read(path);
        final png=await compute(_decodeTexture,{'bytes':bytes,'path':path,'opaque':false});
        final texture=await t.TextureLoader(flipY:false).fromBytes(png);
        if(texture==null)continue;
        texture.colorSpace=t.SRGBColorSpace;
        texture.wrapS=t.RepeatWrapping;texture.wrapT=t.RepeatWrapping;
        textures.add(texture);
      }
      if(textures.isEmpty){geometry.dispose();return null;}
      final material=t.MeshLambertMaterial.fromMap({
        'map':textures.first,
        'color':0xb9dfff,
        'side':t.DoubleSide,
        'transparent':true,
        'opacity':.72,
        'depthWrite':false,
        'depthTest':true,
        'toneMapped':false,
      });
      final mesh=t.Mesh(geometry,material)
        ..frustumCulled=false
        ..renderOrder=25;
      stage.add(mesh);
      return WaterSurface(mesh,textures);
    }catch(_){
      geometry.dispose();
      for(final texture in textures){texture.dispose();}
      rethrow;
    }
  }

  Future<void> _playTerrainFootstep() async {
    if(!sound||catalog==null||world==null||character==null||mount!=null)return;
    final a=character!,worldX=originX+a.root.position.x,worldZ=originZ-a.root.position.z;
    final layer=world!.layerAt(worldX,worldZ),name=layer?.sound.trim()??'';
    if(name.isEmpty)return;
    final path=_resolveWorldAudioAsset(name,music:false);
    if(path==null)return;
    try{
      await footstepAudio.stop();
      await footstepAudio.setReleaseMode(ReleaseMode.stop);
      await footstepAudio.play(DeviceFileSource(await _materializeAudio(path)));
    }catch(e){report('Paso de terreno: '+e.toString());}
  }

  Future<void> _syncWorldAudio() async {
    if(_worldAudioSyncing||catalog==null)return;
    _worldAudioSyncing=true;
    try{
      if(!sound||world==null||character==null){
        await _setLoopingChannel(musicAudio,null,music:true);
        await _setLoopingChannel(ambientAudio,null,music:false);
        return;
      }
      final w=world!,a=character!,x=originX+a.root.position.x,y=groundY,z=originZ-a.root.position.z;
      String? musicPath;
      for(final zone in w.musicZones){
        if(!zone.bounds.contains(x,y,z))continue;
        musicPath=_resolveWorldAudioAsset(w.musicAssets[zone.assetId],music:true);
        if(musicPath!=null)break;
      }
      WorldSoundEffect? nearest;var nearestDistance=double.infinity;
      for(final effect in w.soundEffects){
        if(!effect.contains(x,y,z))continue;
        final dx=x-effect.center.x,dy=y-effect.center.y,dz=z-effect.center.z,d=dx*dx+dy*dy+dz*dz;
        if(d<nearestDistance){nearestDistance=d;nearest=effect;}
      }
      final ambientPath=nearest==null?null:_resolveWorldAudioAsset(w.soundEffectAssets[nearest.assetId],music:false);
      await _setLoopingChannel(musicAudio,musicPath,music:true);
      await _setLoopingChannel(ambientAudio,ambientPath,music:false);
    }catch(e){report('Audio de mundo: '+e.toString());}
    finally{_worldAudioSyncing=false;}
  }
  Future<void> setEffect(String path) async {
    final revision=++_effectRevision,lib=catalog!.library;final png=await compute(_decodeTexture,{'bytes':await lib.read(path),'path':path,'opaque':false});final texture=await t.TextureLoader(flipY:false).fromBytes(png);if(texture==null)return;if(disposed||revision!=_effectRevision){texture.dispose();return;}
    hitSprite?.removeFromParent();hitSprite?.material?.dispose();effectTexture?.dispose();effectTexture=texture;hitSprite=t.Sprite(t.SpriteMaterial.fromMap({'map':texture,'transparent':true,'depthWrite':false,'blending':t.AdditiveBlending,'color':0xffffff}));hitSprite!.visible=false;view!.scene.add(hitSprite!);effectPath=path;say('Textura de efecto seleccionada. La secuencia del laboratorio es una simulación.');
  }
  Future<void> _combatEvent(String who,String event) async {
    try{final a=who=='enemy'?enemy:character;if(a==null)return;
      if(who=='enemy'){final key=event=='attack'?'Ataque 1':event=='death'?'Caída':'Daño';final c=a.clips[key];if(c!=null)a.play(c,repeat:false);final raw=enemyRecord?.sounds[key]??'';final s=catalog?.library.resolve(raw,['sound/monster','sound'],uniqueFallback:true);if(s!=null)unawaited(playSound(s));}
      else{ClipData? c;if(event=='attack'&&attackClips.isNotEmpty){c=attackClips[attackCounter++%attackClips.length];combat.attackDuration=attackClips[attackCounter%attackClips.length].duration;}else{final index=event=='death'?9:damageMotion(weaponFamily(weaponRecord));final candidates=animations.where((p)=>index!=null?motionIndex(p)==index:p.contains('damage')).toList();c=await firstCompatible(a,candidates);}if(c!=null&&a==character)a.play(c,repeat:false);}
      if(event=='death')a.idle=null;
      if(event=='hit'){hitLife=.65;lastImpact=who=='enemy'?'Impacto −${combat.damage.round()}':'Recibido −${combat.enemyDamage.round()}';if(hitSprite!=null){hitSprite!.visible=true;hitSprite!.position.setValues(a.root.position.x,a.root.position.y+1,-.1+a.root.position.z);}}
    }catch(e){report('Animación de combate: $e');}
  }
  Future<void> attack() async {
    if(character==null||enemy==null)throw const FormatException('Carga un personaje y una criatura antes de combatir.');if(mount!=null)throw const FormatException('Desmonta antes de iniciar la prueba de combate.');
    if(attackClips.isEmpty)await prepareWeaponMotions();if(attackClips.isEmpty)throw const FormatException('No existe un ataque compatible con el equipo y arquetipo seleccionados.');
    character!.root.rotation.y=math.atan2(enemy!.root.position.x-character!.root.position.x,enemy!.root.position.z-character!.root.position.z);combat.attack(enemyDistance);notifyListeners();
  }
  double get enemyDistance{if(enemy==null||character==null)return double.infinity;final dx=enemy!.root.position.x-character!.root.position.x,dz=enemy!.root.position.z-character!.root.position.z;return math.sqrt(dx*dx+dz*dz);}
  void resetCombat(){combat.reset();movementTransitions.invalidate();for(final a in [character,enemy]){if(a==null)continue;final c=a.clips['Respirar']??a.clips['Reposo']??a.normal;if(c!=null){a.idle=c;a.play(c);}}notifyListeners();}
  void setWireframe(bool value){wireframe=value;for(final a in [character,enemy,mount,wing]){for(final p in a?.parts??<RenderPart>[]){p.mesh.material?.wireframe=value;}}weapon?.mesh.material?.wireframe=value;secondWeapon?.mesh.material?.wireframe=value;notifyListeners();}
  double _worldGroundAtLocal(double x,double z)=>dungeon?.floorAt(originX+x,originZ-z)??world!.heightAt(originX+x,originZ-z,scale:.02,offset:-200);
  bool _insideCurrentWorldBounds(double x,double z){
    if(world==null)return true;
    final dg=dungeon;
    if(dg!=null){
      final worldX=originX+x,worldZ=originZ-z;
      return worldX>=dg.lower.x&&worldX<=dg.upper.x&&
        worldZ>=dg.lower.z&&worldZ<=dg.upper.z;
    }
    return x.abs()<72&&z.abs()<72;
  }
  bool _worldPositionBlocked(double x,double z){
    if(world==null||worldCollision.isEmpty)return false;
    final radius=mount==null ? .32 : .52;
    final height=mount==null?1.65:math.max(1.65,mount!.height+riderHeight*.75);
    return worldCollision.blocksPosition(x,_worldGroundAtLocal(x,z),z,radius:radius,height:height);
  }
  void _moveCharacterInWorld(double x,double z){
    final a=character;if(a==null)return;
    if(world==null){a.root.position.x=x;a.root.position.z=z;return;}
    if(!_insideCurrentWorldBounds(x,z))return;
    final startX=a.root.position.x,startZ=a.root.position.z;
    var nextX=startX,nextZ=startZ;
    if(!_worldPositionBlocked(x,z)){
      nextX=x;nextZ=z;
    }else{
      if(!_worldPositionBlocked(x,startZ))nextX=x;
      if(!_worldPositionBlocked(nextX,z))nextZ=z;
    }
    a.root.position.x=nextX;
    a.root.position.z=nextZ;
    groundY=_worldGroundAtLocal(nextX,nextZ);
  }
  void tick(double dt){
    if(disposed)return;_frameAccumulator+=dt;_uiAccumulator+=dt;if(_frameAccumulator<1/30)return;final delta=_frameAccumulator.clamp(0.0,.1);_frameAccumulator=0;
    final moving=walkX!=0||walkZ!=0;final transition=movementTransitions.update(x:walkX,z:walkZ,running:running,blocked:sceneCombatLocked);if(transition!=null)applyLocomotion(transition);final desired=movementClip(movementTransitions.requested);
    if(moving&&!sceneCombatLocked&&desired!=null&&character!=null&&(character!.clip!=desired||!character!.playing||!character!.loop))applyLocomotion(movementTransitions.requested);
    for(final a in [character,enemy,mount,wing,...gameActors]){a?.tick(delta);}for(final a in animatedWorldActors){a.tick(delta);}for(final a in maniWorldActors){a.tick(delta);}waterSurface?.tick(delta);
    if(character!=null&&moving&&!sceneCombatLocked&&desired!=null&&character!.clip==desired&&character!.playing){
      final direction=cameraRelativeMovement(walkX,walkZ,yaw);
      final speed=mount!=null?(running?7.0:3.5):(running?4.0:2.0);
      final x=character!.root.position.x+direction.x*delta*speed;
      final z=character!.root.position.z+direction.z*delta*speed;
      _moveCharacterInWorld(x,z);
      character!.root.rotation.y=math.atan2(direction.x,direction.z);
    }
    updateAttachments();combat.step(delta,enemyDistance);if(hitLife>0){hitLife-=delta;if(hitSprite!=null){hitSprite!.scale.setValues(1.5-hitLife,1.5-hitLife,1);hitSprite!.visible=hitLife>0;}}updateCamera();
    _worldAudioAccumulator+=delta;if(_worldAudioAccumulator>.5){_worldAudioAccumulator=0;unawaited(_syncWorldAudio());}
    if(moving&&!sceneCombatLocked&&mount==null){
      _footstepAccumulator+=delta;
      final cadence=running ? .34 : .48;
      if(_footstepAccumulator>=cadence){_footstepAccumulator=0;unawaited(_playTerrainFootstep());}
    }else{
      _footstepAccumulator=0;
    }
    if(_uiAccumulator>.2){_uiAccumulator=0;notifyListeners();}
  }
  void orbit(double dx,double dy){yaw-=dx*.006;pitch=(pitch+dy*.006).clamp(-1.2,1.2);updateCamera();}
  void zoom(double amount){distance=(distance*amount).clamp(.4,250);updateCamera();}
  void updateCamera(){if(!ready||view==null)return;final a=character;final x=(a?.root.position.x??0)+panX,z=(a?.root.position.z??0)+panZ,y=groundY+targetY+(mount==null?0:riderHeight*.6);view!.camera.position.setValues(x+math.sin(yaw)*math.cos(pitch)*distance,y+math.sin(pitch)*distance,z+math.cos(yaw)*math.cos(pitch)*distance);view!.camera.lookAt(t.Vector3(x,y,z));for(final layer in [sky,secondaryCloud,primaryCloud]){layer?.mesh.position.setValues(view!.camera.position.x,view!.camera.position.y,view!.camera.position.z);}}
  Future<void> setBackdrop(String? path) async {
    backdropTexture?.dispose();
    backdropTexture=null;
    if(view==null)return;
    if(path==null){
      view!.scene.background=t.Color.fromHex32(0x11151e);
      return;
    }
    final bytes=await catalog!.library.read(path);
    final png=await compute(_decodeTexture,{
      'bytes':bytes,
      'path':path,
      'opaque':true,
    });
    final texture=await t.TextureLoader(flipY:true).fromBytes(png);
    if(texture==null)throw FormatException('No se pudo cargar el fondo $path');
    texture.colorSpace=t.SRGBColorSpace;
    backdropTexture=texture;
    view!.scene.background=texture;
  }

  Future<void> setSky(
    String? path,{
    String? primaryCloudPath,
    String? secondaryCloudPath,
  }) async {
    final revision=++_skyRevision;
    if(path==null){
      sky?.dispose();primaryCloud?.dispose();secondaryCloud?.dispose();
      sky=primaryCloud=secondaryCloud=null;
      skyPath=this.primaryCloudPath=this.secondaryCloudPath=null;
      if(view!=null)view!.scene.background=t.Color.fromHex32(0x11151e);
      notifyListeners();return;
    }
    final lib=catalog!.library,model=lib.resolve('sky.3do',['sky']);
    if(model==null)throw const FormatException('No se encuentra la cúpula original Sky/sky.3DO.');
    final skyBytes=await lib.read(path);
    final background=await compute(_averageTextureColor,{'bytes':skyBytes,'path':path});
    if(view!=null)view!.scene.background=t.Color.fromHex32(background);
    final binary=Bin(await lib.read(model),model);
    binary.str();
    final data=MeshData.rigid(binary);
    binary.end();

    final stagedSky=await _makeSkyLayer(data,path,radius:850,opacity:1,renderOrder:-1000);
    RenderPart? stagedPrimary,stagedSecondary;
    try{
      if(secondaryCloudPath!=null){
        stagedSecondary=await _makeSkyLayer(
          data,secondaryCloudPath,radius:844,opacity:.58,renderOrder:-999,
        );
      }
      if(primaryCloudPath!=null){
        stagedPrimary=await _makeSkyLayer(
          data,primaryCloudPath,radius:840,opacity:.82,renderOrder:-998,
        );
      }
    }catch(_){
      stagedSky.dispose();stagedPrimary?.dispose();stagedSecondary?.dispose();
      rethrow;
    }
    if(disposed||revision!=_skyRevision){
      stagedSky.dispose();stagedPrimary?.dispose();stagedSecondary?.dispose();return;
    }
    sky?.dispose();primaryCloud?.dispose();secondaryCloud?.dispose();
    sky=stagedSky;primaryCloud=stagedPrimary;secondaryCloud=stagedSecondary;
    skyPath=path;
    this.primaryCloudPath=primaryCloudPath;
    this.secondaryCloudPath=secondaryCloudPath;
    view!.scene.add(stagedSky.mesh);
    if(stagedSecondary!=null)view!.scene.add(stagedSecondary.mesh);
    if(stagedPrimary!=null)view!.scene.add(stagedPrimary.mesh);
    updateCamera();
    say('Cielo original: ${baseName(path)}'+
      (primaryCloudPath==null?'':' · nube 1 ${baseName(primaryCloudPath)}')+
      (secondaryCloudPath==null?'':' · nube 2 ${baseName(secondaryCloudPath)}'));
  }

  Future<void> setWorld(String? path,{double? x,double? z}) async {
    final rev=++_worldRevision;
    if(path==null){loadedWorldAssets.clear();missingWorldAssets.clear();worldCollision.clear();waterAnimation=null;waterPath=null;waterTexturePaths.clear();waterSurface?.dispose();waterSurface=null;for(final p in environmentParts){p.dispose();}environmentParts.clear();for(final a in animatedWorldActors){a.dispose();}animatedWorldActors.clear();for(final a in maniWorldActors){a.dispose();}maniWorldActors.clear();environment.removeFromParent();environment=t.Group();view!.scene.add(environment);world=null;dungeon=null;worldPath=null;groundY=0;originX=originZ=0;enemy?.root.position.y=0;_applyWorldFog(null);unawaited(_syncWorldAudio());updateCamera();notifyListeners();return;}
    loadedWorldAssets.clear();missingWorldAssets.clear();
    final lib=catalog!.library,w=WorldData.parse(await lib.read(path),path);

    if(w.size==0){
      final layout=lib.resolve(w.layout,['world/dungeon'],uniqueFallback:true);
      if(layout==null)throw FormatException('No se encuentra la geometría DG: ${w.layout}.');
      final dg=DgData.parse(await lib.read(layout),layout);
      final anchor=w.layout.toLowerCase().contains('dun_login')?dg.presentationAnchor:dg.center;
      final ox=x??anchor.x,oz=z??anchor.z,stage=t.Group(),parts=<RenderPart>[];
      try{
        var loaded=0;
        for(final piece in dg.parts){
          final requested=piece.texture.trim();
          if(requested.isEmpty)continue;
          final dds=requested.toLowerCase().endsWith('.tga')
            ?requested.substring(0,requested.length-4)+'.dds'
            :requested;
          final tex=lib.resolve(
            dds,
            [
              'entity/texture',
              'world/dungeon',
              'world/dungeon/texture',
              'world/dungeon/dds',
              'effect/dds',
            ],
            uniqueFallback:true,
          )??lib.resolve(
            requested,
            ['entity/texture','world/dungeon','effect/dds'],
            uniqueFallback:true,
          );
          if(tex==null){
            missingWorldAssets.add('dg-texture:${piece.texture}');
            continue;
          }
          final p=await makePart(piece.mesh,tex,opaque:true);
          parts.add(p);stage.add(p.mesh);loaded++;
          if(disposed||rev!=_worldRevision){for(final q in parts){q.dispose();}return;}
        }
        if(parts.isEmpty)throw const FormatException('La mazmorra DG no produjo geometría renderizable.');

        // DG vertices use Shaiya's left-handed world coordinates.
        stage.scale.z=-1;
        stage.position.setValues(-ox,0,oz);
        final collision=WorldCollisionIndex();
        final collisionTransform=v.Matrix4.identity();
        final cs=collisionTransform.storage;
        cs[10]=-1;cs[12]=-ox;cs[14]=oz;
        for(final mesh in dg.collisions){collision.addMesh(mesh,collisionTransform);}

        for(final p in environmentParts){p.dispose();}
        environmentParts..clear()..addAll(parts);
        for(final a in animatedWorldActors){a.dispose();}animatedWorldActors.clear();
        for(final a in maniWorldActors){a.dispose();}maniWorldActors.clear();
        environment.removeFromParent();environment=stage;view!.scene.add(stage);
        waterAnimation=null;waterPath=null;waterTexturePaths.clear();waterSurface?.dispose();waterSurface=null;
        worldCollision.replaceWith(collision);world=w;dungeon=dg;worldPath=path;originX=ox;originZ=oz;groundY=dg.floorAt(ox,oz);_applyWorldFog(w);
        character?.root.position.setValues(0,groundY,0);
        enemy?.root.position.setValues(1.8,groundY,0);
        distance=6;updateCamera();
        view!.scene.background=t.Color.fromHex32(0x090806);
        say('Mazmorra ${w.layout} · $loaded submallas · ${dg.parts.fold<int>(0,(n,p)=>n+p.mesh.triangles)} triángulos · ${worldCollision.triangleCount} triángulos de colisión nativos.');
        notifyListeners();
        return;
      }catch(_){
        for(final p in parts){p.dispose();}
        rethrow;
      }
    }

    if(w.size<128)throw const FormatException('Este mapa es menor que el tamaño de sector configurado.');
    waterAnimation=null;waterPath=null;waterTexturePaths.clear();
    if(w.layout.toLowerCase().endsWith('.wtr')){
      final candidate=lib.resolve(w.layout,['entity/water','world/water'],uniqueFallback:true);
      if(candidate!=null){
        try{
          final table=WtrData.parse(await lib.read(candidate),candidate);
          waterAnimation=table;waterPath=candidate;
          for(final name in table.textures){
            final lower=name.toLowerCase();
            final dds=lower.endsWith('.tga')||lower.endsWith('.jpg')||lower.endsWith('.bmp')
              ?name.substring(0,name.length-4)+'.dds'
              :name;
            final texture=lib.resolve(
              dds,['entity/water','world/water'],uniqueFallback:true,
            )??lib.resolve(name,['entity/water','world/water'],uniqueFallback:true);
            if(texture!=null)waterTexturePaths.add(texture);
          }
        }catch(e){report('WTR ${w.layout}: $e');}
      }
    }
    final ox=(x??w.size/2).clamp(64.0,w.size-64.0),oz=(z??w.size/2).clamp(64.0,w.size-64.0),stage=t.Group(),parts=<RenderPart>[],animated=<VaniActor>[],maniAnimated=<ManiActor>[],collision=WorldCollisionIndex();
    try{
      final grouped=<int,List<double>>{},uv=<int,List<double>>{};final width=w.size~/2+1;
      for(var dz=-64;dz<64;dz+=2){for(var dx=-64;dx<64;dx+=2){final xx=ox+dx,zz=oz+dz;final type=w.types[(zz~/2)*width+xx~/2],layer=type<w.layers.length?type:0;final verts=grouped.putIfAbsent(layer,()=>[]),tex=uv.putIfAbsent(layer,()=>[]),tiling=w.layers.isEmpty?4.0:math.max(.1,w.layers[layer].tile.abs());for(final point in [[0,0],[2,0],[0,2],[2,0],[2,2],[0,2]]){final px=xx+point[0],pz=zz+point[1];verts.addAll([px-ox,w.heightAt(px,pz,scale:.02,offset:-200),-(pz-oz)]);tex.addAll([px/tiling,pz/tiling]);}}}
      for(final entry in grouped.entries){
        if(w.layers.isEmpty)break;
        final layer=w.layers[entry.key],tex=lib.resolve(
          w.layers[entry.key].texture,
          ['terrain','terrain/texture','terrain/dds'],
          uniqueFallback:true,
        );
        if(tex==null){report('Textura de terreno ausente: ${layer.texture}');continue;}
        final n=entry.value.length~/3,no=Float32List(n*3);
        for(var i=0;i<n;i++){
          final localX=entry.value[i*3],localZ=entry.value[i*3+2];
          final normal=w.normalAt(
            ox+localX,oz-localZ,scale:.02,offset:-200,step:1,
          );
          no[i*3]=normal.x;no[i*3+1]=normal.y;no[i*3+2]=normal.z;
        }
        final data=MeshData(
          Float32List.fromList(entry.value),no,Float32List.fromList(uv[entry.key]!),
          Uint16List.fromList(List.generate(n,(i)=>i)),Uint8List(0),Float32List(0),[],path,
        );
        final part=await makePart(data,tex,opaque:true);parts.add(part);stage.add(part.mesh);
      }
      if(parts.isEmpty)throw const FormatException('No se pudo construir el terreno de este sector.');
      var loaded=0;
      final loadedByCategory=<String,int>{};
      const budgets=<String,int>{
        'Building':32,
        'Object':16,
        'Shape':64,
        'Tree':64,
        'VAni':24,
        'Grass':96,
      };
      const priority=<String,int>{
        'Building':0,
        'Object':1,
        'Shape':2,
        'Tree':3,
        'VAni':4,
        'Grass':5,
      };
      double objectDistance(WorldInstance o)=>(o.position.x-ox).abs()+(o.position.z-oz).abs();
      final nearby=w.objects.where((o)=>
        (o.position.x-ox).abs()<78&&(o.position.z-oz).abs()<78&&budgets.containsKey(o.category)
      ).toList()..sort((a,b){
        final category=(priority[a.category]??99).compareTo(priority[b.category]??99);
        return category!=0?category:objectDistance(a).compareTo(objectDistance(b));
      });
      for(final obj in nearby){
        final limit=budgets[obj.category]??0;
        if((loadedByCategory[obj.category]??0)>=limit)continue;
        final model=lib.resolve(obj.asset,['entity/${obj.category}'],uniqueFallback:true);
        if(model==null){
          final stem=baseName(obj.asset).toLowerCase().split('.').first;
          final candidates=lib.files.keys.where((p)=>baseName(p).toLowerCase().contains(stem)).take(3).toList();
          missingWorldAssets.add(
            '${obj.category}:${obj.asset}'+(candidates.isEmpty?'':' -> '+candidates.join(', ')),
          );
          continue;
        }
        if(model.toLowerCase().endsWith('.vani')){
          final bindings=<VaniBinding>[],group=t.Group();
          try{
            final vani=VaniData.parse(await lib.read(model),model);
            for(final mesh in vani.meshes){
              final requested=mesh.texture.trim();
              if(requested.isEmpty)continue;
              final dds=requested.toLowerCase().endsWith('.tga')
                ?requested.substring(0,requested.length-4)+'.dds'
                :requested;
              final tex=lib.resolve(
                dds,
                ['entity/vani','entity/vani/dds','entity/texture','entity/textures'],
                uniqueFallback:true,
              )??lib.resolve(
                requested,
                ['entity/vani','entity/vani/dds','entity/texture','entity/textures'],
                uniqueFallback:true,
              );
              if(tex==null){missingWorldAssets.add('texture:${mesh.texture} @ ${obj.asset}');continue;}
              final part=await makePart(mesh.frame(0),tex);group.add(part.mesh);bindings.add(VaniBinding(part,mesh));
            }
            if(bindings.isEmpty){missingWorldAssets.add('empty:${obj.asset}');continue;}
            final instanceMatrix=worldInstanceMatrix(obj,ox,oz);
            group.matrixAutoUpdate=false;group.matrix.copyFromArray(instanceMatrix.storage);group.matrixWorldNeedsUpdate=true;
            final actor=VaniActor(group,bindings,vani.frameCount);animated.add(actor);stage.add(group);
            loaded++;loadedByCategory[obj.category]=(loadedByCategory[obj.category]??0)+1;
            loadedWorldAssets.add('${obj.category}:${obj.asset}');
          }catch(e){
            for(final binding in bindings){binding.part.dispose();}
            missingWorldAssets.add('error:${obj.asset}:$e');report('VAni $model: $e');
          }
          if(disposed||rev!=_worldRevision){for(final p in parts){p.dispose();}for(final a in animated){a.dispose();}return;}
          continue;
        }
        if(!model.toLowerCase().endsWith('.smod')){
          missingWorldAssets.add('${obj.category}:${obj.asset}');
          continue;
        }
        try{
          final smod=readSmodData(await lib.read(model),model),group=t.Group();
          var pieceCount=0;
          for(final piece in smod.parts){
            final requested=piece.texture.trim();
            if(requested.isEmpty)continue;
            final dds=requested.toLowerCase().endsWith('.tga')
              ?requested.substring(0,requested.length-4)+'.dds'
              :requested;
            final tex=lib.resolve(
              dds,
              [
                'entity/texture',
                'entity/textures',
                'entity/${obj.category}',
                'entity/${obj.category}/texture',
                'entity/${obj.category}/textures',
              ],
              uniqueFallback:true,
            )??lib.resolve(
              requested,
              [
                'entity/texture',
                'entity/textures',
                'entity/${obj.category}',
                'entity/${obj.category}/texture',
                'entity/${obj.category}/textures',
              ],
              uniqueFallback:true,
            );
            if(tex==null){missingWorldAssets.add('texture:${piece.texture} @ ${obj.asset}');continue;}
            final p=await makePart(piece.mesh,tex);parts.add(p);group.add(p.mesh);pieceCount++;
          }
          final instanceMatrix=worldInstanceMatrix(obj,ox,oz);
          collision.addSmod(smod,instanceMatrix);
          if(pieceCount==0){missingWorldAssets.add('empty:${obj.asset}');continue;}
          group.matrixAutoUpdate=false;
          group.matrix.copyFromArray(instanceMatrix.storage);
          group.matrixWorldNeedsUpdate=true;
          stage.add(group);loaded++;loadedByCategory[obj.category]=(loadedByCategory[obj.category]??0)+1;
          loadedWorldAssets.add('${obj.category}:${obj.asset}');
        }catch(e){missingWorldAssets.add('error:${obj.asset}:$e');report('Objeto $model: $e');}
        if(disposed||rev!=_worldRevision){for(final p in parts){p.dispose();}for(final a in animated){a.dispose();}return;}
      }
      final nearbyMani=w.maniInstances.where((o)=>
        (o.position.x-ox).abs()<78&&(o.position.z-oz).abs()<78
      ).toList()..sort((a,b)=>
        ((a.position.x-ox).abs()+(a.position.z-oz).abs())
          .compareTo((b.position.x-ox).abs()+(b.position.z-oz).abs())
      );
      for(final instance in nearbyMani.take(32)){
        final model=lib.resolve(instance.buildingAsset,['entity/building'],uniqueFallback:true);
        final maniPath=lib.resolve(instance.maniAsset,['entity/mani'],uniqueFallback:true);
        if(model==null||maniPath==null){
          missingWorldAssets.add('MAni:${instance.buildingAsset} + ${instance.maniAsset}');
          continue;
        }
        final actorParts=<RenderPart>[],root=t.Group(),pivot=t.Group();
        root.add(pivot);
        try{
          final animation=ManiData.parse(await lib.read(maniPath),maniPath);
          final smod=readSmodData(await lib.read(model),model);
          for(final piece in smod.parts){
            final requested=piece.texture.trim();
            if(requested.isEmpty)continue;
            final dds=requested.toLowerCase().endsWith('.tga')
              ?requested.substring(0,requested.length-4)+'.dds'
              :requested;
            final tex=lib.resolve(
              dds,
              ['entity/texture','entity/textures','entity/building','entity/building/texture','entity/building/textures'],
              uniqueFallback:true,
            )??lib.resolve(
              requested,
              ['entity/texture','entity/textures','entity/building','entity/building/texture','entity/building/textures'],
              uniqueFallback:true,
            );
            if(tex==null){missingWorldAssets.add('mani-texture:${piece.texture} @ ${instance.buildingAsset}');continue;}
            final part=await makePart(piece.mesh,tex);actorParts.add(part);pivot.add(part.mesh);
          }
          if(actorParts.isEmpty){missingWorldAssets.add('mani-empty:${instance.buildingAsset}');continue;}
          final matrix=worldInstanceMatrix(instance.building,ox,oz);
          root.matrixAutoUpdate=false;root.matrix.copyFromArray(matrix.storage);root.matrixWorldNeedsUpdate=true;
          final actor=ManiActor(root,pivot,actorParts,animation);
          maniAnimated.add(actor);stage.add(root);
          loaded++;loadedByCategory['MAni']=(loadedByCategory['MAni']??0)+1;
          loadedWorldAssets.add('MAni:${instance.buildingAsset} + ${instance.maniAsset}');
        }catch(e){
          for(final part in actorParts){part.dispose();}
          missingWorldAssets.add('mani-error:${instance.maniAsset}:$e');report('MAni $maniPath: $e');
        }
        if(disposed||rev!=_worldRevision){
          for(final p in parts){p.dispose();}
          for(final a in animated){a.dispose();}
          for(final a in maniAnimated){a.dispose();}
          return;
        }
      }
      if(disposed||rev!=_worldRevision){for(final p in parts){p.dispose();}for(final a in animated){a.dispose();}for(final a in maniAnimated){a.dispose();}return;}
      for(final p in environmentParts){p.dispose();}
      environmentParts..clear()..addAll(parts);
      for(final a in animatedWorldActors){a.dispose();}
      animatedWorldActors..clear()..addAll(animated);
      for(final a in maniWorldActors){a.dispose();}
      maniWorldActors..clear()..addAll(maniAnimated);
      waterSurface?.dispose();waterSurface=null;
      try{waterSurface=await _buildWaterSurface(w,ox,oz,stage);}
      catch(e){report('Agua WTR: '+e.toString());}
      environment.removeFromParent();environment=stage;view!.scene.add(stage);
      worldCollision.replaceWith(collision);world=w;dungeon=null;worldPath=path;originX=ox;originZ=oz;groundY=w.heightAt(ox,oz,scale:.02,offset:-200);_applyWorldFog(w);character?.root.position.setValues(0,groundY,0);enemy?.root.position.setValues(1.8,groundY,0);distance=8;updateCamera();
      if(catalog!.skies.isNotEmpty){
        final choice=(w.skyFile.isNotEmpty?lib.resolve(w.skyFile,['sky'],uniqueFallback:true):null)
          ??lib.resolve('sky_a1.bmp',['sky'])
          ??lib.resolve('sky.bmp',['sky'])
          ??catalog!.skies.first;
        final cloud1=w.primaryCloudFile.isEmpty?null:lib.resolve(w.primaryCloudFile,['sky'],uniqueFallback:true);
        final cloud2=w.secondaryCloudFile.isEmpty?null:lib.resolve(w.secondaryCloudFile,['sky'],uniqueFallback:true);
        if(skyPath!=choice||primaryCloudPath!=cloud1||secondaryCloudPath!=cloud2){
          try{await setSky(choice,primaryCloudPath:cloud1,secondaryCloudPath:cloud2);}
          catch(e){report('Cielo/nubes: $e');}
        }
      }
      final mix=loadedByCategory.entries.map((e)=>'${e.key}=${e.value}').join(' · ');
      say('Sector de 128 × 128 m · $loaded objetos'+(mix.isEmpty?'':' · '+mix)+' · ${animatedWorldActors.length} VAni · ${maniWorldActors.length} MAni · WTR ${waterTexturePaths.length}/${waterAnimation?.textures.length??0} · agua ${waterSurface==null?'off':'render'} · ${worldCollision.triangleCount} triángulos de colisión nativos.');
    }catch(_){for(final p in parts){p.dispose();}for(final a in animated){a.dispose();}for(final a in maniAnimated){a.dispose();}rethrow;}
  }
  @override void dispose(){disposed=true;backdropTexture?.dispose();++_appearanceRevision;++_creatureRevision;++_mountRevision;++_wingRevision;++_worldRevision;++_weaponRevision;++_effectRevision;++_skyRevision;sky?.dispose();primaryCloud?.dispose();secondaryCloud?.dispose();waterSurface?.dispose();waterSurface=null;for(final a in [character,enemy,mount,wing,...gameActors]){a?.dispose();}gameActors.clear();gameLabels.clear();networkPlayerActors.clear();networkPlayerMountActors.clear();networkPlayerAnimations.clear();networkPlayerGroundY.clear();networkPlayerRiderHeight.clear();weapon?.dispose();secondWeapon?.dispose();for(final p in environmentParts){p.dispose();}for(final a in animatedWorldActors){a.dispose();}animatedWorldActors.clear();for(final a in maniWorldActors){a.dispose();}maniWorldActors.clear();effectTexture?.dispose();_audio?.dispose();_musicAudio?.dispose();_ambientAudio?.dispose();_footstepAudio?.dispose();super.dispose();}
}
int _averageTextureColor(Map<String,Object> args){
  final p=Pixels.decode(args['bytes'] as Uint8List,args['path'] as String);
  final b=p.rgba;
  if(b.isEmpty)return 0x11151e;
  var r=0,g=0,bl=0,n=0;
  final pixels=b.length~/4;
  final stride=math.max(1,pixels~/4096);
  for(var i=0;i<pixels;i+=stride){
    final k=i*4,alpha=b[k+3];
    if(alpha<8)continue;
    r+=b[k];g+=b[k+1];bl+=b[k+2];n++;
  }
  if(n==0)return 0x11151e;
  return ((r~/n)<<16)|((g~/n)<<8)|(bl~/n);
}
Uint8List _decodeBackdropTexture(Map<String,Object> args){
  final p=Pixels.decode(args['bytes'] as Uint8List,args['path'] as String);
  final row=p.width*4,out=Uint8List(p.rgba.length);
  for(var y=0;y<p.height;y++){
    out.setRange(y*row,(y+1)*row,p.rgba,(p.height-1-y)*row);
  }
  return Pixels(p.width,p.height,out).png(opaque:args['opaque'] as bool);
}
Uint8List _decodeTexture(Map<String,Object> args)=>Pixels.decode(args['bytes'] as Uint8List,args['path'] as String).png(opaque:args['opaque'] as bool);
