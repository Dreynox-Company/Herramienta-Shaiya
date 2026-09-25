// Packages only the supplied HUMF male pair. Does not retarget unrelated rigs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:herramienta_shaiya/core/formats.dart';
import 'package:herramienta_shaiya/core/extra_motion.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'dart run ingenieria_inversa/tools/pack_flight.dart hover.ani flight.ani output.json.gz',
    );
    exit(2);
  }
  final a = File(args[0]).readAsBytesSync(),
      b = File(args[1]).readAsBytesSync();
  final hover = ClipData.parse(a, args[0]), flight = ClipData.parse(b, args[1]);
  if (hover.bones.length != 36 || flight.bones.length != 36) {
    throw const FormatException('El perfil suministrado debe tener 36 huesos.');
  }
  Map<String, dynamic> clip(List<int> bytes) => {
    'data': base64Encode(bytes),
    'sha256': sha256.convert(bytes).toString(),
  };
  final value = {
    'schema': 1,
    'source':
        'Par ANI V2 proporcionado; HUMF masculino solamente. No sustituye ANI originales.',
    'profiles': [
      {
        'archetype': 'humf',
        'sex': 'Masculino',
        'parents': hover.bones.map((b) => b.parent).toList(),
        'clips': {'hover': clip(a), 'flight': clip(b)},
      },
    ],
  };
  final output = File(args[2]);
  if (output.existsSync()) {
    throw const FileSystemException('La salida ya existe.');
  }
  final bytes = gzip.encode(utf8.encode(jsonEncode(value)));
  final checked = ExtraMotionLibrary.decode(Uint8List.fromList(bytes));
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(bytes, flush: true);
  stdout.writeln(
    '${checked.profiles.length} perfil validado; ${bytes.length} bytes. Solo HUMF masculino con jerarquía idéntica.',
  );
}
