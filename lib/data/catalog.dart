import '../core/formats.dart';
import 'library.dart';

enum Slot {upper,lower,hand,foot,helmet,face,hair}
const slotLabels={Slot.upper:'Torso y hombreras',Slot.lower:'Piernas y faldones',Slot.hand:'Guantes',Slot.foot:'Botas',Slot.helmet:'Casco',Slot.face:'Rostro',Slot.hair:'Cabello'};
const raceLabels={'human':'Humanos','elf':'Elfos','vile':'Vail','deatheater':'Nordein','pandab':'Panda oscuro','pandaw':'Panda claro','pandw':'Panda claro'};
const archetypeCodes=['humf','huwf','humm','huwm','elmr','elwr','elmm','elwm','vimm','viwm','vimr','viwr','demf','dewf','demr','dewr'];
String animationLabel(String source) {
  final x=baseName(source).toLowerCase();
  var label='Animación';
  for(final entry in <String,String>{'normal':'Reposo','breath':'Respirar','_br':'Respirar','walk':'Caminar','_run':'Correr','jump':'Saltar','swim':'Nadar','sit':'Sentarse','idle':'Gesto de reposo','emoti':'Emoción','skill':'Habilidad','attack':'Ataque','ready':'Guardia','damage':'Daño','die':'Caída','dead':'Caída','select':'Selección','veh':'Montura'}.entries) {if(x.contains(entry.key))label=entry.value;}
  final number=RegExp(r'_(\d+)').firstMatch(x)?.group(1)??'';
  return '$label${number.isEmpty?'':' · $number'}';
}
String setIdentity(String texture) {
  var x=baseName(texture).toLowerCase().replaceFirst(RegExp(r'\.[^.]+$'),'');
  x=x.replaceFirst(RegExp(r'^(hum[fwm]*|huw[fwm]*|elm[mr]*|elw[mr]*|vim[mr]*|viw[mr]*|dem[fr]*|dew[fr]*|pdbw?f?|pdww?f?)_'),'');
  x=x.replaceAllMapped(RegExp(r'(^|_)(upper|torso|lower|hand|glove|foot|boots|helmet|body)(?=_|[0-9]|$)'),(m)=>m.group(1)!);
  return x.replaceAll(RegExp(r'_+'),'_').replaceAll(RegExp(r'^_|_$'),'');
}
String displaySet(String id) {
  var x=id;
  const translations={'christmass':'Navidad','christmas':'Navidad','springtime':'Primavera','wedding':'Boda','swimsuit':'Baño','magician':'Ilusionista','detective':'Detective','chinaset':'Ceremonial','dancer':'Bailarín','vampire':'Vampiro','pirate':'Pirata','medieval':'Medieval','count':'Conde','hanbok':'Hanbok','human_m_fighter':'Humano guerrero','human_f_fighter':'Humana guerrera','body':'Cuerpo'};
  for(final e in translations.entries) {x=x.replaceAll(e.key,e.value);}
  return 'Conjunto ${x.replaceAll('_',' ')}';
}
class PartRecord {
  final Slot slot;
  final MaterialRecord raw;
  final String meshPath,texturePath,tablePath;
  PartRecord(this.slot,this.raw,this.meshPath,this.texturePath,this.tablePath);
  String get key=>setIdentity(raw.texture);
  String get label=>'${slot==Slot.face?'Rostro':slot==Slot.hair?'Cabello':displaySet(key)} · ${raw.id}';
  bool get explicitNude=>RegExp(r'nude|naked|undress|desnudo|basebody',caseSensitive:false).hasMatch(raw.mesh);
}
class Archetype {
  final String id,race,root;
  final Map<Slot,List<PartRecord>> parts;
  final List<String> animations;
  Archetype(this.id,this.race,this.root,this.parts,this.animations);
  String get label=>'${raceLabels[race]??race} · ${id.contains('w')?'Femenino':'Masculino'} · ${id.toUpperCase()}';
  Map<String,Map<Slot,PartRecord>> get sets {
    final out=<String,Map<Slot,PartRecord>>{};
    for(final e in parts.entries) {if([Slot.face,Slot.hair].contains(e.key))continue;for(final p in e.value) {out.putIfAbsent(p.key,()=>{})[e.key]=p;}}
    out.removeWhere((key,value)=>!value.containsKey(Slot.upper));return out;
  }
  PartRecord? base(Slot slot) {
    final rows=parts[slot]??[];if(rows.isEmpty)return null;
    if([Slot.helmet,Slot.hair].contains(slot))return null;
    for(final r in rows) {if(r.explicitNude)return r;}
    // Un archivo denominado body001 puede contener una armadura completa.
    // No se presenta como desnudo ni se superpone debajo de otro conjunto.
    return rows.first;
  }
}
class Catalog {
  final Library library;
  final List<Archetype> archetypes=[];
  final List<WeaponRecord> weapons=[];
  final List<CreatureRecord> creatures=[],mounts=[],wings=[];
  final List<String> worlds=[],sounds=[],effects=[];
  final List<String> warnings=[];
  Catalog(this.library);
  Future<void> load(void Function(String) progress) async {
    final paths=library.files.keys.toList()..sort();
    for(final p in paths.where((p)=>RegExp(r'^character/[^/]+/[^/]+_upper\.mlt$').hasMatch(p))) {
      final root=directoryName(p),id=baseName(p).replaceFirst('_upper.mlt',''),race=p.split('/')[1],parts=<Slot,List<PartRecord>>{};
      for(final slot in Slot.values) {
        final table='$root/${id}_${slot.name}.mlt';parts[slot]=[];if(!library.files.containsKey(table))continue;
        try {
          for(final raw in readMlt(await library.read(table),table)) {
            if(raw.isNull)continue;
            final m=library.resolve(raw.mesh,['$root/3dc',root]),t=library.resolve(raw.texture,['$root/dds',root]);
            if(m==null||t==null) {warnings.add('$table #${raw.id}: falta ${m==null?raw.mesh:raw.texture}');continue;}
            parts[slot]!.add(PartRecord(slot,raw,m,t,table));
          }
        } catch(e) {warnings.add(e.toString());}
      }
      if(parts[Slot.upper]!.isNotEmpty)archetypes.add(Archetype(id,race,root,parts,paths.where((p)=>p.startsWith('$root/ani/${id}_')&&p.endsWith('.ani')).toList()));
      progress('Leyendo arquetipos: ${archetypes.length}');
    }
    for(final p in paths.where((p)=>p.startsWith('item/')&&p.endsWith('.itm'))) {
      try {weapons.addAll(readItm(await library.read(p),p).where((w)=>!w.mesh.toLowerCase().startsWith('null.')));}catch(e){warnings.add(e.toString());}
    }
    for(final p in paths.where((p)=>p.endsWith('.mon')&&(p.startsWith('monster/')||p.startsWith('vehicle/')||p.startsWith('character/wing/')))) {
      try {final entries=readMon(await library.read(p),p).where((c)=>c.parts.any((p)=>!p.isNull));if(p.startsWith('vehicle/')){mounts.addAll(entries);}else if(p.startsWith('character/wing/')){wings.addAll(entries);}else{creatures.addAll(entries);}}catch(e){warnings.add(e.toString());}
    }
    worlds.addAll(paths.where((p)=>p.startsWith('world/')&&p.endsWith('.wld')&&!p.contains('.bak.')));
    sounds.addAll(paths.where((p)=>p.startsWith('sound/')&&RegExp(r'\.(wav|mp3|ogg)$').hasMatch(p)));
    effects.addAll(paths.where((p)=>p.startsWith('effect/')&&RegExp(r'\.(dds|tga|png)$').hasMatch(p)));
    if(archetypes.isEmpty)throw const FormatException('No se encontraron arquetipos MLT utilizables. Revisa el diagnóstico.');
  }
  String creatureLabel(CreatureRecord c) {
    var kind=c.source.startsWith('vehicle/')?'Montura':c.source.contains('/wing/')?'Alas':'Criatura';
    final stem=baseName(c.parts.first.mesh).toLowerCase();
    for(final e in {'bear':'Oso','wolf':'Lobo','dragon':'Dragón','horse':'Caballo','tiger':'Tigre','lion':'León','boar':'Jabalí','spider':'Araña','golem':'Gólem','skeleton':'Esqueleto','rabbit':'Conejo','deer':'Ciervo','unicorn':'Unicornio'}.entries) {if(stem.contains(e.key))kind=e.value;}
    return '$kind ${c.id.toString().padLeft(3,'0')} · ${baseName(c.source).replaceFirst('.mon','')}';
  }
}

