"""Repair a Dart automated-fix regression without suppressing the analyzer."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]/'lib/editor/item_workspace.dart'
s=p.read_text()
s=s.replace(': documents = {data.path: data, text.path: ?text} {',
    ': documents = {data.path: data} {\n    final localized = text;\n    if (localized != null) { documents[localized.path] = localized; }')
a='''    if (text != null)
      for (var row = 0; row < text!.rows.length; row++) {'''
b='''    if (text != null) {
      for (var row = 0; row < text!.rows.length; row++) {'''
if a in s:
    s=s.replace(a,b,1)
    s=s.replace('''        names[key] = (row, v);
      }
    final next''','''        names[key] = (row, v);
      }
    }
    final next''',1)
p.write_text(s)
