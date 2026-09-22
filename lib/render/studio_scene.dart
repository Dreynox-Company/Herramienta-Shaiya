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
import '../core/world_collision.dart';
import '../data/library.dart';
import '../data/catalog.dart';

class RenderPart {
  final MeshData data;final t.Mesh mesh;
  final t.Float32BufferAttribute position,normal,uv;
  final t.Texture texture;
  RenderPart(this.data,this.mesh,this.position,this.normal,this.uv,this.texture);
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
  void dispose(){mesh.removeFromParent();mesh.geometry?.dispose();mesh.material?.dispose();texture.dispose();}
}

class AnimatedWorldPart {
  final RenderPart render;
  final VaniMeshData animation;
  final double fps;
  double time=0;
  int frame=-1;
  AnimatedWorldPart(this.render,this.animation,{this.fps=20});

  void tick(double dt){
    if(animation.frameCount<=1)return;
    time+=dt;
    final next=((time*fps).floor()%animation.frameCount);
    if(next==frame)return;
    frame=next;
    final p=animation.positions[next],n=animation.normals[next],u=animation.uv[next];
    for(var i=0;i<animation.vertices;i++){
      render.position.setXYZ(i,p[i*3],p[i*3+1],p[i*3+2]);
      render.normal.setXYZ(i,n[i*3],n[i*3+1],n[i*3+2]);
      render.uv.setXY(i,u[i*2],u[i*2+1]);
    }
    render.position.needsUpdate=true;
    render.normal.needsUpdate=true;
    render.uv.needsUpdate=true;
  }
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
  RenderPart? weapon,secondWeapon,sky;t.Texture? backdropTexture;WeaponRecord? weaponRecord;Attachment? weaponAttachment,secondAttachment;
  List<ClipData> attackClips=[];int attackCounter=0;
  bool running=false,touchRun=false;
  final movementTransitions=LocomotionTransitions();final Set<String> _missingMovementWarnings={};
  t.Group environment=t.Group();final List<RenderPart> environmentParts=[];
  final List<AnimatedWorldPart> animatedWorldParts=[];
  final Map<String,VaniData> _vaniCache=<String,VaniData>{};
  WorldData? world;WorldCollisionField? worldCollision;String? worldPath,effectPath,skyPath;
  final List<String> loadedWorldAssets=[];
  final List<String> missingWorldAssets=[];
  final Map<String,({double height,double forward})> _seats={};
  String lastImpact='';t.Sprite? hitSprite;t.Texture? effectTexture;double hitLife=0;
  final Combat combat=Combat();AudioPlayer? _audio;AudioPlayer get audio=>_audio??=AudioPlayer();
  AudioPlayer? _worldMusicAudio,_worldAmbientAudio;
  final Map<String,String> _audioFiles=<String,String>{};
  bool _worldAudioBusy=false;
  double _worldAudioAccumulator=0;
  String? worldMusicPath,worldAmbientPath;
  bool sound=false,wireframe=false,ready=false,disposed=false,busy=false;
  int _appearanceRevision=0,_creatureRevision=0,_mountRevision=0,_wingRevision=0,_worldRevision=0,_weaponRevision=0,_clipRevision=0,_effectRevision=0,_skyRevision=0;
  double yaw=.25,pitch=.18,distance=5.2,targetY=1.05,panX=0,panZ=0;
  double riderHeight=1.0,riderForward=0,wingHeight=1.3,wingDepth=.25,wingSize=1;
  double originX=0,originZ=0,groundY=0,walkX=0,walkZ=0,_frameAccumulator=0,_uiAccumulator=0;
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
  void say(String value){status=value;report(value);if(!disposed)notifyListeners();}
  void setGridVisible(bool value){gridVisible=value;if(grid!=null)grid!.visible=value;notifyListeners();}
  Future<RenderPart> makePart(MeshData data,String texturePath,{bool opaque=false}) async {
    final bytes=await catalog!.library.read(texturePath);final png=await compute(_decodeTexture,{'bytes':bytes,'path':texturePath,'opaque':opaque});
    // Shaiya meshes were authored for Direct3D UVs (V=0 at the top).  Do not
    // apply Three/OpenGL's image flip here; doing so maps skin/face regions to
    // the wrong polygons.  2D scene backdrops use their own loading path.
    final texture=await t.TextureLoader(flipY:false).fromBytes(png);if(texture==null)throw FormatException('El motor no pudo cargar $texturePath');
    texture.colorSpace=t.SRGBColorSpace;texture.wrapS=t.RepeatWrapping;texture.wrapT=t.RepeatWrapping;
    final geometry=t.BufferGeometry(),
      positions=t.Float32BufferAttribute.fromList(data.positions.toList(),3),
      normals=t.Float32BufferAttribute.fromList(data.normals.toList(),3),
      texcoords=t.Float32BufferAttribute.fromList(data.uv.toList(),2);
    geometry.setAttributeFromString('position',positions);geometry.setAttributeFromString('normal',normals);geometry.setAttributeFromString('uv',texcoords);geometry.setIndex(data.indices.toList());
    final material=t.MeshLambertMaterial.fromMap({'map':texture,'color':0xffffff,'side':t.DoubleSide,'alphaTest':opaque?0.0:.35,'wireframe':wireframe,'toneMapped':false});final mesh=t.Mesh(geometry,material);mesh.frustumCulled=false;return RenderPart(data,mesh,positions,normals,texcoords,texture);
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
    final cached=_audioFiles[path];
    if(cached!=null&&await File(cached).exists())return cached;
    final bytes=await catalog!.library.read(path,limit:64*1024*1024),dir=await getTemporaryDirectory();
    final safeName=baseName(path).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
    final f=File('${dir.path}/shaiya_${path.hashCode.toUnsigned(32)}_$safeName');
    if(!await f.exists()||await f.length()!=bytes.length)await f.writeAsBytes(bytes,flush:true);
    _audioFiles[path]=f.path;
    return f.path;
  }

