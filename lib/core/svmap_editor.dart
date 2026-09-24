import 'dart:typed_data';

import 'formats.dart';

class SvmapVectorField {
  final int xOffset, yOffset, zOffset;
  double x, y, z;

  SvmapVectorField(
    this.xOffset,
    this.yOffset,
    this.zOffset,
    this.x,
    this.y,
    this.z,
  );

  List<double> get values => [x, y, z];
}

class SvmapMobSpawnEdit {
  final int idOffset, countOffset;
  int id, count;
  SvmapMobSpawnEdit(this.idOffset, this.countOffset, this.id, this.count);
}

class SvmapMobAreaEdit {
  final SvmapVectorField lower, upper;
  final List<SvmapMobSpawnEdit> mobs;
  SvmapMobAreaEdit(this.lower, this.upper, this.mobs);
}

class SvmapNpcWaypointEdit {
  final SvmapVectorField position;
  final int yawOffset;
  double yaw;
  SvmapNpcWaypointEdit(this.position, this.yawOffset, this.yaw);
}

class SvmapNpcEdit {
  final int typeOffset, idOffset;
  int type, id;
  final List<SvmapNpcWaypointEdit> route;
  SvmapNpcEdit(
    this.typeOffset,
    this.idOffset,
    this.type,
    this.id,
    this.route,
  );
}

class SvmapPortalEdit {
  final SvmapVectorField position, target;
  final int factionOrIdOffset,
      minLevelOffset,
      maxLevelOffset,
      targetMapOffset;
  int factionOrId, minLevel, maxLevel, targetMap;

  SvmapPortalEdit(
    this.position,
    this.target,
    this.factionOrIdOffset,
    this.minLevelOffset,
    this.maxLevelOffset,
    this.targetMapOffset,
    this.factionOrId,
    this.minLevel,
    this.maxLevel,
    this.targetMap,
  );
}

class SvmapSpawnEdit {
  final int factionOffset;
  int faction;
  final SvmapVectorField lower, upper;

  SvmapSpawnEdit(this.factionOffset, this.faction, this.lower, this.upper);
}

class SvmapNamedAreaEdit {
  final SvmapVectorField lower, upper;
  final int name1Offset, name2Offset;
  int name1, name2;

  SvmapNamedAreaEdit(
    this.lower,
    this.upper,
    this.name1Offset,
    this.name2Offset,
    this.name1,
    this.name2,
  );
}

/// Fixed-width, lossless SVMAP editor.
///
/// The original bytes remain authoritative. Studio only overwrites numeric
/// fields whose offsets are proven by the parser. Navigation mask, ladder data,
/// spawn unknown integers and any trailing bytes remain byte-for-byte intact.
class SvmapEditorDocument {
  static const int maxBytes = 64 * 1024 * 1024;

  final String path;
  final Uint8List _bytes;
  final int mapSize, cellSize, ladderCount, tailBytes;
  final List<SvmapMobAreaEdit> mobAreas;
  final List<SvmapNpcEdit> npcs;
  final List<SvmapPortalEdit> portals;
  final List<SvmapSpawnEdit> spawns;
  final List<SvmapNamedAreaEdit> namedAreas;

  SvmapEditorDocument._(
    this.path,
    this._bytes,
    this.mapSize,
    this.cellSize,
    this.ladderCount,
    this.tailBytes,
    this.mobAreas,
    this.npcs,
    this.portals,
    this.spawns,
    this.namedAreas,
  );

