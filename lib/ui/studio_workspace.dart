import 'package:flutter/material.dart';
import 'studio_brand.dart';
import 'studio_floating_panel.dart';

/// Docks reserve space; animation and action bars never cover the 3D viewport.
class StudioWorkspace extends StatefulWidget {
  final Widget viewport, left, right, timeline, actions, status;
  final List<String> tabs;
  final List<IconData> icons;
  final int selectedTab;
  final ValueChanged<int> onTab;
  final VoidCallback? onOpenData,
      onOpenSpk,
      onOpenEditor,
      onOpenItems,
      onOpenExcelXml,
      onExportScene;
  final bool hasLibrary;
  final bool leftOwnsScroll;
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
    this.onOpenItems,
    this.onOpenExcelXml,
    this.onExportScene,
    this.hasLibrary = false,
    this.leftOwnsScroll = false,
  });
  @override
  State<StudioWorkspace> createState() => _StudioWorkspaceState();
}

class _StudioWorkspaceState extends State<StudioWorkspace> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  bool leftOpen = true, rightOpen = true, timelineOpen = true;
  double leftWidth = 236, rightWidth = 292;
  bool leftFloating = false, rightFloating = false;
  final leftContent = GlobalKey(), rightContent = GlobalKey();
  double availableWidth = 1440;
  bool leftDockVisible = true, rightDockVisible = true;

  Widget _content(bool left) => KeyedSubtree(
    key: left ? leftContent : rightContent,
    child: left ? widget.left : widget.right,
  );

  void _float(bool left) => setState(() {
    if (left) {
      leftFloating = true;
      leftOpen = true;
    } else {
      rightFloating = true;
      rightOpen = true;
    }
  });

  Widget _floating(bool left, Size bounds) => StudioFloatingPanel(
    key: ValueKey('floating-surface-${left ? 'left' : 'right'}'),
    side: left ? 'left' : 'right',
    bounds: bounds,
    title: left ? widget.tabs[widget.selectedTab] : 'Inspector',
    onDock: () => setState(() {
      if (left) {
        leftFloating = false;
      } else {
        rightFloating = false;
      }
    }),
    onClose: () => setState(() {
      if (left) {
        leftOpen = false;
      } else {
        rightOpen = false;
      }
    }),
    child: left && widget.leftOwnsScroll
        ? _content(left)
        : _scroll(_content(left)),
  );

  Widget _title(String text, VoidCallback close, bool? side) => Container(
    height: 32,
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
        if (side != null)
          IconButton(
            key: ValueKey('float-${side ? 'left' : 'right'}'),
            tooltip: 'Extraer panel',
            onPressed: () => _float(side),
            icon: const Icon(Icons.open_in_new, size: 15),
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
      SingleChildScrollView(padding: const EdgeInsets.all(8), child: body);
  Widget _panel(
    String title,
    Widget child,
    VoidCallback close, {
    double? width,
    bool scroll = true,
    bool? side,
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
          _title(title, close, side),
          Expanded(
            child: scroll
                ? _scroll(child)
                : Padding(padding: const EdgeInsets.all(8), child: child),
          ),
        ],
      ),
    ),
  );
  Widget _splitter(bool left) => MouseRegion(
    key: ValueKey('resize-${left ? 'left' : 'right'}-dock'),
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (event) => setState(() {
        if (left) {
          final budget =
              availableWidth -
              56 -
              380 -
              (rightDockVisible ? rightWidth + 5 : 0);
          leftWidth = (leftWidth + event.delta.dx).clamp(
            210,
            budget.clamp(210, 350),
          );
        } else {
          final budget =
              availableWidth - 56 - 380 - (leftDockVisible ? leftWidth + 5 : 0);
          rightWidth = (rightWidth - event.delta.dx).clamp(
            240,
            budget.clamp(240, 440),
          );
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
      child: SingleChildScrollView(child: Column(children: buttons)),
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
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: Color(0xff121a26),
      border: Border(bottom: BorderSide(color: Color(0xff30394a))),
    ),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('toggle-left'),
          tooltip: 'Biblioteca · mostrar / plegar',
          onPressed: () {
            if (!mobile && leftFloating) {
              setState(() => leftOpen = !leftOpen);
            } else if (mobile) {
              scaffoldKey.currentState?.openDrawer();
            } else {
              setState(() {
                // Closing one dock must not silently open a wider hidden dock.
                if (leftOpen && !showRight) rightOpen = false;
                leftOpen = !leftOpen;
              });
            }
          },
          icon: Icon(
            showLeft ? Icons.view_sidebar_outlined : Icons.menu,
            size: 20,
          ),
        ),
        if (width >= 1050) ...[
          const StudioBrand(size: 28),
          const SizedBox(width: 9),
          const Text('SHSTUDIO', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 18),
        ],
        // A bounded horizontal toolbar replaces the old centered overlay.
        // Even a 360 px window cannot overlap the title, DATA and editor buttons.
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onOpenItems != null)
                  TextButton.icon(
                    key: const ValueKey('open-items-catalog'),
                    onPressed: widget.onOpenItems,
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('Ítems'),
                  ),
                if (widget.onOpenEditor != null)
                  TextButton.icon(
                    key: const ValueKey('open-data-editor'),
                    onPressed: widget.onOpenEditor,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Editor de datos'),
                  ),
                TextButton.icon(
                  onPressed: widget.onOpenData,
                  icon: const Icon(Icons.folder_open, size: 17),
                  label: const Text('DATA'),
                ),
                if (widget.onOpenSpk != null)
                  TextButton.icon(
                    key: const ValueKey('open-spk'),
                    onPressed: widget.onOpenSpk,
                    icon: const Icon(Icons.folder_zip_outlined, size: 17),
                    label: const Text('SPK'),
                  ),
                if (widget.onOpenExcelXml != null)
                  TextButton.icon(
                    key: const ValueKey('open-excelxml'),
                    onPressed: widget.onOpenExcelXml,
                    icon: const Icon(Icons.table_view_outlined, size: 17),
                    label: const Text('XML'),
                  ),
                if (widget.onExportScene != null)
                  IconButton(
                    key: const ValueKey('export-game-scene'),
                    tooltip: 'Exportar escena al cliente Flutter',
                    onPressed: widget.onExportScene,
                    icon: const Icon(Icons.link, size: 18),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('toggle-right'),
          tooltip: 'Inspector · mostrar / plegar',
          onPressed: () {
            if (!mobile && rightFloating) {
              setState(() => rightOpen = !rightOpen);
            } else if (mobile ||
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
          !rightFloating &&
          box.maxWidth -
                  (leftOpen && !leftFloating ? leftWidth + 51 : 46) -
                  rightWidth >
              380;
      final showLeft = !mobile && leftOpen && !leftFloating;
      availableWidth = box.maxWidth;
      leftDockVisible = showLeft;
      rightDockVisible = showRight;
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
                      Expanded(
                        child: widget.leftOwnsScroll
                            ? Padding(
                                padding: const EdgeInsets.all(8),
                                child: _content(true),
                              )
                            : _scroll(_content(true)),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        endDrawer: !showRight && (mobile || !rightFloating)
            ? Drawer(
                width: drawerWidth,
                child: SafeArea(
                  child: _panel(
                    'Inspector',
                    _content(false),
                    () => scaffoldKey.currentState?.closeEndDrawer(),
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: Column(
            children: [
              _header(box.maxWidth, mobile, showLeft, showRight),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, area) => Stack(
                    children: [
                      Positioned.fill(
                        child: Row(
                          children: [
                            if (!mobile) _rail(),
                            if (showLeft) ...[
                              _panel(
                                widget.tabs[widget.selectedTab],
                                _content(true),
                                () => setState(() => leftOpen = false),
                                side: true,
                                width: leftWidth,
                                scroll: !widget.leftOwnsScroll,
                              ),
                              _splitter(true),
                            ],
                            Expanded(child: _center()),
                            if (showRight) ...[
                              _splitter(false),
                              _panel(
                                'Inspector',
                                _content(false),
                                () => setState(() => rightOpen = false),
                                side: false,
                                width: rightWidth,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!mobile && leftFloating && leftOpen)
                        _floating(true, Size(area.maxWidth, area.maxHeight)),
                      if (!mobile && rightFloating && rightOpen)
                        _floating(false, Size(area.maxWidth, area.maxHeight)),
                    ],
                  ),
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
