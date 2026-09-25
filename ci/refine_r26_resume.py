"""Resolve actual R26 failures without bypassing authentication or UI gates.

Every replacement is checked before any write. CI commits readable sources.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r26-resume-applied'
changes = {}


def replace(path, old, new, count=1):
    text = changes.get(path, (ROOT / path).read_text(encoding='utf-8'))
    if old not in text:
        raise RuntimeError(f'R26 resume anchor missing in {path}: {old[:90]}')
    changes[path] = text.replace(old, new, count)


def main():
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    if branch != 'feat/studio-0626-compact-model-picker':
        raise RuntimeError('Refusing to modify a different branch.')
    if MARKER.exists():
        return
    path = 'lib/data/spk_source.dart'
    replace(path, '''    } catch (error) {
      if (failures.length >= 100) failures.removeAt(0);
      failures.add({
        'entryId': record.idHex,
        'offset': record.dataOffset,
        'storedBytes': record.storedBytes,
        'error': error.toString(),
      });
      rethrow;
    }
  }

  Future<Uint8List> _readSimple''', '''    } catch (error) {
      // A failed reread invalidates its format/full-audit label, not healthy entries.
      _validatedFormats.remove(record.entryId);
      fullResourceValidation = null;
      final failure = error is SecretBoxAuthenticationError
          ? SpkFailure(
              'SPK_RESOURCE_AUTHENTICATION',
              'El recurso no supera la autenticación AES-GCM. '
              'No se entregaron bytes ni se modificó el SPK.',
              {'entryId': record.idHex, 'offset': record.dataOffset},
            )
          : error;
      if (failures.length >= 100) failures.removeAt(0);
      failures.add({
        'entryId': record.idHex,
        'offset': record.dataOffset,
        'storedBytes': record.storedBytes,
        'error': failure.toString(),
      });
      if (!identical(failure, error)) throw failure;
      rethrow;
    }
  }

  Future<Uint8List> _readSimple''')
    path = 'lib/ui/studio_workspace.dart'
    replace(path, '''              setState(() => leftOpen = !leftOpen);''', '''              setState(() {
                // Closing one dock must not silently open a wider hidden dock.
                if (leftOpen && !showRight) rightOpen = false;
                leftOpen = !leftOpen;
              });''')
    replace(path, '      child: Column(children: buttons),',
            '      child: SingleChildScrollView(child: Column(children: buttons)),')
    path = 'lib/ui/item_model_picker.dart'
    replace(path, '  final search = TextEditingController();', '''  final search = TextEditingController();
  final listScroll = ScrollController();
  double rowExtent = 58;

  List<ItemModelChoice> get filtered => catalog?.choices.where((c) =>
      c.source == source &&
      (query.isEmpty || c.searchText.contains(foldedSearch(query)))).toList() ?? [];

  void revealSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !listScroll.hasClients) return;
      final rows = filtered;
      final index = rows.indexWhere((c) => c.key == selected?.key);
      final top = (index < 0 ? 0 : index) * rowExtent;
      final position = listScroll.position;
      var target = position.pixels;
      if (top < target) target = top;
      if (top + rowExtent > target + position.viewportDimension) {
        target = top + rowExtent - position.viewportDimension;
      }
      listScroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    });
  }''')
    replace(path, '''            result.choices.where((c) => c.source == source).firstOrNull;
      });''', '''            result.choices.where((c) => c.source == source).firstOrNull;
      });
      revealSelection();''')
    replace(path, '''      ready = false;
    });
  }

  void confirm()''', '''      ready = false;
    });
    revealSelection();
  }

  void confirm()''')
    replace(path, '    search.dispose();', '    listScroll.dispose();\n    search.dispose();')
    replace(path, '''          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,''', '''          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 80),
            child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,''')
    replace(path, '''            ],
          ),
        ),
        Expanded(
          child: !choice.available''', '''            ],
          )),
          ),
        ),
        Expanded(
          child: !choice.available''')
    replace(path, '''    final rows =
        catalog?.choices
            .where(
              (c) =>
                  c.source == source &&
                  (query.isEmpty || c.searchText.contains(foldedSearch(query))),
            )
            .toList() ??
        <ItemModelChoice>[];''', '''    final rows = filtered;
    rowExtent = (MediaQuery.textScalerOf(context).scale(11) * 3 + 22).clamp(58, 160).toDouble();''')
    replace(path, '''              child: Text(
                widget.imageMode
                    ? 'Aplica Image al ítem, no su Icon ni su ID. La familia elegida es una vista previa; '
                          'el cliente usa ese Image en las variantes de cuerpo correspondientes.'
                    : 'Reasigna el par malla/textura del catálogo. Los ítems que compartan esa entrada también cambiarán.',
                style: Theme.of(context).textTheme.bodySmall,
              ),''', '''              child: Row(children: [
                Expanded(child: Text(
                  widget.imageMode ? 'Cambia Image; conserva Icon e ID.' : 'Cambia el par malla y textura compartido.',
                  style: Theme.of(context).textTheme.bodySmall,
                )),
                IconButton(
                  tooltip: 'Alcance del cambio de modelo',
                  icon: const Icon(Icons.info_outline, size: 17),
                  onPressed: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
                    title: const Text('Qué cambia al elegir un modelo'),
                    content: SingleChildScrollView(child: Text(widget.imageMode
                      ? 'Aplica Image al ítem, no su Icon ni su ID. La familia elegida es una vista previa; '
                        'el cliente usa ese mismo Image en las variantes de cuerpo correspondientes. '
                        'Seleccionar no modifica datos. Usar modelo prepara el cambio; Aplicar lo confirma en la sesión.'
                      : 'Reasigna el par malla/textura del catálogo. Los ítems que compartan esa entrada también cambiarán. '
                        'No se sustituyen animaciones ni anclajes de otro modelo automáticamente.')),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
                  )),
                ),
              ]),''')
    replace(path, '''                                onChanged: (text) =>
                                    setState(() => query = text),''', '''                                onChanged: (text) {
                                  setState(() => query = text);
                                  revealSelection();
                                },''')
    replace(path, '''                                    : ListView.builder(
                                        itemCount: rows.length,
                                        itemExtent: 58,''', '''                                    : ListView.builder(
                                        key: const ValueKey('model-picker-list'),
                                        controller: listScroll,
                                        itemCount: rows.length,
                                        itemExtent: rowExtent,''')
    replace(path, '''              ExpansionTile(
                title: const Text('Diagnóstico de catálogos'),
                dense: true,
                children: [
                  SizedBox(
                    height: 100,
                    child: SingleChildScrollView(
                      child: SelectableText(catalog!.warnings.join('\\n')),
                    ),
                  ),
                ],
              ),''', '''              TextButton.icon(
                icon: const Icon(Icons.warning_amber, size: 16),
                label: const Text('Diagnóstico de catálogos'),
                onPressed: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(
                  title: const Text('Catálogos no disponibles'),
                  content: SingleChildScrollView(child: SelectableText(catalog!.warnings.join('\\n'))),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
                )),
              ),''')
    replace(path, '''              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ready''', '''              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    Text(
                      ready''')
    replace(path, '''                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),''', '''                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),''')
    replace(path, '''                  const SizedBox(width: 8),
                  FilledButton.icon(''', '''                  FilledButton.icon(''')
    replace(path, '''                    label: const Text('Usar modelo'),
                  ),
                ],''', '''                    label: const Text('Usar modelo'),
                  ),
                  ]),
                ],''')
    path = 'test/workspace_material_test.dart'
    replace(path, '''      await tester.tap(find.byKey(const ValueKey('toggle-right')));
      await tester.pumpAndSettle();
      expectUnobstructedMaterial(tester);''', '''      // R26 opens the inspector by default when there is enough room.
      if (find.byKey(const ValueKey('play-sound')).hitTestable().evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('toggle-right')));
        await tester.pumpAndSettle();
      }
      expectUnobstructedMaterial(tester);''')
    path = 'test/r26_models_layout_test.dart'
    for index in (16, 17):
        needle = f"        await tester.tap(find.byKey(const ValueKey('model-choice-$source#{index}')));"
        insert = f"""        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('model-choice-$source#{index}')), 45,
          scrollable: find.descendant(of: find.byKey(const ValueKey('model-picker-list')), matching: find.byType(Scrollable)),
        );
