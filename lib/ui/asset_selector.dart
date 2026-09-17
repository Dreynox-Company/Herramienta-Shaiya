import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SelectionMemory {
  String query = '';
  String? cursor;
  double offset = 0;
}

class AssetSelector<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final T? value;
  final String Function(T) id, label;
  final String Function(T)? detail;
  final Future<void> Function(T) onChanged;
  final void Function(Object)? onError;
  final SelectionMemory memory;
  final bool enabled;
  final String emptyLabel;
  const AssetSelector({
    super.key,
    required this.title,
    required this.items,
    required this.value,
    required this.id,
    required this.label,
    required this.onChanged,
    required this.memory,
    this.detail,
    this.onError,
    this.enabled = true,
    this.emptyLabel = 'Sin selección',
  });
  @override
  State<AssetSelector<T>> createState() => _AssetSelectorState<T>();
}

class _AssetSelectorState<T> extends State<AssetSelector<T>> {
  final _focus = FocusNode();
  Timer? _debounce;
  T? _desired, _browse;
  bool _loading = false;
  int _generation = 0;
  String? _error;
  int indexOf(T? item) => item == null
      ? -1
      : widget.items.indexWhere((x) => widget.id(x) == widget.id(item));

  void _step(int delta) {
    if (!widget.enabled || widget.items.isEmpty) return;
    final current = indexOf(_desired ?? _browse ?? widget.value);
    final index =
        (current < 0
                ? (delta < 0 ? widget.items.length - 1 : 0)
                : current + delta)
            .clamp(0, widget.items.length - 1);
    _select(widget.items[index]);
  }

