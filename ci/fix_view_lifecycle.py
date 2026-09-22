from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1]
changed=[]
for name,old,imp in [('lib/main.dart','three.ThreeJS(','render/native_view.dart'),('lib/offline_game/game_app.dart','three.ThreeJS(','../render/native_view.dart'),('lib/ui/editor_model_preview.dart','t.ThreeJS(','../render/native_view.dart')]:
 p=r/name;s=p.read_text()
 if old in s:
  if s.count(old)!=1:raise RuntimeError('Unexpected renderer constructor: '+name)
  p.write_text(f"import '{imp}';\n"+s.replace(old,'NativeView('))
 changed.append(name)
p=r/'pubspec.yaml';s=p.read_text()
if '  flutter_angle: 0.4.2\n' not in s:
 if s.count('  three_js: 0.3.0\n')!=1:raise RuntimeError('Renderer version contract changed')
 p.write_text(s.replace('  three_js: 0.3.0\n','  three_js: 0.3.0\n  flutter_angle: 0.4.2\n'))
changed.append('pubspec.yaml')
p=r/'pubspec.lock';s=p.read_text();old='  flutter_angle:\n    dependency: transitive';new='  flutter_angle:\n    dependency: "direct main"'
if old in s:p.write_text(s.replace(old,new))
elif new not in s:raise RuntimeError('Lock dependency contract changed')
changed.append('pubspec.lock')
p=r/'integration_test/local_game_test.dart';s=p.read_text()
if '// State may settle between frames' not in s:
 s=s.replace('      expect(predicate(), true, reason: label);','      // State may settle between frames: repaint controls before tapping.\n      await t.pump();\n      expect(predicate(), true, reason: label);')
 s=s.replace("      await t.tap(find.text('Partidas'));", "      await t.pump();\n      expect(\n        t\n            .widget<TextButton>(find.widgetWithText(TextButton, 'Partidas'))\n            .onPressed,\n        isNotNull,\n      );\n      await t.tap(find.text('Partidas'));")
p.write_text(s);changed.append('integration_test/local_game_test.dart')
subprocess.run(['git','add','--',*changed],cwd=r,check=True)
print('Applied lifecycle fix and explicit UI-enabled navigation checks.')
