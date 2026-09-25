import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/archive_index.dart';

/// Range reads avoid ever copying or loading the entire SAF in memory.
/// Independent handles avoid seek races between texture and animation loads.
class ArchiveSource {
  ArchiveIndex index;
  Future<Uint8List> Function(int offset, int length) readRange;
  final String? sahPath, safPath;
  final int? countXor;
  Completer<void>? _writeBarrier;
  bool get writing => _writeBarrier != null;
  void beginWrite() {
    if (writing) throw StateError("Transacción en curso");
    _writeBarrier = Completer<void>();
  }

  void endWrite() {
    final barrier = _writeBarrier;
    _writeBarrier = null;
    barrier?.complete();
  }

  Future<void> refreshAfterWrite() async {
    if (sahPath == null || safPath == null) return;
    final fresh = await fromFiles(sahPath!, safPath!, countXor: countXor);
    index = fresh.index;
    readRange = fresh.readRange;
  }

  final List<Map<String, Object?>> failures = [];
  final List<Map<String, Object?>> recentReads = [];
  int reads = 0, bytesRead = 0;
  bool closed = false;
  ArchiveSource(
    this.index,
    this.readRange, {
    this.sahPath,
    this.safPath,
    this.countXor,
  });
  Future<Uint8List> read(String path, {int limit = 64 * 1024 * 1024}) async {
    await _writeBarrier?.future;
    if (closed) throw StateError('La biblioteca ya está cerrada.');
    final e = index.entries[path];
    if (e == null) throw FormatException('Recurso ausente del índice: $path');
    try {
      if (e.length > limit || limit < 0) {
        throw FormatException(
          'Recurso de ${e.length} bytes supera el límite de lectura $limit.',
        );
      }
      final bytes = await readRange(e.offset, e.length);
      if (bytes.length != e.length) {
        throw const FormatException(
          'Lectura SAF incompleta. El archivo pudo cambiar o el permiso pudo revocarse.',
        );
      }
      reads++;
      bytesRead += bytes.length;
      if (recentReads.length >= 32) recentReads.removeAt(0);
      recentReads.add({
        'path': path,
        'offset': e.offset,
        'bytes': e.length,
        'headerHex': bytes
            .take(16)
            .map((n) => n.toRadixString(16).padLeft(2, '0'))
            .join(),
      });
      return bytes;
    } catch (error) {
      if (failures.length == 100) failures.removeAt(0);
      failures.add({
        'path': path,
        'offset': e.offset,
        'bytes': e.length,
        'error': error is FileSystemException
            ? error.osError?.message ?? 'Error de acceso al archivo'
            : error.toString(),
      });
      rethrow;
    }
  }

  Map<String, Object?> diagnostics() => {
    ...index.report,
    'reads': reads,
    'bytesRead': bytesRead,
    'readFailures': failures,
    'recentResourceHeaders': recentReads,
  };
  void close() {
    closed = true;
  }

  static Future<ArchiveSource> fromFiles(
    String sah,
    String saf, {
    int? countXor,
  }) async {
    final header = File(sah), data = File(saf);
    if (!await header.exists() || !await data.exists()) {
      throw const ArchiveFailure(
        'MISSING_PAIR',
        'Se necesitan el índice .sah y su archivo .saf correspondiente',
        {'schema': 1, 'status': 'missing_pair'},
      );
    }
    if (await header.length() > ArchiveIndex.maxIndexBytes) {
      throw const ArchiveFailure('INDEX_TOO_LARGE', 'El índice excede 64 MiB', {
        'schema': 1,
      });
    }
    final sourceLength = await data.length();
    final index = await compute(parseArchiveIndex, {
      'bytes': await header.readAsBytes(),
      'length': sourceLength,
      'xor': countXor,
    });
    return ArchiveSource(
      index,
      (offset, length) async {
        final handle = await data.open(mode: FileMode.read);
        try {
          if (await handle.length() != sourceLength) {
            throw const FormatException(
              'El tamaño SAF cambió después del indexado. Reconecta el par.',
            );
          }
          await handle.setPosition(offset);
          final out = Uint8List(length);
          var done = 0;
          while (done < length) {
            final n = await handle.readInto(out, done, length);
            if (n == 0) throw const FormatException('Fin prematuro del SAF.');
            done += n;
          }
          return out;
        } finally {
          await handle.close();
        }
      },
      sahPath: header.absolute.path,
      safPath: data.absolute.path,
      countXor: countXor,
    );
  }
}

ArchiveIndex parseArchiveIndex(Map<String, Object?> args) =>
    ArchiveIndex.decode(
      args['bytes']! as Uint8List,
      args['length']! as int,
      countXor: args['xor'] as int?,
    );
