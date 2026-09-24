import 'package:flutter/material.dart';

import '../core/wing_systems.dart';
import '../data/library.dart';
import 'excelxml_lab.dart';

class WingSystemsLabPage extends StatefulWidget {
  final Library library;

  const WingSystemsLabPage({super.key, required this.library});

  @override
  State<WingSystemsLabPage> createState() => _WingSystemsLabPageState();
}

class _WingSystemsLabPageState extends State<WingSystemsLabPage> {
  WingSystemsCatalog? catalog;
  String? error;
  bool busy = false;
  int? selectedWingId;

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
      Future<List<int>?> readOptional(String path) async {
        if (!widget.library.files.containsKey(path)) return null;
        return widget.library.read(path, limit: 4 * 1024 * 1024);
      }

      final parsed = WingSystemsCatalog.parse(
        decomposeBytes: await readOptional('excelxml/wingdecompose.xml'),
        expBytes: await readOptional('excelxml/wingexpitem.xml'),
        swapBytes: await readOptional('excelxml/wingswap.xml'),
      );
      if (!mounted) return;
      setState(() {
        catalog = parsed;
        selectedWingId ??= parsed.wingIds.firstOrNull;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openXml(String path) async {
    if (!widget.library.files.containsKey(path)) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ExcelXmlLabPage(library: widget.library, initialPath: path),
      ),
    );
    if (mounted) await _load();
  }

  Widget _summaryCard(String title, String value, IconData icon, String path) =>
      Card(
        child: InkWell(
          onTap: widget.library.files.containsKey(path)
              ? () => _openXml(path)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 10),
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
                      const SizedBox(height: 3),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xff9aabc2),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new, size: 15),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final data = catalog;
    final wingId = selectedWingId;
    final progression = data == null || wingId == null
        ? const <WingDecomposeRule>[]
        : data.progressionFor(wingId);

    return Scaffold(
      backgroundColor: const Color(0xff101722),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wing Systems Lab', style: TextStyle(fontSize: 14)),
            Text(
              'Decompose · EXP items · Swap · DATA real',
              style: TextStyle(fontSize: 9, color: Color(0xff8e9bb0)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Recargar tablas',
            onPressed: busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: busy && data == null
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xffffa596)),
                ),
              ),
            )
          : data == null
          ? const Center(child: Text('No hay tablas de alas montadas.'))
          : Row(
              children: [
                SizedBox(
                  width: 290,
                  child: Material(
                    color: const Color(0xff131b26),
                    child: ListView(
                      padding: const EdgeInsets.all(10),
                      children: [
                        _summaryCard(
                          'WingDecompose',
                          '${data.decompose.length} reglas · '
                              '${data.wingIds.length} WingID',
                          Icons.layers_outlined,
                          'excelxml/wingdecompose.xml',
                        ),
                        const SizedBox(height: 8),
                        _summaryCard(
                          'WingExpItem',
                          '${data.expItems.length} objetos de experiencia',
                          Icons.auto_awesome_outlined,
                          'excelxml/wingexpitem.xml',
                        ),
                        const SizedBox(height: 8),
                        _summaryCard(
                          'WingSwap',
                          '${data.swaps.length} reglas de intercambio',
                          Icons.swap_horiz,
                          'excelxml/wingswap.xml',
                        ),
                        const Divider(height: 24),
                        const Text(
                          'WingID',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final id in data.wingIds)
                          ListTile(
                            dense: true,
                            selected: id == selectedWingId,
                            leading: const Icon(
                              Icons.flight_outlined,
                              size: 16,
                            ),
                            title: Text(
                              'WingID $id',
                              style: const TextStyle(fontSize: 10),
                            ),
                            subtitle: Text(
                              '${data.progressionFor(id).length} grados',
                              style: const TextStyle(fontSize: 8),
                            ),
                            onTap: () => setState(() => selectedWingId = id),
                          ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        wingId == null
                            ? 'Sin WingID'
                            : 'WingID $wingId · progresión nativa',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Las filas siguientes provienen de WingDecompose.xml. '
                        'Studio no las mezcla con WingPosition ni Wing.MON: '
                        'son contratos DATA distintos.',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xff8fa0b8),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (progression.isEmpty)
                        const Text('No hay progresión para este WingID.')
                      else
                        DataTable(
                          headingRowHeight: 34,
                          dataRowMinHeight: 34,
                          dataRowMaxHeight: 42,
                          columns: const [
                            DataColumn(label: Text('Grade')),
                            DataColumn(label: Text('OldWingItem')),
                            DataColumn(label: Text('MaxLevel')),
                            DataColumn(label: Text('Swap')),
                          ],
                          rows: [
                            for (final rule in progression)
                              DataRow(
                                cells: [
                                  DataCell(Text(rule.grade.toString())),
                                  DataCell(Text(rule.oldWingItem.toString())),
                                  DataCell(Text(rule.maxLevel.toString())),
                                  DataCell(
                                    Builder(
                                      builder: (_) {
                                        final swap = data.swapForItem(
                                          rule.oldWingItem,
                                        );
                                        if (swap == null) {
                                          return const Text('—');
                                        }
                                        return Text(
                                          swap.rewards.isEmpty
                                              ? 'Sin recompensa'
                                              : swap.rewards
                                                    .map(
                                                      (reward) =>
                                                          '${reward.itemId} ×'
                                                          '${reward.count}',
                                                    )
                                                    .join(' · '),
                                          style: const TextStyle(fontSize: 9),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  widget.library.files.containsKey(
                                    'excelxml/wingdecompose.xml',
                                  )
                                  ? () => _openXml('excelxml/wingdecompose.xml')
                                  : null,
                              icon: const Icon(
                                Icons.edit_note_outlined,
                                size: 16,
                              ),
                              label: const Text('Editar progresión'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  widget.library.files.containsKey(
                                    'excelxml/wingswap.xml',
                                  )
                                  ? () => _openXml('excelxml/wingswap.xml')
                                  : null,
                              icon: const Icon(Icons.swap_horiz, size: 16),
                              label: const Text('Editar intercambios'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Objetos de experiencia',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final item in data.expItems)
                            Chip(
                              label: Text(
                                item.toString(),
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed:
                              widget.library.files.containsKey(
                                'excelxml/wingexpitem.xml',
                              )
                              ? () => _openXml('excelxml/wingexpitem.xml')
                              : null,
                          icon: const Icon(Icons.edit_note_outlined, size: 16),
                          label: const Text('Editar objetos EXP'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
