import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'formats.dart';
import 'mounted_motion.dart';

/// Supplemental library; original ANI lookups are never modified.
class ExtraMotionProfile {
  final String archetype, sex;
  final List<int> parents;
  final ClipData hover, flight;
  final int? head;
  final Map<String, ClipData> mounted;
  ExtraMotionProfile(
    this.archetype,
    this.sex,
    this.parents,
    this.hover,
    this.flight,
    this.head, {
    this.mounted = const {},
  });
  bool matches(String id, bool female, ClipData original) =>
      id == archetype &&
      sex == (female ? 'Femenino' : 'Masculino') &&
      parents.length == original.bones.length &&
      Iterable<int>.generate(
        parents.length,
      ).every((i) => parents[i] == original.bones[i].parent);
}

class ExtraMotionLibrary {
  final Map<String, ExtraMotionProfile> profiles;
  ExtraMotionLibrary(this.profiles);
  static ExtraMotionLibrary decode(Uint8List compressed) {
    if (compressed.length > 8 * 1024 * 1024) {
      throw const FormatException('Paquete de movimientos demasiado grande.');
    }
    // A bounded chunk sink prevents decompression bombs, before JSON allocation.
    final sink = _BoundedSink(8 * 1024 * 1024);
    final decoder = gzip.decoder.startChunkedConversion(sink);
    decoder.add(compressed);
    decoder.close();
    final raw = jsonDecode(utf8.decode(sink.data.takeBytes())) as Map;
    if (raw['schema'] != 1 ||
        raw['profiles'] is! List ||
        (raw['profiles'] as List).length > 32) {
      throw const FormatException('Manifiesto de movimientos no admitido.');
    }
    final out = <String, ExtraMotionProfile>{};
    for (final row in raw['profiles'] as List) {
      final id = row['archetype'] as String, sex = row['sex'] as String;
      if (!RegExp(r'^[a-z0-9_-]{3,16}$').hasMatch(id) ||
          !['Masculino', 'Femenino'].contains(sex) ||
          out.containsKey(id)) {
        throw const FormatException('Identidad de movimiento inválida.');
      }
      final parents = (row['parents'] as List).cast<int>();
      if (parents.isEmpty || parents.length > 128) {
        throw const FormatException(
          'Esqueleto de movimiento fuera de límites.',
        );
      }
      ClipData clip(String name) {
        final entry = row['clips'][name] as Map,
            b = base64Decode(entry['data'] as String);
        if (b.length > 256 * 1024 ||
            sha256.convert(b).toString() != entry['sha256']) {
          throw FormatException(
            'Integridad del movimiento $id/$name incorrecta.',
          );
        }
        final c = ClipData.parse(b, 'extra:$id/$name');
        if (c.bones.length != parents.length ||
            c.duration > 30 ||
            c.duration < .1) {
          throw FormatException('Movimiento $id/$name incompatible.');
        }
        for (var i = 0; i < parents.length; i++) {
          if (c.bones[i].parent != parents[i]) {
            throw const FormatException(
              'La jerarquía del movimiento no coincide.',
            );
          }
        }
        for (final t in [
          0.0,
          c.duration * .25,
          c.duration * .5,
          c.duration * .75,
        ]) {
          if (c
              .pose(t)
              .any(
                (m) => !m.storage.every((v) => v.isFinite && v.abs() < 1000),
              )) {
            throw FormatException('Pose no válida en $id/$name.');
          }
        }
        return c;
      }

      final semantic = row['semantic'];
      final h = semantic is Map ? semantic['head'] : null;
      if (h != null && (h is! int || h <= 0 || h >= parents.length)) {
        throw const FormatException(
          'Hueso de cabeza fuera del perfil de movimiento.',
        );
      }
      out[id] = ExtraMotionProfile(
        id,
        sex,
        parents,
        clip('hover'),
        clip('flight'),
        h is int ? h : null,
        mounted: {
          for (final key in mountedMotionKeys)
            if ((row['clips'] as Map).containsKey(key)) key: clip(key),
        },
      );
    }
    return ExtraMotionLibrary(out);
  }
}

class _BoundedSink implements Sink<List<int>> {
  final int limit;
  final BytesBuilder data = BytesBuilder(copy: false);
  _BoundedSink(this.limit);
  @override
  void add(List<int> bytes) {
    if (data.length + bytes.length > limit) {
      throw const FormatException('Paquete expandido fuera de límite.');
    }
    data.add(bytes);
  }

  @override
  void close() {}
}
