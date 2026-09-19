import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../core/archive_index.dart';
import 'archive_source.dart';
import 'archive_export.dart';

/// The virtual range source shares the existing bounded, hashed archive writer.
/// Enumerates ALL regular files, not just extensions supported by the viewer.
class DirectoryPack {
  static Future<ExportResult> build(
    Directory data,
    Directory output, {
    Map<String, Uint8List> replacements = const {},
    required ExportControl control,
    required void Function(ExportProgress) progress,
  }) async {
    final root = p.normalize(await data.resolveSymbolicLinks()),
        dest = p.normalize(await output.resolveSymbolicLinks());
    if (p.equals(root, dest) || p.isWithin(root, dest)) {
      throw const FormatException(
        'Construye el SAH/SAF fuera de la carpeta DATA para no incluir el propio destino.',
      );
    }
    final entries = <ArchiveEntry>[],
        files = <File>[],
        stats = <FileStat>[],
        names = <String>{};
    int offset = 0;
    final discovered = await Directory(
      root,
    ).list(recursive: true, followLinks: false).toList();
    discovered.sort((a, b) => a.path.compareTo(b.path));
    for (final entity in discovered) {
      control.check();
      if (entity is Link) {
        throw const FormatException(
          'DATA contiene un enlace simbólico. No se incluye contenido fuera de la carpeta.',
        );
      }
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root)
          .replaceAll('\\', '/');
      ArchiveExport.safePath(relative);
      final key = relative.toLowerCase();
      if (!names.add(key)) {
        throw FormatException('Nombre repetido por mayúsculas: $relative');
      }
      final stat = await entity.stat();
      if (stat.size > 0x7fffffff) {
        throw FormatException(
          '$relative excede el tamaño admitido por un registro SAH.',
        );
      }
      if (files.length >= ArchiveIndex.maxEntries) {
        throw const FormatException('Más de 200.000 archivos.');
      }
      entries.add(
        ArchiveEntry(
          key,
          offset,
          stat.size,
          0,
          rawComponents: relative
              .split('/')
              .map((s) => Uint8List.fromList([...utf8.encode(s), 0]))
              .toList(),
        ),
      );
      files.add(entity);
      stats.add(stat);
      offset += stat.size;
    }
    if (files.isEmpty) throw const FormatException('La carpeta está vacía.');
    // Raw path components use UTF-8, not lossy UTF-16 truncation.
    final source = ArchiveSource(
      ArchiveIndex(
        {for (final e in entries) e.path: e},
        {'version': 0, 'sourceMode': 'directory'},
      ),
      (at, n) async {
        if (n == 0) return Uint8List(0);
        int low = 0, high = entries.length;
        while (low < high) {
          final mid = (low + high) ~/ 2;
          if (entries[mid].offset + entries[mid].length <= at) {
            low = mid + 1;
          } else {
            high = mid;
          }
        }
        if (low >= entries.length) {
          throw const FormatException('Lectura fuera del directorio virtual.');
        }
        final record = entries[low], file = files[low], expected = stats[low];
        if (at < record.offset || n > record.offset + record.length - at) {
          throw const FormatException('Lectura atraviesa dos recursos.');
        }
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const FormatException(
            'Un recurso cambió de tipo durante la construcción.',
          );
        }
        final before = await file.stat();
        if (before.size != expected.size ||
            before.modified != expected.modified) {
          throw FormatException(
            'El recurso cambió durante la construcción: ${record.path}',
          );
        }
        final handle = await file.open();
        try {
          await handle.setPosition(at - record.offset);
          final b = await handle.read(n);
          if (b.length != n) {
            throw const FormatException(
              'Recurso truncado durante la construcción.',
            );
          }
          return b;
        } finally {
          await handle.close();
        }
      },
    );
    try {
      return await ArchiveExport.repack(
        source,
        Directory(dest),
        replacements: replacements,
        control: control,
        progress: progress,
      );
    } finally {
      source.close();
    }
  }
}
