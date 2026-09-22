import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../core/archive_index.dart';
import '../core/seed_data.dart';
import 'archive_source.dart';
import 'archive_export.dart';

/// Append changed payloads, then commit a new index over the SAME SAH path.
/// The old ranges remain valid until the atomic index rename. No 2-file rename
/// fiction: a bounded recovery journal covers failure between the two steps.
class ArchiveWriter {
  static String _hash(List<int> b) => sha256.convert(b).toString();
  static Future<void> _regular(File f, {bool exists = true}) async {
    final type = await FileSystemEntity.type(f.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        !(type == FileSystemEntityType.notFound && !exists)) {
      throw FileSystemException(
        'Se requiere un archivo regular, sin enlaces.',
        f.path,
      );
    }
  }

  static Future<void> writeInPlace(
    ArchiveSource source,
    Map<String, Uint8List> replacements, {
    required Map<String, String> expectedHashes,
    required ExportControl control,
    required void Function(ExportProgress) progress,
    bool keepBackup = false,
    Future<void> Function(String phase)? testCheckpoint,
  }) async {
    if (replacements.isEmpty) return;
    final sahPath = source.sahPath, safPath = source.safPath;
    if (sahPath == null || safPath == null) {
      throw const FormatException(
        'Este proveedor no ofrece escritura nativa. Usa Guardar como o exporta una copia.',
      );
    }
    if (source.writing) {
      throw const FormatException(
        'Ya hay una transacción de archivo en curso.',
      );
    }
    final sah = File(sahPath),
        saf = File(safPath),
        journal = File('$sahPath.shaiya-transaction.json'),
        old = File('$sahPath.shaiya-old'),
        next = File('$sahPath.shaiya-next');
    for (final f in [sah, saf]) {
      await _regular(f);
    }
    for (final f in [journal, old, next]) {
      await _regular(f, exists: false);
      if (await f.exists()) {
        throw const FormatException(
          'Hay una transacción anterior pendiente. Recupera el archivo antes de editar.',
        );
      }
    }
    final oldBytes = await sah.readAsBytes(), length = await saf.length();
    if (_hash(oldBytes) != source.index.report['indexSha256'] ||
        length != source.index.report['payloadBytes']) {
      throw const FormatException(
        'El archivo cambió fuera del editor. Vuelve a abrirlo antes de guardar.',
      );
    }
    if (replacements.keys.any((k) => !source.index.entries.containsKey(k))) {
      throw const FormatException('Cambio fuera del índice original.');
    }
    for (final e in replacements.entries) {
      control.check();
      if (e.value.length > 0x7fffffff) {
        throw const FormatException('Recurso fuera de rango int32.');
      }
      if (expectedHashes[e.key] !=
          _hash(await source.read(e.key, limit: 128 * 1024 * 1024))) {
        throw FormatException(
          '${e.key} cambió desde su apertura. No se sobrescribe.',
        );
      }
    }
    var plain = Uint8List.fromList(
      SeedData.decode(oldBytes, verifyChecksum: true),
    );
    final xor = (source.index.report['uniformXor'] as int?) ?? 0;
    if (xor != 0) {
      plain = Uint8List.fromList(plain.map((b) => b ^ xor).toList());
    }
    final data = ByteData.sublistView(plain);
    var cursor = length;
    for (final e in replacements.entries) {
      final record = source.index.entries[e.key]!;
      if (record.metadataOffset < 0 ||
          record.metadataOffset + 16 > plain.length) {
        throw const FormatException(
          'El índice no tiene offsets de escritura verificados.',
        );
      }
      data.setInt64(record.metadataOffset, cursor, Endian.little);
      data.setInt32(record.metadataOffset + 8, e.value.length, Endian.little);
      cursor += e.value.length;
    }
    if (xor != 0) {
      plain = Uint8List.fromList(plain.map((b) => b ^ xor).toList());
    }
    final newBytes = SeedData.isEncoded(oldBytes)
        ? SeedData.encode(plain, template: oldBytes)
        : plain;
    final parsed = ArchiveIndex.decode(
      newBytes,
      cursor,
      countXor: source.countXor,
    );
    if (parsed.entries.length != source.index.entries.length) {
      throw const FormatException(
        'El guardado alteraría la cantidad de recursos.',
      );
    }
    control.check();
    source.beginWrite();
    RandomAccessFile? lock;
    bool locked = false;
    try {
      lock = await saf.open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      locked = true;
      if (await lock.length() != length ||
          _hash(await sah.readAsBytes()) != _hash(oldBytes)) {
        throw const FormatException(
          'Conflicto al obtener el bloqueo de escritura.',
        );
      }
      // Revalidate edited resources under the write lock, closing the gap
      // between optimistic preflight and exclusive ownership.
      for (final key in replacements.keys) {
        final e = source.index.entries[key]!;
        await lock.setPosition(e.offset);
        if (_hash(await lock.read(e.length)) != expectedHashes[key]) {
          throw FormatException('$key cambió antes de obtener el bloqueo.');
        }
      }
      await lock.setPosition(length);
      await old.writeAsBytes(oldBytes, flush: true);
      await next.writeAsBytes(newBytes, flush: true);
      await journal.writeAsString(
        jsonEncode({
          'schema': 1,
          'countXor': source.countXor,
          'oldIndex': _hash(oldBytes),
          'newIndex': _hash(newBytes),
          'oldLength': length,
          'newLength': cursor,
        }),
        flush: true,
      );
      await testCheckpoint?.call('prepared');
      control.check();
      var done = 0, bytes = 0;
      final total = cursor - length;
      for (final e in replacements.entries) {
        for (var p = 0; p < e.value.length; p += ArchiveExport.chunkSize) {
          control.check();
          final end = (p + ArchiveExport.chunkSize).clamp(0, e.value.length);
          await lock.writeFrom(e.value, p, end);
          bytes += end - p;
          progress(
            ExportProgress(
              'Guardando dentro del SAF',
              e.key,
              done,
              replacements.length,
              bytes,
              total,
            ),
          );
        }
        done++;
      }
      await lock.flush();
      await testCheckpoint?.call('payload');
      control.check();
      // Verify all appended ranges before the new index becomes visible.
      for (final e in replacements.entries) {
        final r = parsed.entries[e.key]!;
        await lock.setPosition(r.offset);
        final b = await lock.read(r.length);
        if (_hash(b) != _hash(e.value)) {
          throw const FormatException(
            'La verificación del recurso escrito no coincide.',
          );
        }
      }
      if (keepBackup) {
        final backup = File(
          '$sahPath.${DateTime.now().microsecondsSinceEpoch}.bak',
        );
        await backup.writeAsBytes(oldBytes, flush: true);
      }
      await next.rename(sah.path);
      await testCheckpoint?.call('committed');
      // No cancellation after commit: the entire transaction is already valid.
      await old.delete();
      await journal.delete();
      progress(
        ExportProgress(
          'Cambios guardados',
          sah.uri.pathSegments.last,
          replacements.length,
          replacements.length,
          total,
          total,
        ),
      );
    } catch (_) {
      if (await journal.exists()) {
        final hash = _hash(await sah.readAsBytes());
        if (hash == _hash(oldBytes)) {
          await lock?.truncate(length);
          await lock?.flush();
          if (await next.exists()) await next.delete();
          if (await old.exists()) await old.delete();
          await journal.delete();
        } else if (hash == _hash(newBytes)) {
          if (await next.exists()) await next.delete();
          if (await old.exists()) await old.delete();
          await journal.delete();
        }
      } else {
        if (await next.exists()) await next.delete();
        if (await old.exists()) await old.delete();
      }
      rethrow;
    } finally {
      if (lock != null) {
        if (locked) await lock.unlock();
        await lock.close();
      }
      try {
        await source.refreshAfterWrite();
      } finally {
        source.endWrite();
      }
    }
  }

