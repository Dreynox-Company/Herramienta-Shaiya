import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' as v;

/// Horizontal input projected from the orbit camera, independent of pitch.
v.Vector3 cameraRelative(double x, double z, double yaw) {
  final norm = math.max(1.0, math.sqrt(x * x + z * z));
  return v.Vector3(
    (math.cos(yaw) * x + math.sin(yaw) * z) / norm,
    0,
    (-math.sin(yaw) * x + math.cos(yaw) * z) / norm,
  );
}

// Original humanoids face -Z in the asset coordinate system; after the
// renderer mirror their forward direction is +Z.
double facingYaw(double dx, double dz) => math.atan2(dx, dz);

class JumpState {
  double height = 0, velocity = 0;
  bool get airborne => height > 0 || velocity > 0;
  bool start() {
    if (airborne) return false;
    velocity = 5.0;
    return true;
  }

  bool step(double dt) {
    if (!airborne) return false;
    final was = airborne;
    height += velocity * dt - 9.81 * dt * dt / 2;
    velocity -= 9.81 * dt;
    if (height <= 0) {
      height = 0;
      velocity = 0;
    }
    return was && !airborne;
  }

  void reset() {
    height = 0;
    velocity = 0;
  }
}

class Destination {
  final double x, z;
  const Destination(this.x, this.z);
  v.Vector3 delta(double px, double pz) => v.Vector3(x - px, 0, z - pz);
  bool reached(double px, double pz) => delta(px, pz).length < .12;
}

class RoutePlanner {
  final double? Function(double x, double z, double expected) floor;
  final bool Function(v.Vector3 a, v.Vector3 b) blocked;
  final int maxNodes;
  final double cell;
  RoutePlanner(
    this.floor,
    this.blocked, {
    this.maxNodes = 6000,
    this.cell = 1.25,
  });
  bool traversable(v.Vector3 a, v.Vector3 b) {
    var last = a.clone();
    final steps = math.max(1, ((b - a).length / .6).ceil());
    for (var i = 1; i <= steps; i++) {
      final point = a + (b - a) * (i / steps),
          y = floor(point.x, point.z, last.y);
      if (y == null || (y - last.y).abs() > 1.0) return false;
      point.y = y;
      if (blocked(last, point)) return false;
      last = point;
    }
    return true;
  }

  List<v.Vector3>? find(v.Vector3 start, v.Vector3 goal) {
    if (traversable(start, goal)) return [goal];
    final open = <_RouteNode>[], seen = <String, double>{};
    void push(_RouteNode node) {
      open.add(node);
      var i = open.length - 1;
      while (i > 0) {
        final parent = (i - 1) ~/ 2;
        if (open[parent].score <= node.score) break;
        open[i] = open[parent];
        i = parent;
      }
      open[i] = node;
    }

    _RouteNode pop() {
      final first = open.first, last = open.removeLast();
      if (open.isEmpty) return first;
      var i = 0;
      while (i * 2 + 1 < open.length) {
        var child = i * 2 + 1;
        if (child + 1 < open.length &&
            open[child + 1].score < open[child].score) {
          child++;
        }
        if (last.score <= open[child].score) break;
        open[i] = open[child];
        i = child;
      }
      open[i] = last;
      return first;
    }

    push(_RouteNode(start, 0, (goal - start).length, null));
    var visited = 0;
    while (open.isNotEmpty && visited++ < maxNodes) {
      final node = pop(), position = node.point;
      if ((position - goal).length < cell * 1.5 &&
          traversable(position, goal)) {
        final path = <v.Vector3>[goal];
        _RouteNode? cursor = node;
        while (cursor?.parent != null) {
          path.add(cursor!.point);
          cursor = cursor.parent;
        }
        return path.reversed.toList();
      }
      for (var dx = -1; dx <= 1; dx++) {
        for (var dz = -1; dz <= 1; dz++) {
          if (dx == 0 && dz == 0) continue;
          final x = position.x + dx * cell,
              z = position.z + dz * cell,
              y = floor(x, z, position.y);
          if (y == null || (y - position.y).abs() > 1) continue;
          final next = v.Vector3(x, y, z),
              cost = node.cost + (next - position).length,
              key =
                  '${((x - start.x) / cell).round()}:${((z - start.z) / cell).round()}:${(y * 2).round()}';
          if (cost >= (seen[key] ?? double.infinity) ||
              !traversable(position, next)) {
            continue;
          }
          seen[key] = cost;
          push(_RouteNode(next, cost, cost + (goal - next).length, node));
        }
      }
    }
    return null;
  }
}

class _RouteNode {
  final v.Vector3 point;
  final double cost, score;
  final _RouteNode? parent;
  _RouteNode(this.point, this.cost, this.score, this.parent);
}
