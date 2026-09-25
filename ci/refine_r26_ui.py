"""Apply the R26 integration delta once on its isolated feature branch.

New feature classes live in normal lib/ files. This readable, assertion-checked
migration avoids transporting full multi-thousand-line files through Contents.
CI commits the materialized sources before analysis/tests/Windows build.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r26-ui-applied'
files = {}


def get(path):
    if path not in files:
        files[path] = (ROOT / path).read_text(encoding='utf-8')
    return files[path]


def replace(path, old, new, count=1):
    text = get(path)
    if old not in text:
        raise RuntimeError(f'Missing R25 anchor in {path}: {old[:100]}')
    files[path] = text.replace(old, new, count)


def main():
    if MARKER.exists():
        return
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    if branch != 'feat/studio-0626-compact-model-picker':
        raise RuntimeError('Refusing to modify another branch.')

    path = 'lib/ui/editor_model_preview.dart'
    replace(path, '  final ModelReference model;\n  const NativeModelPreview',
        '  final ModelReference model;\n  final ValueChanged<bool>? onReadyChanged;\n  const NativeModelPreview')
    replace(path, '    required this.model,\n  });',
        '    required this.model,\n    this.onReadyChanged,\n  });')
    replace(path, '      camera();\n      view.addAnimationEvent',
        '      camera();\n      if (!dead && mounted) widget.onReadyChanged?.call(true);\n      view.addAnimationEvent')
    replace(path, "      if (mounted) setState(() => error = '$e');\n    }\n  }\n\n  void camera()", "      if (mounted) {\n        widget.onReadyChanged?.call(false);\n        setState(() => error = '$e');\n      }\n    }\n  }\n\n  void camera()")
    replace(path, '        vertices += mesh.vertices;',
        '        if (dead) { staged.dispose(); return; }\n        vertices += mesh.vertices;')

    path = 'lib/ui/item_record_editor.dart'
    replace(path, "import 'item_icon_picker.dart';", "import 'item_icon_picker.dart';\nimport 'item_model_picker.dart';\nimport '../editor/item_model_catalog.dart';")
    replace(path, '  ItemEntry entry,\n) => showDialog<bool>(',
        '  ItemEntry entry, {bool chooseModel = false}\n) => showDialog<bool>(')
    replace(path, 'builder: (_) => ItemRecordEditor(workspace: workspace, entry: entry),',
        'builder: (_) => ItemRecordEditor(workspace: workspace, entry: entry, startWithModelPicker: chooseModel),')
    replace(path, '  final int? resourceRow;\n', '  final int? resourceRow;\n  final bool startWithModelPicker;\n')
    replace(path, '    this.resourceRow,\n', '    this.resourceRow,\n    this.startWithModelPicker = false,\n')
    replace(path, '  bool allowClose = false;', '  bool allowClose = false, showTechnical = false, choosingModel = false;')
    replace(path, '      add(widget.resource!, widget.resourceRow!);\n    }\n',
        '      add(widget.resource!, widget.resourceRow!);\n    }\n    if (widget.startWithModelPicker) {\n      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) chooseModel(); });\n    }\n')
    marker = '  Widget editField(_EditableItemField f) {'
    replace(path, marker, '''  bool get canChooseModel => widget.entry != null
      ? ItemModelCatalog.supports(widget.entry!.type)
      : widget.resource is CatalogDocument &&
        (widget.resource as CatalogDocument).materials(widget.resourceRow!).isNotEmpty;

  Future<void> chooseModel() async {
    if (!canChooseModel || choosingModel) return;
    setState(() => choosingModel = true);
    try {
      final image = fields.where((f) => f.span.spec.name.toLowerCase() == 'image').firstOrNull;
      final revision = widget.workspace.revision;
      final choice = await pickItemModel(context, widget.workspace,
        item: widget.entry,
        document: widget.resource is CatalogDocument ? widget.resource as CatalogDocument : null,
        currentOrdinal: image == null ? widget.resource!.rows[widget.resourceRow!].ordinal
          : int.tryParse(image.controller.text));
      if (choice == null || !mounted) return;
      if (widget.workspace.revision != revision || widget.workspace.sourceChanged) {
        throw StateError('La sesión cambió durante la selección. No se aplicó el modelo.');
      }
      // Image selects the native material, including texture, in every body
      // variant. Editing a material instead copies its mesh+texture together.
      final proposed = <_EditableItemField, String>{};
      if (image != null) {
        proposed[image] = '${choice.ordinal}';
      } else {
        for (final f in fields) {
          final name = f.span.spec.name;
          if (name == 'MeshIndex' || name == 'TextureIndex' || name == 'Alpha' ||
              name.startsWith('Parts[') && (name.endsWith('.Mesh') || name.endsWith('.Texture'))) {
            final value = choice.fields[name];
            if (value == null) throw StateError('El modelo tiene un número de partes incompatible.');
            proposed[f] = value;
          }
        }
        final newParts = choice.fields.keys.where((n) => n.endsWith('.Mesh')).length;
        final oldParts = fields.where((f) => f.span.spec.name.endsWith('.Mesh')).length;
        if (newParts != oldParts) throw StateError('No se cambia PartCount al reasignar un MON. Elige una entrada compatible.');
      }
      for (final entry in proposed.entries) {
        widget.workspace.validateField(entry.key.document, entry.key.span, entry.value);
      }
      setState(() {
        for (final entry in proposed.entries) { entry.key.controller.text = entry.value; }
        message = 'Modelo preparado: ${choice.name}. Pulsa Aplicar a la sesión para confirmar.';
      });
    } catch (e) { if (mounted) setState(() => message = '$e'); }
    finally { if (mounted) setState(() => choosingModel = false); }
  }

''' + marker)
    replace(path, 'margin: const EdgeInsets.only(bottom: 10)', 'margin: const EdgeInsets.only(bottom: 4)')
    replace(path, 'padding: const EdgeInsets.all(12)', 'padding: const EdgeInsets.all(8)')
    replace(path, "            Text(\n              '$name · ${f.span.spec.type} · ${meta.group}',", "            if (showTechnical) Text(\n              '$name · ${f.span.spec.type} · ${meta.group}',")
    replace(path, '            const SizedBox(height: 6),', '            const SizedBox(height: 3),')
    replace(path, 'if (f.writable && choices != null)', 'if (showTechnical && f.writable && choices != null)')
    replace(path, '            if (f.writable && isAssetField(name))', '''            if (f.writable && canChooseModel &&
                const {'image', 'meshindex'}.contains(name.toLowerCase()))
              TextButton.icon(onPressed: choosingModel ? null : chooseModel,
                icon: const Icon(Icons.view_in_ar_outlined, size: 16),
                label: const Text('Elegir modelo 3D + textura')),
            if (f.writable && isAssetField(name))''')
    replace(path, '        title: Text(\n', '        insetPadding: const EdgeInsets.all(12),\n        title: Text(\n')
    replace(path, '          width: 830,', '          width: 1040,')
    replace(path, '              const SizedBox(height: 10),\n              TextField(', '''              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (canChooseModel) TextButton.icon(key: const ValueKey('choose-item-model'),
                  onPressed: choosingModel ? null : chooseModel,
                  icon: const Icon(Icons.view_in_ar_outlined, size: 16),
                  label: const Text('Cambiar modelo 3D')),
                FilterChip(label: const Text('Detalles técnicos'), selected: showTechnical,
                  onSelected: (value) => setState(() => showTechnical = value)),
              ]),
              const SizedBox(height: 6),
              TextField(''')
    replace(path, '''                child: ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, i) => editField(visible[i]),
                ),''', '''                child: LayoutBuilder(builder: (_, box) {
                  final columns = box.maxWidth >= 680 && MediaQuery.textScalerOf(context).scale(12) <= 18 ? 2 : 1;
                  final width = (box.maxWidth - (columns - 1) * 8) / columns;
                  return ListView(children: [Wrap(spacing: 8, runSpacing: 0, children: [
                    for (final field in visible) SizedBox(
                      width: field.span.spec.text ? box.maxWidth : width,
                      child: editField(field)),
                  ])]);
                }),''')

    path = 'lib/ui/items_page.dart'
    replace(path, 'padding: const EdgeInsets.all(18)', 'padding: const EdgeInsets.all(10)')
    replace(path, 'size: 64,', 'size: 44,')
    replace(path, 'itemExtent: 76,', 'itemExtent: 60,')
    replace(path, 'size: 38,', 'size: 30,')
    replace(path, 'SizedBox(width: 380, child: list)', 'SizedBox(width: 310, child: list)')
    replace(path, '''          OutlinedButton.icon(
            onPressed: busy ? null : () => resources(item),''', '''          OutlinedButton.icon(
            key: const ValueKey('change-selected-item-model'),
            onPressed: busy ? null : () => run(() async {
              await showItemRecordEditor(context, workspace!, item, chooseModel: true);
            }),
            icon: const Icon(Icons.view_in_ar_outlined),
            label: const Text('Cambiar modelo 3D'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => resources(item),''')

    path = 'lib/ui/editor_style.dart'
    replace(path, '        titleMedium:', '''        titleLarge: textTheme.titleLarge!.copyWith(fontSize: 16),
        headlineSmall: textTheme.headlineSmall!.copyWith(fontSize: 18),
        headlineMedium: textTheme.headlineMedium!.copyWith(fontSize: 20),
        labelMedium: textTheme.labelMedium!.copyWith(fontSize: 11),
        labelSmall: textTheme.labelSmall!.copyWith(fontSize: 10),
        titleMedium:''')
    replace(path, '      iconTheme: const IconThemeData', '''      listTileTheme: const ListTileThemeData(dense: true,
        horizontalTitleGap: 8, minVerticalPadding: 3,
        contentPadding: EdgeInsets.symmetric(horizontal: 8)),
      expansionTileTheme: const ExpansionTileThemeData(
        tilePadding: EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
      cardTheme: const CardThemeData(color: panel, elevation: 0,
        margin: EdgeInsets.zero, shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)))),
      dialogTheme: const DialogThemeData(backgroundColor: surface,
        titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text)),
      sliderTheme: const SliderThemeData(trackHeight: 2,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 12)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        textStyle: const TextStyle(fontSize: 11), minimumSize: const Size(36, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6))),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 450),
        textStyle: TextStyle(fontSize: 11, color: background)),
      iconTheme: const IconThemeData''')

    path = 'lib/ui/studio_workspace.dart'
    replace(path, 'bool leftOpen = true, rightOpen = false, timelineOpen = true;',
        'bool leftOpen = true, rightOpen = true, timelineOpen = true;')
    replace(path, 'double leftWidth = 244, rightWidth = 248;', 'double leftWidth = 236, rightWidth = 292;')
    replace(path, 'height: 38,', 'height: 32,')
    replace(path, 'padding: const EdgeInsets.all(14)', 'padding: const EdgeInsets.all(8)')
    replace(path, 'rightWidth = (rightWidth - event.delta.dx).clamp(210, 340);',
        'rightWidth = (rightWidth - event.delta.dx).clamp(240, 440);')
    replace(path, 'height: 48,', 'height: 42,')
    replace(path, "              if (timelineOpen)\n", "              if (timelineOpen)\n")

    path = 'lib/main.dart'
    replace(path, "import 'ui/studio_workspace.dart';", "import 'ui/studio_workspace.dart';\nimport 'ui/editor_style.dart';\nimport 'ui/studio_sections.dart';")
    replace(path, "const studioVersion = '0.6.25-dev';", "const studioVersion = '0.6.26';")
    text = get(path)
    start, end = text.index('    theme: ThemeData('), text.index('    home: StudioPage(')
    files[path] = text[:start] + '    theme: EditorStyle.theme(ThemeData.dark(useMaterial3: true)),\n' + text[end:]
    text = get(path)
    start, end = text.index('  Widget section('), text.index('  String? excelXmlPath(')
    files[path] = text[:start] + '''  Widget section(String title, List<Widget> children, {String? help}) =>
    StudioSection(title: title, children: children, help: help,
      initiallyExpanded: !const {'Atajos', 'Últimos eventos', 'Registro',
        'Mirada natural', 'Recursos indexados', 'ExcelXml · sistemas de DATA',
        'Efectos y sonido'}.contains(title));
''' + text[end:]
    replace(path, "            section('Alas', [\n              creatureField('wing'),", "            section('Alas', [creatureField('wing')]),\n            section('Ajustes de alas', [")
    replace(path, "            section('Montura', [\n              creatureField('mount'),", "            section('Montura', [creatureField('mount')]),\n            section('Ajustes de montura', [")
    replace(path, 'candidate = await Library.fromSpk(source, progress: report);',
        'candidate = await Library.fromSpkEditable(source, progress: report);')
    replace(path, "        note(progress),\n      ]);", '''        OutlinedButton.icon(onPressed: disabled ? null : openSpkArchive,
          icon: const Icon(Icons.folder_zip_outlined, size: 17),
          label: const Text('Abrir DATA.SPK')),
        if (c != null) ...[
          note(c.library.sourceLabel),
          TextButton.icon(onPressed: working ? null : openDataEditor,
            icon: const Icon(Icons.edit_note, size: 17),
            label: const Text('Editar recursos montados')),
          TextButton.icon(onPressed: working ? null : openItems,
            icon: const Icon(Icons.inventory_2_outlined, size: 17),
            label: const Text('Abrir Ítems SData')),
        ],
        note(progress),
      ]);''')
    replace(path, '  Widget build(BuildContext context) => StudioWorkspace(\n    viewport: viewport(),\n    left: panel(),\n    right: inspector(),', '''  Widget build(BuildContext context) {
    final docks = StudioDockContent.split(panel());
    return RepaintBoundary(key: const ValueKey('studio-shell-capture'), child: StudioWorkspace(
    viewport: viewport(),
    left: docks.navigation,
    right: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [docks.inspector, inspector()]),''')
    replace(path, "  );\n}\n\nUint8List _texturePreview", "  ));\n  }\n}\n\nUint8List _texturePreview")

    path = 'lib/data/library.dart'
    replace(path, '  static Future<Library> fromSpk(\n', '''  /// Mount readable resources lazily. Only confirmed paths enter semantic
  /// Character/Item catalogs; inferred names remain technical Entry IDs.
  /// No whole-archive extraction or decryption is triggered by opening Studio.
  static Future<Library> fromSpkEditable(SpkArchiveSource source, {
    void Function(String)? progress, String? overlayRoot,
  }) async {
    if (!source.canReadSimpleResources) {
      throw const SpkFailure('SPK_WORKSPACE_PROFILE',
        'Autentica primero el perfil de recursos simples.');
    }
    final files = <String, String>{};
    var blocked = 0, confirmed = 0, technical = 0;
    for (final record in source.index.resources) {
      if (!source.canReadRecord(record)) { blocked++; continue; }
      final hasName = source.names.isConfirmed(record.entryId);
      final path = hasName ? canon(SpkArchiveSource.safeRelative(source.names[record.entryId]!))
        : canon('_SPK_SinNombre/${record.idHex}${SpkArchiveSource.extensionFor(source.validatedFormat(record.entryId) ?? 'BIN')}');
      if (!supportedPath(path)) continue;
      if (files.containsKey(path) && files[path] != record.idHex) {
        throw FormatException('Dos Entry IDs reclaman la misma ruta confirmada: $path');
      }
      files[path] = record.idHex;
      if (hasName) { confirmed++; } else { technical++; }
    }
    if (files.isEmpty) throw const FormatException('No hay recursos legibles para montar.');
    progress?.call('SPK: $confirmed rutas confirmadas, $technical Entry IDs, $blocked recursos bloqueados.');
    return _normalise(source.file.path, false, files, spk: source,
      spkOverlayRoot: overlayRoot ?? '${source.file.path}.studio-overlay',
      requireCharacter: false, spkMountReport: {
        'selectiveMount': true, 'confirmedMounted': confirmed,
        'technicalMounted': technical, 'blockedResources': blocked,
        'inferredMounted': 0, 'completePayloadAccess': source.canExtractAll,
      });
  }

  static Future<Library> fromSpk(
''')
    replace(path, "      return 'DATA.SPK · lectura autenticada + overlay editable';", "      return spk!.canExtractAll\n        ? 'DATA.SPK · lectura autenticada + overlay editable'\n        : 'DATA.SPK · acceso parcial autenticado · fragmentos bloqueados · overlay editable';")
    replace(path, 'if (source == null || !source.fullyValidatedResources) return false;',
        'if (source == null || !source.canReadRecord(record)) return false;')
    replace(path, '    return canonical == technical;', "    return canonical == technical ||\n      canonical == canon('_SPK_SinNombre/${record.idHex}.bin');")
    replace(path, "    if (!spk!.canExtractAll) {\n      throw const SpkFailure(\n        'SPK_OVERLAY_PROFILE',\n        'El overlay editable requiere lectura completa y autenticada del SPK.',", "    if (!spk!.canReadSimpleResources) {\n      throw const SpkFailure(\n        'SPK_OVERLAY_PROFILE',\n        'El overlay editable requiere un perfil autenticado. Cada recurso se valida al leerlo.',")

    path = 'lib/ui/spk_archive_browser.dart'
    text = get(path)
    start, end = text.index('  Future<void> mountInStudio()'), text.index('  Future<Map<String, Object?>> _diagnoseProbeFailure(')
    files[path] = text[:start] + '''  Future<void> mountInStudio() => runAction(() async {
    final callback = widget.onMount;
    if (callback == null) return;
    if (!source.canReadSimpleResources) {
      throw const SpkFailure('SPK_STUDIO_MOUNT_PROFILE',
        'Autentica primero el perfil de recursos simples.');
    }
    operation = 'Montando recursos legibles; los nombres inferidos no se usan como rutas nativas…';
    if (mounted) setState(() {});
    await callback(source);
    if (mounted) Navigator.of(context).pop();
  });

''' + text[end:]
    replace(path, 'if (widget.onMount != null && source.canExtractAll)',
        'if (widget.onMount != null && source.canReadSimpleResources)', -1)
    replace(path, "hasConfirmedCoreTables ? 'Usar en Studio' : 'Preparar Studio'",
        "source.canExtractAll ? 'Usar en Studio' : 'Usar recursos legibles'", -1)
    replace(path, "                  : 'Explorador · contenido cifrado',", "                  : source.canReadSimpleResources ? 'Lectura parcial · fragmentos pendientes' : 'Explorador · contenido cifrado',")

    replace('pubspec.yaml', 'version: 0.6.25+33', 'version: 0.6.26+34')
    for path, text in files.items():
        (ROOT / path).write_text(text, encoding='utf-8')
    MARKER.write_text('R26 compact selector + selective SPK\n')


if __name__ == '__main__':
    main()
