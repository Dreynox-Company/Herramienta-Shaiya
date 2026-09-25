import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/offline/save_store.dart';
import 'package:path/path.dart' as p;

const corpus =
    '509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d';
void main() {
  late Directory directory;
  late SaveStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shaiya-save-test-');
    store = SaveStore(directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Future<SaveSnapshot> create({String faction = 'luz'}) => store.create(
    title: 'Partida Ñ — dragón 🐉',
    faction: faction,
    corpusSha256: corpus,
    state: {
      'characters': [
        {'name': 'Ángela', 'level': 1},
      ],
      'gold': 9223372036854775807,
    },
  );
  test(
    'create/load retain Unicode, faction, corpus and 64-bit values',
    () async {
      final s = await create();
      final loaded = await SaveStore(
        directory,
      ).load(s.id, expectedCorpus: corpus);
      expect(loaded.title, 'Partida Ñ — dragón 🐉');
      expect(loaded.state['gold'], 9223372036854775807);
      expect(loaded.faction, 'luz');
      expect(loaded.revision, 1);
      expect(loaded.state, s.state);
      expect(loaded.checksum.length, 64);
    },
  );
  test('Luz and Furia saves are isolated', () async {
    final a = await create(), b = await create(faction: 'furia');
    await store.update(
      a.id,
      expectedRevision: 1,
      expectedCorpus: corpus,
      state: {'gold': 33},
    );
    expect((await store.load(b.id)).state['gold'], 9223372036854775807);
    expect((await store.list()).saves.length, 2);
  });
  test('updates preserve immutable previous revisions', () async {
    final a = await create(),
        path = p.join(directory.path, a.id, '000000000001.json');
    final original = await File(path).readAsBytes();
    final b = await store.update(
      a.id,
      expectedRevision: 1,
      expectedCorpus: corpus,
      state: {'gold': 7},
      title: 'Sesión 2',
    );
    expect(b.revision, 2);
    expect(b.title, 'Sesión 2');
    expect(await File(path).readAsBytes(), original);
    expect((await store.load(a.id)).state['gold'], 7);
  });
  test('stale updates do not replace newer state', () async {
    final a = await create();
    await store.update(
      a.id,
      expectedRevision: 1,
      expectedCorpus: corpus,
      state: {'gold': 1},
    );
    await expectLater(
      store.update(
        a.id,
        expectedRevision: 1,
        expectedCorpus: corpus,
        state: {'gold': 2},
      ),
      throwsA(isA<SaveConflict>()),
    );
    expect((await store.load(a.id)).state['gold'], 1);
  });
  test('different dataset cannot silently load or save progress', () async {
    final a = await create();
    await expectLater(
      store.load(a.id, expectedCorpus: 'f' * 64),
      throwsA(isA<SaveConflict>()),
    );
    await expectLater(
      store.update(
        a.id,
        expectedRevision: 1,
        expectedCorpus: 'f' * 64,
        state: {},
      ),
      throwsA(isA<SaveConflict>()),
    );
  });
  test('deletion is reversible, excluded from ordinary list', () async {
    final a = await create();
    final deleted = await store.trash(a.id, expectedRevision: 1);
    expect(deleted.deleted, true);
    expect((await store.list()).saves, isEmpty);
    expect((await store.list(includeDeleted: true)).saves.single.id, a.id);
    await expectLater(store.load(a.id), throwsA(isA<SaveConflict>()));
    final restored = await store.trash(
      a.id,
      expectedRevision: 2,
      restore: true,
    );
    expect(restored.deleted, false);
    expect(restored.revision, 3);
    expect((await store.load(a.id)).state, a.state);
  });
  test(
    'pending file after simulated interruption never becomes current',
    () async {
      final a = await create();
      final broken = SaveStore(
        directory,
        faultInjector: (stage) => throw StateError('simulated disk failure'),
      );
      await expectLater(
        broken.update(
          a.id,
          expectedRevision: 1,
          expectedCorpus: corpus,
          state: {'gold': 99},
        ),
        throwsStateError,
      );
      expect((await store.load(a.id)).revision, 1);
      await File(
        p.join(directory.path, a.id, '.pending-from-crash'),
      ).writeAsString('broken');
      expect((await store.load(a.id)).state, a.state);
    },
  );
  test(
    'concurrent instances using same directory serialize revisions',
    () async {
      final a = await create();
      Future<String> write(int n) async {
        try {
          await SaveStore(directory).update(
            a.id,
            expectedRevision: 1,
            expectedCorpus: corpus,
            state: {'gold': n},
          );
          return 'saved';
        } on SaveConflict {
          return 'conflict';
        }
      }

      final results = await Future.wait([
        for (var i = 0; i < 10; i++) write(i),
      ]);
      expect(results.where((v) => v == 'saved').length, 1);
      expect((await store.load(a.id)).revision, 2);
    },
  );
  test(
    'corrupt latest revision is reported, never rolled back invisibly',
    () async {
      final a = await create();
      await store.update(
        a.id,
        expectedRevision: 1,
        expectedCorpus: corpus,
        state: {'gold': 1},
      );
      await File(
        p.join(directory.path, a.id, '000000000002.json'),
      ).writeAsString('{bad');
      await expectLater(store.load(a.id), throwsFormatException);
      final list = await store.list();
      expect(list.unreadable.containsKey(a.id), true);
      expect(list.saves, isEmpty);
    },
  );
  test('payload changes without updating checksum are detected', () async {
    final a = await create();
    final file = File(p.join(directory.path, a.id, '000000000001.json'));
    final envelope = jsonDecode(await file.readAsString()) as Map;
    envelope['payload'] = (envelope['payload'] as String).replaceFirst(
      'Ángela',
      'Wrong',
    );
    await file.writeAsString(jsonEncode(envelope));
    await expectLater(store.load(a.id), throwsFormatException);
  });
  test('copied save with mismatching ID is rejected', () async {
    final a = await create(), b = await create();
    await File(
      p.join(directory.path, a.id, '000000000001.json'),
    ).copy(p.join(directory.path, b.id, '000000000001.json'));
    await expectLater(store.load(b.id), throwsFormatException);
  });
  for (final id in ['../outside', 'C:\\game', '/tmp', '123', '..', 'a' * 33]) {
    test('path traversal and malformed ID rejected: $id', () async {
      await expectLater(store.load(id), throwsFormatException);
    });
  }
  test('non-finite and deep states cannot be serialized', () async {
    expect(
      () => store.create(
        title: 'T',
        faction: 'luz',
        corpusSha256: corpus,
        state: {'v': double.nan},
      ),
      throwsFormatException,
    );
    Object? state = 1;
    for (var i = 0; i < 50; i++) {
      state = [state];
    }
    expect(
      () => store.create(
        title: 'T',
        faction: 'luz',
        corpusSha256: corpus,
        state: {'v': state},
      ),
      throwsFormatException,
    );
  });
  test('snapshot size is bounded and previous save remains intact', () async {
    final a = await create();
    await expectLater(
      store.update(
        a.id,
        expectedRevision: 1,
        expectedCorpus: corpus,
        state: {'v': 'X' * SaveStore.maxSnapshotBytes},
      ),
      throwsFormatException,
    );
    expect((await store.load(a.id)).revision, 1);
  });
  test('unknown faction, bad title and missing corpus are not invented', () {
    expect(
      () => store.create(title: '', faction: 'luz', corpusSha256: corpus),
      throwsFormatException,
    );
    expect(
      () => store.create(title: 'T', faction: 'new', corpusSha256: corpus),
      throwsFormatException,
    );
    expect(
      () => store.create(title: 'T', faction: 'luz', corpusSha256: 'unknown'),
      throwsFormatException,
    );
  });
  test('symlink revisions cannot redirect reads or writes', () async {
    if (Platform.isWindows) return; // Symlink privileges differ on Windows.
    final a = await create();
    final revision = p.join(directory.path, a.id, '000000000001.json');
    final original = await File(revision).readAsBytes();
    final outside = File(p.join(directory.path, 'outside'));
    await outside.writeAsBytes(original);
    await File(revision).delete();
    await Link(revision).create(outside.path);
    await expectLater(store.load(a.id), throwsFormatException);
    expect(await outside.readAsBytes(), original);
  });
}
