import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

enum RenderEntityKind { player, npc, mob, item }

final class RenderEntity {
  final int id;
  final RenderEntityKind kind;
  final double x;
  final double y;
  final double z;
  final double yaw;
  final int animation;

  const RenderEntity({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.z,
    required this.yaw,
    this.animation = 0,
  });

  RenderEntity copyWith({
    double? x,
    double? y,
    double? z,
    double? yaw,
    int? animation,
  }) =>
      RenderEntity(
        id: id,
        kind: kind,
        x: x ?? this.x,
        y: y ?? this.y,
        z: z ?? this.z,
        yaw: yaw ?? this.yaw,
        animation: animation ?? this.animation,
      );
}

sealed class LogicCommand {
  const LogicCommand();
}

final class LogicUpsertEntity extends LogicCommand {
  final RenderEntity entity;
  const LogicUpsertEntity(this.entity);
}

final class LogicRemoveEntity extends LogicCommand {
  final int id;
  const LogicRemoveEntity(this.id);
}

final class LogicVelocity extends LogicCommand {
  final int id;
  final double vx;
  final double vy;
  final double vz;

  const LogicVelocity(this.id, this.vx, this.vy, this.vz);
}

/// Packet data is transferred without copying its backing bytes.
///
/// The UI/network layer only performs socket/session framing. Packet decoding,
/// interpolation and entity state mutation happen in the logic isolate.
final class LogicNetworkPacket extends LogicCommand {
  final int type;
  final TransferableTypedData body;

  LogicNetworkPacket(int type, Uint8List bytes)
      : type = type,
        body = TransferableTypedData.fromList(<Uint8List>[bytes]);
}

final class LogicStop extends LogicCommand {
  const LogicStop();
}

final class _LogicBootstrap {
  final SendPort uiPort;
  final int tickHz;

  const _LogicBootstrap(this.uiPort, this.tickHz);
}

/// Fixed-step MMO simulation worker.
///
/// Design rule: no Flutter widgets, textures, meshes or GPU objects cross the
/// isolate boundary. The renderer receives only transformed RenderEntity DTOs.
final class ShaiyaLogicIsolate {
  final ReceivePort _receivePort = ReceivePort();
  Isolate? _isolate;
  SendPort? _commands;
  StreamController<List<RenderEntity>>? _snapshots;

  Stream<List<RenderEntity>> get snapshots =>
      (_snapshots ??= StreamController<List<RenderEntity>>.broadcast(
        sync: true,
      )).stream;

  Future<void> start({int tickHz = 60}) async {
    if (_isolate != null) return;
    final ready = Completer<void>();
    _receivePort.listen((Object? message) {
      if (message is SendPort) {
        _commands = message;
        if (!ready.isCompleted) ready.complete();
        return;
      }
      if (message is List<RenderEntity>) {
        _snapshots?.add(message);
      }
    });
    _isolate = await Isolate.spawn<_LogicBootstrap>(
      _logicMain,
      _LogicBootstrap(_receivePort.sendPort, tickHz.clamp(20, 120)),
      debugName: 'shaiya_logic',
    );
    await ready.future.timeout(const Duration(seconds: 3));
  }

  void upsert(RenderEntity entity) =>
      _commands?.send(LogicUpsertEntity(entity));

  void remove(int id) => _commands?.send(LogicRemoveEntity(id));

  void setVelocity(int id, double vx, double vy, double vz) =>
      _commands?.send(LogicVelocity(id, vx, vy, vz));

  void packet(int type, Uint8List body) =>
      _commands?.send(LogicNetworkPacket(type, body));

  Future<void> dispose() async {
    _commands?.send(const LogicStop());
    _commands = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _receivePort.close();
    await _snapshots?.close();
  }
}

final class _SimEntity {
  RenderEntity render;
  double vx = 0;
  double vy = 0;
  double vz = 0;

  _SimEntity(this.render);
}

void _logicMain(_LogicBootstrap bootstrap) {
  final input = ReceivePort();
  bootstrap.uiPort.send(input.sendPort);

  final entities = <int, _SimEntity>{};
  var running = true;
  var previousMicros = DateTime.now().microsecondsSinceEpoch;
  final targetMicros = (1000000 / bootstrap.tickHz).round();

  input.listen((Object? message) {
    switch (message) {
      case LogicUpsertEntity(:final entity):
        entities[entity.id] = _SimEntity(entity);
      case LogicRemoveEntity(:final id):
        entities.remove(id);
      case LogicVelocity(:final id, :final vx, :final vy, :final vz):
        final entity = entities[id];
        if (entity != null) {
          entity
            ..vx = vx
            ..vy = vy
            ..vz = vz;
        }
      case LogicNetworkPacket(:final type, :final body):
        _applyPacket(entities, type, body.materialize().asUint8List());
      case LogicStop():
        running = false;
        input.close();
    }
  });

  Timer.periodic(Duration(microseconds: targetMicros), (timer) {
    if (!running) {
      timer.cancel();
      return;
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = ((now - previousMicros) / 1000000.0).clamp(0.0, .05);
    previousMicros = now;

    for (final entity in entities.values) {
      if (entity.vx == 0 && entity.vy == 0 && entity.vz == 0) continue;
      final current = entity.render;
      entity.render = current.copyWith(
        x: current.x + entity.vx * dt,
        y: current.y + entity.vy * dt,
        z: current.z + entity.vz * dt,
      );
    }

    // One immutable snapshot per fixed tick. The GPU/UI thread performs no
    // packet parsing or physics work.
    bootstrap.uiPort.send(
      List<RenderEntity>.unmodifiable(
        entities.values.map((entity) => entity.render),
      ),
    );
  });
}

void _applyPacket(
  Map<int, _SimEntity> entities,
  int type,
  Uint8List body,
) {
  final data = ByteData.sublistView(body);

  // MAP_NPC_ENTER: globalId u32, type u8, typeId i16, x/y/z f32, angle u16.
  if (type == 0x0E01 && body.length >= 21) {
    final id = data.getUint32(0, Endian.little);
    entities[id] = _SimEntity(
      RenderEntity(
        id: id,
        kind: RenderEntityKind.npc,
        x: data.getFloat32(7, Endian.little),
        y: data.getFloat32(11, Endian.little),
        z: data.getFloat32(15, Endian.little),
        yaw: data.getUint16(19, Endian.little) * 0.00009587379924285257,
      ),
    );
    return;
  }

  // MOB_ENTER is decoded by the authoritative World session today. Keep raw
  // packet work in this isolate by accepting the normalized entity command
  // until every EP8 packet layout has a verified decoder here.
  if ((type == 0x0E02 || type == 0x0602) && body.length >= 4) {
    entities.remove(data.getUint32(0, Endian.little));
  }
}
