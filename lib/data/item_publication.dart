import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/client_locale.dart';
import '../core/game_text_codec.dart';
import '../editor/document.dart';
import '../editor/schema_reader.dart';
import '../editor/structure_editor.dart';
import 'file_save.dart';
import 'library.dart';

/// Explicit repair/create operations against a known DBItemData + Spanish
/// DBItemText pair. Never creates an item just because its Spanish name is ???? .
class ItemPublicationEdit {
  final int type, id;
  final int? templateId;
  final String name, description;
  final Map<String, String> properties;
  const ItemPublicationEdit({
    required this.type,
    required this.id,
    required this.name,
    required this.description,
    this.templateId,
    this.properties = const {},
  });
}

class ItemPublication {
  final String dataPath, textPath;
  final Uint8List dataBefore, textBefore, dataAfter, textAfter;
  final List<String> warnings;
  final List<Map<String, Object?>> changes;
  ItemPublication._(
    this.dataPath,
    this.textPath,
    this.dataBefore,
    this.textBefore,
    this.dataAfter,
    this.textAfter,
    this.warnings,
    this.changes,
  );

  static FieldSpan field(EditDocument d, int row, String name) =>
      d
          .fields(row)
          .where((f) => f.spec.name.toLowerCase() == name.toLowerCase())
          .firstOrNull ??
      (throw FormatException('Falta $name en ${d.path}.'));
  static int? locate(EditDocument d, int type, int id) {
    final found = <int>[];
    for (var row = 0; row < d.rows.length; row++) {
      final fields = StructureEditor.identity(d, row);
      if (fields.length != 2)
        throw const FormatException('Se requiere identidad Type + TypeId.');
      if (int.tryParse(d.read(fields[0])) == type &&
          int.tryParse(d.read(fields[1])) == id)
        found.add(row);
    }
    if (found.length > 1) throw FormatException('Clave duplicada $type:$id.');
    return found.firstOrNull;
  }

  static ItemPublication prepare({
    required Uint8List data,
    required Uint8List text,
    required String dataPath,
    required String textPath,
    required List<ItemPublicationEdit> edits,
  }) {
    if (edits.isEmpty || edits.length > 32)
      throw const FormatException('Lote de objetos inválido.');
    if (ClientLocale.languageOf(textPath) != 'es' ||
        ClientLocale.directory(textPath) != ClientLocale.directory(dataPath)) {
      throw const FormatException(
        'Se requiere texto español de la misma familia/directorio.',
      );
    }
    final d = EditorReader.open(data, dataPath),
        t = EditorReader.open(
          text,
          textPath,
          encoding: GameTextEncoding.windows1252,
        );
    if (!StructureEditor.supported(d) || !StructureEditor.supported(t)) {
      throw const FormatException(
        'Las tablas no tienen un esquema completo con IDs explícitos.',
      );
    }
    final changes = <Map<String, Object?>>[], seen = <String>{};
    for (final edit in edits) {
      final key = '${edit.type}:${edit.id}';
      if (!seen.add(key) ||
          edit.type < 1 ||
          edit.type > 255 ||
          edit.id < 1 ||
          edit.id > 65535) {
        throw const FormatException('ID repetido o fuera de rango.');
      }
      if (edit.name.trim().isEmpty ||
          edit.name.length > 100 ||
          RegExp(r'^[?\s]+$').hasMatch(edit.name) ||
          edit.description.length > 2048 ||
          edit.name.contains('\u0000') ||
          edit.description.contains('\u0000')) {
        throw const FormatException('Nombre o descripción inválidos.');
      }
      GameTextCodec.windows.encode(edit.name);
      GameTextCodec.windows.encode(edit.description);
      var row = locate(d, edit.type, edit.id),
          textRow = locate(t, edit.type, edit.id);
      final creating = edit.templateId != null;
      if (creating) {
        // The bundled offline backend 0.1.2 uses byte TypeId. Do not introduce
        // new IDs that would be truncated there. Existing higher IDs stay readable.
        if (edit.id > 255)
          throw const FormatException(
            'El backend offline 0.1.2 solo admite nuevos TypeId de 1 a 255.',
          );
        if (row != null || textRow != null)
          throw FormatException('$key ya existe: reparar, no duplicar.');
        final template = locate(d, edit.type, edit.templateId!),
            textTemplate = locate(t, edit.type, edit.templateId!);
        if (template == null || textTemplate == null)
          throw const FormatException(
            'La plantilla debe existir en ambas tablas.',
          );
        void clone(EditDocument doc, int from) {
          final ids = StructureEditor.identity(doc, from);
          StructureEditor.duplicate(doc, from, {
            ids[0].spec.name: '${edit.type}',
            ids[1].spec.name: '${edit.id}',
          });
        }

        clone(d, template);
        clone(t, textTemplate);
        row = d.rows.length - 1;
        textRow = t.rows.length - 1;
      }
      if (row == null || textRow == null) {
        throw FormatException(
          '$key no está en ambas tablas; elige una plantilla explícita o repara la familia de datos.',
        );
      }
      for (final e in edit.properties.entries) {
        if (const {
          'itemtype',
          'itemtypeid',
          'type',
          'typeid',
        }.contains(e.key.toLowerCase())) {
          throw const FormatException(
            'No se cambia la identidad como propiedad.',
          );
        }
        final f = field(d, row, e.key);
        if (f.spec.text || f.spec.type == 'opaque')
          throw const FormatException('Se esperaba una propiedad numérica.');
        final value = int.tryParse(e.value);
        if (value == null || value < 0 || value > 2147483647) {
          throw FormatException('Propiedad fuera de rango: ${e.key}.');
        }
        d.edit(row, f, e.value);
      }
      t.edit(textRow, field(t, textRow, 'itemname'), edit.name.trim());
      t.edit(textRow, field(t, textRow, 'text'), edit.description);
      changes.add({
        'type': edit.type,
        'typeId': edit.id,
        'action': creating ? 'create-from-template' : 'repair-existing',
        'templateId': edit.templateId,
        'name': edit.name.trim(),
        'properties': edit.properties,
      });
    }
    final outD = d.exportBytes(), outT = t.exportBytes();
    final checkD = EditorReader.open(outD, dataPath),
        checkT = EditorReader.open(
          outT,
          textPath,
          encoding: GameTextEncoding.windows1252,
        );
    if (!checkD.complete ||
        !checkT.complete ||
        checkD.rows.length != d.rows.length ||
        checkT.rows.length != t.rows.length) {
      throw const FormatException('El lote no supera la relectura.');
    }
    for (final edit in edits) {
      final row = locate(checkD, edit.type, edit.id),
          textRow = locate(checkT, edit.type, edit.id);
      if (row == null ||
          textRow == null ||
          checkT.read(field(checkT, textRow, 'itemname')) != edit.name.trim()) {
        throw const FormatException(
          'La identidad o el nombre no sobrevivieron la relectura.',
        );
      }
      for (final p in edit.properties.entries) {
        if (checkD.read(field(checkD, row, p.key)) != p.value) {
          throw const FormatException(
            'Una propiedad no sobrevivió la relectura.',
          );
        }
      }
    }
    return ItemPublication._(
      canon(dataPath),
      canon(textPath),
      data,
      text,
      outD,
      outT,
      {...d.warnings, ...t.warnings}.toList(),
      changes,
    );
  }

