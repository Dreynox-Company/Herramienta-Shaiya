"""Replace a dead-end error with source-specific, explicit recovery navigation."""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r28-recovery-ui-applied'


def main():
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip() != 'fix/studio-0628-startup-spk-recovery':
        raise RuntimeError('Refusing a different branch.')
    if MARKER.exists():
        return
    changes = {}
    def replace(path, old, new):
        text = changes.get(path, (ROOT / path).read_text(encoding='utf-8'))
        if text.count(old) != 1:
            raise RuntimeError(f'Recovery anchor mismatch: {path}: {old[:100]}')
        changes[path] = text.replace(old, new, 1)
    path = 'lib/ui/items_page.dart'
    replace(path, "import 'item_record_editor.dart';", "import 'item_record_editor.dart';\nimport 'items_source_recovery.dart';")
    replace(path, '  const ItemsPage({super.key, required this.library, this.initialItemKey});', '''  final ValueChanged<ItemsRecoveryAction>? onRecovery;
  const ItemsPage({super.key, required this.library, this.initialItemKey, this.onRecovery});''')
    replace(path, '  Future<void> load() async {\n    try {', '''  bool loading = false;
  Future<void> load() async {
    if (loading || !mounted) return;
    loading = true;
    setState(() => error = null);
    try {''')
    replace(path, '''    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose()''', '''    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      loading = false;
    }
  }

  @override
  void dispose()''')
    replace(path, '''                  : SelectableText(error!),''', '''                  : ItemsSourceRecovery(library: widget.library, error: error!,
                      onRetry: load, onRecovery: widget.onRecovery),''')
    path = 'lib/main.dart'
    replace(path, "import 'ui/items_page.dart';", "import 'ui/items_page.dart';\nimport 'ui/items_source_recovery.dart';")
    replace(path, '''    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ItemsPage(library: library)),
    );
    if (mounted) focus.requestFocus();
  }

  Future<void> openDataEditor()''', '''    final recovery = await Navigator.of(context).push<ItemsRecoveryAction>(
      MaterialPageRoute(builder: (routeContext) => ItemsPage(library: library,
        onRecovery: (action) => Navigator.pop(routeContext, action))),
    );
    if (!mounted) return;
    switch (recovery) {
      case ItemsRecoveryAction.resources:
        setState(() => tab = 6);
        break;
      case ItemsRecoveryAction.spk:
        await browseMountedSpk();
        break;
      case ItemsRecoveryAction.reference:
        await resolveResourceNames();
        break;
      case null:
        break;
    }
    if (mounted) focus.requestFocus();
  }

  Future<void> openDataEditor()''')
    for path, text in changes.items():
        (ROOT / path).write_text(text, encoding='utf-8')
    MARKER.write_text('R28 source recovery navigation; no synthetic table or relaxed authentication\n')


if __name__ == '__main__':
    main()
