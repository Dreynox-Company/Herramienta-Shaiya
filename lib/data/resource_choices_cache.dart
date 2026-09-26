import 'library.dart';

/// Inspector rebuilds at animation rate. Never rescan and sort an entire DATA
/// once for every MON field. Each library version is scanned only once.
class ResourceChoicesCache {
  Library? _source;
  int? _revision;
  List<String> _paths = const [];
  final Map<String, List<String>> _groups = {};
  int scans = 0;

  List<String> select(Library library, String group, bool Function(String) accepts) {
    if (!identical(_source, library) || _revision != library.revision) {
      _source = library;
      _revision = library.revision;
      _paths = library.files.keys.toList()..sort();
      _groups.clear();
      scans++;
    }
    return _groups.putIfAbsent(group,
      () => List<String>.unmodifiable(_paths.where(accepts)));
  }

  void clear() {
    _source = null;
    _revision = null;
    _paths = const [];
    _groups.clear();
  }
}
