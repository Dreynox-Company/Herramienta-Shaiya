"""Readable integration of optional resource 3D previews; no R25 APIs removed."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r26-selectors-applied'
changes = {}


def replace(path, old, new, count=1):
    text = changes.get(path)
    if text is None:
        text = (ROOT / path).read_text(encoding='utf-8')
    if old not in text:
        raise RuntimeError(f'Missing selector anchor: {path}: {old[:100]}')
    changes[path] = text.replace(old, new, count)


def main():
    if MARKER.exists():
        return
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    if branch != 'feat/studio-0626-compact-model-picker':
        raise RuntimeError('Refusing to update another branch.')
    path = 'lib/ui/asset_selector.dart'
    replace(path, 'class SelectionMemory {', '''typedef AssetPreviewBuilder<T> = Widget Function(BuildContext context,
  T value, ValueChanged<bool> onReady);

class SelectionMemory {''')
    replace(path, '  final String Function(T)? detail;', '  final String Function(T)? detail;\n  final AssetPreviewBuilder<T>? previewBuilder;', -1)
    replace(path, '    this.detail,', '    this.detail,\n    this.previewBuilder,', -1)
    replace(path, '        detail: widget.detail,', '        detail: widget.detail,\n        previewBuilder: widget.previewBuilder,')
    replace(path, '  int _cursor = 0;', '''  int _cursor = 0, _previewGeneration = 0;
  bool _previewReady = false;
  String? get _highlight => _filtered.isEmpty ? null : widget.id(_filtered[_cursor]);
  void _chooseCursor(int index) {
    final before = _highlight;
    setState(() {
      _cursor = index;
      if (before != _highlight) { _previewGeneration++; _previewReady = false; }
    });
  }
  Widget _preview() {
    if (_filtered.isEmpty) return const Center(child: Text('Selecciona un recurso.'));
    final value = _filtered[_cursor], identity = _highlight;
    final request = _previewGeneration;
    return KeyedSubtree(key: ValueKey('resource-preview-$identity'),
      child: widget.previewBuilder!(context, value, (ready) {
        if (mounted && request == _previewGeneration && identity == _highlight) {
          setState(() => _previewReady = ready);
        }
      }));
  }
  Widget _contents() {
    final list = _filtered.isEmpty
      ? const Center(child: Text('No hay recursos que coincidan.'))
      : ListView.builder(controller: _scroll, itemExtent: rowHeight,
          itemCount: _filtered.length, itemBuilder: (_, i) => _row(i));
    if (widget.previewBuilder == null) return list;
    return LayoutBuilder(builder: (_, box) => box.maxWidth >= 700
      ? Row(children: [SizedBox(width: box.maxWidth * .4, child: list),
          const VerticalDivider(width: 10), Expanded(child: _preview())])
      : Column(children: [Expanded(child: list), const Divider(height: 6),
          Expanded(child: _preview())]));
  }''')
    replace(path, 'setState(() => _cursor = (_cursor + delta).clamp(0, _filtered.length - 1));',
        '_chooseCursor((_cursor + delta).clamp(0, _filtered.length - 1));')
    replace(path, '    if (_filtered.isNotEmpty) Navigator.pop(context, _filtered[_cursor]);',
        '    if (_filtered.isNotEmpty && (widget.previewBuilder == null || _previewReady)) {\n      Navigator.pop(context, _filtered[_cursor]);\n    }')
    replace(path, '  void _query(String query) {\n    setState(() {',
        '  void _query(String query) {\n    final before = _highlight;\n    setState(() {')
    replace(path, '''        _filtered.indexWhere((x) => widget.id(x) == selectedId),
      );
    });''', '''        _filtered.indexWhere((x) => widget.id(x) == selectedId),
      );
      if (before != _highlight) { _previewGeneration++; _previewReady = false; }
    });''')
    replace(path, '''          setState(() => _cursor = index);
          _commit();''', '''          _chooseCursor(index);
          if (widget.previewBuilder == null) _commit();''')
    replace(path, 'constraints: const BoxConstraints(maxWidth: 620, maxHeight: 600),',
        "constraints: BoxConstraints(maxWidth: widget.previewBuilder == null ? 620 : 1100,\n          maxHeight: widget.previewBuilder == null ? 600 : MediaQuery.sizeOf(context).height * .86),")
    replace(path, 'fontSize: 17,', 'fontSize: 14,')
    replace(path, '''                child: _filtered.isEmpty
                    ? const Center(
                        child: Text('No hay recursos que coincidan.'),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        itemExtent: rowHeight,
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) => _row(index),
                      ),''', '''                child: _contents(),''')
    replace(path, 'onPressed: _filtered.isEmpty ? null : _commit,',
        'onPressed: _filtered.isEmpty || widget.previewBuilder != null && !_previewReady ? null : _commit,')

    path = 'lib/main.dart'
    replace(path, "import 'ui/studio_sections.dart';", "import 'ui/studio_sections.dart';\nimport 'ui/resource_model_preview.dart';")
    replace(path, '    detail: detail,\n    memory:', '''    detail: detail,
    previewBuilder: catalog != null && (T == PartRecord || T == WeaponRecord ||
        T == CreatureRecord || key.endsWith('/set'))
      ? (ctx, value, ready) => resourceModelPreview(ctx, catalog!.library, value, ready,
          setParts: key.endsWith('/set') ? scene.appearance?.archetype.sets[value] : null)
      : null,
    memory:''')

    path = 'integration_test/native_studio_test.dart'
    replace(path, "import 'package:herramienta_shaiya/ui/editor_model_preview.dart';", "import 'package:herramienta_shaiya/ui/editor_model_preview.dart';\nimport 'package:herramienta_shaiya/ui/item_model_picker.dart';\nimport 'package:herramienta_shaiya/editor/item_model_catalog.dart';\nimport 'package:herramienta_shaiya/editor/model_reference.dart';\nimport 'package:herramienta_shaiya/ui/resource_model_preview.dart';")
    replace(path, "    final exportDir = await Directory.systemTemp.createTemp(\n      'shaiya-export-integration-',", '''    // Capture the actual compact shell, not a mockup or a cropped viewport.
    Future<void> captureBoundary(String key, String name) async {
      await tester.pump(const Duration(milliseconds: 250));
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(ValueKey(key)));
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await File('${output.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    }
    await captureBoundary('studio-shell-capture', 'r26_compact_shell');
    final part = scene.appearance!.slots[Slot.upper]!;
    final modelChoice = ItemModelChoice(model: ModelReference('Torso sintético de prueba',
      [(part.meshPath, part.texturePath, part.raw.alpha)],
      sourcePath: part.tablePath, sourceOrdinal: part.raw.id),
      name: 'Torso sintético de prueba', row: 0, fields: const {});
    final beforeAppearance = scene.appearance;
    final selectedFuture = showDialog<ItemModelChoice>(context: state.context,
      builder: (_) => RepaintBoundary(key: const ValueKey('r26-model-picker-capture'),
        child: ItemModelPicker(library: scene.catalog!.library,
          catalog: Future.value(ItemModelCatalog([modelChoice], [], 0)),
          currentSource: part.tablePath, currentOrdinal: part.raw.id)));
    await waitFor(() => find.byType(NativeModelPreview).evaluate().isNotEmpty,
      'R26 model selector creates an actual native preview');
    final dynamic r26Preview = tester.state(find.byType(NativeModelPreview));
    await waitFor(() => r26Preview.ready == true && r26Preview.actor.parts.isNotEmpty,
      'R26 selector loads the actual paired mesh and DDS');
    expect(r26Preview.error, isNull);
    await captureBoundary('r26-model-picker-capture', 'r26_model_picker');
    await tester.tap(find.byKey(const ValueKey('confirm-model-picker')));
    await tester.pump(const Duration(milliseconds: 250));
    expect((await selectedFuture)?.key, modelChoice.key);
    expect(identical(scene.appearance, beforeAppearance), isTrue);
    passed.add('R26 3D selection returns a native pair without altering the mounted actor');

    final exportDir = await Directory.systemTemp.createTemp(
      'shaiya-export-integration-',''')
    # Remove an unused helper import; the native acceptance uses exact pairs.
    replace(path, "import 'package:herramienta_shaiya/ui/resource_model_preview.dart';\n", '')

    # Register the R26 suite without losing any pre-existing suite.
    path = 'tool/run_all_local.dart'
    replace(path, 'void main() {', "import '../test/r26_models_layout_test.dart' as r26_models;\n\nvoid main() {\n  r26_models.main();")
    for path, text in changes.items():
        (ROOT / path).write_text(text, encoding='utf-8')
    MARKER.write_text('Optional visual selectors and native R26 acceptance\n')


if __name__ == '__main__':
    main()