  static SvmapEditorDocument parse(Uint8List source, String path) {
    if (source.isEmpty || source.length > maxBytes) {
      throw FormatException('$path: SVMAP vacío o mayor de 64 MiB.');
    }
    final bytes = Uint8List.fromList(source);
    final r = _SvCursor(bytes, path);

    final mapSize = r.i32();
    if (mapSize <= 0 || mapSize > 16384) {
      r.fail('Tamaño SVMAP inválido: $mapSize.');
    }
    final maskBytes = (mapSize * mapSize) ~/ 8;
    r.skip(maskBytes);

    final cellSize = r.i32();
    if (cellSize <= 0 || cellSize > 1 << 20) {
      r.fail('CellSize SVMAP inválido: $cellSize.');
    }

    final ladderCount = r.count(100000);
    r.skip(ladderCount * 12);

    final mobAreas = <SvmapMobAreaEdit>[];
    final areaCount = r.count(100000);
    for (var i = 0; i < areaCount; i++) {
      final lower = r.vector();
      final upper = r.vector();
      final mobs = <SvmapMobSpawnEdit>[];
      final count = r.count(10000);
      for (var j = 0; j < count; j++) {
        final idOffset = r.offset;
        final id = r.u32();
        final countOffset = r.offset;
        final amount = r.u32();
        mobs.add(SvmapMobSpawnEdit(idOffset, countOffset, id, amount));
      }
      mobAreas.add(SvmapMobAreaEdit(lower, upper, mobs));
    }

    final npcs = <SvmapNpcEdit>[];
    final npcGroups = r.count(100000);
    for (var i = 0; i < npcGroups; i++) {
      final typeOffset = r.offset;
      final type = r.i32();
      final idOffset = r.offset;
      final id = r.i32();
      final routeCount = r.count(10000);
      final route = <SvmapNpcWaypointEdit>[];
      for (var j = 0; j < routeCount; j++) {
        final position = r.vector();
        final yawOffset = r.offset;
        final yaw = r.f32();
        route.add(SvmapNpcWaypointEdit(position, yawOffset, yaw));
      }
      npcs.add(SvmapNpcEdit(typeOffset, idOffset, type, id, route));
    }

    final portals = <SvmapPortalEdit>[];
    final portalCount = r.count(100000);
    for (var i = 0; i < portalCount; i++) {
      final position = r.vector();
      final factionOffset = r.offset;
      final factionOrId = r.i32();
      final minOffset = r.offset;
      final minLevel = r.u16();
      final maxOffset = r.offset;
      final maxLevel = r.u16();
      final targetMapOffset = r.offset;
      final targetMap = r.u32();
      final target = r.vector();
      portals.add(
        SvmapPortalEdit(
          position,
          target,
          factionOffset,
          minOffset,
          maxOffset,
          targetMapOffset,
          factionOrId,
          minLevel,
          maxLevel,
          targetMap,
        ),
      );
    }

    final spawns = <SvmapSpawnEdit>[];
    final spawnCount = r.count(100000);
    for (var i = 0; i < spawnCount; i++) {
      r.i32(); // unknown and intentionally preserved
      final factionOffset = r.offset;
      final faction = r.i32();
      r.i32(); // unknown and intentionally preserved
      final lower = r.vector();
      final upper = r.vector();
      spawns.add(SvmapSpawnEdit(factionOffset, faction, lower, upper));
    }

    final named = <SvmapNamedAreaEdit>[];
    final namedCount = r.count(100000);
    for (var i = 0; i < namedCount; i++) {
      final lower = r.vector();
      final upper = r.vector();
      final name1Offset = r.offset;
      final name1 = r.i32();
      final name2Offset = r.offset;
      final name2 = r.i32();
      named.add(
        SvmapNamedAreaEdit(
          lower,
          upper,
          name1Offset,
          name2Offset,
          name1,
          name2,
        ),
      );
    }

    final tailBytes = bytes.length - r.offset;
    if (tailBytes < 0) r.fail('SVMAP truncado.');

    // Cross-check the established semantic reader before exposing editing.
    SvmapData.parse(bytes, path);

    return SvmapEditorDocument._(
      path,
      bytes,
      mapSize,
      cellSize,
      ladderCount,
      tailBytes,
      List.unmodifiable(mobAreas),
      List.unmodifiable(npcs),
      List.unmodifiable(portals),
      List.unmodifiable(spawns),
      List.unmodifiable(named),
    );
  }

