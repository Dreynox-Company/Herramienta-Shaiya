part of 'catalog.dart';

/// Every DDS receives a record. Non-color maps keep their material role; no
/// terrain, icon, mask or normal map is misrepresented as a wearable armor.
class TextureEntry {
  final String path, role;
  final Set<String> owners = {};
  final List<String> notes = [];
  String state;
  TextureEntry(this.path, this.role, {this.state = 'pendiente'});
  Map<String, Object> toJson() => {
    'archivo': path,
    'funcion': role,
    'estado': state,
    'referencias': owners.toList()..sort(),
    'notas': notes,
  };
}

String textureRole(String path) {
  final base = baseName(path).toLowerCase();
  if (RegExp(r'_(m|mask|n|normal|spec|s)\.dds$').hasMatch(base)) {
    return 'máscara/material auxiliar';
  }
  if (path.startsWith('terrain/')) return 'terreno';
  if (path.startsWith('sky/')) return 'cielo';
  if (path.startsWith('effect/') || path.startsWith('strip/')) return 'efecto';
  if (path.startsWith('interface/') || path.startsWith('cursor/')) {
    return 'interfaz';
  }
  if (path.startsWith('entity/')) return 'objeto de escenario';
  if (path.startsWith('item/')) return 'objeto equipable';
  if (path.startsWith('vehicle/')) return 'montura';
  if (path.startsWith('monster/')) return 'criatura';
  if (path.startsWith('npc/')) return 'personaje no jugable';
  if (path.contains('/wing/')) return 'alas';
  if (path.startsWith('character/')) return 'apariencia de personaje';
  return 'recurso independiente';
}

int stableVariantId(String value) {
  var hash = 0x811c9dc5;
  for (final b in value.codeUnits) {
    hash = ((hash ^ b) * 0x01000193) & 0x7fffffff;
  }
  return -1 - hash;
}

String _stem(String value) =>
    baseName(value).toLowerCase().replaceFirst(RegExp(r'\.[^.]+$'), '');
bool recolorOf(String candidate, String known) {
  if (!candidate.startsWith(known) || candidate == known) return false;
  final tail = candidate.substring(known.length);
  return RegExp(r'^(?:[1-9])?(?:_[a-z0-9]+)+$|^[1-9]$').hasMatch(tail);
}

Slot? _textureSlot(String name) {
  final s = name.toLowerCase();
  if (RegExp(r'(^|_)(face)\d*').hasMatch(s)) return Slot.face;
  if (RegExp(r'(^|_)(hair)\d*').hasMatch(s)) return Slot.hair;
  for (final e in {
    Slot.helmet: 'helmet|helm',
    Slot.upper: 'upper|torso|body',
    Slot.lower: 'lower|trousers|pants',
    Slot.hand: 'hand|gloves?|arm',
    Slot.foot: 'foot|boots',
  }.entries) {
    if (RegExp('(^|_)(${e.value})(?=[0-9_]|\$)').hasMatch(s)) return e.key;
  }
  return null;
}