  Future<void> playSound(String path) async {
    if(!sound||catalog==null)return;
    try{await audio.play(DeviceFileSource(await _materializeAudio(path)));}catch(e){report('Audio: $e');}
  }

  Future<void> _stopWorldAudio() async {
    worldMusicPath=null;worldAmbientPath=null;
    try{await _worldMusicAudio?.stop();}catch(_){}
    try{await _worldAmbientAudio?.stop();}catch(_){}
  }

  Future<void> _playWorldLoop(AudioPlayer player,String path) async {
    await player.stop();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(DeviceFileSource(await _materializeAudio(path)));
  }

  Future<void> _updateWorldAudio() async {
    if(_worldAudioBusy||disposed)return;
    if(!sound||catalog==null||world==null||character==null){
      if(worldMusicPath!=null||worldAmbientPath!=null)await _stopWorldAudio();
      return;
    }
    _worldAudioBusy=true;
    try{
      final w=world!,a=character!;
      final x=originX+a.root.position.x,y=a.root.position.y,z=originZ-a.root.position.z;
      WorldMusicZone? musicZone;
      for(final zone in w.musicZones){if(zone.contains(x,y,z)){musicZone=zone;break;}}
      String? nextMusic;
      if(musicZone!=null&&musicZone.soundId>=0&&musicZone.soundId<w.musicNames.length){
        final raw=w.musicNames[musicZone.soundId];
        nextMusic=catalog!.library.resolve(raw,['sound/music','sound','music'],uniqueFallback:true);
      }
      if(nextMusic!=worldMusicPath){
        worldMusicPath=nextMusic;
        _worldMusicAudio??=AudioPlayer();
        if(nextMusic==null)await _worldMusicAudio!.stop();
        else await _playWorldLoop(_worldMusicAudio!,nextMusic);
      }

      WorldSoundEffect? ambient;
      var best=double.infinity;
      for(final effect in w.soundEffects){
        if(!effect.contains(x,y,z))continue;
        final dx=x-effect.center.x,dy=y-effect.center.y,dz=z-effect.center.z;
        final d=dx*dx+dy*dy+dz*dz;
        if(d<best){best=d;ambient=effect;}
      }
      String? nextAmbient;
      if(ambient!=null&&ambient.soundId>=0&&ambient.soundId<w.soundEffectNames.length){
        final raw=w.soundEffectNames[ambient.soundId];
        nextAmbient=catalog!.library.resolve(raw,['sound','sound/effect','sound/effects'],uniqueFallback:true);
      }
      if(nextAmbient!=worldAmbientPath){
        worldAmbientPath=nextAmbient;
        _worldAmbientAudio??=AudioPlayer();
        if(nextAmbient==null)await _worldAmbientAudio!.stop();
        else await _playWorldLoop(_worldAmbientAudio!,nextAmbient);
      }
    }catch(e){
      report('Audio de mundo: $e');
    }finally{
      _worldAudioBusy=false;
    }
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
  void tick(double dt){
    if(disposed)return;_frameAccumulator+=dt;_uiAccumulator+=dt;_worldAudioAccumulator+=dt;if(_frameAccumulator<1/30)return;final delta=_frameAccumulator.clamp(0.0,.1);_frameAccumulator=0;
    if(_worldAudioAccumulator>=.75){_worldAudioAccumulator=0;unawaited(_updateWorldAudio());}
    final moving=walkX!=0||walkZ!=0;final transition=movementTransitions.update(x:walkX,z:walkZ,running:running,blocked:sceneCombatLocked);if(transition!=null)applyLocomotion(transition);final desired=movementClip(movementTransitions.requested);
    if(moving&&!sceneCombatLocked&&desired!=null&&character!=null&&(character!.clip!=desired||!character!.playing||!character!.loop))applyLocomotion(movementTransitions.requested);
    for(final a in [character,enemy,mount,wing,...gameActors]){a?.tick(delta);}
    for(final p in animatedWorldParts){p.tick(delta);}
    if(character!=null&&moving&&!sceneCombatLocked&&desired!=null&&character!.clip==desired&&character!.playing){
      final direction=cameraRelativeMovement(walkX,walkZ,yaw);
      final speed=mount!=null?(running?7.0:3.5):(running?4.0:2.0);
      final fromX=character!.root.position.x,fromZ=character!.root.position.z;
      final x=fromX+direction.x*delta*speed;
      final z=fromZ+direction.z*delta*speed;
      if(world==null||(x.abs()<72&&z.abs()<72)){
        var nextX=x,nextZ=z;
        final w=world,field=worldCollision;
        if(w!=null&&field!=null&&!field.isEmpty){
          final radius=mount==null ? .34 : .72,height=mount==null ? 1.7 : 2.3;
          final targetY=w.heightAt(originX+x,originZ-z,scale:.02,offset:-200);
          if(!field.allowsMove(
            fromX:fromX,fromY:groundY,fromZ:fromZ,
            toX:x,toY:targetY,toZ:z,radius:radius,height:height,
          )){
            final xY=w.heightAt(originX+x,originZ-fromZ,scale:.02,offset:-200);
            final zY=w.heightAt(originX+fromX,originZ-z,scale:.02,offset:-200);
            final allowX=field.allowsMove(
              fromX:fromX,fromY:groundY,fromZ:fromZ,
              toX:x,toY:xY,toZ:fromZ,radius:radius,height:height,
            );
            final allowZ=field.allowsMove(
              fromX:fromX,fromY:groundY,fromZ:fromZ,
              toX:fromX,toY:zY,toZ:z,radius:radius,height:height,
            );
            if(allowX&&!allowZ){nextZ=fromZ;}
            else if(allowZ&&!allowX){nextX=fromX;}
            else if(allowX&&allowZ){
              if((x-fromX).abs()>=(z-fromZ).abs())nextZ=fromZ;else nextX=fromX;
            }else{nextX=fromX;nextZ=fromZ;}
          }
        }
        character!.root.position.x=nextX;
        character!.root.position.z=nextZ;
        if(world!=null)groundY=world!.heightAt(originX+nextX,originZ-nextZ,scale:.02,offset:-200);
      }
      character!.root.rotation.y=math.atan2(direction.x,direction.z);
    }
    updateAttachments();combat.step(delta,enemyDistance);if(hitLife>0){hitLife-=delta;if(hitSprite!=null){hitSprite!.scale.setValues(1.5-hitLife,1.5-hitLife,1);hitSprite!.visible=hitLife>0;}}updateCamera();if(_uiAccumulator>.2){_uiAccumulator=0;notifyListeners();}
  }
  void orbit(double dx,double dy){yaw-=dx*.006;pitch=(pitch+dy*.006).clamp(-1.2,1.2);updateCamera();}
  void zoom(double amount){distance=(distance*amount).clamp(.4,250);updateCamera();}
  void updateCamera(){if(!ready||view==null)return;final a=character;final x=(a?.root.position.x??0)+panX,z=(a?.root.position.z??0)+panZ,y=groundY+targetY+(mount==null?0:riderHeight*.6);view!.camera.position.setValues(x+math.sin(yaw)*math.cos(pitch)*distance,y+math.sin(pitch)*distance,z+math.cos(yaw)*math.cos(pitch)*distance);view!.camera.lookAt(t.Vector3(x,y,z));if(sky!=null)sky!.mesh.position.setValues(view!.camera.position.x,view!.camera.position.y,view!.camera.position.z);}
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

  Future<void> setSky(String? path) async {
    final revision=++_skyRevision;
    if(path==null){
      sky?.dispose();sky=null;skyPath=null;
      if(view!=null)view!.scene.background=t.Color.fromHex32(0x11151e);
      notifyListeners();return;
    }
    final lib=catalog!.library,model=catalog!.library.resolve('sky.3do',['sky']);if(model==null)throw const FormatException('No se encuentra la cúpula original Sky/sky.3DO.');
    final skyBytes=await lib.read(path);
    final background=await compute(_averageTextureColor,{'bytes':skyBytes,'path':path});
    if(view!=null)view!.scene.background=t.Color.fromHex32(background);
    final binary=Bin(await lib.read(model),model);binary.str();final data=MeshData.rigid(binary);binary.end();final part=await makePart(data,path,opaque:true);
    if(disposed||revision!=_skyRevision){part.dispose();return;}
    var radius=0.0;for(final coordinate in data.positions){radius=math.max(radius,coordinate.abs());}if(radius<1e-6){part.dispose();throw const FormatException('Cúpula de cielo vacía.');}
    part.mesh.scale.setValues(850/radius,850/radius,-850/radius);part.mesh.renderOrder=-1000;part.mesh.material?.depthWrite=false;part.mesh.material?.depthTest=false;
    sky?.dispose();sky=part;skyPath=path;view!.scene.add(part.mesh);updateCamera();say('Cielo original: ${baseName(path)}');
  }
  Future<void> setWorld(String? path,{double? x,double? z}) async {
    final rev=++_worldRevision;
    if(path==null){loadedWorldAssets.clear();missingWorldAssets.clear();animatedWorldParts.clear();for(final p in environmentParts){p.dispose();}environmentParts.clear();environment.removeFromParent();environment=t.Group();view!.scene.add(environment);world=null;worldCollision=null;worldPath=null;groundY=0;originX=originZ=0;enemy?.root.position.y=0;unawaited(_stopWorldAudio());updateCamera();notifyListeners();return;}
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

        animatedWorldParts.clear();
        for(final p in environmentParts){p.dispose();}
        environmentParts..clear()..addAll(parts);
        environment.removeFromParent();environment=stage;view!.scene.add(stage);
        world=w;worldCollision=null;worldPath=path;originX=ox;originZ=oz;groundY=dg.floorAt(ox,oz);
        character?.root.position.setValues(0,groundY,0);
        enemy?.root.position.setValues(1.8,groundY,0);
        distance=6;updateCamera();
        view!.scene.background=t.Color.fromHex32(0x090806);
        say('Mazmorra ${w.layout} · $loaded submallas · ${dg.parts.fold<int>(0,(n,p)=>n+p.mesh.triangles)} triángulos.');
        notifyListeners();
        return;
      }catch(_){
        for(final p in parts){p.dispose();}
        rethrow;
      }
    }

