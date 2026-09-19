import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:three_js/three_js.dart' as t;
import '../core/formats.dart';
import '../data/library.dart';
import '../editor/document.dart';
import '../editor/model_reference.dart';
import '../render/studio_scene.dart' show StudioScene, Actor;
import 'editor_style.dart';

Future<void> showEditorModel(
  BuildContext context,
  Library library,
  EditDocument document,
  int row,
) async {
  await showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: EditorStyle.surface,
      child: SizedBox(
        width: 1040,
        height: 720,
        child: _ModelDialog(library: library, document: document, row: row),
      ),
    ),
  );
}

class _ModelDialog extends StatefulWidget {
  final Library library;
  final EditDocument document;
  final int row;
  const _ModelDialog({
    required this.library,
    required this.document,
    required this.row,
  });
  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  late final Future<List<ModelReference>> models = ModelReferences.resolve(
    widget.library,
    widget.document,
    widget.row,
  );
  int selected = 0;
  @override
  Widget build(BuildContext c) => Column(
    children: [
      SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Vista 3D · geometría y texturas originales',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: const ValueKey('model-preview-close'),
              onPressed: () => Navigator.pop(c),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      Expanded(
        child: FutureBuilder(
          future: models,
          builder: (c, s) {
            if (s.hasError) {
              return Center(
                child: SelectableText(
                  'No se pudo resolver el modelo:\n${s.error}',
                ),
              );
            }
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.data!.isEmpty) {
              return const Center(
                child: Text(
                  'Este registro no tiene una referencia 3D validada en la biblioteca.\nNo se inventa una geometría por semejanza de nombre.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: selected,
                    items: [
                      for (var i = 0; i < s.data!.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            s.data![i].label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => selected = v!),
                  ),
                ),
                Expanded(
                  child: NativeModelPreview(
                    key: ValueKey(selected),
                    library: widget.library,
                    model: s.data![selected],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class NativeModelPreview extends StatefulWidget {
  final Library library;
  final ModelReference model;
  const NativeModelPreview({
    super.key,
    required this.library,
    required this.model,
  });
  @override
  State<NativeModelPreview> createState() => _NativeModelPreviewState();
}

class _NativeModelPreviewState extends State<NativeModelPreview> {
  late t.ThreeJS view;
  late StudioScene parts;
  Actor? actor;
  String? error;
  String clipName = 'Pose original';
  int _clipRequest = 0;
  bool dead = false, ready = false, wire = false, playing = true;
  double yaw = .35, pitch = .18, distance = 4, centerY = 1, zoom = 1;
  @override
  void initState() {
    super.initState();
    parts = StudioScene((_) {});
    view = t.ThreeJS(
      settings: t.Settings(
        clearColor: 0x10151e,
        antialias: true,
        toneMapping: t.NoToneMapping,
      ),
      setup: setup,
      onSetupComplete: () {
        if (mounted) setState(() => ready = true);
      },
    );
  }

  Future<void> setup() async {
    view.scene = t.Scene();
    view.scene.background = t.Color.fromHex32(0x10151e);
    view.camera = t.PerspectiveCamera(
      42,
      view.width / view.height,
      .001,
      100000,
    );
    final staged = Actor();
    double minX = double.infinity,
        minY = double.infinity,
        minZ = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    try {
      if (widget.model.parts.length > 128) {
        throw const FormatException(
          'Modelo con más de 128 partes: inspecciona por grupos.',
        );
      }
      int vertices = 0;
      for (final ref in widget.model.parts) {
        if (!widget.library.files.containsKey(ref.$1) ||
            !widget.library.files.containsKey(ref.$2)) {
          throw FormatException(
            'Recurso no presente: ${!widget.library.files.containsKey(ref.$1) ? ref.$1 : ref.$2}',
          );
        }
        final b = await widget.library.read(ref.$1, limit: 64 * 1024 * 1024),
            mesh = await compute(_mesh, (b, ref.$1));
        vertices += mesh.vertices;
        if (vertices > 1000000) {
          throw const FormatException(
            'Modelo mayor del presupuesto de vista previa.',
          );
        }
        final part = await parts.makePartFromLibrary(
          widget.library,
          mesh,
          ref.$2,
          opaque: ref.$3 != 0,
        );
        if (dead) {
          part.dispose();
          staged.dispose();
          return;
        }
        staged.parts.add(part);
        staged.root.add(part.mesh);
        for (var i = 0; i < mesh.positions.length; i += 3) {
          minX = math.min(minX, mesh.positions[i]);
          maxX = math.max(maxX, mesh.positions[i]);
          minY = math.min(minY, mesh.positions[i + 1]);
          maxY = math.max(maxY, mesh.positions[i + 1]);
          minZ = math.min(minZ, mesh.positions[i + 2]);
          maxZ = math.max(maxZ, mesh.positions[i + 2]);
        }
      }
      if (staged.parts.isEmpty) {
        throw const FormatException('Modelo sin partes.');
      }
      centerY = (minY + maxY) / 2;
      distance = math.max(
        .02,
        math.max(maxY - minY, math.max(maxX - minX, maxZ - minZ)) * 1.65,
      );
      staged.root.position.setValues(-(minX + maxX) / 2, 0, -(minZ + maxZ) / 2);
      actor = staged;
      view.scene.add(staged.root);
      camera();
      view.addAnimationEvent((dt) {
        if (dead) return;
        if (playing) actor?.tick(dt.clamp(0, .05));
        camera();
      });
    } catch (e) {
      staged.dispose();
      if (mounted) setState(() => error = '$e');
    }
  }

  void camera() {
    if (dead) return;
    final d = distance * zoom;
    view.camera.position.setValues(
      math.sin(yaw) * math.cos(pitch) * d,
      centerY + math.sin(pitch) * d,
      math.cos(yaw) * math.cos(pitch) * d,
    );
    view.camera.lookAt(t.Vector3(0, centerY, 0));
  }

  Future<void> chooseClip(String name) async {
    final request = ++_clipRequest;
    if (name == 'Pose original') {
      if (mounted) {
        setState(() {
          clipName = name;
          error = null;
        });
      }
      actor?.clip = null;
      final a = actor;
      if (a != null) {
        for (final p in a.parts) {
          for (var i = 0; i < p.data.vertices; i++) {
            p.position.setXYZ(
              i,
              p.data.positions[i * 3],
              p.data.positions[i * 3 + 1],
              p.data.positions[i * 3 + 2],
            );
          }
          p.position.needsUpdate = true;
        }
      }
      return;
    }
    try {
      final path = widget.model.animations[name];
      if (path == null) {
        throw FormatException('Animación no disponible: $name');
      }
      final b = await widget.library.read(path),
          clip = await compute(_clip, (b, path));
      if (dead || request != _clipRequest) return;
      if (actor == null || clip.bones.length < actor!.requiredBones) {
        throw const FormatException(
          'Animación incompatible con los huesos del modelo.',
        );
      }
      actor!.play(clip);
      setState(() {
        clipName = name;
        error = null;
      });
    } catch (e) {
      if (mounted && request == _clipRequest) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    dead = true;
    actor?.dispose();
    parts.dispose();
    view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Column(
    children: [
      Expanded(
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) {
                    setState(
                      () => zoom = (zoom * math.exp(e.scrollDelta.dy * .0015))
                          .clamp(.15, 8.0),
                    );
                  }
                },
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() {
                    yaw += d.delta.dx * .01;
                    pitch = (pitch + d.delta.dy * .01).clamp(-1.4, 1.4);
                  }),
                  child: view.build(),
                ),
              ),
            ),
            if (error != null)
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: Material(
                  color: const Color(0xe0492b27),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(error!),
                  ),
                ),
              ),
            if (!ready)
              const Positioned(
                right: 20,
                bottom: 20,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.model.animations.isNotEmpty)
              SizedBox(
                width: 180,
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: clipName,
                  items: [
                    for (final key in [
                      'Pose original',
                      ...widget.model.animations.keys,
                    ])
                      DropdownMenuItem(
                        value: key,
                        child: Text(key, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => chooseClip(v!),
                ),
              ),
            IconButton(
              tooltip: playing ? 'Pausar' : 'Reproducir',
              onPressed: () => setState(() => playing = !playing),
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
            TextButton(
              onPressed: () => setState(() {
                yaw = 0;
                pitch = 0;
                zoom = 1;
              }),
              child: const Text('Frente'),
            ),
            TextButton(
              onPressed: () => setState(() {
                yaw = math.pi;
                pitch = .15;
                zoom = 1;
              }),
              child: const Text('Espalda'),
            ),
            TextButton(
              onPressed: () => setState(() {
                yaw = math.pi / 2;
                pitch = 0;
                zoom = 1;
              }),
              child: const Text('Perfil'),
            ),
            FilterChip(
              label: const Text('Malla'),
              selected: wire,
              onSelected: (v) {
                setState(() => wire = v);
                for (final p in actor?.parts ?? []) {
                  p.mesh.material?.wireframe = v;
                }
              },
            ),
            const Text(
              'Arrastra: girar · rueda: zoom',
              style: TextStyle(fontSize: 10, color: EditorStyle.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

MeshData _mesh((Uint8List, String) a) => a.$2.toLowerCase().endsWith('.3dc')
    ? MeshData.skinned(a.$1, a.$2)
    : MeshData.object(a.$1, a.$2);
ClipData _clip((Uint8List, String) a) => ClipData.parse(a.$1, a.$2);
