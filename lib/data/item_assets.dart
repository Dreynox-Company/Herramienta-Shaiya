import 'dart:typed_data';

import '../core/formats.dart';
import '../core/item_atlas.dart';
import '../core/textures.dart';

/// A replacement keeps the original DATA path and native format. Geometry
/// authoring takes place in a modeler; Studio validates and imports the result.
/// This validator does not claim that a game.exe acceptance test has run.
class ItemAssetReplacement {
  final Uint8List bytes;
  final String description;
  const ItemAssetReplacement(this.bytes, this.description);

  static ItemAssetReplacement validate((String, Uint8List, Uint8List) args) {
    final (path, original, replacement) = args;
    if (replacement.isEmpty || replacement.length > 32 * 1024 * 1024) {
      throw const FormatException(
        'El recurso debe tener entre 1 byte y 32 MiB.',
      );
    }
    if (path.endsWith('.3dc') || path.endsWith('.3do')) {
      final skinned = path.endsWith('.3dc');
      final old = skinned
          ? MeshData.skinned(original, path)
          : MeshData.object(original, path);
      final next = skinned
          ? MeshData.skinned(replacement, path)
          : MeshData.object(replacement, path);
      if (next.repairs.isNotEmpty || next.vertices < 3 || next.triangles < 1) {
        throw const FormatException(
          'La malla importada requiere reparaciones o está vacía.',
        );
      }
      if (old.inverses.length != next.inverses.length ||
          (next.requiredBones > next.inverses.length &&
              skinned &&
              next.inverses.isNotEmpty)) {
        throw const FormatException(
          'El número de huesos no es compatible con el recurso reemplazado.',
        );
      }
      for (var i = 0; i < old.inverses.length; i++) {
        for (var k = 0; k < 16; k++) {
          if ((old.inverses[i].storage[k] - next.inverses[i].storage[k]).abs() >
              1e-4) {
            throw const FormatException(
              'La pose de enlace cambió: requiere retargeting, no sustitución directa.',
            );
          }
        }
      }
      return ItemAssetReplacement(
        Uint8List.fromList(replacement),
        '${next.vertices} vértices · ${next.triangles} triángulos · ${next.inverses.length} matrices de enlace',
      );
    }
    if (path.endsWith('.ani')) {
      final old = ClipData.parse(original, path),
          next = ClipData.parse(replacement, path);
      if (old.bones.length != next.bones.length) {
        throw const FormatException(
          'La animación no tiene el mismo número de huesos.',
        );
      }
      for (var i = 0; i < old.bones.length; i++) {
        if (old.bones[i].parent != next.bones[i].parent) {
          throw const FormatException(
            'La jerarquía ANI no coincide. No se aplica otro esqueleto.',
          );
        }
        for (var k = 0; k < 16; k++) {
          if ((old.bones[i].bind.storage[k] - next.bones[i].bind.storage[k])
                  .abs() >
              1e-4) {
            throw const FormatException(
              'La pose de enlace ANI difiere. Retargeting requerido.',
            );
          }
        }
      }
      return ItemAssetReplacement(
        Uint8List.fromList(replacement),
        '${next.bones.length} huesos · ${next.duration.toStringAsFixed(3)} s',
      );
    }
    if (path.endsWith('.dds') || path.endsWith('.tga')) {
      // Inspect dimensions before decoding: a tiny file may declare huge output.
      void bound(Uint8List b) {
        final d = ByteData.sublistView(b);
        final dds =
            b.length >= 128 && d.getUint32(0, Endian.little) == 0x20534444;
        final tga = b.length >= 18 && const {1, 2, 3, 9, 10, 11}.contains(b[2]);
        if (!dds && !tga)
          throw const FormatException(
            'Importa una textura nativa DDS o TGA, no un archivo renombrado.',
          );
        final w = dds
            ? d.getUint32(16, Endian.little)
            : d.getUint16(12, Endian.little);
        final h = dds
            ? d.getUint32(12, Endian.little)
            : d.getUint16(14, Endian.little);
        if (w < 1 || h < 1 || w * h > 4194304) {
          throw const FormatException(
            'Textura inválida o mayor de 4 millones de píxeles.',
          );
        }
      }

      bound(original);
      bound(replacement);
      final next = Pixels.decode(replacement, path);
      final old = Pixels.decode(original, path);
      if (next.width != old.width || next.height != old.height) {
        throw const FormatException(
          'Conserva las dimensiones para esta sustitución segura.',
        );
      }
      if (path.endsWith('.dds')) {
        final b = ByteData.sublistView(original);
        final levels =
            original.length >= 128 &&
                b.getUint32(0, Endian.little) == 0x20534444
            ? b.getUint32(28, Endian.little)
            : 1;
        final encoded = ItemAtlas.encodeDds(
          next.rgba,
          next.width,
          next.height,
          mipLevels: levels < 1 ? 1 : levels,
        );
        final check = Pixels.decode(encoded, path);
        if (!_same(check.rgba, next.rgba))
          throw const FormatException('La relectura DDS no coincide.');
        return ItemAssetReplacement(
          encoded,
          '${next.width}×${next.height} · DDS RGBA verificado',
        );
      }
      if (replacement.length >= 4 &&
          ByteData.sublistView(replacement).getUint32(0, Endian.little) ==
              0x20534444) {
        throw const FormatException(
          'Esta ruta requiere TGA. No se renombra un DDS a TGA.',
        );
      }
      return ItemAssetReplacement(
        Uint8List.fromList(replacement),
        '${next.width}×${next.height} · TGA',
      );
    }
    throw const FormatException(
      'Formato no habilitado para sustitución validada.',
    );
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
