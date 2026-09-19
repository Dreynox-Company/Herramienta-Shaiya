import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/archive_index.dart';
import 'package:herramienta_shaiya/data/archive_source.dart';
import 'package:herramienta_shaiya/data/archive_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shaiya-export-');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  ArchiveSource source(Map<String, Uint8List> files) {
    final entries = <String, ArchiveEntry>{};
    final data = BytesBuilder();
    var at = 0;
    for (final e in files.entries) {
      entries[e.key] = ArchiveEntry(e.key, at, e.value.length, 17);
      data.add(e.value);
      at += e.value.length;
    }
    final b = data.takeBytes();
    return ArchiveSource(
      ArchiveIndex(entries, {'version': 123}),
      (offset, length) async =>
          Uint8List.fromList(b.sublist(offset, offset + length)),
    );
  }

  test(
    'extracts all entries including formats not used by the renderer',
    () async {
      final s = source({
        'binarysdata/mobs.sdata': Uint8List.fromList([1, 2]),
        'extra/unknown.xyz': Uint8List.fromList([5, 6]),
        'zero.dat': Uint8List(0),
      });
      final r = await ArchiveExport.extract(
        s,
        temp,
        control: ExportControl(),
        progress: (_) {},
      );
      expect(r.files, 3);
      expect(await File('${r.folder}/extra/unknown.xyz').readAsBytes(), [5, 6]);
      expect(await File('${r.folder}/zero.dat').length(), 0);
    },
  );
  test('uses bounded ranges for large entries', () async {
    final length = 3 * 1024 * 1024 + 11;
    var max = 0;
    final s = ArchiveSource(
      ArchiveIndex({'large.dat': ArchiveEntry('large.dat', 0, length, 0)}, {}),
      (o, n) async {
        if (n > max) max = n;
        return Uint8List(n);
      },
    );
    await ArchiveExport.extract(
      s,
      temp,
      control: ExportControl(),
      progress: (_) {},
    );
    expect(max, lessThanOrEqualTo(1024 * 1024));
  });
  test('cancel removes only the new staging directory', () async {
    final marker = File('${temp.path}/keep.txt');
    await marker.writeAsString('do not touch');
    final ctl = ExportControl();
    await expectLater(
      ArchiveExport.extract(
        source({'x.dat': Uint8List(2000000)}),
        temp,
        control: ctl,
        progress: (_) => ctl.cancelled = true,
      ),
      throwsA(isA<ExportCancelled>()),
    );
    expect(await marker.readAsString(), 'do not touch');
    expect((await temp.list().toList()).length, 1);
  });
  test('truncated source cannot publish a partial DATA folder', () async {
    final s = ArchiveSource(
      ArchiveIndex({'bad.dat': const ArchiveEntry('bad.dat', 0, 4, 0)}, {}),
      (o, n) async => Uint8List(1),
    );
    await expectLater(
      ArchiveExport.extract(
        s,
        temp,
        control: ExportControl(),
        progress: (_) {},
      ),
      throwsFormatException,
    );
    expect(await temp.list().isEmpty, isTrue);
  });
  for (final p in [
    '../out',
    '/root',
    'a/../../x',
    'CON.txt',
    'a:stream',
    'a/last.',
    'a/last ',
    'a//b',
  ]) {
    test('unsafe path $p rejected before copying', () async {
      await expectLater(
        ArchiveExport.extract(
          source({p: Uint8List(0)}),
          temp,
          control: ExportControl(),
          progress: (_) {},
        ),
        throwsFormatException,
      );
      expect(await temp.list().isEmpty, isTrue);
    });
  }
  test('new pair verifies hashes, entry versions and modified data', () async {
    final s = source({
      'item/item.sdata': Uint8List.fromList([1, 2]),
      'other.dat': Uint8List.fromList([3, 4]),
    });
    final r = await ArchiveExport.repack(
      s,
      temp,
      replacements: {
        'item/item.sdata': Uint8List.fromList([7, 8, 9]),
      },
      control: ExportControl(),
      progress: (_) {},
    );
    final b = File('${r.folder}/data.saf').readAsBytesSync(),
        i = ArchiveIndex.decode(
          File('${r.folder}/data.sah').readAsBytesSync(),
          b.length,
        );
    expect(i.report['version'], 123);
    expect(i.entries['other.dat']!.version, 17);
    final e = i.entries['item/item.sdata']!;
    expect(b.sublist(e.offset, e.offset + e.length), [7, 8, 9]);
    expect(s.closed, isFalse);
  });
  test('original encoded filenames survive a reconstructed index', () {
    final raw = [
      Uint8List.fromList([...ascii.encode('Item'), 0]),
      Uint8List.fromList([0x4e, 0x69, 0xf1, 0x6f, 0x2e, 0x64, 0x61, 0x74, 0]),
    ];
    final b = ArchiveExport.encodeIndex([
      ArchiveEntry('item/niño.dat', 0, 2, 0, rawComponents: raw),
    ]);
    final i = ArchiveIndex.decode(b, 2);
    expect(i.entries['item/niño.dat']!.rawComponents, raw);
  });
  test('unknown replacement path never enters the archive', () async {
    await expectLater(
      ArchiveExport.repack(
        source({'a.dat': Uint8List(1)}),
        temp,
        replacements: {'unknown.dat': Uint8List(2)},
        control: ExportControl(),
        progress: (_) {},
      ),
      throwsFormatException,
    );
  });
}