/// Es inmutable por selección; un conjunto nuevo reemplaza todos los slots,
/// incluidos los ausentes. Nunca hereda piezas del atuendo anterior.
class Appearance {
  final Archetype archetype;
  final Map<Slot,PartRecord?> selected;
  final bool fullCostume;
  Appearance(this.archetype,Map<Slot,PartRecord?> slots,{this.fullCostume=false}):selected=Map.unmodifiable(slots);
  factory Appearance.initial(Archetype a) => Appearance.forSet(a,a.sets.containsKey('016')?'016':a.sets.keys.first);
  factory Appearance.forSet(Archetype a,String key,{Appearance? previous}) {
    final set=a.sets[key];if(set==null)throw FormatException('El conjunto $key no pertenece a ${a.id}.');
    final slots=<Slot,PartRecord?>{for(final s in Slot.values)s:null};
    slots.addAll(set);
    for(final s in [Slot.face,Slot.hair]) {slots[s]=previous?.archetype.id==a.id?previous!.selected[s]:(a.parts[s]!.isEmpty?null:a.parts[s]!.first);}
    return Appearance(a,slots,fullCostume:!set.containsKey(Slot.lower));
  }
  Appearance withPart(Slot slot,PartRecord? part) {
    if(part!=null && !(archetype.parts[slot]??[]).contains(part))throw const FormatException('La pieza no pertenece al arquetipo activo.');
    return Appearance(archetype,{...selected,slot:part},fullCostume:slot==Slot.upper?false:fullCostume);
  }
  List<PartRecord> get effective {
    final out=<PartRecord>[];
    for(final slot in Slot.values) {
      final p=selected[slot];if(p!=null){out.add(p);continue;}
      if(slot==Slot.lower&&fullCostume)continue;
      final fallback=archetype.base(slot);if(fallback!=null)out.add(fallback);
    }
    return out;
  }
}
