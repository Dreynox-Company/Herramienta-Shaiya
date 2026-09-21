export '../core/motion_catalog.dart';
import '../core/motion_catalog.dart';
import '../core/formats.dart';
import '../core/npc_quest_text.dart';
import '../core/monster_text.dart';
import '../core/db_text.dart';
import 'library.dart';
enum Slot {upper,lower,hand,foot,helmet,face,hair}
const slotLabels={Slot.upper:'Torso y hombreras',Slot.lower:'Piernas y faldones',Slot.hand:'Guantes',Slot.foot:'Botas',Slot.helmet:'Casco',Slot.face:'Rostro',Slot.hair:'Cabello'};
const raceLabels={'human':'Humanos','elf':'Elfos','vile':'Vail','deatheater':'Nordein','pandab':'Panda oscuro','pandaw':'Panda claro','pandw':'Panda claro'};
const archetypeCodes=['humf','huwf','humm','huwm','elmr','elwr','elmm','elwm','vimm','viwm','vimr','viwr','demf','dewf','demr','dewr'];
String animationLabel(String source)=>translatedMotion(source);
String setIdentity(String texture){var x=baseName(texture).toLowerCase().replaceFirst(RegExp(r'\.[^.]+$'),'');x=x.replaceFirst(RegExp(r'^(hum[fwm]*|huw[fwm]*|elm[mr]*|elw[mr]*|vim[mr]*|viw[mr]*|dem[fr]*|dew[fr]*|pd[bw][mw]f)_'),'');x=x.replaceAllMapped(RegExp(r'(^|_)(upper|torso|lower|hand|glove|foot|boots|helmet|body)(?=_|[0-9]|$)'),(m)=>m.group(1)!);return x.replaceAll(RegExp(r'_+'),'_').replaceAll(RegExp(r'^_|_$'),'');}
String displaySet(String id){var x=id;const translations={'christmass':'Navidad','christmas':'Navidad','springtime':'Primavera','wedding':'Boda','swimsuit':'Baño','magician':'Ilusionista','detective':'Detective','chinaset':'Ceremonial','dancer':'Bailarín','vampire':'Vampiro','pirate':'Pirata','medieval':'Medieval','count':'Conde','hanbok':'Hanbok','human_m_fighter':'Humano guerrero','human_f_fighter':'Humana guerrera','body':'Cuerpo'};for(final e in translations.entries){x=x.replaceAll(e.key,e.value);}return 'Conjunto ${x.replaceAll('_',' ')}';}
class PartRecord {
  final Slot slot;final MaterialRecord raw;final String meshPath,texturePath,tablePath;
  PartRecord(this.slot,this.raw,this.meshPath,this.texturePath,this.tablePath);
  String get key=>setIdentity(raw.texture);
  String get label=>'${slot==Slot.face?'Rostro':slot==Slot.hair?'Cabello':displaySet(key)} · ${raw.id}';
  bool get explicitNude=>RegExp(r'nude|naked|undress|desnudo|basebody',caseSensitive:false).hasMatch(raw.mesh);
}
class Archetype {
  final String id,race,root;final Map<Slot,List<PartRecord>> parts;final List<String> animations;
  Archetype(this.id,this.race,this.root,this.parts,this.animations);
  bool get female=>RegExp(r'^(hu|el|vi|de)w|^pd[bw]wf').hasMatch(id);
  String get label=>'${raceLabels[race]??race} · ${female?'Femenino':'Masculino'} · ${id.toUpperCase()}';
  Map<String,Map<Slot,PartRecord>> get sets{final out=<String,Map<Slot,PartRecord>>{};for(final e in parts.entries){if([Slot.face,Slot.hair].contains(e.key))continue;for(final p in e.value){out.putIfAbsent(p.key,()=>{})[e.key]=p;}}out.removeWhere((key,value)=>!value.containsKey(Slot.upper));return out;}
  PartRecord? base(Slot slot){final rows=parts[slot]??[];if(rows.isEmpty)return null;if([Slot.helmet,Slot.hair].contains(slot))return null;for(final r in rows){if(r.explicitNude)return r;}return rows.first;}
}
class Catalog {
  final Library library;final List<Archetype> archetypes=[];final List<WeaponRecord> weapons=[];
  final List<CreatureRecord> creatures=[],npcs=[],mounts=[],wings=[];
  final List<String> worlds=[],sounds=[],effects=[],skies=[],warnings=[];
  SpanishNpcQuestText? spanishText,englishText;
  final Map<int,String> monsterNames={},monsterNamesEnglish={};
  final Map<String,SkillTextRecord> skillTexts={},skillTextsEnglish={};
  final Map<String,ItemTextRecord> itemTexts={},itemTextsEnglish={};
  Catalog(this.library);
  Future<void> load(void Function(String) progress) async {
    final paths=library.files.keys.toList()..sort();
    for(final p in paths.where((p)=>RegExp(r'^character/[^/]+/[^/]+_upper\.mlt$').hasMatch(p))){
      final root=directoryName(p),id=baseName(p).replaceFirst('_upper.mlt',''),race=p.split('/')[1],parts=<Slot,List<PartRecord>>{};
      for(final slot in Slot.values){final table='$root/${id}_${slot.name}.mlt';parts[slot]=[];if(!library.files.containsKey(table))continue;
        try{for(final raw in readMlt(await library.read(table),table)){if(raw.isNull)continue;final m=library.resolve(raw.mesh,['$root/3dc',root]),t=library.resolve(raw.texture,['$root/dds',root]);if(m==null||t==null){warnings.add('$table #${raw.id}: falta ${m==null?raw.mesh:raw.texture}');continue;}parts[slot]!.add(PartRecord(slot,raw,m,t,table));}}catch(e){warnings.add(e.toString());}
      }
      if(parts[Slot.upper]!.isNotEmpty)archetypes.add(Archetype(id,race,root,parts,paths.where((p)=>p.startsWith('$root/ani/${id}_')&&p.endsWith('.ani')).toList()));progress('Leyendo arquetipos: ${archetypes.length}');
    }
    final weaponIds=<String>{};
    for(final p in paths.where((p)=>p.startsWith('item/')&&p.endsWith('.itm')&&!p.contains('.bak.'))){try{for(final w in readItm(await library.read(p),p)){final key='${w.mesh.toLowerCase()}|${w.texture.toLowerCase()}';if(!w.mesh.toLowerCase().startsWith('null.')&&weaponIds.add(key))weapons.add(w);}}catch(e){warnings.add(e.toString());}}
    for(final p in paths.where((p)=>p.endsWith('.mon')&&(p.startsWith('monster/')||p.startsWith('npc/')||p.startsWith('vehicle/')||p.startsWith('character/wing/')))){try{final entries=readMon(await library.read(p),p).where((c)=>c.parts.any((p)=>!p.isNull));if(p.startsWith('vehicle/')){mounts.addAll(entries);}else if(p.startsWith('character/wing/')){wings.addAll(entries);}else if(p.startsWith('npc/')){npcs.addAll(entries);}else{creatures.addAll(entries);}}catch(e){warnings.add(e.toString());}}
    worlds.addAll(paths.where((p)=>p.startsWith('world/')&&p.endsWith('.wld')&&!p.contains('.bak.')));
    skies.addAll(paths.where((p)=>p.startsWith('sky/')&&RegExp(r'\.(dds|tga|bmp|png)$').hasMatch(p)&&!p.contains('cloud')&&!p.contains('star')));
    sounds.addAll(paths.where((p)=>p.startsWith('sound/')&&RegExp(r'\.(wav|mp3|ogg)$').hasMatch(p)));
    effects.addAll(paths.where((p)=>p.startsWith('effect/')&&RegExp(r'\.(dds|tga|png)$').hasMatch(p)));
    final monsterTextPath=paths.where((p)=>p.endsWith('dbmonstertext_spn.sdata')).firstOrNull;
    if(monsterTextPath!=null){
      try{monsterNames.addAll(MonsterTextData.parse(await library.read(monsterTextPath,limit:16*1024*1024),monsterTextPath).names);}
      catch(e){warnings.add('DBMonsterText Spain: $e');}
    }
    final monsterUsaPath=paths.where((p)=>p.endsWith('dbmonstertext_usa.sdata')).firstOrNull;
    if(monsterUsaPath!=null){
      try{monsterNamesEnglish.addAll(MonsterTextData.parse(await library.read(monsterUsaPath,limit:16*1024*1024),monsterUsaPath).names);}
      catch(e){warnings.add('DBMonsterText USA: $e');}
    }
    final skillSpn=paths.where((p)=>p.endsWith('dbskilltext_spn.sdata')).firstOrNull;
    if(skillSpn!=null){
      try{skillTexts.addAll(BinarySDataText.skills(await library.read(skillSpn,limit:16*1024*1024),skillSpn).skills);}
      catch(e){warnings.add('DBSkillText Spain: $e');}
    }
    final skillUsa=paths.where((p)=>p.endsWith('dbskilltext_usa.sdata')).firstOrNull;
    if(skillUsa!=null){
      try{skillTextsEnglish.addAll(BinarySDataText.skills(await library.read(skillUsa,limit:16*1024*1024),skillUsa).skills);}
      catch(e){warnings.add('DBSkillText USA: $e');}
    }
    final itemSpn=paths.where((p)=>p.endsWith('dbitemtext_spn.sdata')).firstOrNull;
    if(itemSpn!=null){
      try{itemTexts.addAll(BinarySDataText.items(await library.read(itemSpn,limit:16*1024*1024),itemSpn).items);}
      catch(e){warnings.add('DBItemText Spain: $e');}
    }
    final itemUsa=paths.where((p)=>p.endsWith('dbitemtext_usa.sdata')).firstOrNull;
    if(itemUsa!=null){
      try{itemTextsEnglish.addAll(BinarySDataText.items(await library.read(itemUsa,limit:16*1024*1024),itemUsa).items);}
      catch(e){warnings.add('DBItemText USA: $e');}
    }
    final spanishPath=paths.where((p)=>p.endsWith('npcquesttrans_spain.sdata')).firstOrNull;
    if(spanishPath!=null){try{spanishText=SpanishNpcQuestText.parse(await library.read(spanishPath,limit:16*1024*1024),spanishPath);}catch(e){warnings.add('NpcQuestTrans Spain: $e');}}
    final englishPath=paths.where((p)=>p.endsWith('npcquesttrans_usa.sdata')).firstOrNull;
    if(englishPath!=null){try{englishText=SpanishNpcQuestText.parse(await library.read(englishPath,limit:16*1024*1024),englishPath);}catch(e){warnings.add('NpcQuestTrans USA: $e');}}
    if(archetypes.isEmpty)throw const FormatException('No se encontraron arquetipos MLT utilizables. Revisa el diagnóstico.');
  }
  SpanishNpcQuestText? questText(String locale)=>locale=='usa'?(englishText??spanishText):(spanishText??englishText);
  SkillTextRecord? skillText(int id,int level,String locale){
    final key='$id:$level',primary=locale=='usa'?skillTextsEnglish:skillTexts,fallback=locale=='usa'?skillTexts:skillTextsEnglish;
    return primary[key]??fallback[key]??primary['$id:1']??fallback['$id:1'];
  }
  ItemTextRecord? itemText(int type,int id,String locale){
    final key='$type:$id',primary=locale=='usa'?itemTextsEnglish:itemTexts,fallback=locale=='usa'?itemTexts:itemTextsEnglish;
    return primary[key]??fallback[key];
  }
  String skillName(int id,int level,String locale)=>skillText(id,level,locale)?.name.trim().isNotEmpty==true
    ?skillText(id,level,locale)!.name.trim()
    :(locale=='usa'?'Skill $id':'Habilidad $id');
  String itemName(int type,int id,String locale)=>itemText(type,id,locale)?.name.trim().isNotEmpty==true
    ?itemText(type,id,locale)!.name.trim()
    :(locale=='usa'?'Item $type:$id':'Objeto $type:$id');
  String monsterName(int id,String locale){
    final primary=locale=='usa'?monsterNamesEnglish:monsterNames;
    final fallback=locale=='usa'?monsterNames:monsterNamesEnglish;
    return primary[id]??fallback[id]??(locale=='usa'?'Creature $id':'Criatura $id');
  }

