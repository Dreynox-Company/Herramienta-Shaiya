import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/file_save.dart';
import '../data/item_assets.dart';
import '../data/item_workspace.dart';

Future<void> importItemAsset(
  BuildContext context,
  ItemWorkspace workspace,
  String path,
) async {
  if (!workspace.source.files.containsKey(path)) {
    throw const FormatException(
      'El recurso referenciado no existe en la DATA conectada.',
    );
  }
  final extension = path.split('.').last;
  final file = await openFile(
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Recurso nativo',
        extensions: extension == 'dds' ? ['dds', 'tga'] : [extension],
      ),
    ],
  );
  if (file == null) return;
  if (await file.length() > 32 * 1024 * 1024) {
    throw const FormatException('Recurso mayor de 32 MiB.');
  }
  final original = await workspace.preview.read(path);
  final replacement = await compute(ItemAssetReplacement.validate, (
    path,
    original,
    await file.readAsBytes(),
  ));
  if (!context.mounted) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Preparar sustitución de recurso compartido'),
      content: SelectableText(
        '$path\n\n${replacement.description}\n\n'
        'Se mantienen ruta y formato nativos. TODOS los objetos que utilicen este archivo '
        'verán el cambio; puede haber referencias fuera del catálogo de ítems. '
        'La sustitución se guarda en la misma sesión, puede deshacerse y se exporta como parche. '
        'No modifica DATA activa ni sustituye la prueba visual en el cliente.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirmar recurso compartido'),
        ),
      ],
    ),
  );
  if (accepted != true) return;
  await workspace.stageAsset(
    path,
    replacement.bytes,
    expectedHash: FileSave.hash(original),
    title: 'Importar $path',
  );
}
