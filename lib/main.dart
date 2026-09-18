import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:file_selector/file_selector.dart';
import 'core/extra_motion.dart';
import 'core/equipment_rules.dart';
import 'core/textures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:three_js/three_js.dart' as three;
import 'core/formats.dart';
import 'data/catalog.dart';
import 'core/game_metadata.dart';
import 'core/world_resources.dart';
import 'data/library.dart';
import 'render/studio_scene.dart';
import 'input/viewport_movement_input.dart';
import 'ui/asset_selector.dart';
import 'ui/studio_workspace.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final data = args.where((x) => x.startsWith('--data=')).firstOrNull;
  runApp(ShaiyaApp(initialData: data?.substring(7)));
}

class ShaiyaApp extends StatelessWidget {
  final String? initialData;
  const ShaiyaApp({super.key, this.initialData});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Shaiya Studio',
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffa5bcff),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff101722),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 12),
        bodySmall: TextStyle(fontSize: 10),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 2,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
      ),
      cardTheme: const CardThemeData(
        color: Color(0xff192331),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
    ),
    home: StudioPage(initialData: initialData),
  );
}

class StudioPage extends StatefulWidget {
  final String? initialData;
  const StudioPage({super.key, this.initialData});
  @override
  State<StudioPage> createState() => _StudioState();
}

