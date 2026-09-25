import 'package:flutter/material.dart';

import 'editor_style.dart';

/// Real layout density, not a scaled screenshot or Transform.scale: text and
/// hit testing retain the OS text scale and the controls keep their callbacks.
class StudioSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? help;
  final bool initiallyExpanded;
  const StudioSection({
    super.key,
    required this.title,
    required this.children,
    this.help,
    this.initiallyExpanded = true,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: ExpansionTile(
      key: PageStorageKey('studio-section-$title'),
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 2),
      childrenPadding: const EdgeInsets.only(top: 4, bottom: 6),
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: const Border(bottom: BorderSide(color: EditorStyle.line)),
      collapsedShape: const Border(bottom: BorderSide(color: EditorStyle.line)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: EditorStyle.text,
        ),
      ),
      children: [
        if (help != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(help!, style: Theme.of(context).textTheme.bodySmall),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ],
    ),
  );
}

/// Only explicit section titles move. Resource selectors and their focus state
/// are never duplicated between docks. The right dock becomes contextual.
class StudioDockContent {
  final Widget navigation, inspector;
  const StudioDockContent(this.navigation, this.inspector);
  static const detailTitles = {
    'Mirada natural',
    'Apariencia guardada',
    'Mejora y elemento',
    'Ajustes de alas',
    'Ajustes de montura',
    'Efectos y sonido',
    'Registro',
    'Visualización',
    'Recursos indexados',
  };
  static StudioDockContent split(Widget body) {
    final source = body is Column ? body.children : [body];
    final left = <Widget>[], right = <Widget>[];
    for (final widget in source) {
      if (widget is StudioSection && detailTitles.contains(widget.title)) {
        right.add(widget);
      } else {
        left.add(widget);
      }
    }
    return StudioDockContent(
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
    );
  }
}