  static Future<String> recover(String sahPath, String safPath) async {
    final sah = File(sahPath),
        saf = File(safPath),
        journal = File('$sahPath.shaiya-transaction.json'),
        old = File('$sahPath.shaiya-old'),
        next = File('$sahPath.shaiya-next');
    for (final f in [sah, saf, journal, old]) {
      await _regular(f);
    }
    if (await journal.length() > 4096) {
      throw const FormatException('Registro de recuperación inválido.');
    }
    final j = jsonDecode(await journal.readAsString()) as Map<String, dynamic>;
    if (j['schema'] != 1 ||
        j['oldLength'] is! int ||
        j['newLength'] is! int ||
        j['oldLength'] < 0 ||
        j['newLength'] < j['oldLength'] ||
        (j['countXor'] != null &&
            (j['countXor'] is! int ||
                j['countXor'] < 0 ||
                j['countXor'] > 0xffffffff))) {
      throw const FormatException('Transacción no reconocida.');
    }
    final oldBytes = await old.readAsBytes();
    if (_hash(oldBytes) != j['oldIndex']) {
      throw const FormatException('El índice de recuperación no coincide.');
    }
    final h = await saf.open(mode: FileMode.append);
    await h.lock(FileLock.exclusive);
    String outcome;
    try {
      final current = _hash(await sah.readAsBytes()), size = await h.length();
      if (current == j['oldIndex'] &&
          size >= j['oldLength'] &&
          size <= j['newLength']) {
        ArchiveIndex.decode(
          oldBytes,
          j['oldLength'],
          countXor: j['countXor'] as int?,
        );
        await h.truncate(j['oldLength']);
        await h.flush();
        outcome =
            'Se conservó el archivo anterior; los cambios incompletos no se aplicaron.';
      } else if (current == j['newIndex'] && size == j['newLength']) {
        ArchiveIndex.decode(
          await sah.readAsBytes(),
          size,
          countXor: j['countXor'] as int?,
        );
        outcome =
            'La transacción ya estaba confirmada. Se conservan los cambios.';
      } else {
        throw const FormatException(
          'Los archivos cambiaron después de la interrupción. Recuperación automática rechazada.',
        );
      }
      if (await next.exists()) {
        await _regular(next);
        await next.delete();
      }
      await old.delete();
      await journal.delete();
    } finally {
      await h.unlock();
      await h.close();
    }
    return outcome;
  }
}
