import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/formats.dart';
import '../core/textures.dart';
import '../core/spk_archive.dart';
import 'file_save.dart';
import 'library.dart';
import 'spk_source.dart';

class ResourceEntry {
  /// Stable identity within this source. Never a guessed game filename.
  final String key;
  final String? path;
  final String displayPath;
  final bool confirmed;
  final SpkRecord? record;
  String? format;
  String? error;
  ResourceEntry({
    required this.key,
    required this.path,
    required this.displayPath,
    required this.confirmed,
    this.record,
    this.format,
  });
  String get name => baseName(displayPath);
  String get folder => directoryName(displayPath);
  bool get readable => path != null;
  String get expectedFormat {
    final dot = displayPath.lastIndexOf('.');
    return dot < 0 ? 'BIN' : displayPath.substring(dot + 1).toUpperCase();
  }

  String get kind => format ?? expectedFormat;
  bool get isModel =>
      const {'3DC', '3DO', 'MLT', 'ITM', 'MON', 'SMOD', 'DG'}.contains(kind);
  bool get isImage =>
      const {'DDS', 'PNG', 'TGA', 'BMP', 'JPEG', 'JPG', 'GIF'}.contains(kind);
  bool get isTable => const {
    'SDATA',
    'MLT',
    'ITM',
    'MON',
    'XML',
    'INI',
    'TXT',
    'JSON',
    'CSV',
  }.contains(kind);
  String get state => !readable
      ? 'Bloqueado'
      : error != null
      ? 'Error de lectura'
      : format != null
      ? 'Leído'
      : 'Por verificar';
}

class ResourceRead {
  final ResourceEntry entry;
  final Uint8List bytes;
  final String format, hash;
  ResourceRead(this.entry, this.bytes, this.format)
    : hash = sha256.convert(bytes).toString();
}

/// Metadata index independent of character availability and semantic filenames.
/// Enumerating never decrypts, extracts or drops blocked SPK records. A hint is
/// searchable, but can never become a canonical Character/Item path here.
class ResourceIndex extends ChangeNotifier {
  final Library library;
  late final List<ResourceEntry> entries;
  late final Set<ResourceEntry> _members;
  late final int _readable;
  ResourceEntry? selected;
  bool indexing = false, cancelled = false, closed = false;
  int scanned = 0, rejected = 0, oversized = 0;
  String status = '';
  int _generation = 0;

  ResourceIndex(this.library) {
    final spk = library.spk;
    if (spk == null) {
      entries = library.files.keys
          .map(
            (path) => ResourceEntry(
              key: path,
              path: path,
              displayPath: path,
              confirmed: true,
            ),
          )
          .toList();
    } else {
      final byId = <String, String>{
        for (final p in library.files.entries) p.value: p.key,
      };
      entries = [
        for (final r in spk.index.resources)
          ResourceEntry(
            key: r.idHex,
            path: byId[r.idHex],
            record: r,
            displayPath:
                spk.names[r.entryId] ??
                byId[r.idHex] ??
                '_SPK_SinNombre/${r.idHex}.bin',
            confirmed: spk.names.isConfirmed(r.entryId),
            format: spk.validatedFormat(r.entryId),
          ),
      ];
    }
    _members = entries.toSet();
    _readable = entries.where((e) => e.readable).length;
    entries.sort((a, b) {
      final compared = a.displayPath.toLowerCase().compareTo(
        b.displayPath.toLowerCase(),
      );
      return compared != 0 ? compared : a.key.compareTo(b.key);
    });
  }

  int get readableCount => _readable;
  int get blockedCount => entries.length - readableCount;
  int get readCount =>
      entries.where((e) => e.format != null && e.error == null).length;
  bool get writable =>
      library.spk != null || (!library.saf && library.archive == null);

  void select(ResourceEntry entry) {
    if (!_members.contains(entry)) {
      throw ArgumentError('Recurso de otra biblioteca.');
    }
    if (selected == entry) return;
    selected = entry;
    _notify();
  }

  List<ResourceEntry> filter(String query, String group) {
    if (group == 'Todos' && query.trim().isEmpty) return entries;
    final words = query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    return entries
        .where((e) {
          final content = '${e.displayPath} ${e.key} ${e.kind}'.toLowerCase();
          if (!words.every(content.contains)) return false;
          return switch (group) {
            'Modelos' => e.isModel,
            'Texturas' => e.isImage,
            'Animaciones' => e.kind == 'ANI',
            'Tablas / texto' => e.isTable,
            'Bloqueados' => !e.readable,
            'Errores' => e.error != null,
            _ => true,
          };
        })
        .toList(growable: false);
  }

