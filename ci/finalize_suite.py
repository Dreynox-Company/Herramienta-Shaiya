"""Small idempotent source correction recovered from native integration results."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[1]
p=root/'lib/offline_game/game_app.dart';s=p.read_text()
old='    setState(() => leaving = true);\n    Navigator.of(context).pop();'
new='    setState(() => leaving = true);\n    await WidgetsBinding.instance.endOfFrame;\n    if (mounted) Navigator.of(context).pop();'
if old in s:
 if s.count(old)!=1:raise RuntimeError('Unexpected navigation contract')
 p.write_text(s.replace(old,new))
elif new not in s:raise RuntimeError('Navigation code changed; inspect before applying')
p=root/'tool/run_all_local.dart';s=p.read_text()
if "import '../test/local_game_test.dart' as suite25;" not in s:
 if s.count('\nvoid main() {')!=1 or s.count('  suite24.main();')!=1:raise RuntimeError('Local regression inventory changed')
 s=s.replace('\nvoid main() {',"\nimport '../test/local_game_test.dart' as suite25;\n\nvoid main() {")
 s=s.replace('  suite24.main();','  suite24.main();\n  suite25.main();');p.write_text(s)
subprocess.run(['git','add','--','lib/offline_game/game_app.dart','tool/run_all_local.dart'],cwd=root,check=True)
print('Navigation now waits for PopScope state; local runner includes all test files.')
