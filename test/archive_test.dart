import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/core/archive_index.dart';
import 'package:herramienta_shaiya/data/archive_source.dart';
import 'package:herramienta_shaiya/data/library.dart';

class SahWriter {
  final BytesBuilder out = BytesBuilder();
  void u(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void i(int v) {
    final b = ByteData(4)..setInt32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void q(int v) {
    final b = ByteData(8)..setInt64(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void str(String s) {
    final b = utf8.encode(s);
    u(b.length + 1);
    out.add(b);
    out.add([0]);
  }
}

Uint8List sampleIndex({
  int xor = 0,
  int offset = 0,
  int length = 4,
  String name = 'body.dds',
  String root = 'data',
  int declared = 1,
  bool trailing = true,
}) {
  final w = SahWriter();
  w.out.add(ascii.encode('SAH'));
  w.i(0);
  w.u(declared);
  w.out.add(Uint8List(40));
  w.str(root);
  w.u(xor);
  w.u(1);
  w.str('Character');
  w.u(xor);
  w.u(1);
  w.str('Human');
  w.u(1 ^ xor);
  w.str(name);
  w.q(offset);
  w.i(length);
  w.i(0);
  w.u(0);
  if (trailing) w.out.add(Uint8List(8));
  return w.out.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SAH index profiles and validation', () {
    test('standard index with root name keeps relative paths', () {
      final index = ArchiveIndex.decode(sampleIndex(), 4);
      final e = index.entries['character/human/body.dds']!;
      expect(e.offset, 0);
      expect(e.length, 4);
      expect(index.report['profile'], 'SAH estándar');
    });
    test('empty root and absent footer are supported', () {
      expect(
        ArchiveIndex.decode(
          sampleIndex(root: '', trailing: false),
          4,
        ).entries.length,
        1,
      );
    });
    test(
      'the 0x55 variant transforms file counts, never subdirectory counts',
      () {
        final index = ArchiveIndex.decode(sampleIndex(xor: 0x55), 4);
        expect(index.entries.length, 1);
        expect(index.report['profile'], contains('0x55'));
      },
    );
    test('single-byte uniform index XOR is independently verified', () {
      final encoded = Uint8List.fromList(
        sampleIndex().map((x) => x ^ 0x7b).toList(),
      );
      expect(ArchiveIndex.decode(encoded, 4).entries.length, 1);
    });
    test('explicit alternate count profile is bounded and validated', () {
      expect(
        ArchiveIndex.decode(
          sampleIndex(xor: 42),
          4,
          countXor: 42,
        ).entries.length,
        1,
      );
      expect(
        () => ArchiveIndex.decode(sampleIndex(), 4, countXor: 999),
        throwsArgumentError,
      );
    });
    test('64-bit SAF offsets above 4 GiB are retained exactly', () {
      const offset = 0x100000000 + 17;
      final i = ArchiveIndex.decode(sampleIndex(offset: offset), offset + 4);
      expect(i.entries.values.single.offset, offset);
    });
    for (final n in [0, 1, 20, 50, 51, 80, 120]) {
      test('truncated index at $n bytes yields an exportable diagnostic', () {
        final b = sampleIndex();
        expect(
          () => ArchiveIndex.decode(b.sublist(0, n.clamp(0, b.length)), 4),
          throwsA(isA<ArchiveFailure>()),
        );
      });
    }
    test('SAF from a different pair cannot provide an out-of-range entry', () {
      expect(
        () => ArchiveIndex.decode(sampleIndex(offset: 10), 4),
        throwsA(isA<ArchiveFailure>()),
      );
    });
    test('negative offsets and lengths are rejected', () {
      for (final b in [sampleIndex(offset: -1), sampleIndex(length: -1)]) {
        expect(() => ArchiveIndex.decode(b, 4), throwsA(isA<ArchiveFailure>()));
      }
    });
    test('unknown nonzero trailer is never silently skipped', () {
      final b = sampleIndex()..last = 1;
      expect(() => ArchiveIndex.decode(b, 4), throwsA(isA<ArchiveFailure>()));
    });
    test('declared file count must match the parsed tree', () {
      expect(
        () => ArchiveIndex.decode(sampleIndex(declared: 2), 4),
        throwsA(isA<ArchiveFailure>()),
      );
    });
    for (final unsafe in [
      '..',
      '.',
      '../outside.dds',
      'C:\\secret',
      'a/b.dds',
      'a\u0000b.dds',
      '',
    ]) {
      test('unsafe name is rejected: ${jsonEncode(unsafe)}', () {
        expect(
          () => ArchiveIndex.decode(sampleIndex(name: unsafe), 4),
          throwsA(isA<ArchiveFailure>()),
        );
      });
    }
    test('custom signature still requires valid structure and ranges', () {
      final b = sampleIndex()..setRange(0, 3, ascii.encode('XYZ'));
      final i = ArchiveIndex.decode(b, 4);
      expect(i.report['warnings'], isNotEmpty);
      expect(() => ArchiveIndex.decode(b, 0), throwsA(isA<ArchiveFailure>()));
    });
    test('report carries content fingerprint, not local file paths', () {
      final b = sampleIndex();
      final r = ArchiveIndex.decode(b, 4).report;
      expect(r['indexSha256'], sha256.convert(b).toString());
      expect(jsonEncode(r), isNot(contains('C:\\Users')));
    });
  });
  group('Archive range reads', () {
    test('reads only the requested entry and reports a short read', () async {
      var calls = 0;
      final i = ArchiveIndex.decode(sampleIndex(offset: 1024), 1028);
      final source = ArchiveSource(i, (o, n) async {
        calls++;
        expect(o, 1024);
        expect(n, 4);
        return Uint8List.fromList([1, 2, 3, 4]);
      });
      expect(calls, 0);
      expect(await source.read('character/human/body.dds'), [1, 2, 3, 4]);
      expect(calls, 1);
      expect(source.bytesRead, 4);
      final broken = ArchiveSource(i, (o, n) async => Uint8List(3));
      await expectLater(
        broken.read('character/human/body.dds'),
        throwsFormatException,
      );
      expect(broken.diagnostics()['readFailures'], isNotEmpty);
    });
    test('refuses per-resource budget before a range read', () async {
      var called = false;
      final source = ArchiveSource(ArchiveIndex.decode(sampleIndex(), 4), (
        o,
        n,
      ) async {
        called = true;
        return Uint8List(n);
      });
      await expectLater(
        source.read('character/human/body.dds', limit: 3),
        throwsFormatException,
      );
      expect(called, false);
    });
    test('closing the library cancels future reads', () async {
      final s = ArchiveSource(
        ArchiveIndex.decode(sampleIndex(), 4),
        (o, n) async => Uint8List(n),
      )..close();
      await expectLater(s.read('character/human/body.dds'), throwsStateError);
    });
    test(
      'real SAF file is opened read-only; concurrent reads preserve data',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'shaiya-archive-test-',
        );
        try {
          final sah = File('${dir.path}/Data.SAH'),
              saf = File('${dir.path}/Data.SAF');
          await sah.writeAsBytes(sampleIndex());
          await saf.writeAsBytes([7, 6, 5, 4]);
          final before = sha256.convert(await saf.readAsBytes()).toString();
          final lib = await Library.fromArchive(sah.path, saf.path);
          final all = await Future.wait(
            List.generate(16, (_) => lib.read('Character/Human/body.dds')),
          );
          expect(all.every((b) => b[0] == 7 && b[3] == 4), true);
          expect(sha256.convert(await saf.readAsBytes()).toString(), before);
          expect(lib.sourceDiagnostics['reads'], 16);
          lib.dispose();
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
    test(
      'a sparse SAF beyond 4 GiB can be read without allocating the archive',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'shaiya-large-index-',
        );
        try {
          const offset = 0x100000000 + 23;
          final sah = File('${dir.path}/data.sah'),
              saf = File('${dir.path}/data.saf');
          await sah.writeAsBytes(sampleIndex(offset: offset));
          final f = await saf.open(mode: FileMode.write);
          await f.setPosition(offset);
          await f.writeFrom([9, 8, 7, 6]);
          await f.close();
          final lib = await Library.fromArchive(sah.path, saf.path);
          expect(await lib.read('character/human/body.dds'), [9, 8, 7, 6]);
          expect(lib.sourceDiagnostics['bytesRead'], 4);
          lib.dispose();
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
    test('changing payload length after indexing fails visibly', () async {
      final dir = await Directory.systemTemp.createTemp('shaiya-changed-');
      try {
        final sah = File('${dir.path}/data.sah'),
            saf = File('${dir.path}/data.saf');
        await sah.writeAsBytes(sampleIndex());
        await saf.writeAsBytes([1, 2, 3, 4]);
        final lib = await Library.fromArchive(sah.path, saf.path);
        await saf.writeAsBytes([1, 2]);
        await expectLater(
          lib.read('character/human/body.dds'),
          throwsFormatException,
        );
        expect(lib.sourceDiagnostics['readFailures'], isNotEmpty);
        lib.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