  Uint8List encode() => Uint8List.fromList(_bytes);

  void validateEncoded(Uint8List bytes) {
    final parsed = SvmapEditorDocument.parse(bytes, path);
    if (parsed.mapSize != mapSize ||
        parsed.cellSize != cellSize ||
        parsed.ladderCount != ladderCount ||
        parsed.mobAreas.length != mobAreas.length ||
        parsed.npcs.length != npcs.length ||
        parsed.portals.length != portals.length ||
        parsed.spawns.length != spawns.length ||
        parsed.namedAreas.length != namedAreas.length ||
        parsed.tailBytes != tailBytes) {
      throw FormatException('$path: la edición alteró la topología SVMAP.');
    }
    for (var i = 0; i < mobAreas.length; i++) {
      if (parsed.mobAreas[i].mobs.length != mobAreas[i].mobs.length) {
        throw FormatException('$path: cambió la lista de mobs del área $i.');
      }
    }
    for (var i = 0; i < npcs.length; i++) {
      if (parsed.npcs[i].route.length != npcs[i].route.length) {
        throw FormatException('$path: cambió la ruta del NPC $i.');
      }
    }
  }

  void setMobAreaBounds(
    int area, {
    List<double>? lower,
    List<double>? upper,
  }) {
    final value = _at(mobAreas, area, 'área de mobs');
    if (lower != null) _setVector(value.lower, lower);
    if (upper != null) _setVector(value.upper, upper);
  }

  void setMobSpawn(
    int area,
    int mob, {
    int? id,
    int? count,
  }) {
    final value = _at(_at(mobAreas, area, 'área de mobs').mobs, mob, 'mob');
    if (id != null) {
      _u32(value.idOffset, id, 'MonsterID');
      value.id = id;
    }
    if (count != null) {
      _u32(value.countOffset, count, 'cantidad de mobs');
      value.count = count;
    }
  }

  void setNpcIdentity(int index, {int? type, int? id}) {
    final value = _at(npcs, index, 'NPC');
    if (type != null) {
      _i32(value.typeOffset, type, 'tipo NPC');
      value.type = type;
    }
    if (id != null) {
      _i32(value.idOffset, id, 'ID NPC');
      value.id = id;
    }
  }

  void setNpcWaypoint(
    int npc,
    int waypoint, {
    List<double>? position,
    double? yaw,
  }) {
    final value = _at(_at(npcs, npc, 'NPC').route, waypoint, 'waypoint');
    if (position != null) _setVector(value.position, position);
    if (yaw != null) {
      _float(value.yawOffset, yaw, 'yaw NPC');
      value.yaw = yaw;
    }
  }

  void setPortal(
    int index, {
    List<double>? position,
    int? factionOrId,
    int? minLevel,
    int? maxLevel,
    int? targetMap,
    List<double>? target,
  }) {
    final value = _at(portals, index, 'portal');
    if (position != null) _setVector(value.position, position);
    if (factionOrId != null) {
      _i32(value.factionOrIdOffset, factionOrId, 'facción/ID portal');
      value.factionOrId = factionOrId;
    }
    if (minLevel != null) {
      _u16(value.minLevelOffset, minLevel, 'nivel mínimo');
      value.minLevel = minLevel;
    }
    if (maxLevel != null) {
      _u16(value.maxLevelOffset, maxLevel, 'nivel máximo');
      value.maxLevel = maxLevel;
    }
    if (targetMap != null) {
      _u32(value.targetMapOffset, targetMap, 'mapa destino');
      value.targetMap = targetMap;
    }
    if (target != null) _setVector(value.target, target);
  }

