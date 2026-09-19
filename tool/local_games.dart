import 'dart:convert';
import 'dart:io';
import 'package:herramienta_shaiya/offline/save_store.dart';

/// Storage CLI for local-runtime development. It does not start game.exe and
/// does not claim that persisted JSON is already authoritative game-server state.
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'Uso: dart run tool/local_games.dart DIRECTORIO ACCION [--clave valor]\n'
      'Acciones: list, create, load, save, trash, restore.\n'
      'create: --title "Partida" --faction luz|furia --corpus HASH\n'
      'load: --id ID [--corpus HASH]\n'
      'save: --id ID --revision N --corpus HASH --state archivo.json\n'
      'trash/restore: --id ID --revision N\n'
      'Esta herramienta administra guardados; no incluye un servidor de juego.',
    );
    exitCode = 2;
    return;
  }
  try {
    final values = <String, String>{};
    for (var i = 2; i < args.length; i += 2) {
      if (!args[i].startsWith('--') ||
          i + 1 >= args.length ||
          values.containsKey(args[i])) {
        throw const FormatException('Argumentos incompletos o repetidos.');
      }
      values[args[i]] = args[i + 1];
    }
    String need(String key) =>
        values['--$key'] ?? (throw FormatException('Falta --$key'));
    final store = SaveStore(Directory(args[0]));
    Object output;
    switch (args[1]) {
      case 'list':
        final listing = await store.list(includeDeleted: true);
        output = {
          'partidas': listing.saves.map((v) => v.metadata).toList(),
          'errores': listing.unreadable,
        };
      case 'create':
        output = (await store.create(
          title: need('title'),
          faction: need('faction'),
          corpusSha256: need('corpus'),
        )).metadata;
      case 'load':
        final save = await store.load(
          need('id'),
          expectedCorpus: values['--corpus'],
        );
        output = {...save.metadata, 'state': save.state};
      case 'save':
        final source = File(need('state'));
        if (await source.length() > SaveStore.maxSnapshotBytes) {
          throw const FormatException('Estado demasiado grande.');
        }
        final state = jsonDecode(await source.readAsString());
        if (state is! Map<String, dynamic>) {
          throw const FormatException('El estado debe ser un objeto JSON.');
        }
        output = (await store.update(
          need('id'),
          expectedRevision: int.parse(need('revision')),
          expectedCorpus: need('corpus'),
          state: state,
        )).metadata;
      case 'trash':
      case 'restore':
        output = (await store.trash(
          need('id'),
          expectedRevision: int.parse(need('revision')),
          restore: args[1] == 'restore',
        )).metadata;
      default:
        throw const FormatException('Acción no reconocida.');
    }
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'runtime': 'storage-only; native-client-not-connected',
        'result': output,
      }),
    );
  } catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}
