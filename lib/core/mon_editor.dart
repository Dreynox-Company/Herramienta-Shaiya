import 'dart:typed_data';

import 'legacy_text.dart';

const monAnimationSlots = <String>[
  'Caminar',
  'Correr',
  'Ataque 1',
  'Ataque 2',
  'Ataque 3',
  'Caída',
  'Respirar',
  'Daño',
  'Reposo',
];

const monSoundSlots = <String>['Ataque 1', 'Ataque 2', 'Ataque 3', 'Caída'];

const monEffectSlots = <String>['Ataque 1', 'Ataque 2', 'Ataque 3', 'Caída'];

/// Native Shaiya MON sentinel observed in the real Vehicle corpus. A MON slot
/// containing LOAD delegates resolution to the client instead of naming a
/// concrete ANI/WAV/EFT resource.
const monLoadSentinel = 'LOAD';

bool isMonLoadSentinel(String? value) =>
    value != null && value.trim().toUpperCase() == monLoadSentinel;

class EditableMonString {
  final Uint8List originalBytes;
  final String originalValue;
  String value;

  EditableMonString(this.originalBytes)
    : originalValue = LegacyText.decode(originalBytes),
      value = LegacyText.decode(originalBytes);

  bool get changed => value != originalValue;

  Uint8List encoded() {
    if (!changed) return Uint8List.fromList(originalBytes);
    if (value.contains('\u0000') || value.length > 65535) {
      throw const FormatException('Cadena MON inválida o demasiado larga.');
    }
    return LegacyText.encodeLegacy(value);
  }
}

class EditableMonPart {
  final EditableMonString mesh;
  final EditableMonString texture;
  EditableMonPart(this.mesh, this.texture);
}

class EditableMonRecord {
  final EditableMonString name;
  final int flag;
  final Map<String, EditableMonString> animations;
  final Map<String, EditableMonString> sounds;
  final Map<String, EditableMonString> effects;
  final EditableMonString? attached;
  final List<EditableMonPart> parts;
  final Uint8List heightRaw;
  final int tailCount;
  final Uint8List tailRaw;

  EditableMonRecord({
    required this.name,
    required this.flag,
    required this.animations,
    required this.sounds,
    required this.effects,
    required this.attached,
    required this.parts,
    required this.heightRaw,
    required this.tailCount,
    required this.tailRaw,
  });
}

/// Lossless editor for MO2/MO4 MON files.
///
/// Unchanged strings and opaque tail records are emitted byte-for-byte. Only
/// fields explicitly edited by Studio are re-encoded. This lets Wing.MON be
/// modified without inventing semantics for fields that are still unknown.
class EditableMonDocument {
  final String source;
  final String signature;
  final Uint8List signatureRaw;
  final List<EditableMonRecord> records;

  EditableMonDocument._(
    this.source,
    this.signature,
    this.signatureRaw,
    this.records,
  );

  bool get isMo4 => signature == 'MO4';

  EditableMonRecord _record(int recordId) {
    if (recordId < 0 || recordId >= records.length) {
      throw FormatException('Registro MON fuera de rango: $recordId');
    }
    return records[recordId];
  }

