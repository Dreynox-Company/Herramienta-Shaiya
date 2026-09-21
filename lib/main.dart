import 'render/native_view.dart';
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
import 'ui/data_editor.dart';
import 'ui/spk_archive_browser.dart';
import 'core/game_text_codec.dart';
import 'core/legacy_text.dart';
import 'offline_game/scene_profile.dart';
import 'data/file_save.dart';

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
    renderer = NativeView(
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
    bool preserveMovement = false,
  }) async {
    if (working || importing) return;
    setState(() => working = true);
    try {
      await scene.runUserAction(action, preserveMovement: preserveMovement);
    } catch (e) {
      showError(e);
    } finally {
      if (mounted) {
        setState(() => working = false);
        if (restoreFocus) focus.requestFocus();
      }
    }
  }

  Future<void> openDataEditor() async {
    final library = catalog?.library;
    if (library == null || working) return;
    final beforeRevision = library.revision;
    scene.clearMovement();
    focus.unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RepaintBoundary(
          key: const ValueKey('data-editor-capture'),
          child: DataEditorPage(
            library: library,
            initialEncoding: LegacyText.preferred,
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (library.revision != beforeRevision) {
      await act(() async {
        final look = scene.appearance;
        final refreshed = Catalog(library);
        await refreshed.load((s) {
          if (mounted) setState(() => progress = s);
        });
        if (!mounted) return;
        final a = refreshed.archetypes
            .where(
              (a) =>
                  a.id == look?.archetype.id && a.race == look?.archetype.race,
            )
            .firstOrNull;
        scene.catalog = refreshed;
        catalog = refreshed;
        _memories.clear();
        if (a != null && look != null) {
          final slots = <Slot, PartRecord?>{};
          for (final slot in Slot.values) {
            final prior = look.selected[slot];
            slots[slot] = prior == null
                ? null
                : (a.parts[slot] ?? [])
                      .where(
                        (p) =>
                            p.raw.id == prior.raw.id &&
                            p.tablePath == prior.tablePath,
                      )
                      .firstOrNull;
          }
          await scene.setAppearance(Appearance(a, slots, preset: look.preset));
        }
        scene.say(
          'Datos guardados y catálogo recargado. Las referencias y texturas nuevas están disponibles en el laboratorio.',
        );
      });
    }
    if (mounted) focus.requestFocus();
  }

  Future<void> exportGameScene() async {
    final selected = await getSaveLocation(
      suggestedName: 'escena.shaiya.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Escena del cliente Flutter', extensions: ['json']),
      ],
    );
    if (selected == null) return;
    await act(() async {
      final bytes = Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent(
            '  ',
          ).convert(SceneProfile.capture(scene)),
        ),
      );
      final file = File(selected.path);
      if (await file.exists()) {
        await FileSave.replace(
          file.path,
          bytes,
          expectedHash: FileSave.hash(await file.readAsBytes()),
        );
      } else {
        await file.create(exclusive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      scene.say(
        'Escena exportada. Vincúlala en el cliente Flutter; no modifica el ejecutable clásico.',
      );
    });
  }

  Future<void> openSpkArchive() async {
    scene.clearMovement();
    focus.unfocus();
    await SpkArchiveBrowserPage.pickAndOpen(context);
    if (mounted) focus.requestFocus();
  }

  Future<void> sourceMenu() async {
    scene.clearMovement();
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Biblioteca de recursos'),
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
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('Archivo DATA.SPK'),
                subtitle: const Text(
                  'Explorar carpetas, archivos, buscar y extraer recursos',
                ),
                onTap: () => Navigator.pop(ctx, 'spk'),
              ),
              if (catalog?.library.archive != null)
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outlined),
                  title: const Text('Extraer / editar el archivo DATA'),
                  subtitle: const Text(
                    'Extracción y guardado transaccional desde el editor',
                  ),
                  onTap: () => Navigator.pop(ctx, 'editor'),
                ),
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('Codificación de nombres'),
                subtitle: Text(LegacyText.preferred.label),
                onTap: () => Navigator.pop(ctx, 'encoding'),
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
    if (mode == 'spk') {
      await openSpkArchive();
    } else if (mode == 'editor') {
      await openDataEditor();
    } else if (mode == 'encoding') {
      await chooseNameEncoding();
    } else if (mode == 'report') {
      await act(exportArchiveReport);
    } else if (mode != null) {
      await connect(archive: mode == 'archive');
    }
  }

  Future<void> chooseNameEncoding() async {
    final selected = await showDialog<GameTextEncoding>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Codificación original del cliente'),
        children: GameTextEncoding.values
            .where((e) => e != GameTextEncoding.utf16le)
            .map(
              (e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(c, e),
                child: Text(e.label),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null) return;
    LegacyText.preferred = selected;
    scene.say(
      'Codificación: ${selected.label}. Vuelve a abrir la biblioteca para actualizar todos los nombres. No se ha modificado DATA.',
    );
    if (mounted) setState(() {});
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
        'version': '0.6.11',
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