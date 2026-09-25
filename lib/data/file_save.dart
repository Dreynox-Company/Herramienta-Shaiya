import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class FileSave {
  static String hash(List<int> b) => sha256.convert(b).toString();
  static Future<void> replace(
    String path,
    Uint8List bytes, {
    required String expectedHash,
    bool keepBackup = false,
  }) async {
    final file = File(path), dir = Directory(p.dirname(path));
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('Solo se reemplazan archivos regulares.');
    }
    final resolved = await file.resolveSymbolicLinks(),
        parent = await dir.resolveSymbolicLinks();
    if (!p.isWithin(parent, resolved)) {
      throw const FormatException('El archivo sale del directorio autorizado.');
    }
    final before = await file.readAsBytes();
    if (hash(before) != expectedHash) {
      throw const FormatException(
        'El archivo cambió fuera del editor. No se sobrescribe una versión ajena.',
      );
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final tmp = File('$path.$stamp.partial');
    await tmp.create(exclusive: true);
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      if (hash(await tmp.readAsBytes()) != hash(bytes)) {
        throw const FormatException(
          'La verificación de escritura no coincide.',
        );
      }
      if (hash(await file.readAsBytes()) != expectedHash) {
        throw const FormatException(
          'Conflicto de versión al confirmar el guardado.',
        );
      }
      if (keepBackup) {
        await File('$path.$stamp.bak').writeAsBytes(before, flush: true);
      }
      await tmp.rename(path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }
}
