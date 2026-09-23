import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Binary layout sent from [NetworkAndLogicIsolate] to the render isolate.
///
/// No entity objects, maps, JSON, Flutter objects, meshes or textures cross the
/// isolate boundary. The render loop receives two tightly packed arrays:
///
/// floats (8 values/entity):
///   0 x, 1 y, 2 z, 3 yaw, 4 scaleX, 5 scaleY, 6 scaleZ, 7 lerpAlpha
///
/// ints (4 values/entity):
///   0 id, 1 kind, 2 animation/state, 3 flags
final class BinaryRenderSnapshot {
  static const int floatStride = 8;
  static const int intStride = 4;

  final int sequence;
  final int count;
  final Float32List transforms;
  final Int32List metadata;

  const BinaryRenderSnapshot({
    required this.sequence,
    required this.count,
    required this.transforms,
    required this.metadata,
  });

  double x(int index) => transforms[index * floatStride];
  double y(int index) => transforms[index * floatStride + 1];
  double z(int index) => transforms[index * floatStride + 2];
  double yaw(int index) => transforms[index * floatStride + 3];
  int id(int index) => metadata[index * intStride];
  int kind(int index) => metadata[index * intStride + 1];
  int animation(int index) => metadata[index * intStride + 2];
  int flags(int index) => metadata[index * intStride + 3];
}

enum RenderEntityKind { player, npc, mob, item }

sealed class LogicCommand {
  const LogicCommand();
}

final class LogicUpsertEntity extends LogicCommand {
  final int id;
  final RenderEntityKind kind;
  final double x;
  final double y;
  final double z;
  final double yaw;
  final int animation;
  final int flags;

  const LogicUpsertEntity({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.z,
    required this.yaw,
    this.animation = 0,
    this.flags = 0,
  });
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

/// Raw ps0032 body transferred without copying the underlying byte storage.
final class LogicNetworkPacket extends LogicCommand {
  final int type;
  final TransferableTypedData body;

  LogicNetworkPacket(int type, Uint8List bytes)
      : type = type,
        body = TransferableTypedData.fromList(<Uint8List>[bytes]);
}

/// Deterministic stress fixture used by performance/QA runs. It exercises the
/// same entity path as real network packets without touching the UI isolate.
final class LogicSimulateWorld extends LogicCommand {
  final int entityCount;
  final int seed;

  const LogicSimulateWorld({
    this.entityCount = 256,
    this.seed = 1337,
  });
}

final class LogicStop extends LogicCommand {
  const LogicStop();
}

final class _LogicBootstrap {
  final SendPort renderPort;
  final int tickHz;

  const _LogicBootstrap(this.renderPort, this.tickHz);
}

final class _SimEntity {
  final int id;
  final RenderEntityKind kind;
  double x;
  double y;
  double z;
  double yaw;
  double vx;
  double vy;
  double vz;
  double scaleX;
  double scaleY;
  double scaleZ;
  int animation;
  int flags;

  _SimEntity({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.z,
    required this.yaw,
    this.vx = 0,
    this.vy = 0,
    this.vz = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.scaleZ = 1,
    this.animation = 0,
    this.flags = 0,
  });
}

/// Fixed-step network + MMORPG logic worker.
///
/// The main Flutter isolate is deliberately kept out of packet parsing,
/// interpolation, movement integration and entity bookkeeping. Its only jobs
/// are:
/// 1. receive [BinaryRenderSnapshot] data,
/// 2. frustum-cull/batch the visible records,
/// 3. encode GPU commands.
final class NetworkAndLogicIsolate {
  final ReceivePort _receivePort = ReceivePort();
  final StreamController<BinaryRenderSnapshot> _snapshots =
      StreamController<BinaryRenderSnapshot>.broadcast(sync: true);

  Isolate? _isolate;
  SendPort? _commands;
  StreamSubscription<Object?>? _subscription;

  Stream<BinaryRenderSnapshot> get snapshots => _snapshots.stream;

  Future<void> start({int tickHz = 60}) async {
    if (_isolate != null) return;

    final ready = Completer<void>();
    _subscription = _receivePort.listen((Object? message) {
      if (message is SendPort) {
        _commands = message;
        if (!ready.isCompleted) ready.complete();
        return;
      }

      if (message is! List<Object?> || message.length != 4) return;
      final sequence = message[0];
      final count = message[1];
      final floatData = message[2];
      final intData = message[3];
      if (sequence is! int ||
          count is! int ||
          floatData is! TransferableTypedData ||
          intData is! TransferableTypedData) {
        return;
      }

      final transforms =
          floatData.materialize().asFloat32List(0, count * BinaryRenderSnapshot.floatStride);
      final metadata =
          intData.materialize().asInt32List(0, count * BinaryRenderSnapshot.intStride);

      _snapshots.add(BinaryRenderSnapshot(
        sequence: sequence,
        count: count,
        transforms: transforms,
        metadata: metadata,
      ));
    });

    _isolate = await Isolate.spawn<_LogicBootstrap>(
      _networkAndLogicMain,
      _LogicBootstrap(_receivePort.sendPort, tickHz.clamp(20, 120)),
      debugName: 'NetworkAndLogicIsolate',
    );

    await ready.future.timeout(const Duration(seconds: 3));
  }

  void upsert(LogicUpsertEntity entity) => _commands?.send(entity);

  void remove(int id) => _commands?.send(LogicRemoveEntity(id));

  void setVelocity(int id, double vx, double vy, double vz) =>
      _commands?.send(LogicVelocity(id, vx, vy, vz));