class _StudioState extends State<StudioPage> {
  late final StudioScene scene;
  late final three.ThreeJS renderer;
  Catalog? catalog;
  int tab = 0;
  bool importing = false, working = false;
  String progress = 'Selecciona DATA para comenzar.';
  final List<String> diagnostics = [];
  final captureKey = GlobalKey();
  final focus = FocusNode();
  final Map<String, SelectionMemory> _memories = {};
  String inspectorTarget = 'Personaje', lastSound = '';
  double gestureScale = 1;
  final xController = TextEditingController(),
      zController = TextEditingController();
  @override
  void initState() {
    super.initState();
    scene = StudioScene(log);
    renderer = three.ThreeJS(
      settings: three.Settings(
        clearColor: 0x11151e,
        antialias: true,
        enableShadowMap: false,
        toneMapping: three.NoToneMapping,
      ),
      setup: () => scene.setup(renderer),
      onSetupComplete: () {
        if (mounted) {
          setState(() {});
          if (widget.initialData != null) connect(path: widget.initialData);
        }
      },
    );
    scene.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void log(String value) {
    diagnostics.insert(0, '${DateTime.now().toIso8601String()} · $value');
    if (diagnostics.length > 300) diagnostics.removeLast();
  }

  void showError(Object e) {
    log(e.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> act(
    Future<void> Function() action, {
    bool restoreFocus = false,
  }) async {
    if (working || importing) return;
    scene.clearMovement();
    setState(() => working = true);
    try {
      await action();
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) {
        setState(() => working = false);
        if (restoreFocus) focus.requestFocus();
      }
    }
  }

  Future<void> sourceMenu() async {
    scene.clearMovement();
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir biblioteca de recursos'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Carpeta DATA'),
                subtitle: const Text(
                  'Conservar el método habitual, con subcarpetas',
                ),
                onTap: () => Navigator.pop(ctx, 'folder'),
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Archivos DATA.SAH + DATA.SAF'),
                subtitle: Text(
                  Platform.isAndroid
                      ? 'Selecciona los dos archivos simultáneamente. No se copian.'
                      : 'Índice SAH y contenido SAF. Detección del compañero en la misma carpeta.',
                ),
                onTap: () => Navigator.pop(ctx, 'archive'),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Exportar diagnóstico de archivo'),
                subtitle: const Text(
                  'Disponible incluso si un archivo no se pudo abrir',
                ),
                onTap: () => Navigator.pop(ctx, 'report'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (mode == 'report') {
      await act(exportArchiveReport);
    } else if (mode != null) {
      await connect(archive: mode == 'archive');
    }
  }

  Future<void> loadBundledExtras() async {
    if (scene.extraMotions != null) return;
    final docs = await getApplicationDocumentsDirectory();
    final choices = [
      File('${docs.path}/HerramientaShaiya/flight.json.gz'),
      File(
        '${File(Platform.resolvedExecutable).parent.path}/Extras/flight.json.gz',
      ),
    ];
    for (final f in choices) {
      if (!await f.exists()) continue;
      try {
        if (await f.length() > 8 * 1024 * 1024) {
          throw const FormatException('Paquete de movimientos fuera de límite');
        }
        await scene.installExtras(
          await compute(ExtraMotionLibrary.decode, await f.readAsBytes()),
        );
        return;
      } catch (e) {
        log('Movimientos suplementarios: $e');
      }
    }
  }

  Future<void> importExtras() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Vuelo suplementario', extensions: ['gz']),
      ],
    );
    if (file == null) return;
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('Paquete de movimientos fuera de límite');
    }
    final bytes = await file.readAsBytes();
    final extras = await compute(ExtraMotionLibrary.decode, bytes);
    final d = await getApplicationDocumentsDirectory();
    final folder = Directory('${d.path}/HerramientaShaiya');
    await folder.create(recursive: true);
    await File(
      '${folder.path}/flight.json.gz',
    ).writeAsBytes(bytes, flush: true);
    await scene.installExtras(extras);
    scene.say(
      '${extras.profiles.length} perfiles suplementarios de vuelo verificados; los ANI originales se conservan.',
    );
  }

  Future<void> exportArchiveReport() async {
    final report =
        Library.lastArchiveReport ?? catalog?.library.sourceDiagnostics;
    if (report == null) {
      throw const FormatException(
        'Todavía no se ha intentado abrir un archivo SAH/SAF.',
      );
    }
    await saveFile(
      'diagnostico_archivo_${DateTime.now().millisecondsSinceEpoch}.json',
      const JsonEncoder.withIndent('  ').convert({
        'app': 'Shaiya Studio',
        'version': '0.4.0',
        'platform': Platform.operatingSystem,
        'time': DateTime.now().toIso8601String(),
        'archive': report,
        'activeSource': catalog?.library.sourceDiagnostics,
      }),
    );
  }

  Future<void> connect({String? path, bool archive = false}) async {
    if (importing || working) return;
    scene.clearMovement();
    setState(() => importing = true);
    final old = scene.catalog;
    Library? candidate;
    try {
      void report(String s) {
        if (mounted) setState(() => progress = s);
      }

      final lib = path == null
          ? (archive
                ? await Library.chooseArchive(report)
                : await Library.choose(report))
          : await Library.fromDirectory(path, report);
      if (lib == null) return;
      candidate = lib;
      await loadBundledExtras();
      final next = Catalog(lib);
      await next.load(report);
      if (!mounted) return;
      scene.catalog = next;
      final first =
          next.archetypes.where((a) => a.id == 'humf').firstOrNull ??
          next.archetypes.first;
      await scene.setAppearance(Appearance.initial(first));
      catalog = next;
      _memories.clear();
      diagnostics.addAll(next.warnings);
      scene.combat.reset();
      await scene.selectCreature(null, 'enemy');
      await scene.selectCreature(null, 'mount');
      await scene.selectCreature(null, 'wing');
      await scene.setWorld(null);
      await scene.setSky(null);
      progress =
          '${lib.files.length} recursos · ${lib.sourceLabel} · solo lectura';
      if (old?.library != lib) old?.library.dispose();
    } catch (e) {
      if (catalog != scene.catalog) scene.catalog = old;
      if (candidate != null && candidate != catalog?.library) {
        if (archive) {
          Library.lastArchiveReport = {
            ...candidate.sourceDiagnostics,
            'mountError': e.toString(),
            'stage': 'catalogue/appearance',
          };
        }
        candidate.dispose();
      }
      progress = 'No se pudo conectar DATA: $e';
      showError(e);
    } finally {
      if (mounted) {
        setState(() => importing = false);
        focus.requestFocus();
      }
    }
  }

  @override
  void dispose() {
    scene.removeListener(refresh);
    scene.dispose();
    catalog?.library.dispose();
    renderer.dispose();
    focus.dispose();
    xController.dispose();
    zController.dispose();
    super.dispose();
  }

  bool get disabled => working || importing || !scene.ready;
  Widget field<T>(
    String key,
    String title,
    List<T> items,
    T? value,
    String Function(T) id,
    String Function(T) label,
    Future<void> Function(T) apply, {
    String Function(T)? detail,
    String empty = 'Sin selección',
  }) => AssetSelector<T>(
    key: ValueKey(key),
    title: title,
    items: items,
    value: value,
    id: id,
    label: label,
    detail: detail,
    memory: _memories.putIfAbsent(key, SelectionMemory.new),
    enabled: !importing && scene.ready,
    emptyLabel: empty,
    onError: showError,
    onChanged: (v) async {
      scene.clearMovement();
      await apply(v);
    },
  );
  Widget section(String title, List<Widget> children, {String? help}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xffdbe3f1),
                    ),
                  ),
                ),
                if (help != null)
                  Tooltip(
                    message: help,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Color(0xff8394af),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
  Widget note(String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      value,
      style: const TextStyle(
        fontSize: 10,
        color: Color(0xff98a8bf),
        height: 1.5,
      ),
    ),
  );
  Widget slider(
    String title,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 10, color: Color(0xffaebbd0)),
            ),
          ),
          Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 10)),
        ],
      ),
      SizedBox(
        height: 28,
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: disabled ? null : change,
        ),
      ),
    ],
  );
  Widget toggle(String text, bool value, ValueChanged<bool>? change) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(text, style: const TextStyle(fontSize: 11)),
        value: value,
        onChanged: change,
      );
  String creatureId(CreatureRecord c) => '${c.source}#${c.id}';
  String partId(PartRecord p) => '${p.tablePath}#${p.raw.id}';
  Widget partField(Slot slot) {
    final a = scene.appearance!.archetype, p = scene.appearance!.selected[slot];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: field<PartRecord>(
            '${a.race}/${a.id}/${slot.name}',
            slotLabels[slot]!,
            a.parts[slot] ?? [],
            p,
            partId,
            (p) => p.label,
            (v) => scene.setAppearance(scene.appearance!.withPart(slot, v)),
            detail: (p) => '${p.raw.mesh} · ${p.raw.texture}',
            empty: slot == Slot.helmet
                ? 'Sin casco'
                : 'Base / integrado en el traje',
          ),
        ),
        if (![Slot.face].contains(slot))
          SizedBox(
            width: 25,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: slot == Slot.hair
                  ? 'Quitar cabello'
                  : 'Retirar pieza / restaurar base',
              onPressed: disabled
                  ? null
                  : () => act(
                      () => scene.setAppearance(
                        scene.appearance!.withPart(slot, null),
                      ),
                    ),
              icon: const Icon(Icons.remove_circle_outline, size: 16),
            ),
          ),
      ],
    );
  }

  Widget creatureField(String kind) {
    final c = catalog!,
        items = kind == 'mount'
            ? c.mounts
            : kind == 'wing'
            ? c.wings
            : c.creatures,
        current = kind == 'mount'
            ? scene.mountRecord
            : kind == 'wing'
            ? scene.wingRecord
            : scene.enemyRecord;
    return field<CreatureRecord>(
      kind,
      kind == 'mount'
          ? 'Montura'
          : kind == 'wing'
          ? 'Alas'
          : 'Oponente',
      items,
      current,
      creatureId,
      c.creatureLabel,
      (v) => scene.selectCreature(v, kind),
      detail: (v) => v.parts.map((p) => p.mesh).join(' · '),
      empty: kind == 'mount' ? 'A pie' : 'Ninguno',
    );
  }

  Widget panel() {
    final c = catalog, a = scene.appearance?.archetype;
    if (c == null || a == null) {
      return section('Biblioteca local', [
        note(
          'Conecta la carpeta DATA descomprimida. Los recursos permanecen en tu equipo.',
        ),
        FilledButton.icon(
          onPressed: disabled ? null : () => connect(),
          icon: const Icon(Icons.folder_open, size: 17),
          label: const Text('Seleccionar DATA'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: disabled ? null : () => connect(archive: true),
          icon: const Icon(Icons.inventory_2_outlined, size: 17),
          label: const Text('Abrir DATA.SAH + DATA.SAF'),
        ),
        TextButton.icon(
          onPressed: () => act(exportArchiveReport),
          icon: const Icon(Icons.receipt_long, size: 16),
          label: const Text('Exportar diagnóstico de archivo'),
        ),
        note(progress),
      ]);
    }
    switch (tab) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('Identidad', [
              field<String>(
                'race',
                'Raza',
                c.archetypes.map((x) => x.race).toSet().toList(),
                a.race,
                (x) => x,
                (x) => raceLabels[x] ?? x,
                (v) => scene.setAppearance(
                  Appearance.initial(
                    c.archetypes.firstWhere((x) => x.race == v),
                  ),
                ),
              ),
              field<Archetype>(
                '${a.race}/archetype',
                'Cuerpo / arquetipo',
                c.archetypes.where((x) => x.race == a.race).toList(),
                a,
                (x) => '${x.race}/${x.id}',
                (x) => x.label,
                (v) => scene.setAppearance(Appearance.initial(v)),
              ),
              field<CharacterClass>(
                'class/${a.id}',
                'Clase',
                scene.availableClasses,
                scene.characterClass,
                (c) => c.id,
                (c) => c.label,
                scene.selectClass,
              ),
              partField(Slot.face),
              partField(Slot.hair),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Proteger rostro y cabello',
                  style: TextStyle(fontSize: 11),
                ),
                subtitle: const Text(
                  'Ocultar la cabeza integrada en trajes completos',
                  style: TextStyle(fontSize: 10),
                ),
                value: scene.separateCostumeHead,
                onChanged: disabled
                    ? null
                    : (value) => act(() async {
                        scene.separateCostumeHead = value;
                        await scene.setAppearance(scene.appearance!);
                      }),
              ),
            ]),
            section('Mirada natural', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Seguir dirección de la cámara',
                  style: TextStyle(fontSize: 11),
                ),
                value: scene.headTracking,
                onChanged: (v) => setState(() => scene.headTracking = v),
              ),
              note(
                'Capa aditiva limitada y suavizada; no modifica las animaciones. Se relaja al mirar detrás del cuerpo y se desactiva al morir.',
              ),
            ]),
            section('Apariencia guardada', [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: disabled ? null : () => act(saveAppearance),
                      child: const Text(
                        'Guardar',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: disabled ? null : () => act(loadAppearance),
                      child: const Text(
                        'Recuperar',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ]),
            section('Cuerpo base', [
              OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () => act(() async {
                        final look = scene.appearance!;
                        await scene.setAppearance(
                          Appearance.base(look.archetype, previous: look),
                        );
                      }),
                icon: const Icon(Icons.accessibility_new, size: 16),
                label: const Text(
                  'Restaurar base',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              note(
                a.hasOriginalNude
                    ? 'Cuerpo base y Nude original disponibles en Conjuntos. Se conservan las texturas originales.'
                    : 'Cuerpo base disponible en Conjuntos. No se ha identificado un set nude completo en este arquetipo; la vestimenta que contiene DATA se conserva.',
              ),
            ]),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section(
              'Conjunto',
              [
                field<String>(
                  '${a.race}/${a.id}/set',
                  'Atuendo completo',
                  a.sets.keys.toList(),
                  scene.appearance!.preset ??
                      scene.appearance!.selected[Slot.upper]?.key,
                  (s) => s,
                  displaySet,
                  (v) => scene.setAppearance(
                    Appearance.forSet(
                      scene.appearance!.archetype,
                      v,
                      previous: scene.appearance,
                    ),
                  ),
                  detail: (s) =>
                      a.sets[s]!.values.map((p) => p.raw.texture).join(' · '),
                ),
              ],
              help:
                  'Un conjunto sustituye todas las piezas incompatibles. ↑ y ↓ recorren el catálogo cuando este campo tiene el foco.',
            ),
            note(
              'El conjunto conserva cara y cabello y equipa su casco correspondiente. El cabello se oculta al llevar casco y reaparece al retirarlo.',
            ),
            section('Piezas', [
              for (final s in [
                Slot.upper,
                Slot.lower,
                Slot.hand,
                Slot.foot,
                Slot.helmet,
              ])
                partField(s),
            ]),
            section(
              'Armas',
              [
                field<WeaponRecord>(
                  'weapons/${a.id}/${scene.characterClass.id}',
                  'Equipo de combate',
                  scene.availableWeapons,
                  scene.weaponRecord,
                  (w) => '${w.source}#${w.id}',
                  c.names.weaponTitle,
                  scene.equip,
                  detail: (w) =>
                      '${c.names.weaponDetail(w)}\n${scene.compatibilityFor(w).reason}',
                  empty: 'Sin arma',
                ),
                TextButton(
                  onPressed: disabled
                      ? null
                      : () => act(() => scene.equip(null)),
                  child: const Text(
                    'Quitar arma',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
              help:
                  'Se conservan los anclajes originales IT2. Las armas dobles utilizan ambas manos cuando el perfil lo define.',
            ),
            section('Mano secundaria', [
              if (permitsShield(scene.weaponRecord))
                field<WeaponRecord>(
                  'shields/${a.id}/${scene.characterClass.id}',
                  'Escudo',
                  scene.availableShields,
                  scene.shieldRecord,
                  (w) => '${w.source}#${w.id}',
                  c.names.weaponTitle,
                  scene.equipShield,
                  detail: (w) =>
                      '${c.names.weaponDetail(w)}\n${scene.compatibilityFor(w).reason}',
                  empty: 'Sin escudo',
                )
              else
                note(
                  'El arma actual ocupa ambas manos. Equipa un arma de una mano para añadir un escudo.',
                ),
              TextButton(
                onPressed: disabled
                    ? null
                    : () => act(() => scene.equipShield(null)),
                child: const Text('Quitar escudo'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Inspeccionar equipo de otras clases',
                  style: TextStyle(fontSize: 11),
                ),
                subtitle: const Text(
                  'No cambia las reglas del juego; los anclajes siguen comprobándose',
                  style: TextStyle(fontSize: 10),
                ),
                value: scene.inspectAnyEquipment,
                onChanged: (v) => setState(() => scene.inspectAnyEquipment = v),
              ),
            ]),
            weaponEffectsPanel(),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('Alas', [
              creatureField('wing'),
              if (scene.wing != null) ...[
                actorAnimation(scene.wing!, 'wing'),
                slider(
                  'Rotación horizontal',
                  scene.wingYaw * 180 / 3.141592653589793,
                  -180,
                  180,
                  (v) => setState(
                    () => scene.wingYaw = v * 3.141592653589793 / 180,
                  ),
                ),
                slider(
                  'Altura del anclaje',
                  scene.wingHeight,
                  -2,
                  4,
                  (v) => setState(() => scene.wingHeight = v),
                ),
                slider(
                  'Separación de espalda',
                  scene.wingDepth,
                  -2,
                  2,
                  (v) => setState(() => scene.wingDepth = v),
                ),
                slider(
                  'Escala',
                  scene.wingSize,
                  .1,
                  3,
                  (v) => setState(() => scene.wingSize = v),
                ),
                TextButton(
                  onPressed: disabled
                      ? null
                      : () => act(() => scene.selectCreature(null, 'wing')),
                  child: const Text(
                    'Quitar alas',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
              note(
                'El anclaje sigue el torso y la transformación del jinete, también al montar.',
              ),
            ]),
            section('Vuelo suplementario', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Flotar / volar al equipar alas',
                  style: TextStyle(fontSize: 11),
                ),
                value: scene.flightEnabled,
                onChanged: scene.setFlightEnabled,
              ),
              if (scene.extraMotions == null)
                OutlinedButton.icon(
                  onPressed: disabled ? null : () => act(importExtras),
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Importar flight.json.gz'),
                ),
              note(
                scene.extraMotions == null
                    ? 'Paquete suplementario no instalado. La marcha original permanece activa.'
                    : '${scene.extraMotions!.profiles.length} perfiles aislados de los ANI originales. ${scene.character?.hover != null ? 'Este cuerpo tiene vuelo compatible.' : 'No se aplica un movimiento incompatible a este cuerpo.'}',
              ),
            ]),
            section('Montura', [
              creatureField('mount'),
              if (scene.mount != null) ...[
                actorAnimation(scene.mount!, 'mount'),
                slider(
                  'Altura del asiento',
                  scene.riderHeight,
                  0,
                  6,
                  (v) => setState(() => scene.riderHeight = v),
                ),
                slider(
                  'Avance del asiento',
                  scene.riderForward,
                  -3,
                  3,
                  (v) => setState(() => scene.riderForward = v),
                ),
                TextButton(
                  onPressed: disabled
                      ? null
                      : () => act(() => scene.selectCreature(null, 'mount')),
                  child: const Text(
                    'Desmontar',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                note(
                  'W: marcha · W + Shift: carrera. El ajuste de asiento se recuerda por montura durante la sesión.',
                ),
              ],
            ]),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section(
              'Prueba de combate',
              [
                creatureField('enemy'),
                enemyTools(),
                if (scene.enemy != null) ...[
                  actorAnimation(scene.enemy!, 'enemy'),
                  slider(
                    'Distancia al personaje',
                    scene.enemyDistance.clamp(.5, 12),
                    .5,
                    12,
                    (v) => setState(() {
                      scene.enemy!.root.position.x =
                          (scene.character?.root.position.x ?? 0) + v;
                      scene.enemy!.root.position.z =
                          scene.character?.root.position.z ?? 0;
                    }),
                  ),
                ],
                toggle(
                  'Contraataque',
                  scene.combat.counterattack,
                  (v) => setState(() => scene.combat.counterattack = v),
                ),
                toggle(
                  'Ataque automático',
                  scene.combat.automatic,
                  scene.enemy == null || scene.mount != null
                      ? null
                      : (v) {
                          if (v) {
                            act(() async {
                              await scene.attack();
                              scene.combat.automatic = true;
                            });
                          } else {
                            setState(() => scene.combat.automatic = false);
                          }
                        },
                ),
                slider(
                  'Daño del personaje',
                  scene.combat.damage,
                  10,
                  250,
                  (v) => setState(() => scene.combat.damage = v),
                ),
                slider(
                  'Daño de criatura',
                  scene.combat.enemyDamage,
                  10,
                  150,
                  (v) => setState(() => scene.combat.enemyDamage = v),
                ),
                slider(
                  'Alcance',
                  scene.combat.range,
                  1,
                  12,
                  (v) => setState(() => scene.combat.range = v),
                ),
                OutlinedButton(
                  onPressed: scene.resetCombat,
                  child: const Text(
                    'Reiniciar prueba',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
              help: 'Simulación local. No reproduce las fórmulas del servidor.',
            ),
            section('Efectos y sonido', [
              toggle(
                'Activar audio',
                scene.sound,
                (v) => setState(() => scene.sound = v),
              ),
              field<String>(
                'impact',
                'Textura de impacto',
                c.effects,
                scene.effectPath,
                (s) => s,
                baseName,
                scene.setEffect,
                detail: (s) => s,
                empty: 'Sin textura',
              ),
              field<String>(
                'audio',
                'Sonido / música',
                c.sounds,
                lastSound.isEmpty ? null : lastSound,
                (s) => s,
                baseName,
                (v) async {
                  scene.sound = true;
                  await scene.playSound(v);
                  setState(() => lastSound = v);
                },
                detail: (s) => s,
              ),
              note(
                'Texturas y audio originales. El impacto del laboratorio no sustituye todas las secuencias EFT.',
              ),
            ]),
            section('Registro', [
              SelectableText(
                scene.combat.log.take(12).join('\n'),
                style: const TextStyle(fontSize: 10, height: 1.6),
              ),
            ]),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('Escenario', [
              field<String>(
                'world',
                'Mapa / región',
                c.worlds,
                scene.worldPath,
                (s) => s,
                c.names.mapTitle,
                (v) => scene.setWorld(v),
                detail: (s) => s,
                empty: 'Estudio',
              ),
              field<String>(
                'sky',
                'Cielo',
                c.skies,
                scene.skyPath,
                (s) => s,
                baseName,
                scene.setSky,
                detail: (s) => s,
                empty: 'Sin cielo',
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: disabled
                          ? null
                          : () => act(() => scene.setWorld(null)),
                      child: const Text(
                        'Estudio',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: disabled
                          ? null
                          : () => act(() => scene.setSky(null)),
                      child: const Text(
                        'Sin cielo',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: xController,
                      style: const TextStyle(fontSize: 11),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'X'),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: zController,
                      style: const TextStyle(fontSize: 11),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Z'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: disabled || scene.worldPath == null
                    ? null
                    : () => act(() async {
                        final x = double.tryParse(xController.text),
                            z = double.tryParse(zController.text);
                        if (x == null || z == null) {
                          throw const FormatException(
                            'Escribe dos coordenadas numéricas.',
                          );
                        }
                        await scene.setWorld(scene.worldPath, x: x, z: z);
                      }),
                child: const Text(
                  'Ir a coordenadas',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              note(
                'Escenario completo · ${scene.game.loaded?.objectCount ?? 0} objetos · ${scene.game.loaded?.triangleCount ?? 0} triángulos. Recursos pendientes: ${scene.game.loaded?.missingObjects ?? 0}. La densidad del terreno depende del nivel de detalle.',
              ),
            ]),
            worldOptions(),
            section('Visualización', [
              toggle('Malla de alambre', scene.wireframe, scene.setWireframe),
              slider('Cámara', scene.distance, .4, 60, (v) {
                scene.distance = v;
                scene.updateCamera();
              }),
              slider('Altura del encuadre', scene.targetY, -1, 6, (v) {
                scene.targetY = v;
                scene.updateCamera();
              }),
              OutlinedButton.icon(
                onPressed: () => act(capture),
                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                label: const Text(
                  'Captura PNG',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ]),
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('Recursos indexados', [
              Text(
                '${c.library.files.length} recursos\n${c.archetypes.length} arquetipos\n${c.weapons.length} armas\n${c.creatures.length} criaturas\n${c.mounts.length} registros de monturas\n${c.wings.length} alas\n${c.worlds.length} mapas\n${c.skies.length} cielos',
                style: const TextStyle(fontSize: 11, height: 1.75),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => act(exportDiagnostics),
                child: const Text(
                  'Exportar diagnóstico',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              note(
                'Las listas contienen recursos encontrados, no combinaciones exhaustivamente homologadas.',
              ),
            ]),
            section('Recursos y archivos', [
              OutlinedButton.icon(
                onPressed: disabled ? null : () => act(textureBrowser),
                icon: const Icon(Icons.texture, size: 16),
                label: const Text('Explorador de todas las DDS'),
              ),
              OutlinedButton.icon(
                onPressed: () => act(exportArchiveReport),
                icon: const Icon(Icons.receipt_long, size: 16),
                label: const Text('Informe SAH / SAF'),
              ),
              note(c.library.sourceLabel),
            ]),
            SelectableText(
              diagnostics.take(45).join('\n\n'),
              style: const TextStyle(fontSize: 10, height: 1.45),
            ),
          ],
        );
    }
  }

  Widget actorAnimation(Actor a, String target) {
    final names = a.clips.keys.toList();
    final selected = names.where((s) => a.clips[s] == a.clip).firstOrNull;
    return field<String>(
      '$target/animation',
      'Animación',
      names,
      selected,
      (s) => s,
      (s) => s,
      (v) => scene.previewActorAnimation(target, v),
    );
  }

  Actor? get inspected => switch (inspectorTarget) {
    'Montura' => scene.mount,
    'Alas' => scene.wing,
    'Criatura' => scene.enemy,
    _ => scene.character,
  };
  Widget inspector() {
    final actor = inspected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('Objeto inspeccionado', [
          DropdownButton<String>(
            value: inspectorTarget,
            isExpanded: true,
            items: ['Personaje', 'Montura', 'Alas', 'Criatura']
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
            onChanged: (s) => setState(() => inspectorTarget = s!),
          ),
          if (actor == null)
            note('No hay un objeto de este tipo cargado.')
          else ...[
            Text(
              '${actor.parts.fold(0, (n, p) => n + p.data.triangles)} triángulos · ${actor.world.length} huesos',
              style: const TextStyle(fontSize: 10, color: Color(0xffa7b8d1)),
            ),
            note(
              actor.clip == null
                  ? 'Sin animación'
                  : '${animationLabel(actor.clip!.source)}\n${baseName(actor.clip!.source)}',
            ),
            slider(
              'Velocidad de reproducción',
              actor.speed,
              .1,
              2,
              (v) => setState(() => actor.speed = v),
            ),
            toggle(
              'Reproducción',
              actor.playing,
              (v) => setState(() => actor.playing = v),
            ),
            if (actor.clip != null)
              note(
                'Duración ${actor.clip!.duration.toStringAsFixed(2)} s\nTiempo ${actor.time.toStringAsFixed(2)} s\nPosición X ${actor.root.position.x.toStringAsFixed(2)} / Y ${actor.root.position.y.toStringAsFixed(2)} / Z ${actor.root.position.z.toStringAsFixed(2)}',
              ),
          ],
        ]),
        section('Atajos', [
          note(
            'W A S D  —  caminar\nShift + dirección  —  correr\n1–4  —  ataques disponibles\nR  —  reiniciar combate\nArrastrar  —  orbitar\nRueda / pellizco  —  acercar\n↑ / ↓ en un selector  —  cambiar recurso\nIntro en el selector  —  catálogo',
          ),
          note(
            'Los atajos del personaje solo actúan cuando el visor tiene el foco. No interfieren con las búsquedas.',
          ),
        ]),
        if (scene.combat.log.isNotEmpty)
          section('Últimos eventos', [
            Text(
              scene.combat.log.take(5).join('\n'),
              style: const TextStyle(fontSize: 10, height: 1.5),
            ),
          ]),
      ],
    );
  }

  Widget timeline() {
    final a = scene.character;
    if (a == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final clip = a.clip;
        final progress = clip == null
            ? 0.0
            : ((a.loop
                          ? a.time % clip.duration
                          : a.time.clamp(0.0, clip.duration)) /
                      clip.duration)
                  .clamp(0.0, 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: a.playing ? 'Pausar' : 'Reproducir',
                  onPressed: () => setState(() => a.playing = !a.playing),
                  icon: Icon(
                    a.playing ? Icons.pause : Icons.play_arrow,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => act(() async {
                      final memory = _memories.putIfAbsent(
                        'character/animation',
                        SelectionMemory.new,
                      );
                      final p = await showDialog<String>(
                        context: context,
                        builder: (_) => AssetPickerDialog<String>(
                          title: 'Animaciones del personaje',
                          items: scene.animations,
                          current: clip?.source,
                          id: (x) => x,
                          label: animationLabel,
                          detail: baseName,
                          memory: memory,
                        ),
                      );
                      if (p != null) await scene.selectAnimation(p);
                    }),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            clip == null
                                ? 'Sin animación'
                                : animationLabel(clip.source),
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.expand_more, size: 16),
                      ],
                    ),
                  ),
                ),
                if (constraints.maxWidth > 350) ...[
                  const SizedBox(width: 14),
                  Text(
                    '${(clip == null ? 0 : progress * clip.duration).toStringAsFixed(2)} / ${clip?.duration.toStringAsFixed(2) ?? '0'} s',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xff8fa1bb),
                    ),
                  ),
                ],
                PopupMenuButton<double>(
                  tooltip: 'Velocidad',
                  onSelected: (v) => setState(() => a.speed = v),
                  itemBuilder: (_) => [.25, .5, 1.0, 1.5, 2.0]
                      .map((v) => PopupMenuItem(value: v, child: Text('$v×')))
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      '${a.speed.toStringAsFixed(2)}×',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 18,
              child: Slider(
                value: progress,
                onChanged: clip == null
                    ? null
                    : (v) {
                        scene.clearMovement();
                        a.time = v * clip.duration;
                        a.playing = false;
                        a.pose();
                        setState(() {});
                      },
              ),
            ),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Future<void> performAttack([int index = 0]) async {
    if (disabled || scene.enemy == null) return;
    try {
      scene.clearMovement();
      scene.attackCounter = index;
      await scene.attack();
      focus.requestFocus();
    } catch (e) {
      showError(e);
    }
  }

  Widget actionBar() => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      children: [
        for (var i = 0; i < scene.attackClips.length && i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: '${i + 1}: ${baseName(scene.attackClips[i].source)}',
              child: SizedBox(
                width: 91,
                child: FilledButton.tonal(
                  onPressed:
                      disabled ||
                          scene.enemy == null ||
                          scene.mount != null ||
                          scene.combat.cooldownRemaining > 0
                      ? null
                      : () => performAttack(i),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scene.combat.cooldownRemaining > 0
                              ? '${scene.combat.cooldownRemaining.toStringAsFixed(1)} s'
                              : 'Ataque ${i + 1}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: scene.enemy == null
              ? null
              : () {
                  scene.resetCombat();
                  focus.requestFocus();
                },
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text('Reiniciar', style: TextStyle(fontSize: 10)),
        ),
        const SizedBox(width: 9),
        Center(
          child: Text(
            scene.mount != null
                ? 'Montado · W / Shift'
                : scene.enemy == null
                ? 'Selecciona un oponente en Combate'
                : 'Alcance ${scene.enemyDistance.toStringAsFixed(1)} / ${scene.combat.range.toStringAsFixed(1)} m',
            style: const TextStyle(fontSize: 10, color: Color(0xff99a9c2)),
          ),
        ),
      ],
    ),
  );
  Widget weaponEffectsPanel() => section('Mejora y elemento', [
    slider(
      'Nivel de mejora · +${scene.game.enchant}',
      scene.game.enchant.toDouble(),
      0,
      20,
      (value) {
        setState(() => scene.game.enchant = value.round());
      },
    ),
    Wrap(
      spacing: 5,
      children: [
        for (final level in [0, 1, 2, 3, 7, 9, 12, 15, 20])
          ActionChip(
            label: Text('+$level', style: const TextStyle(fontSize: 10)),
            onPressed: disabled
                ? null
                : () => act(() async {
                    scene.game.enchant = level;
                    await scene.rebuildWeaponEffect();
                  }),
          ),
      ],
    ),
    const SizedBox(height: 8),
    field<int>(
      'element',
      'Elemento',
      [0, 1, 2, 3, 4],
      scene.game.element,
      (i) => '$i',
      (i) => ['Sin elemento', 'Fuego', 'Agua', 'Viento', 'Tierra'][i],
      (i) async {
        scene.game.element = i;
        await scene.rebuildWeaponEffect();
      },
    ),
    field<EffectRecipe>(
      'weapon-fx',
      'Receta de partículas',
      catalog!.names.weaponEffects,
      scene.game.recipe,
      (p) => '${p.id}',
      (p) => 'Efecto ${p.id} · ${p.particles.length} emisores',
      (p) async {
        scene.game.recipe = p;
        await scene.rebuildWeaponEffect();
      },
      detail: (p) => p.particles
          .map((e) => e.texture)
          .where((s) => s.isNotEmpty)
          .join(' · '),
    ),
    OutlinedButton(
      onPressed: disabled ? null : () => act(scene.rebuildWeaponEffect),
      child: const Text(
        'Aplicar mejora visual',
        style: TextStyle(fontSize: 11),
      ),
    ),
    note(
      'Previsualización: usa las texturas de Weapon.SEFF. El nivel regula la intensidad; no se afirma una correspondencia exacta entre cada nivel y las recetas del cliente original.',
    ),
  ]);
  Widget enemyTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      field<CreatureRecord>(
        'spawn-extra',
        'Añadir otra criatura',
        catalog!.creatures,
        null,
        creatureId,
        catalog!.creatureLabel,
        scene.addOpponent,
        empty: 'Seleccionar y añadir',
        detail: (v) => v.parts.map((p) => p.mesh).join(' · '),
      ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: disabled || scene.enemyRecord == null
                  ? null
                  : () => act(() => scene.addOpponent(scene.enemyRecord!)),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Añadir copia', style: TextStyle(fontSize: 10)),
            ),
          ),
          IconButton(
            tooltip: 'Retirar objetivo',
            onPressed: disabled ? null : scene.removeOpponent,
            icon: const Icon(Icons.remove_circle_outline, size: 18),
          ),
          IconButton(
            tooltip: 'Vaciar escena',
            onPressed: disabled ? null : scene.clearOpponents,
            icon: const Icon(Icons.clear_all, size: 18),
          ),
        ],
      ),
      if (scene.game.opponents.isNotEmpty)
        field<String>(
          'targets',
          'Oponentes en escena',
          scene.game.opponents.keys.toList(),
          scene.combat.target,
          (id) => id,
          (id) {
            final p = scene.game.opponents[id]!;
            return '${catalog!.creatureLabel(p.record)} · ${scene.combat.health[id]?.round()} PV';
          },
          (id) async {
            scene.selectOpponent(id);
          },
        ),
      note(
        'Clic sobre una criatura para seleccionarla; Tab cambia de objetivo. Clic en el suelo: caminar. Espacio: salto. Cada oponente conserva su propia vida.',
      ),
    ],
  );
  Widget worldOptions() {
    final loaded = scene.game.loaded;
    return section('Exploración', [
      if (loaded != null && loaded.data.areas.isNotEmpty)
        field<WorldArea>(
          'places/${scene.worldPath}',
          'Lugares del mapa',
          loaded.data.areas,
          null,
          (a) => '${a.name}/${a.center}',
          (a) => catalog!.names.areaTitle(a, loaded.data.areas.indexOf(a)),
          (a) async {
            await scene.visitArea(a);
          },
          detail: (a) =>
              '${a.comment} · ${a.center.x.round()}, ${a.center.z.round()}',
        ),
      field<int>(
        'detail',
        'Detalle del terreno',
        [0, 1, 2],
        scene.game.quality,
        (i) => '$i',
        (i) => [
          'Ligero · streaming cercano',
          'Equilibrado · streaming cercano',
          'Alto · más distancia de dibujado',
        ][i],
        (i) async {
          scene.game.quality = i;
          if (scene.worldPath != null) {
            final path = scene.worldPath!;
            await scene.setWorld(path);
          }
        },
      ),
      if (loaded != null) ...[
        slider('Radio de carga (m)', loaded.drawRadius, 96, 320, (r) {
          loaded.setDrawRadius(r);
          scene.updateCamera();
          setState(() {});
        }),
        note(
          '${loaded.residentChunks} sectores residentes · ${loaded.pendingChunks} pendientes\n${loaded.objectCount} objetos próximos · ${loaded.releasedChunks} sectores liberados. Las colisiones lejanas también se retiran.',
        ),
      ],
      if (scene.game.environments.isNotEmpty)
        field<int>(
          'environment/${scene.worldPath}',
          'Ambiente original',
          List.generate(scene.game.environments.length, (i) => i),
          scene.game.environmentIndex,
          (i) => '$i',
          (i) {
            final e = scene.game.environments[i];
            return '${e.start.toString().padLeft(4, '0')} – ${e.end.toString().padLeft(4, '0')}';
          },
          scene.setEnvironment,
        ),
      note(
        'WASD relativo a la cámara · Shift: correr · Espacio: saltar. El destino por clic busca una ruta sobre el suelo y las colisiones disponibles. Los recursos sin colisión original no actúan como muros.',
      ),
    ]);
  }

  Widget healthBar(String label, double hp) => SizedBox(
    width: 158,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xffdfe7f6)),
              ),
            ),
            Text(
              '${hp.round()}',
              style: const TextStyle(fontSize: 10, color: Color(0xffdfe7f6)),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: (hp / scene.combat.maxHealth).clamp(0.0, 1.0),
          minHeight: 4,
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    ),
  );
  Widget viewport() => RepaintBoundary(
    key: captureKey,
    child: Stack(
      children: [
        Positioned.fill(child: renderer.build()),
        Positioned.fill(
          child: ViewportMovementInput(
            focusNode: focus,
            onChanged: (x, z, run) => scene.setMovement(x, z, run: run),
            onAction: (key) {
              final keys = [
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
              ];
              final index = keys.indexOf(key);
              if (index >= 0 && index < scene.attackClips.length) {
                performAttack(index);
              }
              if (key == LogicalKeyboardKey.keyR) scene.resetCombat();
              if (key == LogicalKeyboardKey.space) act(scene.jump);
              if (key == LogicalKeyboardKey.tab) scene.cycleOpponent();
              if (key == LogicalKeyboardKey.escape) {
                scene.clearMovement();
                scene.combat.automatic = false;
              }
            },
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  scene.zoom(event.scrollDelta.dy > 0 ? 1.08 : 1 / 1.08);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  focus.requestFocus();
                  final size = captureKey.currentContext?.size;
                  if (size != null) {
                    try {
                      scene.clickScene(
                        details.localPosition.dx,
                        details.localPosition.dy,
                        size.width,
                        size.height,
                      );
                    } catch (e) {
                      log('Selección: $e');
                    }
                  }
                },
                onScaleStart: (_) {
                  gestureScale = 1;
                  focus.requestFocus();
                },
                onScaleUpdate: (d) {
                  if (d.pointerCount == 1) {
                    scene.orbit(d.focalPointDelta.dx, d.focalPointDelta.dy);
                  } else {
                    scene.zoom(gestureScale / d.scale);
                    gestureScale = d.scale;
                  }
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 14,
          right: 14,
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scene.appearance?.archetype.label ?? 'Estudio 3D',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xffe8edf8),
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  scene.mount != null
                      ? 'Montado · ${scene.running ? 'Carrera' : 'Marcha'}'
                      : scene.walkX != 0 || scene.walkZ != 0
                      ? (scene.running ? 'Corriendo' : 'Caminando')
                      : 'Vista libre',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xffb9c9df),
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
                if (scene.enemy != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xd9182130),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 10,
                        children: [
                          healthBar('Personaje', scene.combat.playerHealth),
                          healthBar(
                            scene.selectedTargetName,
                            scene.combat.enemyHealth,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (scene.hitLife > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      scene.lastImpact,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xffffd6a1),
                        shadows: [Shadow(blurRadius: 5, color: Colors.black)],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (catalog == null && !importing)
          Center(
            child: SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 350),
                padding: const EdgeInsets.all(25),
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xf51b2638),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xff35465f)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.view_in_ar_outlined,
                      size: 28,
                      color: Color(0xffadc1ff),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Tu biblioteca.\nTu espacio 3D.',
                      style: TextStyle(fontSize: 27, height: 1.2),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Personajes, equipo y escenarios originales. Selecciona DATA para comenzar.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xffa7b7ce),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: disabled ? null : () => connect(),
                      icon: const Icon(Icons.folder_open, size: 17),
                      label: const Text('Conectar DATA'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (scene.character != null)
          Positioned(
            bottom: 12,
            right: 12,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => setState(() => scene.touchRun = !scene.touchRun),
                  child: Tooltip(
                    message: 'Correr con los controles táctiles',
                    child: Container(
                      width: 40,
                      height: 28,
                      decoration: BoxDecoration(
                        color: scene.touchRun
                            ? const Color(0xff536d9f)
                            : const Color(0xc8232d40),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Icon(Icons.directions_run, size: 17),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                IconButton(
                  tooltip: 'Saltar · Espacio',
                  onPressed: disabled ? null : () => act(scene.jump),
                  icon: const Icon(Icons.upgrade, size: 18),
                ),
                movePad(Icons.arrow_upward, 0, -1),
                Row(
                  children: [
                    movePad(Icons.arrow_back, -1, 0),
                    movePad(Icons.arrow_downward, 0, 1),
                    movePad(Icons.arrow_forward, 1, 0),
                  ],
                ),
              ],
            ),
          ),
        if (importing || working || scene.busy || scene.game.loadingWorld)
          Positioned(
            bottom: 12,
            left: 12,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 225),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xec1c293d),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        importing ? progress : 'Preparando recursos…',
                        maxLines: 2,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Widget movePad(IconData icon, double x, double z) => Listener(
    onPointerDown: (_) {
      scene.setMovement(x, z, run: scene.touchRun);
    },
    onPointerUp: (_) {
      scene.clearMovement();
    },
    onPointerCancel: (_) {
      scene.clearMovement();
    },
    child: Container(
      margin: const EdgeInsets.all(2),
      width: 32,
      height: 29,
      decoration: BoxDecoration(
        color: const Color(0xc8232d40),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(icon, size: 16, color: const Color(0xffc6d3e8)),
    ),
  );
  Future<File> saveFile(String name, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/HerramientaShaiya');
    await folder.create(recursive: true);
    final f = File('${folder.path}/$name');
    await f.writeAsString(content, flush: true);
    scene.say('Guardado: ${f.path}');
    return f;
  }

  Future<void> saveAppearance() async {
    final look = scene.appearance!;
    await saveFile(
      'apariencia.json',
      jsonEncode({
        'version': 2,
        'preset': look.preset,
        'archetype': look.archetype.id,
        'race': look.archetype.race,
        'fullCostume': look.fullCostume,
        'slots': {
          for (final e in look.selected.entries) e.key.name: e.value?.raw.id,
        },
      }),
    );
  }

  Future<void> loadAppearance() async {
    final dir = await getApplicationDocumentsDirectory(),
        f = File('${dir.path}/HerramientaShaiya/apariencia.json');
    if (!await f.exists()) {
      throw const FormatException('No hay una apariencia guardada.');
    }
    final data = jsonDecode(await f.readAsString()) as Map;
    final a = catalog!.archetypes
        .where((a) => a.id == data['archetype'] && a.race == data['race'])
        .firstOrNull;
    if (a == null) {
      throw const FormatException('El arquetipo guardado no existe en DATA.');
    }
    final slots = <Slot, PartRecord?>{};
    for (final s in Slot.values) {
      final id = (data['slots'] as Map)[s.name];
      slots[s] = id == null
          ? null
          : a.parts[s]!.where((p) => p.raw.id == id).firstOrNull;
      if (id != null && slots[s] == null) {
        throw FormatException('No se encuentra ${s.name} #$id.');
      }
    }
    await scene.setAppearance(
      Appearance(
        a,
        slots,
        preset: data['preset'] is String ? data['preset'] as String : null,
      ),
    );
  }

  Future<void> textureBrowser() async {
    final c = catalog!;
    String search = '';
    TextureEntry? selected;
    Uint8List? preview;
    String status = '';
    int revision = 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final entries = c.textureInventory.values
              .where(
                (e) => '${e.path} ${e.role} ${e.state}'.toLowerCase().contains(
                  search.toLowerCase(),
                ),
              )
              .toList();
          Future<void> show(TextureEntry e) async {
            final token = ++revision;
            setDialog(() {
              selected = e;
              preview = null;
              status = 'Leyendo textura…';
            });
            try {
              final bytes = await c.library.read(
                e.path,
                limit: 32 * 1024 * 1024,
              );
              final png = await compute(_texturePreview, {
                'bytes': bytes,
                'path': e.path,
              });
              if (ctx.mounted && token == revision) {
                setDialog(() {
                  preview = png;
                  status = '${e.role} · ${e.state}';
                });
              }
            } catch (err) {
              if (ctx.mounted && token == revision) {
                setDialog(() => status = err.toString());
              }
            }
          }

          return AlertDialog(
            title: Text(
              'Inventario DDS · ${c.textureInventory.length} archivos',
            ),
            content: SizedBox(
              width: 850,
              height: 540,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar nombre, función o estado',
                    ),
                    onChanged: (q) => setDialog(() => search = q),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (ctx, i) {
                              final e = entries[i];
                              return ListTile(
                                dense: true,
                                selected: identical(e, selected),
                                title: Text(
                                  baseName(e.path),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                subtitle: Text(
                                  '${e.role} · ${e.state}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                onTap: () => show(e),
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (preview != null)
                                  Image.memory(
                                    preview!,
                                    height: 230,
                                    fit: BoxFit.contain,
                                  ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  selected?.path ?? 'Selecciona una textura',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                note(status),
                                if (selected != null) ...[
                                  note(selected!.notes.join('\n')),
                                  note(selected!.owners.take(12).join('\n')),
                                  if (selected!.role ==
                                      'apariencia de personaje')
                                    OutlinedButton(
                                      onPressed: () async {
                                        final a = scene.appearance!.archetype;
                                        final prototype =
                                            await showDialog<PartRecord>(
                                              context: ctx,
                                              builder: (sub) => AlertDialog(
                                                title: const Text(
                                                  'Prototipo del cuerpo actual',
                                                ),
                                                content: SizedBox(
                                                  width: 480,
                                                  height: 380,
                                                  child: ListView(
                                                    children: a.parts.values
                                                        .expand((v) => v)
                                                        .where(
                                                          (p) => p.raw.id >= 0,
                                                        )
                                                        .map(
                                                          (p) => ListTile(
                                                            title: Text(
                                                              '${slotLabels[p.slot]} · ${p.label}',
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                            ),
                                                            subtitle: Text(
                                                              p.raw.mesh,
                                                            ),
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                  sub,
                                                                  p,
                                                                ),
                                                          ),
                                                        )
                                                        .toList(),
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(sub),
                                                    child: const Text(
                                                      'Cancelar',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                        if (prototype == null || !ctx.mounted) {
                                          return;
                                        }
                                        try {
                                          final part = await c.bindTexture(
                                            a,
                                            prototype.slot,
                                            selected!.path,
                                            prototype,
                                          );
                                          await scene.setAppearance(
                                            scene.appearance!.withPart(
                                              prototype.slot,
                                              part,
                                            ),
                                          );
                                          if (ctx.mounted) {
                                            setDialog(
                                              () => status =
                                                  'Asociación manual aplicada. Comprueba la distribución UV en el visor.',
                                            );
                                          }
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            setDialog(
                                              () => status = e.toString(),
                                            );
                                          }
                                        }
                                      },
                                      child: const Text(
                                        'Asociar a un prototipo y previsualizar',
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await saveFile(
                    'inventario_dds.json',
                    const JsonEncoder.withIndent('  ').convert(
                      c.textureInventory.values.map((e) => e.toJson()).toList(),
                    ),
                  );
                },
                child: const Text('Exportar inventario'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> exportDiagnostics() async {
    await saveFile(
      'diagnostico.json',
      const JsonEncoder.withIndent('  ').convert({
        'version': '0.4.0',
        'time': DateTime.now().toIso8601String(),
        'platform': Platform.operatingSystem,
        'resources': catalog?.library.files.length,
        'source': catalog?.library.sourceDiagnostics,
        'archiveAttempt': Library.lastArchiveReport,
        'streaming': scene.game.loaded?.streamingStats,
        'messages': diagnostics,
      }),
    );
  }

  Future<void> capture() async {
    final boundary =
        captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final im = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
    im.dispose();
    if (bytes == null) {
      throw const FormatException('No se pudo capturar el visor.');
    }
    final dir = await getApplicationDocumentsDirectory(),
        f = File(
          '${dir.path}/Shaiya_${DateTime.now().millisecondsSinceEpoch}.png',
        );
    await f.writeAsBytes(bytes.buffer.asUint8List());
    scene.say('Captura guardada: ${f.path}');
  }

  @override
  Widget build(BuildContext context) => StudioWorkspace(
    viewport: viewport(),
    left: panel(),
    right: inspector(),
    timeline: timeline(),
    actions: actionBar(),
    hasLibrary: scene.character != null,
    onOpenData: disabled ? null : sourceMenu,
    tabs: const [
      'Personaje',
      'Equipamiento',
      'Alas y monturas',
      'Combate',
      'Escenario',
      'Diagnóstico',
    ],
    icons: const [
      Icons.person_outline,
      Icons.shield_outlined,
      Icons.pets_outlined,
      Icons.sports_martial_arts,
      Icons.landscape_outlined,
      Icons.fact_check_outlined,
    ],
    selectedTab: tab,
    onTab: (v) {
      scene.clearMovement();
      setState(() => tab = v);
    },
    status: Row(
      children: [
        const Icon(Icons.lock_outline, size: 11, color: Color(0xff8cbaa3)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            scene.status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        const Text('Local · Solo lectura'),
      ],
    ),
  );
}

Uint8List _texturePreview(Map<String, Object> args) =>
    Pixels.decode(args['bytes'] as Uint8List, args['path'] as String).png();
