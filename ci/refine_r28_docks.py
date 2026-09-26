"""Give both docks a single movable surface; never duplicate their controls."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r28-docks-applied'

def apply(root):
    path = root / 'lib/ui/studio_workspace.dart'
    text = path.read_text(encoding='utf-8')
    def replace(old, new, count=1):
        nonlocal text
        if text.count(old) != count: raise RuntimeError(f'Dock anchor mismatch: {old[:100]}')
        text = text.replace(old, new)
    replace("import 'studio_brand.dart';", "import 'studio_brand.dart';\nimport 'studio_floating_panel.dart';")
    replace('  double leftWidth = 236, rightWidth = 292;', '''  double leftWidth = 236, rightWidth = 292;
  bool leftFloating = false, rightFloating = false;
  final leftContent = GlobalKey(), rightContent = GlobalKey();
  double availableWidth = 1440;
  bool leftDockVisible = true, rightDockVisible = true;

  Widget _content(bool left) => KeyedSubtree(
    key: left ? leftContent : rightContent,
    child: left ? widget.left : widget.right);

  void _float(bool left) => setState(() {
    if (left) { leftFloating = true; leftOpen = true; }
    else { rightFloating = true; rightOpen = true; }
  });

  Widget _floating(bool left, Size bounds) => StudioFloatingPanel(
    key: ValueKey('floating-surface-${left ? 'left' : 'right'}'),
    side: left ? 'left' : 'right', bounds: bounds,
    title: left ? widget.tabs[widget.selectedTab] : 'Inspector',
    onDock: () => setState(() {
      if (left) leftFloating = false; else rightFloating = false;
    }),
    onClose: () => setState(() {
      if (left) leftOpen = false; else rightOpen = false;
    }),
    child: left && widget.leftOwnsScroll ? _content(left) : _scroll(_content(left)),
  );''')
    replace('  Widget _title(String text, VoidCallback close) => Container(',
      '  Widget _title(String text, VoidCallback close, bool? side) => Container(')
    replace("        IconButton(\n          tooltip: 'Plegar panel',", """        if (side != null)
          IconButton(key: ValueKey('float-${side ? 'left' : 'right'}'),
            tooltip: 'Extraer panel', onPressed: () => _float(side),
            icon: const Icon(Icons.open_in_new, size: 15)),
        IconButton(
          tooltip: 'Plegar panel',""")
    replace('    bool scroll = true,\n  }) => SizedBox(', '    bool scroll = true,\n    bool? side,\n  }) => SizedBox(')
    replace('          _title(title, close),', '          _title(title, close, side),')
    replace('  Widget _splitter(bool left) => MouseRegion(', "  Widget _splitter(bool left) => MouseRegion(\n    key: ValueKey('resize-${left ? 'left' : 'right'}-dock'),")
    replace('''          leftWidth = (leftWidth + event.delta.dx).clamp(210, 350);''', '''          final budget = availableWidth - 56 - 380 - (rightDockVisible ? rightWidth + 5 : 0);
          leftWidth = (leftWidth + event.delta.dx).clamp(210, budget.clamp(210, 350));''')
    replace('''          rightWidth = (rightWidth - event.delta.dx).clamp(240, 440);''', '''          final budget = availableWidth - 56 - 380 - (leftDockVisible ? leftWidth + 5 : 0);
          rightWidth = (rightWidth - event.delta.dx).clamp(240, budget.clamp(240, 440));''')
    replace('''            if (mobile) {
              scaffoldKey.currentState?.openDrawer();''', '''            if (!mobile && leftFloating) {
              setState(() => leftOpen = !leftOpen);
            } else if (mobile) {
              scaffoldKey.currentState?.openDrawer();''')
    replace('''            if (mobile ||
                (!showRight &&''', '''            if (!mobile && rightFloating) {
              setState(() => rightOpen = !rightOpen);
            } else if (mobile ||
                (!showRight &&''')
    replace('''          rightOpen &&
          box.maxWidth - (leftOpen ? leftWidth + 51 : 46) - rightWidth > 380;
      final showLeft = !mobile && leftOpen;''', '''          rightOpen && !rightFloating &&
          box.maxWidth - (leftOpen && !leftFloating ? leftWidth + 51 : 46) - rightWidth > 380;
      final showLeft = !mobile && leftOpen && !leftFloating;
      availableWidth = box.maxWidth;
      leftDockVisible = showLeft;
      rightDockVisible = showRight;''')
    replace('''                                child: widget.left,
                              )
                            : _scroll(widget.left),''', '''                                child: _content(true),
                              )
                            : _scroll(_content(true)),''')
    replace('''        endDrawer: Drawer(''', '''        endDrawer: !showRight && (mobile || !rightFloating) ? Drawer(''')
    replace('''              widget.right,
              () => scaffoldKey.currentState?.closeEndDrawer(),''', '''              _content(false),
              () => scaffoldKey.currentState?.closeEndDrawer(),''')
    replace('''        ),
        body: SafeArea(''', '''        ) : null,
        body: SafeArea(''')
    replace('''              Expanded(
                child: Row(
                  children: [
                    if (!mobile) _rail(),''', '''              Expanded(
                child: LayoutBuilder(builder: (context, area) => Stack(children: [
                Positioned.fill(child: Row(
                  children: [
                    if (!mobile) _rail(),''')
    replace('''                        widget.left,
                        () => setState(() => leftOpen = false),
                        width: leftWidth,''', '''                        _content(true),
                        () => setState(() => leftOpen = false),
                        side: true,
                        width: leftWidth,''')
    replace('''                        widget.right,
                        () => setState(() => rightOpen = false),
                        width: rightWidth,''', '''                        _content(false),
                        () => setState(() => rightOpen = false),
                        side: false,
                        width: rightWidth,''')
    replace('''                  ],
                ),
              ),
              Container(
                height: 25,''', '''                  ],
                )),
                if (!mobile && leftFloating && leftOpen)
                  _floating(true, Size(area.maxWidth, area.maxHeight)),
                if (!mobile && rightFloating && rightOpen)
                  _floating(false, Size(area.maxWidth, area.maxHeight)),
                ])),
              ),
              Container(
                height: 25,''')
    path.write_text(text, encoding='utf-8')

def main():
    if subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip() != 'fix/studio-0628-startup-spk-recovery':
        raise RuntimeError('Refusing a different branch.')
    if MARKER.exists(): return
    apply(ROOT)
    MARKER.write_text('R28 floating panels; rendering uses actual viewport constraints\n')
if __name__ == '__main__': main()