""" + needle
        replace(path, needle, insert, count=10)
    path = 'test/r26_spk_selective_test.dart'
    replace(path, '''      final changed = await source.file.readAsBytes();
      changed[record.dataOffset + 50] ^= 1;''', '''      await source.readEntry(record);
      expect(source.validatedFormat(record.entryId), isNotNull);
      final readsBeforeCorruption = source.reads;
      final changed = await source.file.readAsBytes();
      changed[record.dataOffset + 50] ^= 1;''')
    replace(path, '''      await expectLater(lib.read(path), throwsA(isA<SpkFailure>()));
      expect(source.fullResourceValidation, isNull);''', '''      await expectLater(lib.read(path), throwsA(isA<SpkFailure>().having(
        (error) => error.code, 'code', 'SPK_RESOURCE_AUTHENTICATION')));
      expect(source.fullResourceValidation, isNull);
      expect(source.validatedFormat(record.entryId), isNull);
      expect(source.reads, readsBeforeCorruption);
      expect(source.failures.last['entryId'], record.idHex);
      expect(source.canReadFragmentedResources, isFalse);
      await source.readEntry(source.index.simpleResources.last);
      expect(source.reads, readsBeforeCorruption + 1);''')
    for path, text in changes.items():
        (ROOT / path).write_text(text, encoding='utf-8')
    MARKER.write_text('R26 resume: responsive selectors, deliberate docks, authenticated read diagnostics\n')


if __name__ == '__main__':
    main()