extension TextureDiscovery on Catalog {
  Future<void> discoverTextures(void Function(String) progress) async {
    textureInventory.clear();
    final files = library.files.keys.where((p) => p.endsWith('.dds')).toList()
      ..sort();
    for (final path in files) {
      final role = textureRole(path);
      textureInventory[path] = TextureEntry(
        path,
        role,
        state: role == 'apariencia de personaje'
            ? 'pendiente de asociación'
            : 'catalogado por función',
      );
    }
    void owner(String tex, String ref) {
      final e = textureInventory[tex];
      if (e != null) {
        e.owners.add(ref);
        e.state = 'asociado';
      }
    }

    for (final a in archetypes) {
      for (final rows in a.parts.values) {
        for (final p in rows) {
          owner(p.texturePath, '${a.id}:${p.meshPath}');
        }
      }
    }
    var done = 0;
    for (final a in archetypes) {
      final prototypes = a.parts.values.expand((p) => p).toList();
      final used = prototypes.map((p) => p.texturePath).toSet();
      final prospective = files.where(
        (p) =>
            p.startsWith('${a.root}/dds/') &&
            !used.contains(p) &&
            textureRole(p) == 'apariencia de personaje',
      );
      var scanned = 0;
      for (final path in prospective) {
        if (++scanned % 24 == 0) await Future<void>.delayed(Duration.zero);
        final stem = _stem(path);
        final candidates =
            prototypes
                .where((p) => recolorOf(stem, _stem(p.raw.texture)))
                .toList()
              ..sort(
                (p, q) =>
                    _stem(q.raw.texture).length
                        .compareTo(_stem(p.raw.texture).length),
              );
        PartRecord? parent = candidates.firstOrNull;
        String? model;
        Slot? slot;
        if (parent != null) {
          model = parent.meshPath;
          slot = parent.slot;
        } else {
          final prefix = a.id.substring(0, 3);
          final matching = stem.startsWith('${a.id}_')
              ? stem
              : stem.startsWith('${prefix}_')
              ? '${a.id}_${stem.substring(prefix.length + 1)}'
              : null;
          if (matching != null) {
            model = library.resolve('$matching.3dc', ['${a.root}/3dc']);
            slot = _textureSlot(stem);
          }
        }
        if (model == null || slot == null) continue;
        try {
          final mesh = await appearanceMesh(model);
          final baseline = await appearanceMesh(a.base(Slot.upper)!.meshPath);
          if (mesh.requiredBones > baseline.inverses.length ||
              mesh.uv.length != mesh.vertices * 2 ||
              mesh.vertices == 0) {
            throw const FormatException('Malla o UV incompatible');
          }
          final bytes = await library.read(path, limit: 32 * 1024 * 1024);
          final pixels = Pixels.decode(bytes, path);
          if (pixels.width < 4 || pixels.height < 4) {
            throw const FormatException('Textura sin resolución de apariencia');
          }
          // Namespace the generated identity by the path, never by discovery order.
          final record = PartRecord(
            slot,
            MaterialRecord(
              stableVariantId('${a.id}/$path'),
              baseName(model),
              baseName(path),
              parent?.raw.alpha ??
                  (slot == Slot.face || slot == Slot.hair ? 0 : 1),
            ),
            model,
            path,
            '${a.root}/${a.id}_variantes',
            variantBaseKey: parent?.key,
            association: parent != null
                ? 'Variante del material original; malla y UV compartidas'
                : 'Malla homónima; estructura verificada',
          );
          a.parts[slot]!.add(record);
          owner(path, '${a.id}:$model');
          textureInventory[path]?.notes.add(record.association);
        } catch (e) {
          textureInventory[path]?.notes.add('$e');
        }
      }
      progress(
        'Descubriendo variantes DDS: ${++done}/${archetypes.length} cuerpos',
      );
      await Future<void>.delayed(Duration.zero);
    }
    // Companion masks refer to their color surface; they do not need a new mesh.
    for (final entry in textureInventory.values.where(
      (e) => e.role == 'máscara/material auxiliar',
    )) {
      final diffuse = entry.path.replaceFirst(
        RegExp(r'_(m|mask|n|normal|spec|s)\.dds$'),
        '.dds',
      );
      final target = textureInventory[diffuse];
      if (target != null) {
        entry.owners.addAll(target.owners);
        entry.notes.add('Mapa auxiliar de $diffuse');
        entry.state = target.owners.isEmpty
            ? 'auxiliar catalogado'
            : 'auxiliar asociado';
      }
    }
    for (final w in weapons) {
      final root = directoryName(w.source);
      final tex = library.resolve(w.texture, ['$root/dds', root]);
      if (tex != null) owner(tex, 'ITM:${w.source}#${w.id}:${w.mesh}');
    }
    for (final c in [...creatures, ...mounts, ...wings]) {
      final root = directoryName(c.source);
      for (final p in c.parts) {
        final tex = library.resolve(p.texture, ['$root/dds', root]);
        if (tex != null) owner(tex, 'MON:${c.source}#${c.id}:${p.mesh}');
      }
    }
    for (final e in textureInventory.values.where(
      (e) => e.state == 'pendiente de asociación',
    )) {
      e.notes.add(
        'Sin correspondencia UV inequívoca. Se conserva en el explorador; no se impone una malla arbitraria.',
      );
    }
  }

  /// Explicit local override used by the inspector, never an overwrite in DATA.
  Future<PartRecord> bindTexture(
    Archetype a,
    Slot slot,
    String texture,
    PartRecord prototype,
  ) async {
    if (textureRole(texture) != 'apariencia de personaje') {
      throw const FormatException(
        'Un mapa auxiliar/terreno no es una textura de atuendo.',
      );
    }
    if (!a.parts[slot]!.contains(prototype)) {
      throw const FormatException('El prototipo pertenece a otro cuerpo.');
    }
    await appearanceMesh(prototype.meshPath);
    Pixels.decode(await library.read(texture), texture);
    final record = PartRecord(
      slot,
      MaterialRecord(
        stableVariantId('${a.id}/manual/$texture'),
        prototype.raw.mesh,
        baseName(texture),
        prototype.raw.alpha,
      ),
      prototype.meshPath,
      texture,
      '${a.root}/${a.id}_manual',
      variantBaseKey: prototype.key,
      association: 'Asociación manual, inspeccionar UV',
    );
    a.parts[slot]!.removeWhere((p) => p.raw.id == record.raw.id);
    a.parts[slot]!.add(record);
    final e = textureInventory[texture];
    if (e != null) {
      e.owners.add('${a.id}:${record.meshPath}');
      e.state = 'asociación manual';
    }
    return record;
  }
}
