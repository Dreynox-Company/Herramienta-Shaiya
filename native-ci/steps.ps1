# Coordinates are based on native screenshots; preserve screenshots at each state.
Click 0.145 0.891
Start-Sleep 6
Shot '05-character-editor.png'
$ws=New-Object -ComObject WScript.Shell
Click 0.12 0.48
$ws.SendKeys('DreynoxLocal')
Click 0.267 0.48
Start-Sleep 2
Shot '06-name-check.png'
$ws.SendKeys('{ENTER}')
Start-Sleep 1
Click 0.258 0.393
Shot '06b-mode-options.png'
Click 0.155 0.52
Shot '06c-mode-selected.png'
Click 0.936 0.954
Start-Sleep 6
Shot '07-character-created.png'
$ws.SendKeys('{ENTER}')
Start-Sleep 2
Shot '08-character-selection.png'
Click 0.70 0.919
Start-Sleep 15
Shot '09-world-entry.png'
Start-Sleep 8
Shot '10-world-loaded.png'
if($ws.AppActivate($game.Id)){$ws.SendKeys('w');Start-Sleep 1}
Shot '11-movement-attempt.png'
@'
import sqlite3,pathlib,json,os
p=pathlib.Path(os.environ['SHAIYA_OFFLINE_SLOT'])/'world.sqlite'
with sqlite3.connect(p) as c:
 c.row_factory=sqlite3.Row
 tables=[r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")]
 t=next(n for n in tables if n.lower()=='characters')
 rows=[dict(r) for r in c.execute('SELECT * FROM '+t)]
 safe=[{k:r[k] for k in ('Name','Map','PosX','PosY','PosZ','Level','Mode') if k in r} for r in rows]
 pathlib.Path('proof/native-created-characters.json').write_text(json.dumps({'source':'native GUI, no database insertion from test script','characters':safe},indent=2))
'@ | Set-Content native_rows.py
python native_rows.py