  void _select(T value) {
    setState(() {
      _desired = value;
      _browse = value;
      _error = null;
    });
    _generation++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), _drain);
  }

  Future<void> _drain() async {
    if (_loading || !mounted || _desired == null) return;
    setState(() => _loading = true);
    while (mounted && _desired != null) {
      final next = _desired as T, version = _generation;
      try {
        await widget.onChanged(next);
        if (mounted) widget.memory.cursor = widget.id(next);
      } catch (e) {
        if (mounted) {
          setState(() => _error = e.toString());
          widget.onError?.call(e);
        }
      }
      if (!mounted) return;
      if (version == _generation) {
        setState(() => _desired = null);
        break;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _open() async {
    if (!widget.enabled || widget.items.isEmpty) return;
    _focus.requestFocus();
    final next = await showDialog<T>(
      context: context,
      builder: (_) => AssetPickerDialog<T>(
        title: widget.title,
        items: widget.items,
        current: _desired ?? widget.value,
        id: widget.id,
        label: widget.label,
        detail: widget.detail,
        memory: widget.memory,
      ),
    );
    if (!mounted) return;
    _focus.requestFocus();
    if (next != null) _select(next);
  }

  @override
  void didUpdateWidget(covariant AssetSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.value == null
        ? null
        : oldWidget.id(oldWidget.value as T);
    final after = widget.value == null ? null : widget.id(widget.value as T);
    if (!_loading && _desired == null && before != after) _browse = null;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _open();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _desired ?? widget.value, index = indexOf(selected);
    final body = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _error != null
              ? const Color(0xffdc8a86)
              : _focus.hasFocus
              ? const Color(0xffa2b8ff)
              : const Color(0xff343f52),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xffaab6c9),
                  ),
                ),
              ),
              Text(
                index < 0
                    ? '— / ${widget.items.length}'
                    : '${index + 1} / ${widget.items.length}',
                style: const TextStyle(fontSize: 9, color: Color(0xff8997ac)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  selected == null ? widget.emptyLabel : widget.label(selected),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: widget.enabled
                        ? const Color(0xffedf0f8)
                        : const Color(0xff8390a4),
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(6),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.unfold_more,
                    size: 17,
                    color: Color(0xffa2b8ff),
                  ),
                ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xffffbab0)),
            ),
          if (_focus.hasFocus)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                '↑ / ↓: cambiar · Intro: catálogo',
                style: TextStyle(fontSize: 9, color: Color(0xffa2b8ff)),
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Focus(
        focusNode: _focus,
        onFocusChange: (_) {
          if (mounted) setState(() {});
        },
        onKeyEvent: _key,
        child: Semantics(
          label: widget.title,
          value: selected == null ? widget.emptyLabel : widget.label(selected),
          button: true,
          child: Material(
            color: const Color(0xff202735),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              canRequestFocus: false,
              onTap: widget.enabled ? _open : null,
              onLongPress: widget.enabled ? _focus.requestFocus : null,
              borderRadius: BorderRadius.circular(6),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

class AssetPickerDialog<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final T? current;
  final String Function(T) id, label;
  final String Function(T)? detail;
  final SelectionMemory memory;
  const AssetPickerDialog({
    super.key,
    required this.title,
    required this.items,
    required this.current,
    required this.id,
    required this.label,
    required this.memory,
    this.detail,
  });
  @override
  State<AssetPickerDialog<T>> createState() => _AssetPickerDialogState<T>();
}

class _AssetPickerDialogState<T> extends State<AssetPickerDialog<T>> {
  late final TextEditingController _search;
  late final ScrollController _scroll;
  late List<T> _filtered;
  int _cursor = 0;
  static const rowHeight = 64.0;
  String? get selectedId =>
      widget.current == null ? null : widget.id(widget.current as T);
  List<T> filter(String query) => widget.items
      .where(
        (x) =>
            '${widget.label(x)} ${widget.detail?.call(x) ?? ''} ${widget.id(x)}'
                .toLowerCase()
                .contains(query.toLowerCase()),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    var query = widget.memory.query;
    _filtered = filter(query);
    if (selectedId != null &&
        !_filtered.any((x) => widget.id(x) == selectedId)) {
      query = '';
      _filtered = filter(query);
    }
    _search = TextEditingController(text: query);
    final preferred = selectedId ?? widget.memory.cursor;
    _cursor = math.max(
      0,
      _filtered.indexWhere((x) => widget.id(x) == preferred),
    );
    _scroll = ScrollController(
      initialScrollOffset: math.max(0, (_cursor - 2) * rowHeight),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position,
        top = _cursor * rowHeight,
        bottom = top + rowHeight;
    double target = pos.pixels;
    if (top < pos.pixels) target = top;
    if (bottom > pos.pixels + pos.viewportDimension) {
      target = bottom - pos.viewportDimension;
    }
    _scroll.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    setState(() => _cursor = (_cursor + delta).clamp(0, _filtered.length - 1));
    _reveal();
  }

  void _commit() {
    if (_filtered.isNotEmpty) Navigator.pop(context, _filtered[_cursor]);
  }

  void _query(String query) {
    setState(() {
      _filtered = filter(query);
      _cursor = math.max(
        0,
        _filtered.indexWhere((x) => widget.id(x) == selectedId),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    widget.memory.query = _search.text;
    widget.memory.offset = _scroll.hasClients ? _scroll.offset : 0;
    if (_filtered.isNotEmpty) {
      widget.memory.cursor = widget.id(_filtered[_cursor]);
    }
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Widget _row(int index) {
    final item = _filtered[index],
        id = widget.id(item),
        active = index == _cursor;
    return Material(
      color: active ? const Color(0xff2b3a55) : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _cursor = index);
          _commit();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Icon(
                  id == selectedId
                      ? Icons.check_circle_outline
                      : active
                      ? Icons.chevron_right
                      : Icons.circle_outlined,
                  size: id == selectedId ? 19 : 14,
                  color: active
                      ? const Color(0xffb4c7ff)
                      : const Color(0xff61708a),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.label(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (widget.detail != null)
                      Text(
                        widget.detail!(item).replaceAll('\n', ' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff9dabc1),
                        ),
                      ),
                  ],
                ),
              ),
              if (id == selectedId)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    'Actual',
                    style: TextStyle(fontSize: 10, color: Color(0xffb4c7ff)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
      const SingleActivator(LogicalKeyboardKey.pageDown): () => _move(6),
      const SingleActivator(LogicalKeyboardKey.pageUp): () => _move(-6),
      const SingleActivator(LogicalKeyboardKey.enter): _commit,
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
    };
    final search = CallbackShortcuts(
      bindings: bindings,
      child: TextField(
        autofocus: true,
        controller: _search,
        onChanged: _query,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, número o archivo',
          prefixIcon: const Icon(Icons.search, size: 19),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: () {
                    _search.clear();
                    _query('');
                  },
                  icon: const Icon(Icons.close, size: 16),
                ),
        ),
      ),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 600),
        child: CallbackShortcuts(
          bindings: bindings,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar catálogo',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 19),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
                child: search,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Text(
                      '${_filtered.length} resultados',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff9dabc1),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '↑↓ Recorrer   Intro Aplicar',
                      style: TextStyle(fontSize: 10, color: Color(0xff9dabc1)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(
                        child: Text('No hay recursos que coincidan.'),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        itemExtent: rowHeight,
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) => _row(index),
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _filtered.isEmpty
                            ? ''
                            : widget.label(_filtered[_cursor]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      onPressed: _filtered.isEmpty ? null : _commit,
                      child: const Text('Aplicar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