  void setSpawn(
    int index, {
    int? faction,
    List<double>? lower,
    List<double>? upper,
  }) {
    final value = _at(spawns, index, 'spawn');
    if (faction != null) {
      _i32(value.factionOffset, faction, 'facción spawn');
      value.faction = faction;
    }
    if (lower != null) _setVector(value.lower, lower);
    if (upper != null) _setVector(value.upper, upper);
  }

  void setNamedArea(
    int index, {
    List<double>? lower,
    List<double>? upper,
    int? name1,
    int? name2,
  }) {
    final value = _at(namedAreas, index, 'área con nombre');
    if (lower != null) _setVector(value.lower, lower);
    if (upper != null) _setVector(value.upper, upper);
    if (name1 != null) {
      _i32(value.name1Offset, name1, 'Name1');
      value.name1 = name1;
    }
    if (name2 != null) {
      _i32(value.name2Offset, name2, 'Name2');
      value.name2 = name2;
    }
  }

  T _at<T>(List<T> values, int index, String label) {
    if (index < 0 || index >= values.length) {
      throw FormatException('$path: $label fuera de rango: $index.');
    }
    return values[index];
  }

  void _setVector(SvmapVectorField field, List<double> values) {
    if (values.length != 3) {
      throw const FormatException('Una posición SVMAP requiere X/Y/Z.');
    }
    _float(field.xOffset, values[0], 'X');
    _float(field.yOffset, values[1], 'Y');
    _float(field.zOffset, values[2], 'Z');
    field
      ..x = values[0]
      ..y = values[1]
      ..z = values[2];
  }

  ByteData get _data => ByteData.sublistView(_bytes);

  void _float(int offset, double value, String label) {
    if (!value.isFinite || value.abs() > 100000000) {
      throw FormatException('$path: $label no es un float SVMAP válido.');
    }
    _data.setFloat32(offset, value, Endian.little);
  }

  void _i32(int offset, int value, String label) {
    if (value < -0x80000000 || value > 0x7fffffff) {
      throw FormatException('$path: $label fuera de int32.');
    }
    _data.setInt32(offset, value, Endian.little);
  }

  void _u32(int offset, int value, String label) {
    if (value < 0 || value > 0xffffffff) {
      throw FormatException('$path: $label fuera de uint32.');
    }
    _data.setUint32(offset, value, Endian.little);
  }

  void _u16(int offset, int value, String label) {
    if (value < 0 || value > 0xffff) {
      throw FormatException('$path: $label fuera de uint16.');
    }
    _data.setUint16(offset, value, Endian.little);
  }
}

class _SvCursor {
  final Uint8List bytes;
  late final ByteData data = ByteData.sublistView(bytes);
  final String path;
  int offset = 0;

  _SvCursor(this.bytes, this.path);

  Never fail(String message) =>
      throw FormatException('$path · byte $offset: $message');

  void need(int count) {
    if (count < 0 || offset + count > bytes.length) {
      fail('Archivo truncado ($count bytes).');
    }
  }

  void skip(int count) {
    need(count);
    offset += count;
  }

  int i32() {
    need(4);
    final value = data.getInt32(offset, Endian.little);
    offset += 4;
    return value;
  }

  int u32() {
    need(4);
    final value = data.getUint32(offset, Endian.little);
    offset += 4;
    return value;
  }

  int u16() {
    need(2);
    final value = data.getUint16(offset, Endian.little);
    offset += 2;
    return value;
  }

  double f32() {
    need(4);
    final value = data.getFloat32(offset, Endian.little);
    offset += 4;
    if (!value.isFinite) fail('Float no finito.');
    return value;
  }

  int count(int max) {
    final value = u32();
    if (value > max) fail('Recuento fuera de límite: $value.');
    return value;
  }

  SvmapVectorField vector() {
    final xOffset = offset;
    final x = f32();
    final yOffset = offset;
    final y = f32();
    final zOffset = offset;
    final z = f32();
    return SvmapVectorField(xOffset, yOffset, zOffset, x, y, z);
  }
}
