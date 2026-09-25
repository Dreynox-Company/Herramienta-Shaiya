import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/archive_index.dart';
import 'archive_source.dart';

class ExportCancelled implements Exception {
  const ExportCancelled();
  @override
  String toString() => 'Exportación cancelada. El origen no se modificó.';
}

class ExportControl {
  bool cancelled = false;
  void check() {
    if (cancelled) throw const ExportCancelled();
  }
}

class ExportProgress {
  final String phase, path;
  final int done, total, bytes, totalBytes;
  const ExportProgress(
    this.phase,
    this.path,
    this.done,
    this.total,
    this.bytes,
    this.totalBytes,
  );
  double? get ratio => totalBytes == 0 ? null : bytes / totalBytes;
}

class ExportResult {
  final String folder;
  final int files, bytes;
  final List<Map<String, Object?>> manifest;
  const ExportResult(this.folder, this.files, this.bytes, this.manifest);
}

/// Streaming copy-on-write export. Never edits a loaded archive in place.
/// All products are staged in a new sibling directory and renamed only after
/// successful range checks, re-reading and hashing. Originals remain untouched.
class ArchiveExport {
  static const chunkSize = 1024 * 1024;
  static Future<ExportResult> extract(
    ArchiveSource source,
    Directory destinationParent, {
    required ExportControl control,
    required void Function(ExportProgress) progress,
  }) => _run(source, destinationParent, control, progress, pack: false);
  static Future<ExportResult> repack(
    ArchiveSource source,
    Directory destinationParent, {
    required Map<String, Uint8List> replacements,
    required ExportControl control,
    required void Function(ExportProgress) progress,
  }) => _run(
    source,
    destinationParent,
    control,
    progress,
    pack: true,
    replacements: replacements,
  );
  static String safePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.length > 4096) {
      throw FormatException('Ruta no extraíble: $path');
    }
    for (final s in normalized.split('/')) {
      if (s.isEmpty ||
          s == '.' ||
          s == '..' ||
          s.endsWith('.') ||
          s.endsWith(' ') ||
          RegExp(r'[<>:"|?*\x00-\x1f\x7f]').hasMatch(s) ||
          RegExp(
            r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
            caseSensitive: false,
          ).hasMatch(s)) {
        throw FormatException(
          'Ruta no segura en el sistema de archivos: $path',
        );
      }
    }
    return normalized;
  }

  static Future<ExportResult> _run(
    ArchiveSource source,
    Directory parent,
    ExportControl control,
    void Function(ExportProgress) notify, {
    required bool pack,
    Map<String, Uint8List> replacements = const {},
  }) async {
    control.check();
    if (source.closed) throw StateError('Archivo cerrado.');
    if (!await parent.exists()) {
      throw const FormatException('La carpeta de destino no existe.');
    }
    final base = Directory(await parent.resolveSymbolicLinks());
    final list = source.index.entries.values.toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (replacements.keys.any((p) => !source.index.entries.containsKey(p))) {
      throw const FormatException(
        'Un cambio no pertenece al archivo de origen.',
      );
    }
    // Preflight all paths before creating any outputs. One invalid entry fails
    // the entire export rather than silently omitting a resource.
    final paths = <String>{};
    for (final e in list) {
      final p = safePath(e.path);
      if (!paths.add(p.toLowerCase())) {
        throw const FormatException('Colisión de nombres de archivo.');
      }
    }
    for (final p in paths) {
      var prefix = p;
      while (prefix.contains('/')) {
        prefix = prefix.substring(0, prefix.lastIndexOf('/'));
        if (paths.contains(prefix)) {
          throw const FormatException(
            'Un archivo también figura como directorio.',
          );
        }
      }
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    final staging = Directory('${base.path}/.shaiya-$id.partial');
    await staging.create();
    final target = '${base.path}/${pack ? 'SAH_SAF_editado' : 'DATA'}_$id';
    final manifests = <Map<String, Object?>>[];
    var offset = 0, doneBytes = 0;
    final totalBytes = list.fold<int>(
      0,
      (n, e) => n + (replacements[e.path]?.length ?? e.length),
    );
    RandomAccessFile? saf;
    try {
      if (pack) {
        saf = await File('${staging.path}/data.saf')
            .open(mode: FileMode.writeOnly);
      }
      final newEntries = <ArchiveEntry>[];
      for (var i = 0; i < list.length; i++) {
        control.check();
        final e = list[i], replacement = replacements[e.path];
        final length = replacement?.length ?? e.length;
        if (length > 0x7fffffff) {
          throw FormatException(
            '${e.path} excede el tamaño que admite el índice SAH estándar.',
          );
        }
        final sink = _DigestSink();
        final hash = sha256.startChunkedConversion(sink);
        RandomAccessFile? out;
        try {
          if (!pack) {
            final f = File('${staging.path}/${e.path}');
            await f.parent.create(recursive: true);
            out = await f.open(mode: FileMode.writeOnly);
          }
          var p = 0;
          while (p < length) {
            control.check();
            if (source.closed) {
              throw StateError(
                'Se cerró la biblioteca durante la exportación.',
              );
            }
            final n = min(chunkSize, length - p);
            final bytes = replacement != null
                ? Uint8List.sublistView(replacement, p, p + n)
                : await source.readRange(e.offset + p, n);
            if (bytes.length != n) {
              throw FormatException('Lectura truncada: ${e.path}, byte $p.');
            }
            hash.add(bytes);
            await (saf ?? out!).writeFrom(bytes);
            p += n;
            doneBytes += n;
            notify(
              ExportProgress(
                'Copiando',
                e.path,
                i,
                list.length,
                doneBytes,
                totalBytes,
              ),
            );
          }
          hash.close();
          if (out != null) await out.flush();
        } finally {
          await out?.close();
        }
        final digest = sink.value!;
        manifests.add({
          'path': e.path,
          'bytes': length,
          'sha256': digest,
          'modified': replacement != null,
        });
        newEntries.add(
          ArchiveEntry(
            e.path,
            offset,
            length,
            e.version,
            rawComponents: e.rawComponents,
          ),
        );
        offset += length;
        // Verify the saved output, not merely the input stream.
        if (!pack) {
          final saved = await sha256
              .bind(File('${staging.path}/${e.path}').openRead())
              .first;
          if (saved.toString() != digest) {
            throw FormatException('No coincide la copia escrita: ${e.path}.');
          }
        }
        notify(
          ExportProgress(
            'Verificado',
            e.path,
            i + 1,
            list.length,
            doneBytes,
            totalBytes,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
      if (saf != null) {
        await saf.flush();
        await saf.close();
        saf = null;
        final sah = encodeIndex(
          newEntries,
          version: source.index.report['version'] as int? ?? 0,
        );
        await File('${staging.path}/data.sah').writeAsBytes(sah, flush: true);
        final parsed = ArchiveIndex.decode(sah, offset);
        if (parsed.entries.length != newEntries.length) {
          throw const FormatException('El índice regenerado perdió registros.');
        }
        final dataFile = File('${staging.path}/data.saf');
        for (var i = 0; i < newEntries.length; i++) {
          control.check();
          final e = newEntries[i], actual = parsed.entries[e.path];
          if (actual == null ||
              actual.offset != e.offset ||
              actual.length != e.length ||
              actual.version != e.version) {
            throw const FormatException(
              'El índice regenerado alteró un rango.',
            );
          }
          final saved = await sha256
              .bind(dataFile.openRead(e.offset, e.offset + e.length))
              .first;
          if (saved.toString() != manifests[i]['sha256']) {
            throw FormatException('SAF escrito incorrectamente: ${e.path}.');
          }
          notify(
            ExportProgress(
              'Verificando SAF',
              e.path,
              i + 1,
              list.length,
              i + 1,
              list.length,
            ),
          );
        }
      }
      control.check();
      await File('${staging.path}/manifest-shaiya-$id.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'format': 'shaiya-safe-export',
          'version': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'mode': pack ? 'nuevo SAH/SAF estándar' : 'extracción íntegra',
          'sourceIndexSha256': source.index.report['indexSha256'],
          'files': manifests,
          'count': list.length,
          'bytes': offset,
          'notice': pack
              ? 'Par nuevo en formato estándar. No sobrescribe el original ni conserva protecciones personalizadas del índice. La compatibilidad de un cliente modificado requiere prueba en ese cliente.'
              : 'Todos los recursos del índice copiados y verificados sin reinterpretar su contenido.',
        }),
        flush: true,
      );
      await staging.rename(target);
      return ExportResult(target, list.length, offset, manifests);
    } catch (e) {
      await saf?.close();
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  static Uint8List encodeIndex(List<ArchiveEntry> entries, {int version = 0}) {
    if (entries.length > ArchiveIndex.maxEntries) {
      throw const FormatException('Demasiados recursos para el SAH.');
    }
    final root = _DirectoryNode('', Uint8List.fromList([0]));
    for (final e in entries) {
      safePath(e.path);
      final parts = e.path.split('/');
      var node = root;
      for (var i = 0; i < parts.length - 1; i++) {
        final raw = e.rawComponents.length == parts.length
            ? e.rawComponents[i]
            : Uint8List.fromList([...utf8.encode(parts[i]), 0]);
        node = node.children.putIfAbsent(
          parts[i],
          () => _DirectoryNode(parts[i], raw),
        );
      }
      node.files.add(e);
    }
    final writer = _IndexWriter();
    writer.out.add(ascii.encode('SAH'));
    writer.i32(version);
    writer.u32(entries.length);
    writer.out.add(Uint8List(40));
    void visit(_DirectoryNode node) {
      writer.rawName(node.raw);
      writer.u32(node.files.length);
      for (final e in node.files) {
        final parts = e.path.split('/');
        final raw = e.rawComponents.length == parts.length
            ? e.rawComponents.last
            : Uint8List.fromList([...utf8.encode(parts.last), 0]);
        writer.rawName(raw);
        writer.i64(e.offset);
        writer.i32(e.length);
        writer.i32(e.version);
      }
      writer.u32(node.children.length);
      for (final child in node.children.values) {
        visit(child);
      }
    }

    visit(root);
    writer.out.add(Uint8List(8));
    return writer.out.takeBytes();
  }
}

class _DirectoryNode {
  final String name;
  final Uint8List raw;
  final Map<String, _DirectoryNode> children = {};
  final List<ArchiveEntry> files = [];
  _DirectoryNode(this.name, this.raw);
}

class _IndexWriter {
  final out = BytesBuilder(copy: false);
  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void i32(int v) {
    final b = ByteData(4)..setInt32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void i64(int v) {
    final b = ByteData(8)..setInt64(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void rawName(Uint8List b) {
    if (b.length > 4096) throw const FormatException('Nombre demasiado largo.');
    u32(b.length);
    out.add(b);
  }
}

class _DigestSink implements Sink<Digest> {
  String? value;
  @override
  void add(Digest d) {
    value = d.toString();
  }

  @override
  void close() {}
}
