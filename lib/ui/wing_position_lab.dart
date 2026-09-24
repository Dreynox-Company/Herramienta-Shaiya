import 'package:flutter/material.dart';

import '../core/wing_position.dart';
import '../data/library.dart';

class WingPositionLabPage extends StatefulWidget {
  final Library library;

  const WingPositionLabPage({super.key, required this.library});

  @override
  State<WingPositionLabPage> createState() => _WingPositionLabPageState();
}

class _WingPositionLabPageState extends State<WingPositionLabPage> {
  WingPositionDocument? document;
  String? error;
  bool busy = false;
  int? selectedKey;
  String filter = '';
  final Set<int> dirty = <int>{};
  final Map<int, WingPositionProfile> loadedProfiles =
      <int, WingPositionProfile>{};
  WingPositionProfile? clipboard;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final path = WingPositionDocument.canonicalPath;
      if (!widget.library.files.containsKey(path)) {
        throw const FormatException(
          'DATA/ExcelXml/WingPosition.xml no está montado.',
        );
      }
      final parsed = WingPositionDocument.parse(
        await widget.library.read(path, limit: 4 * 1024 * 1024),
        path,
      );
      if (!mounted) return;
      setState(() {
        document = parsed;
        selectedKey ??= parsed.profiles.firstOrNull?.key;
        loadedProfiles
          ..clear()
          ..addEntries(parsed.profiles.map((p) => MapEntry(p.key, p)));
        dirty.clear();
        revision++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  WingPositionProfile? get selected {
    final key = selectedKey;
    if (key == null) return null;
    return document?.profiles.where((p) => p.key == key).firstOrNull;
  }

  List<WingPositionProfile> get visibleProfiles {
    final profiles = document?.profiles ?? const <WingPositionProfile>[];
    final query = filter.trim().toLowerCase();
    if (query.isEmpty) return profiles;
    return profiles
        .where(
          (p) =>
              p.identityLabel.toLowerCase().contains(query) ||
              'f${p.family} j${p.job} s${p.sex}'.contains(query),
        )
        .toList(growable: false);
  }

  bool _different(WingPositionProfile a, WingPositionProfile b) =>
      a.boneIndex != b.boneIndex ||
      (a.rotX - b.rotX).abs() > 1e-6 ||
      (a.rotY - b.rotY).abs() > 1e-6 ||
      (a.rotZ - b.rotZ).abs() > 1e-6 ||
      (a.upDown - b.upDown).abs() > 1e-6 ||
      (a.frontBack - b.frontBack).abs() > 1e-6 ||
      (a.leftRight - b.leftRight).abs() > 1e-6;

  void _update(WingPositionProfile profile) {
    final doc = document;
    if (doc == null) return;
    doc.update(profile);
    final loaded = loadedProfiles[profile.key];
    setState(() {
      if (loaded != null && !_different(profile, loaded)) {
        dirty.remove(profile.key);
      } else {
        dirty.add(profile.key);
      }
      revision++;
    });
  }

  WingPositionProfile _poseFrom(
    WingPositionProfile target,
    WingPositionProfile source,
  ) =>
      target.copyWith(
        boneIndex: source.boneIndex,
        rotX: source.rotX,
        rotY: source.rotY,
        rotZ: source.rotZ,
        upDown: source.upDown,
        frontBack: source.frontBack,
        leftRight: source.leftRight,
      );

  void _pasteToCurrent() {
    final source = clipboard;
    final target = selected;
    if (source == null || target == null) return;
    _update(_poseFrom(target, source));
  }

  void _pasteToBothSexes() {
    final source = clipboard;
    final current = selected;
    final doc = document;
    if (source == null || current == null || doc == null) return;
    for (final sex in const [0, 1]) {
      final target = doc.resolve(current.family, current.job, sex);
      if (target != null) {
        final updated = _poseFrom(target, source);
        doc.update(updated);
        final loaded = loadedProfiles[target.key];
        if (loaded != null && !_different(updated, loaded)) {
          dirty.remove(target.key);
        } else {
          dirty.add(target.key);
        }
      }
    }
    setState(() => revision++);
  }

  void _pasteToSameJobAllFamilies() {
    final source = clipboard;
    final current = selected;
    final doc = document;
    if (source == null || current == null || doc == null) return;
    for (var family = 0; family < 4; family++) {
      for (var sex = 0; sex < 2; sex++) {
        final target = doc.resolve(family, current.job, sex);
        if (target != null) {
          doc.update(_poseFrom(target, source));
          dirty.add(target.key);
        }
      }
    }
    setState(() => revision++);
  }

  void _restoreCurrentBaseline() {
    final current = selected;
    if (current == null) return;
    final baseline = WingPositionDocument.verifiedResolve(
      current.family,
      current.job,
      current.sex,
    );
    if (baseline == null) return;
    _update(
      current.copyWith(
        boneIndex: baseline.boneIndex,
        rotX: baseline.rotX,
        rotY: baseline.rotY,
        rotZ: baseline.rotZ,
        upDown: baseline.upDown,
        frontBack: baseline.frontBack,
        leftRight: baseline.leftRight,
      ),
    );
  }

  Future<void> _restoreAllBaseline() async {
    final doc = document;
    if (doc == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar los 48 perfiles'),
        content: const Text(
          'Se reemplazarán en memoria BONE_IDX, posición XYZ y rotación XYZ '
          'por el baseline ps0032 verificado. El archivo no se modifica hasta '
          'pulsar Guardar WingPosition.xml.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    for (final baseline in WingPositionDocument.verifiedBaseline) {
      final target = doc.resolve(baseline.family, baseline.job, baseline.sex);
      if (target == null) continue;
      doc.update(
        target.copyWith(
          boneIndex: baseline.boneIndex,
          rotX: baseline.rotX,
          rotY: baseline.rotY,
          rotZ: baseline.rotZ,
          upDown: baseline.upDown,
          frontBack: baseline.frontBack,
          leftRight: baseline.leftRight,
        ),
      );
    }
    dirty.clear();
    for (final profile in doc.profiles) {
      final loaded = loadedProfiles[profile.key];
      if (loaded == null || _different(profile, loaded)) {
        dirty.add(profile.key);
      }
    }
    setState(() => revision++);
  }

  Future<void> _save() async {
    final doc = document;
    if (doc == null || busy) return;
    setState(() => busy = true);
    try {
      final bytes = doc.encode();
      doc.validateEncoded(bytes);
      await widget.library.writeResource(
        WingPositionDocument.canonicalPath,
        bytes,
      );
      final reparsed = WingPositionDocument.parse(
        bytes,
        WingPositionDocument.canonicalPath,
      );
      if (!mounted) return;
      setState(() {
        document = reparsed;
        loadedProfiles
          ..clear()
          ..addEntries(reparsed.profiles.map((p) => MapEntry(p.key, p)));
        dirty.clear();
        revision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'WingPosition.xml guardado y revalidado: 48/48 perfiles.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _numberField(
    String label,
    double value,
    ValueChanged<double> apply, {
    double? min,
    double? max,
    int decimals = 4,
  }) =>
      TextFormField(
        key: ValueKey('$revision-${selectedKey ?? -1}-$label-$value'),
        initialValue: value.toStringAsFixed(decimals),
        enabled: !busy,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        onFieldSubmitted: (raw) {
          var parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
          if (parsed == null || !parsed.isFinite) return;
          if (min != null && parsed < min) parsed = min;
          if (max != null && parsed > max) parsed = max;
          apply(parsed);
        },
      );

  Widget _profileList() {
    final currentKey = selectedKey;
    final rows = visibleProfiles;
    return Material(
      color: const Color(0xff131b26),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar familia, job o sexo…',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) => setState(() => filter = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${rows.length}/48 perfiles · ${dirty.length} modificados',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xff8fa0b8),
                    ),
                  ),
                ),
                if (document?.matchesVerifiedSource == true)
                  const Tooltip(
                    message: 'SHA-256 coincide con WingPosition canónico',
                    child: Icon(
                      Icons.verified_outlined,
                      size: 16,
                      color: Color(0xff9ad3b2),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, index) {
                final p = rows[index];
                final changed = dirty.contains(p.key);
                return ListTile(
                  dense: true,
                  selected: p.key == currentKey,
                  leading: Icon(
                    changed
                        ? Icons.edit_note_outlined
                        : Icons.flight_outlined,
                    size: 17,
                  ),
                  title: Text(
                    p.identityLabel,
                    style: const TextStyle(fontSize: 10),
                  ),
                  subtitle: Text(
                    'F${p.family} J${p.job} S${p.sex} · hueso '
                    '${p.boneIndex} · rot '
                    '${p.rotX.toStringAsFixed(1)}/'
                    '${p.rotY.toStringAsFixed(1)}/'
                    '${p.rotZ.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 8),
                  ),
                  onTap: () => setState(() {
                    selectedKey = p.key;
                    revision++;
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    final p = selected;
    if (p == null) {
      return const Center(child: Text('Selecciona un perfil WingPosition.'));
    }

    WingPositionProfile withNumber(String field, double value) => switch (field) {
      'rotX' => p.copyWith(rotX: value),
      'rotY' => p.copyWith(rotY: value),
      'rotZ' => p.copyWith(rotZ: value),
      'upDown' => p.copyWith(upDown: value),
      'frontBack' => p.copyWith(frontBack: value),
      'leftRight' => p.copyWith(leftRight: value),
      _ => p,
    };

    final baseline = WingPositionDocument.verifiedResolve(
      p.family,
      p.job,
      p.sex,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          p.identityLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Perfil nativo F${p.family}/J${p.job}/S${p.sex} · '
          '${p.provenance}',
          style: const TextStyle(fontSize: 9, color: Color(0xff8fa0b8)),
        ),
        const SizedBox(height: 14),
        if (p.boneWritable)
          TextFormField(
            key: ValueKey('$revision-${p.key}-bone-${p.boneIndex}'),
            initialValue: p.boneIndex.toString(),
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'BONE_IDX',
              helperText: 'Hueso nativo de anclaje',
            ),
            onFieldSubmitted: (raw) {
              final value = int.tryParse(raw.trim());
              if (value == null || value < 0 || value > 255) return;
              _update(p.copyWith(boneIndex: value));
            },
          ),
        const SizedBox(height: 10),
        const Text(
          'Posición nativa',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _numberField(
          'X · WING_LEFT_RIGHT',
          p.leftRight,
          (v) => _update(withNumber('leftRight', v)),
        ),
        const SizedBox(height: 8),
        _numberField(
          'Y · WING_UP_DOWN',
          p.upDown,
          (v) => _update(withNumber('upDown', v)),
        ),
        const SizedBox(height: 8),
        _numberField(
          'Z · WING_FRONT_BACK',
          p.frontBack,
          (v) => _update(withNumber('frontBack', v)),
        ),
        const SizedBox(height: 14),
        const Text(
          'Rotación Euler nativa · grados',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _numberField(
          'Rotación X',
          p.rotX,
          (v) => _update(withNumber('rotX', v)),
          min: -3600,
          max: 3600,
        ),
        const SizedBox(height: 8),
        _numberField(
          'Rotación Y',
          p.rotY,
          (v) => _update(withNumber('rotY', v)),
          min: -3600,
          max: 3600,
        ),
        const SizedBox(height: 8),
        _numberField(
          'Rotación Z',
          p.rotZ,
          (v) => _update(withNumber('rotZ', v)),
          min: -3600,
          max: 3600,
        ),
        const SizedBox(height: 14),
        if (baseline != null)
          Text(
            _different(p, baseline)
                ? 'Este perfil difiere del baseline ps0032 verificado.'
                : 'Este perfil coincide con el baseline ps0032 verificado.',
            style: TextStyle(
              fontSize: 9,
              color: _different(p, baseline)
                  ? const Color(0xffffc28f)
                  : const Color(0xff9ad3b2),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => setState(() => clipboard = p),
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: const Text('Copiar pose'),
            ),
            OutlinedButton.icon(
              onPressed: busy || clipboard == null ? null : _pasteToCurrent,
              icon: const Icon(Icons.content_paste_go_outlined, size: 16),
              label: const Text('Pegar aquí'),
            ),
            OutlinedButton.icon(
              onPressed:
                  busy || clipboard == null ? null : _pasteToBothSexes,
              icon: const Icon(Icons.people_alt_outlined, size: 16),
              label: const Text('Pegar a ambos sexos'),
            ),
            OutlinedButton.icon(
              onPressed: busy || clipboard == null
                  ? null
                  : _pasteToSameJobAllFamilies,
              icon: const Icon(Icons.hub_outlined, size: 16),
              label: const Text('Pegar job en 4 familias'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : _restoreCurrentBaseline,
              icon: const Icon(Icons.restore_outlined, size: 16),
              label: const Text('Baseline actual'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Escala y espejo geométrico no existen en WingPosition.xml. '
          'Studio no inventa esos campos: se mantienen como preview 3D hasta '
          'tener un writer 3DC/3DO o una fuente nativa confirmada.',
          style: TextStyle(fontSize: 9, color: Color(0xff8fa0b8), height: 1.4),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff101722),
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WingPosition Lab', style: TextStyle(fontSize: 14)),
          Text(
            '48 perfiles nativos · familia × job × sexo',
            style: TextStyle(fontSize: 9, color: Color(0xff8e9bb0)),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Releer WingPosition.xml',
          onPressed: busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Restaurar baseline completo',
          onPressed: busy ? null : _restoreAllBaseline,
          icon: const Icon(Icons.settings_backup_restore),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: busy || document == null ? null : _save,
          icon: const Icon(Icons.save_outlined, size: 17),
          label: Text(
            widget.library.isSpkWorkspace
                ? 'Guardar overlay SPK'
                : 'Guardar WingPosition.xml',
          ),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xffffb6a7)),
              ),
            ),
          )
        : busy && document == null
        ? const Center(child: CircularProgressIndicator())
        : Row(
            children: [
              SizedBox(width: 340, child: _profileList()),
              const VerticalDivider(width: 1),
              Expanded(child: _editor()),
            ],
          ),
  );
}