  String creatureLabel(CreatureRecord c){var kind=c.source.startsWith('vehicle/')?'Montura':c.source.contains('/wing/')?'Alas':'Criatura';final stem=baseName(c.parts.first.mesh).toLowerCase();if(c.source.startsWith('npc/'))kind='NPC';for(final e in {'bear':'Oso','wolf':'Lobo','dragon':'Dragón','horse':'Caballo','tiger':'Tigre','lion':'León','boar':'Jabalí','spider':'Araña','golem':'Gólem','skeleton':'Esqueleto','rabbit':'Conejo','deer':'Ciervo','unicorn':'Unicornio'}.entries){if(stem.contains(e.key))kind=e.value;}return '$kind ${c.id.toString().padLeft(3,'0')} · ${baseName(c.source).replaceFirst('.mon','')}';}
}
class Appearance {
  final Archetype archetype;final Map<Slot,PartRecord?> selected;final bool fullCostume;
  Appearance(this.archetype,Map<Slot,PartRecord?> slots,{this.fullCostume=false}):selected=Map.unmodifiable(slots);
  factory Appearance.initial(Archetype a)=>Appearance.forSet(a,a.sets.containsKey('001')?'001':a.sets.containsKey('016')?'016':a.sets.keys.first);
  factory Appearance.forSet(Archetype a,String key,{Appearance? previous}){final set=a.sets[key];if(set==null)throw FormatException('El conjunto $key no pertenece a ${a.id}.');final slots=<Slot,PartRecord?>{for(final s in Slot.values)s:null};slots.addAll(set);for(final s in [Slot.face,Slot.hair]){slots[s]=previous?.archetype.id==a.id&&previous?.archetype.race==a.race?previous!.selected[s]:((a.parts[s]??[]).isEmpty?null:a.parts[s]!.first);}return Appearance(a,slots,fullCostume:!set.containsKey(Slot.lower));}
  Appearance withPart(Slot slot,PartRecord? part){if(part!=null&&!(archetype.parts[slot]??[]).contains(part))throw const FormatException('La pieza no pertenece al arquetipo activo.');if(slot==Slot.upper&&part!=null){final set=archetype.sets[part.key];if(set!=null&&!set.containsKey(Slot.lower))return Appearance.forSet(archetype,part.key,previous:this);}if(slot==Slot.lower&&fullCostume&&part!=null)throw const FormatException('El atuendo integral ya incluye las piernas. Cambia primero el torso por una armadura modular.');return Appearance(archetype,{...selected,slot:part},fullCostume:slot==Slot.upper?false:fullCostume);}
  List<PartRecord> get effective{final out=<PartRecord>[];for(final slot in Slot.values){final p=selected[slot];if(p!=null){out.add(p);continue;}if(slot==Slot.lower&&fullCostume)continue;final fallback=archetype.base(slot);if(fallback!=null)out.add(fallback);}return out;}
}
