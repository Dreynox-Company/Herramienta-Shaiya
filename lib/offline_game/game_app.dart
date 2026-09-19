import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/gestures.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:three_js/three_js.dart' as three;
import '../core/equipment_rules.dart';
import '../core/extra_motion.dart';
import '../core/formats.dart';
import '../data/catalog.dart';
import '../data/library.dart';
import '../input/viewport_movement_input.dart';
import '../offline/save_store.dart';
import '../render/studio_scene.dart';
import '../ui/data_editor.dart';
import 'progress.dart';
import 'scene_profile.dart';

void launchLocalGame(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final data = args.where((v) => v.startsWith('--data=')).firstOrNull;
  runApp(LocalGameApp(initialData: data?.substring(7)));
}

class LocalGameApp extends StatelessWidget {
  final String? initialData;
  final SaveStore? saveStore;
  const LocalGameApp({super.key, this.initialData, this.saveStore});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Shaiya Local · Cliente Flutter',
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xff10151e),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffc6ac73),
        brightness: Brightness.dark,
      ),
      visualDensity: VisualDensity.compact,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 12),
        bodySmall: TextStyle(fontSize: 11),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    ),
    home: GameMenu(initialData: initialData, saveStore: saveStore),
  );
}

class GameMenu extends StatefulWidget {
  final String? initialData;
  final SaveStore? saveStore;
  const GameMenu({super.key, this.initialData, this.saveStore});
  @override
  State<GameMenu> createState() => _GameMenuState();
}

