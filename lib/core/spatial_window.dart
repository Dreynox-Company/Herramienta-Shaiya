import 'dart:math' as math;

typedef CellId = ({int x, int z});

class SpatialWindow {
  final double cellSize;
  final int maxCells;
  double radius, margin;
  SpatialWindow({
    this.cellSize = 64,
    this.radius = 176,
    this.margin = 80,
    this.maxCells = 196,
  });
  CellId at(double x, double z) =>
      (x: (x / cellSize).floor(), z: (z / cellSize).floor());
  double distance2(CellId cell, double x, double z) {
    final dx = math.max(
      0.0,
      math.max(cell.x * cellSize - x, x - (cell.x + 1) * cellSize),
    );
    final dz = math.max(
      0.0,
      math.max(cell.z * cellSize - z, z - (cell.z + 1) * cellSize),
    );
    return dx * dx + dz * dz;
  }

  List<CellId> select(
    double x,
    double z, {
    double? limit,
    bool Function(CellId)? valid,
  }) {
    final r = limit ?? radius, out = <CellId>[];
    for (
      var ix = ((x - r) / cellSize).floor();
      ix <= ((x + r) / cellSize).floor();
      ix++
    ) {
      for (
        var iz = ((z - r) / cellSize).floor();
        iz <= ((z + r) / cellSize).floor();
        iz++
      ) {
        final c = (x: ix, z: iz);
        if (distance2(c, x, z) <= r * r && (valid?.call(c) ?? true)) out.add(c);
      }
    }
    out.sort((a, b) => distance2(a, x, z).compareTo(distance2(b, x, z)));
    return out.take(maxCells).toList();
  }

  bool retain(CellId cell, double x, double z) =>
      distance2(cell, x, z) <= (radius + margin) * (radius + margin);
}
