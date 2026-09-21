import 'package:flutter/material.dart';

/// Docks reserve space; animation and action bars never cover the 3D viewport.
class StudioWorkspace extends StatefulWidget {
  final Widget viewport, left, right, timeline, actions, status;
  final List<String> tabs;
  final List<IconData> icons;
  final int selectedTab;
  final ValueChanged<int> onTab;
  final VoidCallback? onOpenData, onOpenSpk, onOpenEditor, onExportScene;
  final bool hasLibrary;
  const StudioWorkspace({
    super.key,
    required this.viewport,
    required this.left,
    required this.right,
    required this.timeline,
    required this.actions,
    required this.status,
    required this.tabs,
    required this.icons,
    required this.selectedTab,
    required this.onTab,
    required this.onOpenData,
    this.onOpenSpk,
    this.onOpenEditor,
    this.onExportScene,
    this.hasLibrary = false,
  });
  @override
  State<StudioWorkspace> createState() => _StudioWorkspaceState();
}

class _StudioWorkspaceState extends State<StudioWorkspace> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool leftOpen = true, rightOpen = false, timelineOpen = true;
  double leftWidth = 244, rightWidth = 248;

  Widget _title(String text, VoidCallback close) => Container(
    height: 38,
    padding: const EdgeInsets.only(left: 14, right: 4),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xff2c3546))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Plegar panel',
          onPressed: close,
          icon: const Icon(Icons.close, size: 16),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
  Widget _scroll(Widget body) =>
      SingleChildScrollView(padding: const EdgeInsets.all(14), child: body);
  Widget _panel(
    String title,
    Widget child,
    VoidCallback close, {
    double? width,
  }) => SizedBox(
    width: width,
    // ListTile, SwitchListTile and CheckboxListTile paint their feedback on
    // Material. An opaque Container between them and Scaffold's Material
    // hides that feedback and triggers a framework assertion in debug.
    // Keep this surface local so docked and drawer panels behave identically.
    child: Material(
      color: const Color(0xff171e29),
      child: Column(
        children: [
          _title(title, close),
          Expanded(child: _scroll(child)),
        ],
      ),
    ),
  );
  Widget _splitter(bool left) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (event) => setState(() {
        if (left) {
          leftWidth = (leftWidth + event.delta.dx).clamp(210, 350);
        } else {
          rightWidth = (rightWidth - event.delta.dx).clamp(210, 340);
        }
      }),
      child: Container(
        width: 5,
        color: const Color(0xff222b39),
        child: Center(
          child: Container(
            width: 1,
            height: 36,
            color: const Color(0xff536078),
          ),
        ),
      ),
    ),
  );

  Widget _rail() {
    final buttons = <Widget>[const SizedBox(height: 8)];
    for (var i = 0; i < widget.tabs.length; i++) {
      buttons.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Tooltip(
            message: widget.tabs[i],
            child: IconButton(
              key: ValueKey('tab-$i'),
              onPressed: () {
                widget.onTab(i);
                setState(() => leftOpen = true);
              },
              isSelected: widget.selectedTab == i,
              selectedIcon: Icon(
                widget.icons[i],
                color: const Color(0xffb3c6ff),
              ),
              icon: Icon(widget.icons[i], color: const Color(0xff8998af)),
              iconSize: 20,
              style: IconButton.styleFrom(
                backgroundColor: widget.selectedTab == i
                    ? const Color(0xff2b3850)
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      width: 46,
      color: const Color(0xff131a24),
      child: Column(children: buttons),
    );
  }

  Widget _mobileTabs() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: DropdownButton<int>(
      value: widget.selectedTab,
      isExpanded: true,
      items: List.generate(
        widget.tabs.length,
        (i) => DropdownMenuItem(
          value: i,
          child: Row(
            children: [
              Icon(widget.icons[i], size: 18),
              const SizedBox(width: 8),
              Text(widget.tabs[i], style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
      onChanged: (i) {
        if (i != null) widget.onTab(i);
      },
    ),
  );

  Widget _header(
    double width,
    bool mobile,
    bool showLeft,
    bool showRight,
  ) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: Color(0xff121a26),
      border: Border(bottom: BorderSide(color: Color(0xff30394a))),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('toggle-left'),
              tooltip: 'Biblioteca · mostrar / plegar',
              onPressed: () {
                if (mobile) {
                  scaffoldKey.currentState?.openDrawer();
                } else {
                  setState(() => leftOpen = !leftOpen);
                }
              },
              icon: Icon(
                showLeft ? Icons.view_sidebar_outlined : Icons.menu,
                size: 20,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.view_in_ar_outlined,
              size: 21,
              color: Color(0xffb2c5ff),
            ),
            const SizedBox(width: 9),
            const Text(
              'SHAIYA',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.7,
              ),
            ),
            if (width > 740)
              const Text(
                '  STUDIO',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.5,
                  color: Color(0xff9aaac4),
                ),
              ),
            const Spacer(),
            if (width > 1100)
              const Text(
                '0.6.5 · SPK Explorer',
                style: TextStyle(fontSize: 10, color: Color(0xff8091ab)),
              ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: widget.onOpenData,
              icon: const Icon(Icons.folder_open, size: 17),
              label: const Text('DATA', style: TextStyle(fontSize: 12)),
            ),
            if (widget.onOpenSpk != null)
              TextButton.icon(
                key: const ValueKey('open-spk'),
                onPressed: widget.onOpenSpk,
                icon: const Icon(Icons.folder_zip_outlined, size: 17),
                label: const Text('SPK', style: TextStyle(fontSize: 12)),
              ),
            if (widget.onExportScene != null)
              IconButton(
                key: const ValueKey('export-game-scene'),
                tooltip: 'Exportar escena al cliente Flutter',
                onPressed: widget.onExportScene,
                icon: const Icon(Icons.link, size: 18),
              ),
            IconButton(
              key: const ValueKey('toggle-right'),
              tooltip: 'Inspector · mostrar / plegar',
              onPressed: () {
                if (mobile ||
                    (!showRight &&
                        width - (leftOpen ? leftWidth + 51 : 46) - rightWidth <=
                            380)) {
                  scaffoldKey.currentState?.openEndDrawer();
                } else {
                  setState(() => rightOpen = !rightOpen);
                }
              },
              icon: Icon(showRight ? Icons.last_page : Icons.tune, size: 19),
            ),
          ],
        ),
        if (widget.onOpenEditor != null)
          Align(
            alignment: Alignment.center,
            child: width < 570
                ? IconButton(
                    key: const ValueKey('open-data-editor'),
                    tooltip: 'Editor avanzado de datos',
                    onPressed: widget.onOpenEditor,
                    icon: const Icon(Icons.edit_note, size: 24),
                  )
                : OutlinedButton.icon(
                    key: const ValueKey('open-data-editor'),
                    onPressed: widget.onOpenEditor,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text(
                      'Editor de datos',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
          ),
      ],
    ),
  );

  Widget _center() => Column(
    children: [
      Expanded(
        child: ClipRect(
          key: const ValueKey('viewport-region'),
          child: widget.viewport,
        ),
      ),
      if (widget.hasLibrary) ...[
        Container(
          key: const ValueKey('action-region'),
          decoration: const BoxDecoration(
            color: Color(0xff182130),
            border: Border(top: BorderSide(color: Color(0xff30394a))),
          ),
          child: widget.actions,
        ),
        Container(
          decoration: const BoxDecoration(
            color: Color(0xff141d2b),
            border: Border(top: BorderSide(color: Color(0xff30394a))),
          ),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('toggle-timeline'),
                tooltip: timelineOpen
                    ? 'Plegar animación'
                    : 'Expandir animación',
                onPressed: () => setState(() => timelineOpen = !timelineOpen),
                icon: Icon(
                  timelineOpen
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  size: 17,
                ),
                visualDensity: VisualDensity.compact,
              ),
              if (timelineOpen)
                Expanded(
                  child: Padding(
                    key: const ValueKey('timeline-region'),
                    padding: const EdgeInsets.only(right: 10),
                    child: widget.timeline,
                  ),
                )
              else
                const Expanded(
                  child: Text(
                    'Animación',
                    style: TextStyle(fontSize: 10, color: Color(0xff92a3be)),
                  ),
                ),
            ],
          ),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final mobile = box.maxWidth < 840;
      final showRight =
          !mobile &&
          rightOpen &&
          box.maxWidth - (leftOpen ? leftWidth + 51 : 46) - rightWidth > 380;
      final showLeft = !mobile && leftOpen;
      final drawerWidth = (box.maxWidth - 28).clamp(240, 330).toDouble();
      return Scaffold(
        key: scaffoldKey,
        backgroundColor: const Color(0xff101722),
        drawer: mobile
            ? Drawer(
                width: drawerWidth,
                child: SafeArea(
                  child: Column(
                    children: [
                      _mobileTabs(),
                      Expanded(child: _scroll(widget.left)),
                    ],
                  ),
                ),
              )
            : null,
        endDrawer: Drawer(
          width: drawerWidth,
          child: SafeArea(
            child: _panel(
              'Inspector',
              widget.right,
              () => scaffoldKey.currentState?.closeEndDrawer(),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _header(box.maxWidth, mobile, showLeft, showRight),
              Expanded(
                child: Row(
                  children: [
                    if (!mobile) _rail(),
                    if (showLeft) ...[
                      _panel(
                        widget.tabs[widget.selectedTab],
                        widget.left,
                        () => setState(() => leftOpen = false),
                        width: leftWidth,
                      ),
                      _splitter(true),
                    ],
                    Expanded(child: _center()),
                    if (showRight) ...[
                      _splitter(false),
                      _panel(
                        'Inspector',
                        widget.right,
                        () => setState(() => rightOpen = false),
                        width: rightWidth,
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                height: 25,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: const Color(0xff111823),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xff92a1b8),
                  ),
                  child: widget.status,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