  /// Publish a NEW complete patch folder only after all files pass validation.
  /// Live DATA/SPK is not mutated by this multi-file operation.
  Future<Directory> export(Library library, Directory destination) async {
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('La carpeta de publicación ya existe.');
    }
    await destination.parent.create(recursive: true);
    final stage = await destination.parent.createTemp('.appearance-stage-');
    try {
      for (final pair in [
        (dataPath, dataBefore, dataAfter),
        (textPath, textBefore, textAfter),
      ]) {
        final actual = await library.read(pair.$1);
        if (FileSave.hash(actual) != FileSave.hash(pair.$2)) {
          throw FormatException('DATA cambió durante la edición: ${pair.$1}.');
        }
        final file = File('${stage.path}/COPIAR_EN_DATA/${pair.$1}');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(pair.$3, flush: true);
        if (FileSave.hash(await file.readAsBytes()) != FileSave.hash(pair.$3)) {
          throw const FileSystemException('Error de integridad al publicar.');
        }
      }
      await File('${stage.path}/manifest.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'schema': 1,
          'kind': 'shaiya-item-table-patch',
          'nativeRuntimeModified': false,
          'changes': changes,
          'warnings': warnings,
          'files': [
            for (final pair in [
              (dataPath, dataBefore, dataAfter),
              (textPath, textBefore, textAfter),
            ])
              {
                'path': pair.$1,
                'beforeSha256': FileSave.hash(pair.$2),
                'afterSha256': FileSave.hash(pair.$3),
              },
          ],
        }),
        flush: true,
      );
      await File('${stage.path}/LEEME.txt').writeAsString(
        'PARCHE DE OBJETOS — DATA ORIGINAL INTACTA\n\n'
        'Cierra el juego y el servidor local. Respalda las dos tablas originales.\n'
        'Comprueba que sus SHA-256 coinciden con beforeSha256 en manifest.json.\n'
        'Copia el contenido de COPIAR_EN_DATA a la misma DATA con que se creó el lote.\n'
        'No mezcles BinarySData de otra versión ni apliques solo una de las tablas.\n'
        'Reabre DATA en Studio para comprobar nombre, icono e Image.\n\n'
        'Los objetos nuevos conservan propiedades de una plantilla explícita.\n'
        'No se escriben DBSetItemData, bases del servidor, modelos MLT nuevos ni game.exe.\n'
        'Las tablas de balance del servidor deben sincronizarse por su importador propio.\n'
        'Esto no instala un controlador nativo de vuelo.\n',
        flush: true,
      );
      // Recheck source immediately before committing the complete directory.
      for (final pair in [(dataPath, dataBefore), (textPath, textBefore)]) {
        if (FileSave.hash(await library.read(pair.$1)) !=
            FileSave.hash(pair.$2)) {
          throw const FormatException(
            'Conflicto de DATA al confirmar la publicación.',
          );
        }
      }
      if (await destination.exists())
        throw const FileSystemException('Conflicto de destino.');
      return await stage.rename(destination.path);
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }
}