    if(w.size<128)throw const FormatException('Este mapa es menor que el tamaño de sector configurado.');
    final ox=(x??w.size/2).clamp(64.0,w.size-64.0),oz=(z??w.size/2).clamp(64.0,w.size-64.0),stage=t.Group(),parts=<RenderPart>[],animated=<AnimatedWorldPart>[];
    try{
      final grouped=<int,List<double>>{},uv=<int,List<double>>{};final width=w.size~/2+1;
      for(var dz=-64;dz<64;dz+=2){for(var dx=-64;dx<64;dx+=2){final xx=ox+dx,zz=oz+dz;final type=w.types[(zz~/2)*width+xx~/2],layer=type<w.layers.length?type:0;final verts=grouped.putIfAbsent(layer,()=>[]),tex=uv.putIfAbsent(layer,()=>[]),tiling=w.layers.isEmpty?4.0:math.max(.1,w.layers[layer].tile.abs());for(final point in [[0,0],[2,0],[0,2],[2,0],[2,2],[0,2]]){final px=xx+point[0],pz=zz+point[1];verts.addAll([px-ox,w.heightAt(px,pz,scale:.02,offset:-200),-(pz-oz)]);tex.addAll([px/tiling,pz/tiling]);}}}
      for(final entry in grouped.entries){if(w.layers.isEmpty)break;final layer=w.layers[entry.key],tex=lib.resolve(w.layers[entry.key].texture,['terrain','terrain/texture','terrain/dds'],uniqueFallback:true);if(tex==null){report('Textura de terreno ausente: ${layer.texture}');continue;}final n=entry.value.length~/3,no=Float32List(n*3);for(var i=0;i<n;i++){no[i*3+1]=1;}final data=MeshData(Float32List.fromList(entry.value),no,Float32List.fromList(uv[entry.key]!),Uint16List.fromList(List.generate(n,(i)=>i)),Uint8List(0),Float32List(0),[],path);final part=await makePart(data,tex,opaque:true);parts.add(part);stage.add(part.mesh);}
      if(parts.isEmpty)throw const FormatException('No se pudo construir el terreno de este sector.');var loaded=0;
      final collisionTriangles=<WorldCollisionTriangle>[];
      final nearby=w.objects.where((o)=>(o.position.x-ox).abs()<82&&(o.position.z-oz).abs()<82).toList()..sort((a,b)=>((a.position.x-ox).abs()+(a.position.z-oz).abs()).compareTo((b.position.x-ox).abs()+(b.position.z-oz).abs()));
      for(final obj in nearby){
        final roots=switch(obj.category){
          'dungeon'=><String>['world/dungeon'],
          'VAni'=><String>['entity/VAni'],
          _=><String>['entity/${obj.category}'],
        };
        final model=lib.resolve(obj.asset,roots);
        if(model==null){
          missingWorldAssets.add('${obj.category}:${obj.asset}');
          continue;
        }
        try{
          final lowerModel=model.toLowerCase(),group=t.Group();
          final instanceMatrix=worldInstanceMatrix(obj,ox,oz);
          var pieceCount=0;
          if(lowerModel.endsWith('.smod')){
            final smod=readSmodData(await lib.read(model),model),objects=smod.parts;
            collisionTriangles.addAll(transformSmodCollisions(smod.collisions,instanceMatrix));
            for(final piece in objects){
              final requested=piece.texture.trim();
              if(requested.isEmpty)continue;
              final dds=requested.toLowerCase().endsWith('.tga')
                ?requested.substring(0,requested.length-4)+'.dds'
                :requested;
              final tex=lib.resolve(
                dds,
                [
                  'entity/texture','entity/textures','entity/${obj.category}',
                  'entity/${obj.category}/texture','entity/${obj.category}/textures',
                ],
                uniqueFallback:true,
              )??lib.resolve(
                requested,
                [
                  'entity/texture','entity/textures','entity/${obj.category}',
                  'entity/${obj.category}/texture','entity/${obj.category}/textures',
                ],
                uniqueFallback:true,
              );
              if(tex==null){missingWorldAssets.add('texture:${piece.texture} @ ${obj.asset}');continue;}
              final p=await makePart(piece.mesh,tex);parts.add(p);group.add(p.mesh);pieceCount++;
            }
          }else if(lowerModel.endsWith('.vani')){
            final vani=_vaniCache[model]??=readVani(await lib.read(model),model);
            for(final mesh in vani.meshes){
              final requested=mesh.texture.trim();
              if(requested.isEmpty)continue;
              final dds=requested.toLowerCase().endsWith('.tga')
                ?requested.substring(0,requested.length-4)+'.dds'
                :requested;
              final tex=lib.resolve(
                dds,
                ['entity/VAni','entity/VAni/texture','entity/texture','entity/textures'],
                uniqueFallback:true,
              )??lib.resolve(
                requested,
                ['entity/VAni','entity/VAni/texture','entity/texture','entity/textures'],
                uniqueFallback:true,
              );
              if(tex==null){missingWorldAssets.add('vani-texture:$requested @ ${obj.asset}');continue;}
              final p=await makePart(mesh.frame(0,model),tex);
              parts.add(p);group.add(p.mesh);animated.add(AnimatedWorldPart(p,mesh));pieceCount++;
            }
          }else{
            missingWorldAssets.add('unsupported:${obj.category}:${obj.asset}');
            continue;
          }
          if(pieceCount==0){missingWorldAssets.add('empty:${obj.asset}');continue;}
          group.matrixAutoUpdate=false;
          group.matrix.copyFromArray(instanceMatrix.storage);
          group.matrixWorldNeedsUpdate=true;
          stage.add(group);loaded++;loadedWorldAssets.add('${obj.category}:${obj.asset}');
        }catch(e){missingWorldAssets.add('error:${obj.asset}:$e');report('Objeto $model: $e');}
        if(disposed||rev!=_worldRevision){for(final p in parts){p.dispose();}return;}
      }
      if(disposed||rev!=_worldRevision){for(final p in parts){p.dispose();}return;}
      animatedWorldParts..clear()..addAll(animated);for(final p in environmentParts){p.dispose();}environmentParts..clear()..addAll(parts);environment.removeFromParent();environment=stage;view!.scene.add(stage);world=w;worldCollision=WorldCollisionField(collisionTriangles);worldPath=path;originX=ox;originZ=oz;groundY=w.heightAt(ox,oz,scale:.02,offset:-200);character?.root.position.setValues(0,groundY,0);enemy?.root.position.setValues(1.8,groundY,0);distance=8;updateCamera();
      if(sky==null&&catalog!.skies.isNotEmpty){
        final choice=(w.skyFile.isNotEmpty?lib.resolve(w.skyFile,['sky'],uniqueFallback:true):null)
          ??lib.resolve('sky_a1.bmp',['sky'])
          ??lib.resolve('sky.bmp',['sky'])
          ??catalog!.skies.first;
        try{await setSky(choice);}catch(e){report('Cielo: $e');}
      }
      say('Sector de 128 × 128 m · $loaded objetos · altura original · ${worldCollision?.triangles.length??0} triángulos de colisión SMOD.');
    }catch(_){for(final p in parts){p.dispose();}rethrow;}
  }
  @override void dispose(){disposed=true;animatedWorldParts.clear();_vaniCache.clear();backdropTexture?.dispose();++_appearanceRevision;++_creatureRevision;++_mountRevision;++_wingRevision;++_worldRevision;++_weaponRevision;++_effectRevision;++_skyRevision;sky?.dispose();for(final a in [character,enemy,mount,wing,...gameActors]){a?.dispose();}gameActors.clear();gameLabels.clear();networkPlayerActors.clear();networkPlayerMountActors.clear();networkPlayerAnimations.clear();networkPlayerGroundY.clear();networkPlayerRiderHeight.clear();weapon?.dispose();secondWeapon?.dispose();for(final p in environmentParts){p.dispose();}effectTexture?.dispose();_audio?.dispose();_worldMusicAudio?.dispose();_worldAmbientAudio?.dispose();super.dispose();}
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