  void packet(int type, Uint8List body) =>
      _commands?.send(LogicNetworkPacket(type, body));

  void simulateWorld({int entityCount = 256, int seed = 1337}) =>
      _commands?.send(LogicSimulateWorld(
        entityCount: entityCount.clamp(1, 20000),
        seed: seed,
      ));

  Future<void> dispose() async {
    _commands?.send(const LogicStop());
    _commands = null;
    await _subscription?.cancel();
    _subscription = null;
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _receivePort.close();
    await _snapshots.close();
  }
}

void _networkAndLogicMain(_LogicBootstrap bootstrap) {
  final input = ReceivePort();
  bootstrap.renderPort.send(input.sendPort);

  final entities = <int, _SimEntity>{};
  var running = true;
  var sequence = 0;
  var previousMicros = DateTime.now().microsecondsSinceEpoch;
  final targetMicros = (1000000 / bootstrap.tickHz).round();

  input.listen((Object? message) {
    switch (message) {
      case LogicUpsertEntity m:
        entities[m.id] = _SimEntity(
          id: m.id,
          kind: m.kind,
          x: m.x,
          y: m.y,
          z: m.z,
          yaw: m.yaw,
          animation: m.animation,
          flags: m.flags,
        );
      case LogicRemoveEntity m:
        entities.remove(m.id);
      case LogicVelocity m:
        final entity = entities[m.id];
        if (entity != null) {
          entity
            ..vx = m.vx
            ..vy = m.vy
            ..vz = m.vz;
        }
      case LogicNetworkPacket m:
        _applyPs0032Packet(
          entities,
          m.type,
          m.body.materialize().asUint8List(),
        );
      case LogicSimulateWorld m:
        _populateSimulation(entities, m.entityCount, m.seed);
      case LogicStop():
        running = false;
        input.close();
    }
  });

  Timer.periodic(Duration(microseconds: targetMicros), (Timer timer) {
    if (!running) {
      timer.cancel();
      return;
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = ((now - previousMicros) / 1000000.0).clamp(0.0, .05);
    previousMicros = now;

    for (final entity in entities.values) {
      entity
        ..x += entity.vx * dt
        ..y += entity.vy * dt
        ..z += entity.vz * dt;
      if (entity.vx != 0 || entity.vz != 0) {
        entity.yaw = math.atan2(entity.vx, entity.vz);
      }
    }

    final ordered = entities.values.toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));
    final floats = Float32List(
      ordered.length * BinaryRenderSnapshot.floatStride,
    );
    final ints = Int32List(
      ordered.length * BinaryRenderSnapshot.intStride,
    );

    for (var i = 0; i < ordered.length; i++) {
      final entity = ordered[i];
      final fo = i * BinaryRenderSnapshot.floatStride;
      floats[fo] = entity.x;
      floats[fo + 1] = entity.y;
      floats[fo + 2] = entity.z;
      floats[fo + 3] = entity.yaw;
      floats[fo + 4] = entity.scaleX;
      floats[fo + 5] = entity.scaleY;
      floats[fo + 6] = entity.scaleZ;
      floats[fo + 7] = 1;

      final io = i * BinaryRenderSnapshot.intStride;
      ints[io] = entity.id;
      ints[io + 1] = entity.kind.index;
      ints[io + 2] = entity.animation;
      ints[io + 3] = entity.flags;
    }

    bootstrap.renderPort.send(<Object?>[
      sequence++,
      ordered.length,
      TransferableTypedData.fromList(<TypedData>[floats]),
      TransferableTypedData.fromList(<TypedData>[ints]),
    ]);
  });
}

void _populateSimulation(
  Map<int, _SimEntity> entities,
  int count,
  int seed,
) {
  entities.clear();
  final random = math.Random(seed);
  for (var i = 0; i < count; i++) {
    final angle = random.nextDouble() * math.pi * 2;
    final radius = 5 + random.nextDouble() * 180;
    final speed = .15 + random.nextDouble() * 1.4;
    entities[100000 + i] = _SimEntity(
      id: 100000 + i,
      kind: i % 5 == 0 ? RenderEntityKind.npc : RenderEntityKind.mob,
      x: math.cos(angle) * radius,
      y: 0,
      z: math.sin(angle) * radius,
      yaw: angle,
      vx: math.cos(angle + math.pi / 2) * speed,
      vz: math.sin(angle + math.pi / 2) * speed,
      animation: 1,
    );
  }
}

/// Verified packet layouts can move here progressively. Unsupported packets
/// remain in the authoritative ps0032 session and are not guessed.
void _applyPs0032Packet(
  Map<int, _SimEntity> entities,
  int type,
  Uint8List body,
) {
  final data = ByteData.sublistView(body);

  // MAP_NPC_ENTER 0x0E01:
  // globalId:u32, type:u8, typeId:i16, x/y/z:f32, angle:u16.
  if (type == 0x0E01 && body.length >= 21) {
    final id = data.getUint32(0, Endian.little);
    entities[id] = _SimEntity(
      id: id,
      kind: RenderEntityKind.npc,
      x: data.getFloat32(7, Endian.little),
      y: data.getFloat32(11, Endian.little),
      z: data.getFloat32(15, Endian.little),
      yaw: data.getUint16(19, Endian.little) *
          (math.pi * 2 / 65536.0),
    );
    return;
  }

  // MAP_NPC_LEAVE / MOB_LEAVE. Both begin with globalId:u32.
  if ((type == 0x0E02 || type == 0x0602) && body.length >= 4) {
    entities.remove(data.getUint32(0, Endian.little));
  }
}
