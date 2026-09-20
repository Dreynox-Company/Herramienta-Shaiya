# Coordinates come from captured native UI states. No character is seeded in SQLite.
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
Click 0.20 0.10
Start-Sleep 3
Shot '08-character-selected.png'
Click 0.70 0.919
Start-Sleep 20
Shot '09-world-entry.png'
Start-Sleep 8
Shot '10-world-loaded.png'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeKeys {
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
}
'@
if($ws.AppActivate($game.Id)){
  [NativeKeys]::keybd_event(0x57,0x11,0,[UIntPtr]::Zero)
  Start-Sleep 2
  [NativeKeys]::keybd_event(0x57,0x11,2,[UIntPtr]::Zero)
}
Start-Sleep 4
Shot '11-after-movement.png'
$game.Refresh()
if(!$game.HasExited){$game.CloseMainWindow() | Out-Null}
Start-Sleep 4
$game.Refresh()
if(!$game.HasExited){if($ws.AppActivate($game.Id)){$ws.SendKeys('{ENTER}')};Start-Sleep 5}
$game.Refresh();$normalExit=$game.HasExited
if(!$normalExit){Shot '12-before-forced-client-disconnect.png';Stop-Process -Id $game.Id -Force}
Start-Sleep 16
@{normalWindowClose=$normalExit;serverSaveWaitSeconds=16;servicesKeptRunningForSave=$true}|ConvertTo-Json|Set-Content proof/disconnect-save.json
@'
import sqlite3,pathlib,json,os
p=pathlib.Path(os.environ['SHAIYA_OFFLINE_SLOT'])/'world.sqlite'
with sqlite3.connect(p) as c:
 c.row_factory=sqlite3.Row
 assert c.execute('PRAGMA quick_check').fetchone()[0]=='ok'
 tables=[r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")]
 t=next(n for n in tables if n.lower()=='characters')
 rows=[dict(r) for r in c.execute('SELECT * FROM '+t)]
 safe=[{k:r[k] for k in ('Name','Map','PosX','PosY','PosZ','Level','Mode') if k in r} for r in rows]
 pathlib.Path('proof/native-created-characters.json').write_text(json.dumps({'source':'native GUI and keyboard, no insertion or updates from test script','sqliteQuickCheck':'ok','characters':safe},indent=2))
 assert any(r['Name']=='DreynoxLocal' for r in rows),'Native character was not created'
'@ | Set-Content native_rows.py
python native_rows.py
if($LASTEXITCODE -ne 0){throw 'Native character persistence failed'}