class _GameMenuState extends State<GameMenu> {
  SaveStore? store;
  Catalog? catalog;
  SaveListing? listing;
  String message = 'Selecciona los recursos de tu instalación.',
      faction = 'luz';
  bool busy = false, trash = false;
  String? sourceIdentity;
  final name = TextEditingController(text: 'Mi aventura');
  String? archetypeId, classId;
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      store = widget.saveStore;
      if (store == null) {
        final home = await getApplicationSupportDirectory();
        store = SaveStore(
          Directory(path.join(home.path, 'ShaiyaLocal', 'partidas')),
        );
      }
      await _refresh();
      if (widget.initialData != null) await _openDirectory(widget.initialData!);
    } catch (e) {
      _message('$e');
    }
  }

  void _message(String value) {
    if (mounted) setState(() => message = value);
  }

  Future<void> _refresh() async {
    final next = await store?.list(includeDeleted: trash);
    if (mounted) setState(() => listing = next);
  }

  List<Archetype> get allowed => (catalog?.archetypes ?? [])
      .where(
        (a) => faction == 'luz'
            ? {'human', 'elf', 'pandaw', 'pandw'}.contains(a.race)
            : {'vile', 'deatheater', 'pandab'}.contains(a.race),
      )
      .toList();
  Archetype? get chosen =>
      allowed.where((a) => a.id == archetypeId).firstOrNull ??
      allowed.firstOrNull;
  Future<void> _load(Library? library) async {
    if (library == null) return;
    final next = Catalog(library);
    try {
      await next.load(_message);
    } catch (_) {
      library.dispose();
      rethrow;
    }
    if (!mounted) {
      library.dispose();
      return;
    }
    final previous = catalog;
    setState(() {
      catalog = next;
      sourceIdentity = sha256
          .convert(utf8.encode('local-source-v1:${library.location}'))
          .toString();
      archetypeId = chosen?.id;
      classId = chosen == null ? null : classesFor(chosen!.id).first.id;
      message =
          '${next.archetypes.length} cuerpos · ${next.weapons.length} modelos de equipo · ${next.worlds.length} mapas';
    });
    previous?.library.dispose();
  }

  Future<void> _openDirectory(String dir) =>
      _guard(() => _loadFromDirectory(dir));
  Future<void> _loadFromDirectory(String dir) async =>
      _load(await Library.fromDirectory(dir, _message));
  Future<void> _guard(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      _message(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _create() async {
    final a = chosen;
    if (a == null || store == null || sourceIdentity == null) return;
    final cls =
        classesFor(a.id).where((c) => c.id == classId).firstOrNull ??
        classesFor(a.id).first;
    final save = await store!.create(
      title: name.text.trim(),
      faction: faction,
      corpusSha256: sourceIdentity!,
      state: {
        'engine': 'flutter-local-v1',
        'progress': LocalProgress().toJson(),
        'scene': {
          'schema': 1,
          'archetype': a.id,
          'class': cls.id,
          'flight': false,
        },
        'rules': const LocalRules().toJson(),
        'health': 1000.0,
      },
    );
    await _enter(save);
    await _refresh();
  }

  Future<void> _enter(SaveSnapshot save) async {
    if (catalog == null) {
      throw StateError('Conecta DATA antes de abrir una partida.');
    }
    if (save.corpusSha256 != sourceIdentity) {
      throw const FormatException(
        'Conecta la misma fuente DATA con la que creaste esta partida.',
      );
    }
    if (save.state['engine'] != 'flutter-local-v1') {
      throw const FormatException(
        'Esta partida no pertenece al cliente Flutter.',
      );
    }
    LocalProgress.parse(
      Map<String, dynamic>.from(save.state['progress']! as Map),
    );
    LocalRules.parse(Map<String, dynamic>.from(save.state['rules']! as Map));
    if (save.state['scene'] is! Map) {
      throw const FormatException('Escena de partida inválida.');
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlaySession(catalog: catalog!, store: store!, initial: save),
      ),
    );
    await _refresh();
  }

  @override
  void dispose() {
    name.dispose();
    catalog?.library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = chosen,
        items = allowed,
        classes = a == null ? <CharacterClass>[] : classesFor(a.id);
    final cls = classes.any((c) => c.id == classId)
        ? classId
        : classes.firstOrNull?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'SHAIYA  /  LOCAL',
          style: TextStyle(letterSpacing: 3, fontSize: 15),
        ),
        actions: [
          TextButton.icon(
            onPressed: busy
                ? null
                : () =>
                      _guard(() async => _load(await Library.choose(_message))),
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Carpeta DATA', style: TextStyle(fontSize: 11)),
          ),
          TextButton.icon(
            onPressed: busy
                ? null
                : () => _guard(
                    () async => _load(await Library.chooseArchive(_message)),
                  ),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('SAH + SAF', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, bounds) {
          final create = Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Nueva partida',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sin cuenta ni conexión. Estado local independiente del cliente original.',
                  style: TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: name,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la partida',
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'luz',
                      label: Text('Luz'),
                      tooltip: 'Alianza de la Luz',
                      icon: Icon(Icons.wb_sunny_outlined),
                    ),
                    ButtonSegment(
                      value: 'furia',
                      label: Text('Furia'),
                      tooltip: 'Unión de la Furia',
                      icon: Icon(Icons.nightlight_outlined),
                    ),
                  ],
                  selected: {faction},
                  onSelectionChanged: (v) => setState(() {
                    faction = v.first;
                    archetypeId = null;
                    classId = null;
                  }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('arch-$faction-${items.length}'),
                  initialValue: a?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Raza / cuerpo'),
                  items: [
                    for (final x in items)
                      DropdownMenuItem(
                        value: x.id,
                        child: Text(x.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() {
                    archetypeId = id;
                    classId = null;
                  }),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey('cls-${a?.id}'),
                  initialValue: cls,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Clase'),
                  items: [
                    for (final x in classes)
                      DropdownMenuItem(value: x.id, child: Text(x.label)),
                  ],
                  onChanged: (id) => classId = id,
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: busy || a == null || store == null
                      ? null
                      : () => _guard(_create),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Crear y entrar al mundo'),
                ),
                const SizedBox(height: 26),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'RECONSTRUCCIÓN  ·  0.1',
                  style: TextStyle(
                    color: Color(0xffc6ac73),
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Mallas, escenarios, animaciones y sonidos se leen de tus recursos. El combate y el progreso usan un reglamento local explícito; no se presentan como una reproducción exacta del servidor original.',
                  style: TextStyle(height: 1.6, color: Colors.white54),
                ),
              ],
            ),
          );
          final saves = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Tus partidas',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                    FilterChip(
                      label: const Text('Papelera'),
                      selected: trash,
                      onSelected: busy
                          ? null
                          : (v) {
                              setState(() => trash = v);
                              unawaited(_refresh());
                            },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: (listing?.saves.isEmpty ?? true)
                    ? const Center(
                        child: Text(
                          'Las partidas guardadas aparecerán aquí.',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: listing!.saves.length,
                        separatorBuilder: (_, i) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = listing!.saves[i];
                          final p = s.state['progress'] as Map?;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            leading: Icon(
                              s.faction == 'luz'
                                  ? Icons.wb_sunny_outlined
                                  : Icons.nightlight_outlined,
                              color: s.deleted
                                  ? Colors.white30
                                  : const Color(0xffc6ac73),
                            ),
                            title: Text(s.title),
                            subtitle: Text(
                              '${s.faction.toUpperCase()} · nivel ${p?['level'] ?? 1} · revisión ${s.revision}\n${s.updatedAt}',
                              style: const TextStyle(fontSize: 11, height: 1.6),
                            ),
                            isThreeLine: true,
                            onTap: busy || s.deleted
                                ? null
                                : () => _guard(() => _enter(s)),
                            trailing: IconButton(
                              tooltip: s.deleted
                                  ? 'Restaurar partida'
                                  : 'Mover a papelera',
                              onPressed: busy
                                  ? null
                                  : () => _guard(() async {
                                      await store!.trash(
                                        s.id,
                                        expectedRevision: s.revision,
                                        restore: s.deleted,
                                      );
                                      await _refresh();
                                    }),
                              icon: Icon(
                                s.deleted
                                    ? Icons.restore
                                    : Icons.delete_outline,
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (listing?.unreadable.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${listing!.unreadable.length} partidas no se pudieron verificar; no se borraron.',
                  ),
                ),
            ],
          );
          return Column(
            children: [
              if (busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: bounds.maxWidth > 800
                    ? Row(
                        children: [
                          SizedBox(
                            width: 430,
                            child: SingleChildScrollView(child: create),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: saves),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: SingleChildScrollView(child: create)),
                          SizedBox(height: 230, child: saves),
                        ],
                      ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xff19212d),
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PlaySession extends StatefulWidget {
  final Catalog catalog;
  final SaveStore store;
  final SaveSnapshot initial;
  const PlaySession({
    super.key,
    required this.catalog,
    required this.store,
    required this.initial,
  });
  @override
  State<PlaySession> createState() => _PlaySessionState();
}

class _PlaySessionState extends State<PlaySession> with WidgetsBindingObserver {
  late final StudioScene scene;
  late final three.ThreeJS renderer;
  late SaveSnapshot save;
  late LocalProgress progress;
  late LocalRules rules;
  late final String encounterSession;
  final focus = FocusNode();
  final viewportKey = GlobalKey();
  final messages = <String>[];
  bool ready = false,
      busy = true,
      saving = false,
      panel = true,
      leaving = false;
  String status = 'Preparando personaje…';
  String? profilePath;
  String? profileDigest;
  String? rejectedProfileDigest;
  bool checkingProfile = false;
  Timer? autosave, watch;
  int tab = 0;
  String query = '';
  CreatureRecord? pendingCreature;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    save = widget.initial;
    encounterSession = '${DateTime.now().microsecondsSinceEpoch}';
    progress = LocalProgress.parse(
      Map<String, dynamic>.from(save.state['progress']! as Map),
    );
    rules = LocalRules.parse(
      Map<String, dynamic>.from(save.state['rules']! as Map),
    );
    scene = StudioScene(_log)..catalog = widget.catalog;
    renderer = three.ThreeJS(
      settings: three.Settings(
        clearColor: 0x11151e,
        antialias: true,
        enableShadowMap: false,
        toneMapping: three.NoToneMapping,
      ),
      setup: () async {
        await scene.setup(renderer);
        final original = scene.combat.onTargetEvent;
        scene.combat.onTargetEvent = (id, actor, event) {
          original?.call(id, actor, event);
          if (actor == 'enemy' &&
              event == 'death' &&
              progress.defeat('$encounterSession:$id', rules)) {
            _log(
              'Victoria · +${rules.killExperience} EXP · +${rules.goldReward} oro',
            );
          }
          if (actor == 'player' && event == 'death') {
            progress.deaths++;
            _log('Has caído. Puedes resucitar en la posición actual.');
          }
        };
        renderer.addAnimationEvent((dt) {
          if (ready && !busy && !leaving) progress.advance(dt);
        });
      },
      onSetupComplete: () => unawaited(_load()),
    );
    scene.addListener(_redraw);
    autosave = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_save().then((_) {})),
    );
    watch = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_checkProfile()),
    );
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _log(String text) {
    if (!mounted) return;
    setState(() {
      status = text;
      messages.insert(0, text);
      if (messages.length > 80) messages.removeLast();
    });
  }

  Future<void> _load() async {
    try {
      final home = Directory(path.dirname(Platform.resolvedExecutable));
      final candidates = [
        File(path.join(home.path, 'extras', 'flight_profiles.json.gz')),
        File(path.join(home.path, 'flight_profiles.json.gz')),
        File(path.join(home.path, 'Extras', 'flight.json.gz')),
      ];
      for (final f in candidates) {
        if (await f.exists()) {
          await scene.installExtras(
            ExtraMotionLibrary.decode(await f.readAsBytes()),
          );
          break;
        }
      }
      await SceneProfile.apply(
        scene,
        Map<String, dynamic>.from(save.state['scene']! as Map),
      );
      final health = save.state['health'];
      if (health is! num || !health.isFinite || health < 0 || health > 1000) {
        throw const FormatException('Salud de la partida no válida.');
      }
      scene.combat.playerHealth = health.toDouble();
      if (mounted) {
        setState(() {
          ready = true;
          status = 'Partida cargada. Elige escenario y encuentros en el panel.';
        });
      }
    } catch (e) {
      _log('No se pudo cargar la partida: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (busy || leaving) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      _log(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
      if (mounted) {
        focus.requestFocus();
        final keys = HardwareKeyboard.instance.logicalKeysPressed;
        scene.setMovement(
          (keys.contains(LogicalKeyboardKey.keyD) ? 1.0 : 0.0) -
              (keys.contains(LogicalKeyboardKey.keyA) ? 1.0 : 0.0),
          (keys.contains(LogicalKeyboardKey.keyS) ? 1.0 : 0.0) -
              (keys.contains(LogicalKeyboardKey.keyW) ? 1.0 : 0.0),
          run: HardwareKeyboard.instance.isShiftPressed,
        );
      }
    }
  }

  Future<bool> _save() async {
    if (!ready || busy || saving || leaving) return false;
    saving = true;
    _redraw();
    try {
      final s = await widget.store.update(
        save.id,
        expectedRevision: save.revision,
        expectedCorpus: save.corpusSha256,
        state: {
          'engine': 'flutter-local-v1',
          'progress': progress.toJson(),
          'rules': rules.toJson(),
          'scene': SceneProfile.capture(scene),
          'health': scene.combat.playerHealth,
        },
      );
      save = s;
      _log('Guardado local · revisión ${save.revision}');
      return true;
    } catch (e) {
      _log('No se guardó: $e');
      return false;
    } finally {
      saving = false;
      _redraw();
    }
  }

  Future<void> _exit() async {
    if (leaving || busy || saving) return;
    scene.clearMovement();
    if (ready && !await _save()) return;
    if (!mounted) return;
    setState(() => leaving = true);
    Navigator.of(context).pop();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (!ready) return AppExitResponse.exit;
    return await _save() ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  void dispose() {
    autosave?.cancel();
    watch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    scene.removeListener(_redraw);
    scene.dispose();
    renderer.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> _sceneImport({bool choose = true}) async {
    if (choose) {
      final f = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Escena Shaiya', extensions: ['json']),
        ],
      );
      if (f == null) return;
      profilePath = f.path;
    }
    if (profilePath == null) return;
    final f = File(profilePath!);
    if (await f.length() > 1024 * 1024) {
      throw const FormatException('El perfil excede 1 MiB.');
    }
    final bytes = await f.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    if (profileDigest == digest) return;
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map) throw const FormatException('Perfil de escena inválido.');
    final value = Map<String, dynamic>.from(raw);
    // Retain the previous valid pose if an edited resource fails to load.
    final before = SceneProfile.capture(scene);
    try {
      await SceneProfile.apply(scene, value);
      profileDigest = digest;
      _log('Escena aplicada · seguimiento del archivo activo');
    } catch (e) {
      try {
        await SceneProfile.apply(scene, before);
      } catch (restore) {
        _log('Restauración parcial: $restore');
      }
      rethrow;
    }
  }

  Future<void> _checkProfile() async {
    if (profilePath == null ||
        busy ||
        !ready ||
        leaving ||
        checkingProfile ||
        scene.combat.inGuard) {
      return;
    }
    checkingProfile = true;
    try {
      final f = File(profilePath!);
      if (!await f.exists() || await f.length() > 1024 * 1024) return;
      final digest = sha256.convert(await f.readAsBytes()).toString();
      if (digest == profileDigest || digest == rejectedProfileDigest) return;
      await _act(() async {
        try {
          await _sceneImport(choose: false);
          rejectedProfileDigest = null;
        } catch (_) {
          rejectedProfileDigest = digest;
          rethrow;
        }
      });
    } on FileSystemException catch (e) {
      _log('El archivo de escena cambió durante la lectura: ${e.message}');
    } finally {
      checkingProfile = false;
    }
  }

  Future<void> _editor() async {
    scene.clearMovement();
    scene.combat.cancelActions();
    scene.paused = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DataEditorPage(library: widget.catalog.library),
        ),
      );
    } finally {
      scene.paused = false;
    }
    // The edited library increments revision. A fresh catalog resolves edited
    // tables; the renderer's own texture cache is flushed on source revision.
    final before = SceneProfile.capture(scene),
        fresh = Catalog(widget.catalog.library);
    await fresh.load(_log);
    scene.catalog = fresh;
    await SceneProfile.apply(scene, before, reloadWorld: true);
    _log('Registros guardados recargados en el cliente Flutter.');
  }

  Future<void> _spawn() async {
    final c = pendingCreature;
    if (c == null) return;
    final dead = scene.game.opponents.values
        .where((o) => (scene.combat.health[o.id] ?? 0) <= 0)
        .map((o) => o.id)
        .toList();
    for (final id in dead) {
      scene.selectOpponent(id);
      scene.removeOpponent();
    }
    await scene.addOpponent(c);
    _log('Encuentro local: ${scene.catalog!.creatureLabel(c)}');
  }

  Future<void> _extras() async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Perfiles suplementarios', extensions: ['gz']),
      ],
    );
    if (f == null) return;
    if (await File(f.path).length() > 8 * 1024 * 1024) {
      throw const FormatException('Paquete demasiado grande.');
    }
    await scene.installExtras(ExtraMotionLibrary.decode(await f.readAsBytes()));
  }

  Widget _health(String name, double health, {bool target = false}) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(
              '${health.round()}',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: (health / 1000).clamp(0, 1),
          minHeight: 5,
          color: target ? const Color(0xffc98e87) : const Color(0xffaebce8),
        ),
      ],
    ),
  );
  Widget _select<T>(
    String label,
    List<T> items,
    T? current,
    String Function(T) title,
    Future<void> Function(T?) onPick, {
    String empty = 'Ninguno',
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 5),
        OutlinedButton(
          onPressed: busy
              ? null
              : () async {
                  final chosen = await showDialog<(bool, T?)>(
                    context: context,
                    builder: (context) => _Choice<T>(
                      title: label,
                      items: items,
                      label: title,
                      current: current,
                      empty: empty,
                    ),
                  );
                  if (chosen != null) await _act(() => onPick(chosen.$2));
                },
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  current == null ? empty : title(current),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.unfold_more, size: 18),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _side() {
    final c = scene.catalog!, a = scene.appearance;
    return Container(
      width: 300,
      color: const Color(0xff19212d),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 16),
              const Expanded(child: Text('Configuración de partida')),
              IconButton(
                tooltip: 'Cerrar panel',
                onPressed: () => setState(() => panel = false),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Mundo')),
              ButtonSegment(value: 1, label: Text('Equipo')),
              ButtonSegment(value: 2, label: Text('Progreso')),
            ],
            selected: {tab},
            onSelectionChanged: (v) => setState(() => tab = v.first),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (tab == 0) ...[
                  _select<String>(
                    'Escenario completo',
                    c.worlds,
                    scene.worldPath,
                    c.names.mapTitle,
                    (p) => scene.setWorld(p),
                    empty: 'Estudio de pruebas',
                  ),
                  _select<CreatureRecord>(
                    'Criatura de encuentro',
                    c.creatures,
                    pendingCreature,
                    c.creatureLabel,
                    (v) async {
                      setState(() => pendingCreature = v);
                    },
                  ),
                  FilledButton.icon(
                    onPressed: busy || pendingCreature == null
                        ? null
                        : () => _act(_spawn),
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir encuentro'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Población manual en esta reconstrucción. Las estadísticas y recompensas son reglas locales, no datos certificados del servidor.',
                    style: TextStyle(
                      color: Colors.white54,
                      height: 1.6,
                      fontSize: 11,
                    ),
                  ),
                  const Divider(height: 30),
                  const Text(
                    'Enlace con el editor',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _act(() => _sceneImport()),
                    icon: const Icon(Icons.link),
                    label: const Text('Vincular escena .json'),
                  ),
                  if (profilePath != null) ...[
                    Text(
                      path.basename(profilePath!),
                      style: const TextStyle(fontSize: 10),
                    ),
                    TextButton(
                      onPressed: () => setState(() => profilePath = null),
                      child: const Text('Desvincular'),
                    ),
                  ],
                  const Text(
                    'El editor puede exportar el personaje, equipo, mapa y anclajes. Los cambios del perfil se aplican fuera de combate. El game.exe original no entiende este contrato.',
                    style: TextStyle(
                      color: Colors.white54,
                      height: 1.6,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (tab == 1 && a != null) ...[
                  _select<String>(
                    'Conjunto',
                    a.archetype.sets.keys.toList(),
                    a.preset,
                    displaySet,
                    (v) async {
                      if (v != null) {
                        await scene.setAppearance(
                          Appearance.forSet(a.archetype, v, previous: a),
                        );
                      }
                    },
                  ),
                  for (final slot in [Slot.face, Slot.hair, Slot.helmet])
                    _select<PartRecord>(
                      slotLabels[slot]!,
                      a.archetype.parts[slot] ?? [],
                      a.selected[slot],
                      (r) => r.label,
                      (r) => scene.setAppearance(a.withPart(slot, r)),
                    ),
                  _select<WeaponRecord>(
                    'Arma',
                    scene.availableWeapons,
                    scene.weaponRecord,
                    c.names.weaponTitle,
                    scene.equip,
                  ),
                  _select<WeaponRecord>(
                    'Escudo',
                    permitsShield(scene.weaponRecord)
                        ? scene.availableShields
                        : [],
                    scene.shieldRecord,
                    c.names.weaponTitle,
                    scene.equipShield,
                  ),
                  _select<CreatureRecord>(
                    'Alas',
                    c.wings,
                    scene.wingRecord,
                    c.creatureLabel,
                    (v) => scene.selectCreature(v, 'wing'),
                  ),
                  _select<CreatureRecord>(
                    'Montura',
                    c.mounts,
                    scene.mountRecord,
                    c.creatureLabel,
                    (v) => scene.selectCreature(v, 'mount'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => _act(_extras),
                    child: const Text('Cargar movimientos suplementarios'),
                  ),
                  const Text(
                    'Shift + Espacio: alternar vuelo con alas. Los ANI incompatibles no se mezclan con el esqueleto.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ],
                if (tab == 2) ...[
                  Text(
                    'Nivel ${progress.level}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: progress.experience / progress.requiredExperience,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${progress.experience} / ${progress.requiredExperience} EXP',
                  ),
                  const Divider(height: 30),
                  ListTile(
                    leading: const Icon(Icons.toll),
                    title: Text('${progress.gold} oro'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: Text('${progress.potions} pociones'),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () {
                            final before = scene.combat.playerHealth;
                            scene.combat.playerHealth = progress.consumePotion(
                              before,
                              rules,
                            );
                            _log(
                              scene.combat.playerHealth > before
                                  ? 'Poción consumida.'
                                  : 'No se puede usar una poción ahora.',
                            );
                          },
                    child: const Text('Usar poción'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      _log(
                        progress.buyPotion(rules)
                            ? 'Poción comprada.'
                            : 'Oro insuficiente o inventario lleno.',
                      );
                    },
                    child: Text('Comprar poción · ${rules.healCost} oro'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${progress.victories} victorias · ${progress.deaths} caídas\n${(progress.seconds / 60).floor()} minutos de partida',
                    style: const TextStyle(color: Colors.white54, height: 1.6),
                  ),
                  const Divider(height: 30),
                  const Text('Registro local'),
                  const SizedBox(height: 10),
                  for (final text in messages.take(12))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_exit());
    },
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          '${save.title}  /  Nivel ${progress.level}',
          style: const TextStyle(fontSize: 14),
        ),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: busy || !ready ? null : () => _act(_editor),
            icon: const Icon(Icons.dataset_outlined, size: 18),
            label: const Text('Editor de datos'),
          ),
          IconButton(
            tooltip: 'Guardar partida',
            onPressed: busy || saving
                ? null
                : () => unawaited(_save().then((_) {})),
            icon: Icon(saving ? Icons.hourglass_top : Icons.save_outlined),
          ),
          IconButton(
            tooltip: 'Panel de mundo y equipo',
            onPressed: () => setState(() => panel = !panel),
            icon: const Icon(Icons.tune),
          ),
          TextButton(
            onPressed: busy || saving ? null : _exit,
            child: const Text('Partidas'),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    key: viewportKey,
                    children: [
                      Positioned.fill(child: renderer.build()),
                      Positioned.fill(
                        child: ViewportMovementInput(
                          focusNode: focus,
                          onChanged: (x, z, run) {
                            if (!busy) scene.setMovement(x, z, run: run);
                          },
                          onFlightToggle: () =>
                              unawaited(_act(scene.toggleFlight)),
                          onAction: (key) {
                            if (busy) return;
                            if (key == LogicalKeyboardKey.space) {
                              unawaited(_act(scene.jump));
                            }
                            if (key == LogicalKeyboardKey.tab) {
                              scene.cycleOpponent();
                            }
                            if ([
                              LogicalKeyboardKey.digit1,
                              LogicalKeyboardKey.digit2,
                              LogicalKeyboardKey.digit3,
                              LogicalKeyboardKey.digit4,
                            ].contains(key)) {
                              unawaited(_act(scene.attack));
                            }
                            if (key == LogicalKeyboardKey.escape) {
                              scene.clearMovement();
                              setState(() => panel = !panel);
                            }
                          },
                          child: Listener(
                            onPointerSignal: (e) {
                              if (e is PointerScrollEvent) {
                                scene.zoom(
                                  e.scrollDelta.dy > 0 ? 1.08 : 1 / 1.08,
                                );
                              }
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (d) {
                                scene.orbit(d.delta.dx, d.delta.dy);
                              },
                              onTapUp: (d) {
                                focus.requestFocus();
                                final size = viewportKey.currentContext?.size;
                                if (!busy && size != null) {
                                  try {
                                    scene.clickScene(
                                      d.localPosition.dx,
                                      d.localPosition.dy,
                                      size.width,
                                      size.height,
                                    );
                                  } catch (e) {
                                    _log('$e');
                                  }
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 18,
                        left: 20,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xe619212d),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Wrap(
                            spacing: 22,
                            runSpacing: 14,
                            children: [
                              _health(
                                '${scene.characterClass.label} · ${save.faction}',
                                scene.combat.playerHealth,
                              ),
                              if (scene.opponentCount > 0)
                                _health(
                                  scene.selectedTargetName,
                                  scene.combat.enemyHealth,
                                  target: true,
                                ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        bottom: 18,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: busy || !ready
                                  ? null
                                  : () => unawaited(_act(scene.attack)),
                              icon: const Icon(Icons.flash_on, size: 17),
                              label: const Text('Atacar · 1'),
                            ),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => unawaited(_act(scene.jump)),
                              child: const Text('Saltar'),
                            ),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => unawaited(_act(scene.toggleFlight)),
                              child: Text(
                                scene.flightEnabled ? 'Aterrizar' : 'Volar',
                              ),
                            ),
                            if (scene.combat.playerHealth <= 0)
                              FilledButton(
                                onPressed: () =>
                                    setState(() => scene.resetCombat()),
                                child: const Text('Resucitar'),
                              ),
                          ],
                        ),
                      ),
                      if (busy && !ready)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                ),
                if (panel && ready) _side(),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            color: const Color(0xff101720),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const SizedBox(width: 15),
                const Text(
                  'WASD · Shift: correr · Espacio: saltar · Shift+Espacio: vuelo',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Choice<T> extends StatefulWidget {
  final String title, empty;
  final List<T> items;
  final String Function(T) label;
  final T? current;
  const _Choice({
    required this.title,
    required this.items,
    required this.label,
    required this.current,
    required this.empty,
  });
  @override
  State<_Choice<T>> createState() => _ChoiceState<T>();
}

class _ChoiceState<T> extends State<_Choice<T>> {
  String query = '';
  late final ScrollController scroll;
  @override
  void initState() {
    super.initState();
    final at = widget.current == null
        ? 0
        : widget.items.indexOf(widget.current as T) + 1;
    scroll = ScrollController(
      initialScrollOffset: (at * 48.0 - 150).clamp(
        0,
        (widget.items.length * 48.0 - 380).clamp(0, double.infinity),
      ),
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.items
        .where(
          (v) => widget.label(v).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 510,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre o identificador',
              ),
              onChanged: (v) {
                setState(() => query = v);
                if (scroll.hasClients) scroll.jumpTo(0);
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemExtent: 48,
                itemCount: rows.length + 1,
                itemBuilder: (context, i) {
                  final row = i == 0 ? null : rows[i - 1];
                  return ListTile(
                    selected: row == widget.current,
                    title: Text(
                      row == null ? widget.empty : widget.label(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(context, (true, row)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