  String _resourcePath(
    String value, {
    required String label,
    required Set<String> extensions,
    bool allowEmpty = false,
    bool allowLoadSentinel = false,
  }) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (allowLoadSentinel && isMonLoadSentinel(normalized)) {
      return monLoadSentinel;
    }
    if (normalized.isEmpty && allowEmpty) return '';
    if (normalized.isEmpty ||
        normalized.contains('..') ||
        normalized.startsWith('/') ||
        normalized.contains(':')) {
      throw FormatException('Ruta $label inválida para MON: $value');
    }
    final lower = normalized.toLowerCase();
    if (!extensions.any(lower.endsWith)) {
      throw FormatException('Extensión no admitida para $label MON: $value');
    }
    return normalized;
  }

  void setAnimation(int recordId, String slot, String animation) {
    if (!monAnimationSlots.contains(slot)) {
      throw FormatException('Slot ANI MON no soportado: $slot');
    }
    _record(recordId).animations[slot]!.value = _resourcePath(
      animation,
      label: 'ANI',
      extensions: const {'.ani'},
      allowLoadSentinel: true,
    );
  }

  void setSound(int recordId, String slot, String sound) {
    if (!monSoundSlots.contains(slot)) {
      throw FormatException('Slot WAV MON no soportado: $slot');
    }
    _record(recordId).sounds[slot]!.value = _resourcePath(
      sound,
      label: 'sonido',
      extensions: const {'.wav', '.ogg'},
      allowEmpty: true,
      allowLoadSentinel: true,
    );
  }

  void setEffect(int recordId, String slot, String effect) {
    if (!monEffectSlots.contains(slot)) {
      throw FormatException('Slot EFT MON no soportado: $slot');
    }
    _record(recordId).effects[slot]!.value = _resourcePath(
      effect,
      label: 'efecto',
      extensions: const {'.eft', '.3de'},
      allowEmpty: true,
      allowLoadSentinel: true,
    );
  }

  void setAttachedEffect(int recordId, String effect) {
    final attached = _record(recordId).attached;
    if (attached == null) {
      throw const FormatException(
        'Este MON es MO2 y no contiene Effect.Attached.',
      );
    }
    attached.value = _resourcePath(
      effect,
      label: 'efecto adjunto',
      extensions: const {'.eft', '.3de'},
      allowEmpty: true,
      allowLoadSentinel: true,
    );
  }

  void setPart(int recordId, int partId, {String? mesh, String? texture}) {
    final record = _record(recordId);
    if (partId < 0 || partId >= record.parts.length) {
      throw FormatException('Parte MON fuera de rango: $partId');
    }
    final part = record.parts[partId];
    if (mesh != null) {
      part.mesh.value = _resourcePath(
        mesh,
        label: 'malla',
        extensions: const {'.3dc', '.3do'},
      );
    }
    if (texture != null) {
      part.texture.value = _resourcePath(
        texture,
        label: 'textura',
        extensions: const {'.dds', '.tga', '.png', '.bmp'},
      );
    }
  }

  Uint8List encode() {
    final out = BytesBuilder(copy: false)..add(signatureRaw);
    _u32(out, records.length);
    for (final record in records) {
      _string(out, record.name);
      out.addByte(record.flag);
      for (final slot in monAnimationSlots) {
        _string(out, record.animations[slot]!);
      }
      for (final slot in monSoundSlots) {
        _string(out, record.sounds[slot]!);
      }
      for (final slot in monEffectSlots) {
        _string(out, record.effects[slot]!);
      }
      if (isMo4) _string(out, record.attached!);
      _u32(out, record.parts.length);
      for (final part in record.parts) {
        _string(out, part.mesh);
        _string(out, part.texture);
      }
      if (record.heightRaw.length != 4) {
        throw const FormatException('Altura MON corrupta.');
      }
      out.add(record.heightRaw);
      _u32(out, record.tailCount);
      if (record.tailRaw.length != record.tailCount * 8) {
        throw const FormatException('Cola MON inconsistente.');
      }
      out.add(record.tailRaw);
    }
    return out.takeBytes();
  }

  void validateEncoded(Uint8List bytes) {
    final parsed = EditableMonDocument.parse(bytes, source);
    if (parsed.signature != signature ||
        parsed.records.length != records.length) {
      throw const FormatException('MON perdió registros al serializar.');
    }
    for (var i = 0; i < records.length; i++) {
      for (final slot in monAnimationSlots) {
        if (parsed.records[i].animations[slot]!.value !=
            records[i].animations[slot]!.value) {
          throw FormatException('MON no revalidó ANI $slot en registro $i.');
        }
      }
      for (final slot in monSoundSlots) {
        if (parsed.records[i].sounds[slot]!.value !=
            records[i].sounds[slot]!.value) {
          throw FormatException('MON no revalidó WAV $slot en registro $i.');
        }
      }
      for (final slot in monEffectSlots) {
        if (parsed.records[i].effects[slot]!.value !=
            records[i].effects[slot]!.value) {
          throw FormatException('MON no revalidó EFT $slot en registro $i.');
        }
      }
      if (isMo4 &&
          parsed.records[i].attached!.value != records[i].attached!.value) {
        throw FormatException(
          'MON no revalidó el efecto adjunto del registro $i.',
        );
      }
      if (parsed.records[i].parts.length != records[i].parts.length) {
        throw FormatException('MON alteró las partes del registro $i.');
      }
      for (var p = 0; p < records[i].parts.length; p++) {
        if (parsed.records[i].parts[p].mesh.value !=
                records[i].parts[p].mesh.value ||
            parsed.records[i].parts[p].texture.value !=
                records[i].parts[p].texture.value) {
          throw FormatException('MON no revalidó la parte $p del registro $i.');
        }
      }
      if (parsed.records[i].tailCount != records[i].tailCount ||
          !_equal(parsed.records[i].tailRaw, records[i].tailRaw)) {
        throw FormatException('MON alteró datos opacos del registro $i.');
      }
    }
  }

  static EditableMonDocument parse(Uint8List bytes, String source) {
    final r = _MonReader(bytes, source);
    final signatureRaw = r.raw(3);
    final signature = String.fromCharCodes(signatureRaw);
    if (signature != 'MO2' && signature != 'MO4') {
      throw FormatException('$source: firma MON desconocida $signature.');
    }
    final count = r.u32(max: 100000);
    final rows = <EditableMonRecord>[];
    for (var i = 0; i < count; i++) {
      final name = EditableMonString(r.string());
      final flag = r.u8();
      final animations = <String, EditableMonString>{
        for (final slot in monAnimationSlots)
          slot: EditableMonString(r.string()),
      };
      final sounds = <String, EditableMonString>{
        for (final slot in monSoundSlots) slot: EditableMonString(r.string()),
      };
      final effects = <String, EditableMonString>{
        for (final slot in monEffectSlots) slot: EditableMonString(r.string()),
      };
      final attached = signature == 'MO4'
          ? EditableMonString(r.string())
          : null;
      final partCount = r.u32(max: 10000);
      final parts = <EditableMonPart>[
        for (var p = 0; p < partCount; p++)
          EditableMonPart(
            EditableMonString(r.string()),
            EditableMonString(r.string()),
          ),
      ];
      final heightRaw = r.raw(4);
      final tailCount = r.u32(max: 10000);
      final tailRaw = r.raw(tailCount * 8);
      rows.add(
        EditableMonRecord(
          name: name,
          flag: flag,
          animations: animations,
          sounds: sounds,
          effects: effects,
          attached: attached,
          parts: parts,
          heightRaw: heightRaw,
          tailCount: tailCount,
          tailRaw: tailRaw,
        ),
      );
    }
    r.end();
    return EditableMonDocument._(source, signature, signatureRaw, rows);
  }

  static void _u32(BytesBuilder out, int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  static void _string(BytesBuilder out, EditableMonString value) {
    final bytes = value.encoded();
    _u32(out, bytes.length);
    out.add(bytes);
  }

  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _MonReader {
  final Uint8List bytes;
  final String source;
  late final ByteData data = ByteData.sublistView(bytes);
  int offset = 0;

  _MonReader(this.bytes, this.source);

  void need(int count) {
    if (count < 0 || offset + count > bytes.length) {
      throw FormatException(
        '$source · byte $offset: MON truncado ($count bytes).',
      );
    }
  }

  Uint8List raw(int count) {
    need(count);
    final out = Uint8List.fromList(bytes.sublist(offset, offset + count));
    offset += count;
    return out;
  }

  int u8() {
    need(1);
    return bytes[offset++];
  }

  int u32({int max = 0xffffffff}) {
    need(4);
    final value = data.getUint32(offset, Endian.little);
    offset += 4;
    if (value > max) {
      throw FormatException(
        '$source · byte $offset: recuento MON fuera de límite: $value.',
      );
    }
    return value;
  }

  Uint8List string() {
    final length = u32(max: 1024 * 1024);
    return raw(length);
  }

  void end() {
    if (offset != bytes.length) {
      throw FormatException(
        '$source · byte $offset: quedan ${bytes.length - offset} bytes MON.',
      );
    }
  }
}
