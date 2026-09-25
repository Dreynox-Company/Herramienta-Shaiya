import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../core/equipment_rules.dart';
import '../data/catalog.dart';
import '../data/equipment_registry.dart';
import '../data/item_publication.dart';
import '../render/studio_scene.dart';
import '../data/item_workspace.dart';
import '../editor/workbench_model.dart';
import 'editor_icons.dart';
import 'item_record_editor.dart';
import 'items_page.dart';

/// One searchable registered-item view reused for armor, weapons, wings, mounts.
/// Raw-resource pickers live in the mutually exclusive other mode in Studio.
class EquipmentRegistryPanel extends StatefulWidget {
  final StudioScene scene;
  final String target;
  final bool enabled;
  final Future<void> Function(Future<void> Function()) run;
  const EquipmentRegistryPanel({
    super.key,
    required this.scene,
    required this.target,
    required this.enabled,
    required this.run,
  });
  @override
  State<EquipmentRegistryPanel> createState() => _EquipmentRegistryPanelState();
}

class _EquipmentRegistryPanelState extends State<EquipmentRegistryPanel> {
  late Future<EquipmentRegistry> future;
  late int revision;
  int loadGeneration = 0;
  ItemWorkspace? workspace;
  EditorImages? images;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final generation = ++loadGeneration;
    revision = widget.scene.catalog!.library.revision;
    final library = widget.scene.catalog!.library;
    workspace?.removeListener(_sessionChanged);
    future = ItemWorkspace.forLibrary(library).then((session) {
      if (mounted &&
          generation == loadGeneration &&
          widget.scene.catalog?.library == library) {
        workspace = session;
        session.addListener(_sessionChanged);
        final old = images;
        images = EditorImages(session.preview);
        WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      }
      return session.registry;
    });
  }

  @override
  void didUpdateWidget(covariant EquipmentRegistryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene.catalog?.library != widget.scene.catalog?.library ||
        revision != widget.scene.catalog!.library.revision) {
      _reload();
    }
  }

  @override
  void dispose() {
    workspace?.removeListener(_sessionChanged);
    images?.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted || workspace == null) return;
    final old = images;
    images = EditorImages(workspace!.preview);
    setState(() => future = Future.value(workspace!.registry));
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
  }

  Future<RegisteredItem?> choose(List<RegisteredItem> items, String title) =>
      showDialog<RegisteredItem>(
        context: context,
        builder: (_) =>
            _ItemPicker(items: items, title: title, workspace: workspace!),
      );

  Future<void> openItem(RegisteredItem? item) async {
    widget.scene.clearMovement();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ItemsPage(
          library: widget.scene.catalog!.library,
          initialItemKey: item?.key,
        ),
      ),
    );
  }

  Widget editCurrent(
    List<RegisteredItem> matches,
    String label,
  ) => TextButton.icon(
    icon: const Icon(Icons.tune, size: 16),
    label: Text(
      matches.isEmpty
          ? '$label: sin objeto registrado'
          : 'Editar $label · ${matches.length == 1 ? matches.single.label : '${matches.length} IDs'}',
    ),
    onPressed: !widget.enabled || matches.isEmpty
        ? null
        : () => widget.run(() async {
            final item = matches.length == 1
                ? matches.single
                : await choose(matches, 'Selecciona el ID de $label a editar');
            if (mounted && item != null) await openItem(item);
          }),
  );

  Widget row(
    EquipmentRegistry r,
    String label,
    List<RegisteredItem> candidates,
    Future<void> Function(RegisteredItem) select,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: OutlinedButton.icon(
      icon: const Icon(Icons.inventory_2_outlined, size: 16),
      onPressed: !widget.enabled || candidates.isEmpty
          ? null
          : () async {
              final item = await choose(candidates, label);
              if (item != null && mounted) await widget.run(() => select(item));
            },
      label: Text('$label · ${candidates.length} objetos'),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<EquipmentRegistry>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SelectableText(
          '${snapshot.error}\nNo se mezclan tablas de otra carpeta.',
        );
      }
      final r = snapshot.data;
      if (r == null) return const LinearProgressIndicator();
      final scene = widget.scene,
          c = scene.catalog!,
          a = scene.appearance!.archetype,
          cls = scene.characterClass;
      bool allowed(RegisteredItem i) => i.allows(a, cls);
      final children = <Widget>[
        Text(
          'Objetos de ${r.textPath ?? r.dataPath}',
          style: const TextStyle(fontSize: 10),
        ),
        const Text(
          'El ID del objeto y el índice Image/MLT son identidades distintas.',
          style: TextStyle(fontSize: 10),
        ),
        const SizedBox(height: 8),
      ];
      if (widget.target == 'equipment') {
        for (final slot in [
          Slot.upper,
          Slot.lower,
          Slot.hand,
          Slot.foot,
          Slot.helmet,
        ]) {
          final items = (r.bySlot[EquipmentRegistry.bodySlot(slot)] ?? [])
              .where((i) => allowed(i) && r.partsFor(i, slot, a).length == 1)
              .toList();
          children.add(
            row(r, slotLabels[slot]!, items, (item) async {
              final part = r.partsFor(item, slot, a).single;
              // Do not call withPart(upper): that API equips the whole raw set.
              await scene.setAppearance(
                Appearance(a, {...scene.appearance!.selected, slot: part}),
              );
              scene.say('Equipado ${item.label} · Image ${item.image}');
            }),
          );
          final current = scene.appearance!.selected[slot];
          if (current != null) {
            final matches = r.forPart(current, a, cls);
            children.add(
              Text(
                matches.isEmpty
                    ? '${current.label}: sin objeto registrado'
                    : matches.length == 1
                    ? matches.single.label
                    : '${current.label}: ${matches.length} objetos comparten el recurso',
                style: const TextStyle(fontSize: 10),
              ),
            );
            if (r.hasSpanishText || matches.isNotEmpty) {
              children.add(
                TextButton(
                  onPressed: !widget.enabled
                      ? null
                      : () => widget.run(() async {
                          if (matches.isEmpty) {
                            await editItem(r, slot, current, matches);
                          } else {
                            final item = matches.length == 1
                                ? matches.single
                                : await choose(matches, 'Elige el ID a editar');
                            if (mounted && item != null) await openItem(item);
                          }
                        }),
                  child: Text(
                    matches.isEmpty
                        ? 'Registrar esta pieza'
                        : 'Editar ítem: propiedades, icono y recursos',
                  ),
                ),
              );
            }
          }
        }
        for (final shield in [false, true]) {
          final available = shield
              ? scene.availableShields
              : scene.availableWeapons;
          final items = (r.bySlot[shield ? 6 : 5] ?? [])
              .where(
                (i) => allowed(i) && r.weaponsFor(i, available).length == 1,
              )
              .toList();
          children.add(
            row(r, shield ? 'Escudo' : 'Arma', items, (item) async {
              final weapon = r.weaponsFor(item, available).single;
              if (shield) {
                await scene.equipShield(weapon);
              } else {
                await scene.equip(weapon);
              }
              scene.say('Equipado ${item.label}');
            }),
          );
          final equipped = shield ? scene.shieldRecord : scene.weaponRecord;
          if (equipped != null) {
            children.add(
              editCurrent(
                r.forWeapon(equipped, a, cls),
                shield ? 'escudo' : 'arma',
              ),
            );
          }
        }
      } else {
        final wing = widget.target == 'wing';
        final entries = wing ? c.wings : c.mounts;
        final items = (r.bySlot[wing ? wingEquipmentSlot : 13] ?? [])
            .where((i) => allowed(i) && r.creaturesFor(i, entries).isNotEmpty)
            .toList();
        children.add(
          row(r, wing ? 'Alas' : 'Montura', items, (item) async {
            final matches = r.creaturesFor(item, entries);
            final record = matches.length == 1
                ? matches.single
                : await showDialog(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Elige la familia MON explícitamente'),
                      children: [
                        for (final match in matches)
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, match),
                            child: Text('${match.source} #${match.id}'),
                          ),
                      ],
                    ),
                  );
            if (record != null) {
              await scene.selectCreature(record, widget.target);
            }
          }),
        );
        final equipped = wing ? scene.wingRecord : scene.mountRecord;
        if (equipped != null) {
          children.add(
            editCurrent(
              r.forCreature(equipped, widget.target, a, cls),
              wing ? 'alas' : 'montura',
            ),
          );
        }
        children.add(
          const Text(
            'Si varias familias MON comparten Image, se exige seleccionar la familia; nunca se toma la primera.',
            style: TextStyle(fontSize: 10),
          ),
        );
      }
      children.add(
        TextButton.icon(
          key: const ValueKey('equipment-open-items'),
          onPressed: !widget.enabled ? null : () => openItem(null),
          icon: const Icon(Icons.inventory_2_outlined, size: 16),
          label: const Text('Ítems · todos los tipos'),
        ),
      );
      if (workspace?.dirty == true) {
        children.add(
          const Text(
            'Hay cambios de sesión. El catálogo Ítems muestra el 3D de los recursos preparados. '
            'El personaje principal conserva su DATA conectada hasta instalar el parche y recargarla.',
            style: TextStyle(fontSize: 10),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    },
  );

  Future<void> editItem(
    EquipmentRegistry r,
    Slot slot,
    PartRecord part,
    List<RegisteredItem> candidates,
  ) async {
    if (workspace?.dirty == true) {
      throw const FormatException(
        'Hay cambios pendientes en la sesión de Ítems. '
        'Exporta e instala el parche en una copia, o descarta los cambios, antes de crear una fila nueva. '
        'La creación no publica una tabla que omita tus cambios.',
      );
    }

    final scene = widget.scene,
        c = scene.catalog!,
        a = scene.appearance!.archetype;
    if (!c.library.files.containsKey(part.tablePath.toLowerCase()) ||
        !part.tablePath.toLowerCase().endsWith('.mlt')) {
      throw const FormatException(
        'Esta pieza no tiene una referencia MLT nativa. Registra primero el material; no se inventa Image.',
      );
    }
    final existing = candidates.length == 1
        ? candidates.single
        : candidates.isEmpty
        ? null
        : await choose(
            candidates,
            'Varios IDs comparten la pieza: elige cuál reparar',
          );
    if (!mounted || (candidates.isNotEmpty && existing == null)) return;
    final template =
        existing ??
        await choose(
          (r.bySlot[EquipmentRegistry.bodySlot(slot)] ?? [])
              .where((i) => i.allows(a, scene.characterClass))
              .toList(),
          'Elige una plantilla del mismo slot y clase',
        );
    if (template == null || !mounted) return;
    final ids = {
      for (final item in r.items.where((i) => i.type == template.type)) item.id,
    };
    final free = List.generate(
      255,
      (i) => i + 1,
    ).where((i) => !ids.contains(i)).firstOrNull;
    if (existing == null && free == null) {
      throw const FormatException(
        'No queda un TypeId compatible con el backend offline 0.1.2.',
      );
    }
    final result = await showDialog<ItemPublicationEdit>(
      context: context,
      builder: (_) => _ItemEditDialog(
        item: template,
        creating: existing == null,
        id: existing?.id ?? free!,
        image: part.raw.id,
        resource: part.texturePath,
      ),
    );
    if (result == null || !mounted) return;
    final prepared = ItemPublication.prepare(
      data: await c.library.read(r.dataPath),
      text: await c.library.read(r.textPath!),
      dataPath: r.dataPath,
      textPath: r.textPath!,
      edits: [result],
    );
    if (!mounted) return;
    if (prepared.warnings.isNotEmpty) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Advertencias del archivo original'),
          content: SingleChildScrollView(
            child: SelectableText(prepared.warnings.join('\n')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Exportar copia validada'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final out = await prepared.export(
      c.library,
      Directory(
        '${docs.path}/HerramientaShaiya/Publicaciones/Objeto_${result.type}_${result.id}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    scene.say('Parche exportado: ${out.path}. DATA original intacta.');
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Parche de objetos preparado'),
          content: SelectableText(
            '${out.path}\n\nLas dos tablas fueron reabiertas y verificadas. Lee LEEME.txt antes de copiar. '
            'No se modifica game.exe ni la base del servidor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }
}

class _ItemPicker extends StatefulWidget {
  final List<RegisteredItem> items;
  final String title;
  final ItemWorkspace workspace;
  const _ItemPicker({
    required this.items,
    required this.title,
    required this.workspace,
  });
  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String query = '';
  late final EditorImages images;
  @override
  void initState() {
    super.initState();
    images = EditorImages(widget.workspace.preview);
  }

  @override
  void dispose() {
    images.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.items
        .where(
          (i) => foldedSearch(
            '${i.label} ${i.image} ${i.description}',
          ).contains(foldedSearch(query)),
        )
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                labelText: 'Buscar nombre, Type:TypeId, nivel o Image',
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (ctx, i) {
                  final item = entries[i];
                  return ListTile(
                    dense: true,
                    leading: DataIcon(
                      images: images,
                      path: widget.workspace.dataPath,
                      summary: widget.workspace.byKey[item.key]!.summary,
                      size: 36,
                    ),
                    title: Text(item.label),
                    trailing: IconButton(
                      tooltip: 'Editar propiedades de ${item.key}',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () async {
                        final result = await showItemRecordEditor(
                          context,
                          widget.workspace,
                          widget.workspace.byKey[item.key]!,
                        );
                        // The original candidate list is stale after changing Image,
                        // class requirements, or stats. Reopen with a fresh registry.
                        if (mounted && result == true) Navigator.pop(context);
                      },
                    ),
                    subtitle: Text('Image ${item.image} · Icon ${item.icon}'),
                    onTap: () => Navigator.pop(context, item),
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

class _ItemEditDialog extends StatefulWidget {
  final RegisteredItem item;
  final bool creating;
  final int id, image;
  final String resource;
  const _ItemEditDialog({
    required this.item,
    required this.creating,
    required this.id,
    required this.image,
    required this.resource,
  });
  @override
  State<_ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends State<_ItemEditDialog> {
  late final TextEditingController name, description, id;
  final properties = <String, TextEditingController>{};
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: !widget.creating && widget.item.hasName ? widget.item.name : '',
    );
    description = TextEditingController(text: widget.item.description);
    id = TextEditingController(text: '${widget.id}');
    for (final e in widget.item.values.entries.where(
      (e) => !const {'itemtype', 'itemtypeid', 'image'}.contains(e.key),
    )) {
      properties[e.key] = TextEditingController(text: '${e.value}');
    }
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    id.dispose();
    for (final c in properties.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.creating
          ? 'Registrar pieza desde plantilla ${widget.item.key}'
          : 'Reparar objeto ${widget.item.key}',
    ),
    content: SizedBox(
      width: 680,
      height: 520,
      child: ListView(
        children: [
          SelectableText(
            'Recurso: ${widget.resource}\nImage nativo: ${widget.image}. El archivo MLT no se renumera.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: id,
            readOnly: !widget.creating,
            decoration: const InputDecoration(
              labelText: 'TypeId (la reparación conserva su identidad)',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: name,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Nombre español del objeto',
            ),
          ),
          TextField(
            controller: description,
            maxLines: 3,
            maxLength: 2048,
            decoration: const InputDecoration(labelText: 'Descripción'),
          ),
          const Text(
            'Icon es el índice nativo. Esta edición no crea una miniatura ni cambia el atlas. '
            'Las demás propiedades se conservan de la plantilla salvo las que edites explícitamente.',
          ),
          ExpansionTile(
            title: const Text('Icono y propiedades originales'),
            children: [
              for (final e in properties.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: TextField(
                    controller: e.value,
                    decoration: InputDecoration(labelText: e.key),
                  ),
                ),
            ],
          ),
          const Text(
            'La publicación genera ambas tablas en una carpeta nueva. No escribe sobre DATA ni otorga objetos al servidor.',
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final identity = int.tryParse(id.text);
          if (identity == null ||
              name.text.trim().isEmpty ||
              RegExp(r'^[?\s]+$').hasMatch(name.text)) {
            setState(
              () => error = 'Introduce un TypeId válido y un nombre real.',
            );
            return;
          }
          Navigator.pop(
            context,
            ItemPublicationEdit(
              type: widget.item.type,
              id: identity,
              templateId: widget.creating ? widget.item.id : null,
              name: name.text,
              description: description.text,
              properties: {
                'image': '${widget.image}',
                for (final e in properties.entries)
                  if (e.value.text != '${widget.item.values[e.key]}')
                    e.key: e.value.text,
              },
            ),
          );
        },
        child: const Text('Validar y exportar parche'),
      ),
    ],
  );
}
