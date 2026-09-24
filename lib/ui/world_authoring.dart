import 'package:flutter/material.dart';

import '../core/svmap_editor.dart';
import '../core/wtr_editor.dart';
import '../data/library.dart';

enum _SvSection { portals, npcs, mobs, spawns, named }

class WorldAuthoringPage extends StatefulWidget {
  final Library library;
  final String? initialPath;

  const WorldAuthoringPage({
    super.key,
    required this.library,
    this.initialPath,
  });

  @override
  State<WorldAuthoringPage> createState() => _WorldAuthoringPageState();
}

class _WorldAuthoringPageState extends State<WorldAuthoringPage> {
  String filter = '';
  String? path;
  WtrEditorDocument? wtr;
  SvmapEditorDocument? svmap;
  bool busy = false;
  bool dirty = false;
  int revision = 0;
  _SvSection section = _SvSection.portals;
  int selected = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPath;
    if (initial != null && widget.library.files.containsKey(initial)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) open(initial);
      });
    }
  }

  List<String> get resources {
    final q = filter.trim().toLowerCase();
    final out = widget.library.files.keys
        .where(
          (p) =>
              p.toLowerCase().endsWith('.svmap') ||
              p.toLowerCase().endsWith('.wtr'),
        )
        .where((p) => q.isEmpty || p.toLowerCase().contains(q))
        .toList()
      ..sort();
    return out;
  }

  Future<void> open(String resource) async {
    if (busy) return;
    setState(() {
      busy = true;
      path = resource;
      wtr = null;
      svmap = null;
      dirty = false;
      selected = 0;
      section = _SvSection.portals;
    });
    try {
      final bytes = await widget.library.read(
        resource,
        limit: SvmapEditorDocument.maxBytes,
      );
      final lower = resource.toLowerCase();
      if (lower.endsWith('.wtr')) {
        final parsed = WtrEditorDocument.parse(bytes, resource);
        if (!mounted) return;
        setState(() => wtr = parsed);
      } else {
        final parsed = SvmapEditorDocument.parse(bytes, resource);
        if (!mounted) return;
        setState(() => svmap = parsed);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final resource = path;
    if (resource == null || !dirty || busy) return;
    setState(() => busy = true);
    try {
      if (wtr != null) {
        final bytes = wtr!.encode();
        wtr!.validateEncoded(bytes);
        await widget.library.writeResource(resource, bytes);
        wtr = WtrEditorDocument.parse(bytes, resource);
      } else if (svmap != null) {
        final bytes = svmap!.encode();
        svmap!.validateEncoded(bytes);
        await widget.library.writeResource(resource, bytes);
        svmap = SvmapEditorDocument.parse(bytes, resource);
      }
      if (!mounted) return;
      setState(() {
        dirty = false;
        revision++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${resource.split('/').last} guardado y revalidado.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _numberField(
    String label,
    num value,
    void Function(String) apply, {
    bool integer = false,
  }) =>
      TextFormField(
        key: ValueKey('$revision-$path-$label-$value'),
        initialValue: integer ? value.toInt().toString() : value.toString(),
        enabled: !busy,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !integer,
          signed: true,
        ),
        decoration: InputDecoration(labelText: label),
        style: const TextStyle(fontSize: 10),
        onFieldSubmitted: (raw) {
          try {
            apply(raw);
            setState(() => dirty = true);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString())),
            );
          }
        },
      );

  Widget _vectorEditor(
    String label,
    SvmapVectorField value,
    void Function(List<double>) apply,
  ) {
    final values = [value.x, value.y, value.z];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _numberField(
                  ['X', 'Y', 'Z'][i],
                  values[i],
                  (raw) {
                    final parsed = double.parse(raw.replaceAll(',', '.'));
                    final next = List<double>.from(values)..[i] = parsed;
                    apply(next);
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _sidebar() => Material(
        color: const Color(0xff131b26),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar SVMAP / WTR…',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => filter = v),
              ),
            ),
            Expanded(
              child: resources.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No hay .svmap/.wtr en la DATA montada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xff8fa0b8),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: resources.length,
                      itemBuilder: (_, index) {
                        final resource = resources[index];
                        final active = resource == path;
                        return ListTile(
                          dense: true,
                          selected: active,
                          leading: Icon(
                            resource.endsWith('.wtr')
                                ? Icons.layers_outlined
                                : Icons.map_outlined,
                            size: 17,
                          ),
                          title: Text(
                            resource.split('/').last,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                          subtitle: Text(
                            resource,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 8),
                          ),
                          onTap: busy ? null : () => open(resource),
                        );
                      },
                    ),
            ),
          ],
        ),
      );

  Widget _header(String title, String subtitle) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: const Color(0xff172131),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xff8fa0b8),
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: busy || path == null ? null : () => open(path!),
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text('Recargar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: busy || !dirty ? null : save,
              icon: const Icon(Icons.save_outlined, size: 15),
              label: Text(
                widget.library.isSpkWorkspace
                    ? 'Guardar overlay'
                    : 'Guardar DATA',
              ),
            ),
          ],
        ),
      );

  Widget _wtr() {
    final doc = wtr!;
    return Column(
      children: [
        _header(
          path!.split('/').last,
          'WTR · ${doc.textures.length} capas · unknown2=${doc.unknown2} · '
          'unknown3=${doc.unknown3}',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _numberField(
                'Tamaño de celda / tileSize',
                doc.tileSize,
                (raw) => doc.setTileSize(
                  double.parse(raw.replaceAll(',', '.')),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Texturas',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < doc.textures.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    key: ValueKey(
                      '$revision-wtr-$i-${doc.textures[i].value}',
                    ),
                    initialValue: doc.textures[i].value,
                    enabled: !busy,
                    style: const TextStyle(fontSize: 10),
                    decoration: InputDecoration(
                      labelText: 'Capa $i',
                      helperText:
                          'DDS/TGA/BMP/PNG · ruta ASCII segura',
                      helperStyle: const TextStyle(fontSize: 8),
                    ),
                    onFieldSubmitted: (value) {
                      try {
                        doc.setTexture(i, value);
                        setState(() => dirty = true);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Object> _itemsFor(SvmapEditorDocument doc) => switch (section) {
        _SvSection.portals => doc.portals,
        _SvSection.npcs => doc.npcs,
        _SvSection.mobs => doc.mobAreas,
        _SvSection.spawns => doc.spawns,
        _SvSection.named => doc.namedAreas,
      };

  String _sectionLabel(_SvSection value) => switch (value) {
        _SvSection.portals => 'Portales',
        _SvSection.npcs => 'NPC',
        _SvSection.mobs => 'Áreas de mobs',
        _SvSection.spawns => 'Spawns',
        _SvSection.named => 'Áreas con nombre',
      };

  String _itemTitle(Object item, int index) => switch (item) {
        SvmapPortalEdit() =>
          '#$index · mapa ${item.targetMap} · '
              'Lv ${item.minLevel}-${item.maxLevel}',
        SvmapNpcEdit() =>
          '#$index · NPC ${item.id} · tipo ${item.type} · '
              '${item.route.length} puntos',
        SvmapMobAreaEdit() =>
          '#$index · ${item.mobs.length} tipos de mob',
        SvmapSpawnEdit() => '#$index · facción ${item.faction}',
        SvmapNamedAreaEdit() =>
          '#$index · nombres ${item.name1}/${item.name2}',
        _ => '#$index',
      };

  Widget _svmapEditor(SvmapEditorDocument doc, Object item, int index) {
    if (item is SvmapPortalEdit) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _vectorEditor(
            'Posición del portal',
            item.position,
            (v) => doc.setPortal(index, position: v),
          ),
          const SizedBox(height: 10),
          _numberField(
            'Facción / ID',
            item.factionOrId,
            (v) => doc.setPortal(index, factionOrId: int.parse(v)),
            integer: true,
          ),
          _numberField(
            'Nivel mínimo',
            item.minLevel,
            (v) => doc.setPortal(index, minLevel: int.parse(v)),
            integer: true,
          ),
          _numberField(
            'Nivel máximo',
            item.maxLevel,
            (v) => doc.setPortal(index, maxLevel: int.parse(v)),
            integer: true,
          ),
          _numberField(
            'Mapa destino',
            item.targetMap,
            (v) => doc.setPortal(index, targetMap: int.parse(v)),
            integer: true,
          ),
          const SizedBox(height: 10),
          _vectorEditor(
            'Coordenadas destino',
            item.target,
            (v) => doc.setPortal(index, target: v),
          ),
        ],
      );
    }
    if (item is SvmapNpcEdit) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _numberField(
            'Tipo NPC',
            item.type,
            (v) => doc.setNpcIdentity(index, type: int.parse(v)),
            integer: true,
          ),
          _numberField(
            'ID NPC',
            item.id,
            (v) => doc.setNpcIdentity(index, id: int.parse(v)),
            integer: true,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < item.route.length; i++)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Waypoint $i',
                style: const TextStyle(fontSize: 10),
              ),
              children: [
                _vectorEditor(
                  'Posición',
                  item.route[i].position,
                  (v) => doc.setNpcWaypoint(index, i, position: v),
                ),
                _numberField(
                  'Yaw',
                  item.route[i].yaw,
                  (v) => doc.setNpcWaypoint(
                    index,
                    i,
                    yaw: double.parse(v.replaceAll(',', '.')),
                  ),
                ),
              ],
            ),
        ],
      );
    }
    if (item is SvmapMobAreaEdit) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _vectorEditor(
            'Límite inferior',
            item.lower,
            (v) => doc.setMobAreaBounds(index, lower: v),
          ),
          const SizedBox(height: 10),
          _vectorEditor(
            'Límite superior',
            item.upper,
            (v) => doc.setMobAreaBounds(index, upper: v),
          ),
          const Divider(height: 24),
          for (var i = 0; i < item.mobs.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    _numberField(
                      'Monster ID #$i',
                      item.mobs[i].id,
                      (v) => doc.setMobSpawn(
                        index,
                        i,
                        id: int.parse(v),
                      ),
                      integer: true,
                    ),
                    _numberField(
                      'Cantidad',
                      item.mobs[i].count,
                      (v) => doc.setMobSpawn(
                        index,
                        i,
                        count: int.parse(v),
                      ),
                      integer: true,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    if (item is SvmapSpawnEdit) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _numberField(
            'Facción',
            item.faction,
            (v) => doc.setSpawn(index, faction: int.parse(v)),
            integer: true,
          ),
          const SizedBox(height: 10),
          _vectorEditor(
            'Límite inferior',
            item.lower,
            (v) => doc.setSpawn(index, lower: v),
          ),
          const SizedBox(height: 10),
          _vectorEditor(
            'Límite superior',
            item.upper,
            (v) => doc.setSpawn(index, upper: v),
          ),
        ],
      );
    }
    final named = item as SvmapNamedAreaEdit;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _vectorEditor(
          'Límite inferior',
          named.lower,
          (v) => doc.setNamedArea(index, lower: v),
        ),
        const SizedBox(height: 10),
        _vectorEditor(
          'Límite superior',
          named.upper,
          (v) => doc.setNamedArea(index, upper: v),
        ),
        _numberField(
          'Name1',
          named.name1,
          (v) => doc.setNamedArea(index, name1: int.parse(v)),
          integer: true,
        ),
        _numberField(
          'Name2',
          named.name2,
          (v) => doc.setNamedArea(index, name2: int.parse(v)),
          integer: true,
        ),
      ],
    );
  }

  Widget _svmap() {
    final doc = svmap!;
    final items = _itemsFor(doc);
    final safeIndex = items.isEmpty
        ? 0
        : selected.clamp(0, items.length - 1).toInt();
    final active = items.isEmpty ? null : items[safeIndex];

    return Column(
      children: [
        _header(
          path!.split('/').last,
          'SVMAP · mapSize=${doc.mapSize} · cellSize=${doc.cellSize} · '
          '${doc.portals.length} portales · ${doc.npcs.length} NPC · '
          '${doc.mobAreas.length} áreas mob',
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<_SvSection>(
            segments: [
              for (final value in _SvSection.values)
                ButtonSegment(
                  value: value,
                  label: Text(
                    _sectionLabel(value),
                    style: const TextStyle(fontSize: 9),
                  ),
                ),
            ],
            selected: {section},
            onSelectionChanged: busy
                ? null
                : (values) => setState(() {
                    section = values.first;
                    selected = 0;
                  }),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 280,
                child: Material(
                  color: const Color(0xff151e2a),
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            'Sin ${_sectionLabel(section).toLowerCase()}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xff8fa0b8),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) => ListTile(
                            dense: true,
                            selected: i == safeIndex,
                            title: Text(
                              _itemTitle(items[i], i),
                              style: const TextStyle(fontSize: 9),
                            ),
                            onTap: () => setState(() => selected = i),
                          ),
                        ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: active == null
                    ? const SizedBox.shrink()
                    : _svmapEditor(doc, active, safeIndex),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _content() {
    if (busy && path == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (path == null) {
      return const Center(
        child: Text(
          'Selecciona un WTR o SVMAP de la DATA montada.',
          style: TextStyle(color: Color(0xff8fa0b8)),
        ),
      );
    }
    if (wtr != null) return _wtr();
    if (svmap != null) return _svmap();
    return const Center(child: CircularProgressIndicator());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xff101722),
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('World Authoring', style: TextStyle(fontSize: 14)),
              Text(
                'WTR + SVMAP · edición lossless/fail-closed',
                style: TextStyle(fontSize: 9, color: Color(0xff8e9bb0)),
              ),
            ],
          ),
        ),
        body: Row(
          children: [
            SizedBox(width: 300, child: _sidebar()),
            const VerticalDivider(width: 1),
            Expanded(child: _content()),
          ],
        ),
      );
}