  Future<ResourceRead> read(
    ResourceEntry entry, {
    int limit = 64 * 1024 * 1024,
  }) async {
    if (!_members.contains(entry)) {
      throw ArgumentError('Recurso de otra biblioteca.');
    }
    final path = entry.path;
    if (path == null) {
      throw const SpkFailure(
        'SPK_RESOURCE_LOCKED',
        'Este registro está indexado, pero su perfil de lectura aún no está validado.',
      );
    }
    try {
      final bytes = await library.read(path, limit: limit);
      final format = await compute(SpkArchiveSource.detectFormat, bytes);
      if (!closed) {
        entry.format = format;
        entry.error = null;
        if (!indexing) _notify();
      }
      return ResourceRead(entry, bytes, format);
    } catch (e) {
      if (!closed) {
        entry.format = null;
        entry.error = '$e';
        if (!indexing) _notify();
      }
      rethrow;
    }
  }

  /// Explicit, cancelable format indexing. Metadata only is retained; not all
  /// plaintext buffers. No cached type authorizes a future plaintext read.
  Future<void> scan({Iterable<ResourceEntry>? selection}) async {
    if (indexing || closed) return;
    final generation = ++_generation;
    final candidates = (selection ?? entries).where((e) => e.readable).toList();
    indexing = true;
    cancelled = false;
    scanned = rejected = oversized = 0;
    try {
      for (final entry in candidates) {
        if (closed || cancelled || generation != _generation) break;
        if ((entry.record?.decodedBytes ?? 0) > 64 * 1024 * 1024) {
          oversized++;
        } else {
          try {
            await read(entry);
          } catch (_) {
            rejected++;
          }
        }
        scanned++;
        status =
            '$scanned/${candidates.length} · $rejected fallos · $oversized fuera de presupuesto';
        if (scanned % 16 == 0) {
          _notify();
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      if (!closed && generation == _generation) {
        indexing = false;
        status =
            '${cancelled ? 'Indexación cancelada' : 'Indexación finalizada'} · $status';
        _notify();
      }
    }
  }

  Future<void> replace(ResourceRead original, Uint8List replacement) async {
    if (!writable || indexing) {
      throw StateError('La fuente no permite reemplazar ahora.');
    }
    if (!_members.contains(original.entry) || original.entry.path == null) {
      throw ArgumentError('Recurso ajeno.');
    }
    if (replacement.length > 64 * 1024 * 1024) {
      throw const FormatException('Recurso mayor de 64 MiB.');
    }
    final nextFormat = await compute(
      SpkArchiveSource.detectFormat,
      replacement,
    );
    if (nextFormat != original.format || nextFormat == 'BIN') {
      throw const FormatException(
        'El reemplazo no tiene el mismo formato reconocido.',
      );
    }
    // Exact parsers, not just a magic number. No implicit retargeting.
    await compute(validateResourceReplacement, (
      original.bytes,
      replacement,
      nextFormat,
    ));
    final path = original.entry.path!;
    if (library.isSpkWorkspace) {
      await library.writeSpkOverlay(
        {path: replacement},
        expectedHashes: {path: original.hash},
        keepBackup: true,
      );
      library.revision++;
    } else {
      await FileSave.replace(
        library.files[path]!,
        replacement,
        expectedHash: original.hash,
        keepBackup: true,
      );
      library.revision++;
    }
    _notify();
  }

  void _notify() {
    if (!closed) notifyListeners();
  }

  @override
  void dispose() {
    closed = true;
    cancelled = true;
    _generation++;
    super.dispose();
  }
}

void validateResourceReplacement((Uint8List, Uint8List, String) input) {
  final (original, next, format) = input;
  switch (format) {
    case '3DC':
      final before = MeshData.skinned(original, 'original.3dc');
      final after = MeshData.skinned(next, 'replacement.3dc');
      if (before.inverses.length != after.inverses.length) {
        throw const FormatException(
          'El reemplazo cambia el esqueleto; no se realiza retargeting implícito.',
        );
      }
    case '3DO':
      MeshData.object(next, 'replacement.3do');
    case 'ANI':
      final before = ClipData.parse(original, 'original.ani');
      final after = ClipData.parse(next, 'replacement.ani');
      if (before.bones.length != after.bones.length ||
          List.generate(
            before.bones.length,
            (i) => before.bones[i].parent != after.bones[i].parent,
          ).any((v) => v)) {
        throw const FormatException('La jerarquía ANI no coincide.');
      }
    case 'DDS' || 'PNG' || 'TGA' || 'BMP' || 'JPEG' || 'GIF':
      Pixels.decode(next, 'replacement.${format.toLowerCase()}');
    case 'MLT':
      readMlt(next, 'replacement.mlt');
    case 'ITM':
      readItm(next, 'replacement.itm');
    case 'MON':
      readMon(next, 'replacement.mon');
    default:
      throw const FormatException(
        'Este formato se modifica en el editor estructurado, no por sustitución directa.',
      );
  }
}
