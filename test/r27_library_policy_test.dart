import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/data/library.dart';

Future<void> putText(Directory root, String path, String value) async {
  final file = File('${root.path}/$path');
  await file.parent.create(recursive: true);
  await file.writeAsString(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a resource-only directory requires an explicit opt-in', () async {
    final root = await Directory.systemTemp.createTemp('r27-library-policy-');
    addTearDown(() => root.delete(recursive: true));
    await putText(root, 'Script/note.txt', 'not a playable character');
    await expectLater(Library.fromDirectory(root.path, (_) {}), throwsFormatException);
    await expectLater(Library.fromDirectory(root.path, (_) {}, requireCharacter: true), throwsFormatException);
    final resources = await Library.fromDirectory(root.path, (_) {}, requireCharacter: false);
    addTearDown(resources.dispose);
    expect(resources.files.keys, ['script/note.txt']);
    expect(String.fromCharCodes(await resources.read('script/note.txt')), 'not a playable character');
  });

  test('nested DATA is normalized in both strict and resource-only mode', () async {
    final root = await Directory.systemTemp.createTemp('r27-nested-library-');
    addTearDown(() => root.delete(recursive: true));
    await putText(root, 'client/DATA_Espanol/Character/Human/example.txt', 'body metadata');
    await putText(root, 'client/DATA_Espanol/Script/example.txt', 'script metadata');
    for (final strict in [true, false]) {
      final lib = await Library.fromDirectory(root.path, (_) {}, requireCharacter: strict);
      addTearDown(lib.dispose);
      expect(lib.files.keys.toSet(), {'character/human/example.txt', 'script/example.txt'});
      expect(String.fromCharCodes(await lib.read('script/example.txt')), 'script metadata');
    }
  });

  test('resource mode does not silently choose one of two nested DATA roots', () async {
    final root = await Directory.systemTemp.createTemp('r27-ambiguous-library-');
    addTearDown(() => root.delete(recursive: true));
    await putText(root, 'clientA/Character/Human/example.txt', 'first');
    await putText(root, 'clientB/Character/Human/example.txt', 'second');
    for (final strict in [true, false]) {
      await expectLater(
        Library.fromDirectory(root.path, (_) {}, requireCharacter: strict),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('varias bibliotecas'))),
      );
    }
  });

  test('resource mode does not weaken canonical relative path validation', () {
    for (final path in ['../outside.txt', 'Character/../../outside.txt', '/absolute.txt', r'C:\outside.txt']) {
      expect(() => canon(path), throwsFormatException);
    }
    expect(canon(r'Character\Human\EXAMPLE.TXT'), 'character/human/example.txt');
  });
}
