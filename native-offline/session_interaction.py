"""Bounded interaction with the owned reference-client window in isolated CI.
Screenshots and private SQLite observations, never inferred gameplay success.
"""
import ctypes, os, time, sqlite3, json
from pathlib import Path
from ctypes import wintypes

def advance(game, windows, screenshot, report):
    if os.environ.get('GITHUB_ACTIONS')!='true':raise RuntimeError('Isolated CI only.')
    user=ctypes.windll.user32
    candidates=[w for w in windows(game.pid) if w['title']=='Shaiya']
    if len(candidates)!=1:raise RuntimeError('Expected one owned client window.')
    hwnd=wintypes.HWND(candidates[0]['handle']);rect=wintypes.RECT()
    if not user.GetClientRect(hwnd,ctypes.byref(rect)):raise RuntimeError('No client rectangle')
    def click(x,y):
        if game.poll() is not None:raise RuntimeError('Native client exited.')
        user.SetForegroundWindow(hwnd);time.sleep(.2)
        point=wintypes.POINT(round((rect.right-rect.left)*x),round((rect.bottom-rect.top)*y))
        if not user.ClientToScreen(hwnd,ctypes.byref(point)):raise RuntimeError('Coordinate conversion failed')
        user.SetCursorPos(point.x,point.y);user.mouse_event(2,0,0,0,0);time.sleep(.1);user.mouse_event(4,0,0,0,0)
    def key(vk):
        user.SetForegroundWindow(hwnd);user.keybd_event(vk,0,0,0);time.sleep(.1);user.keybd_event(vk,0,2,0)
    click(.445,.855);time.sleep(15);screenshot('after-server-enter.png')
    click(.79,.39);time.sleep(1);click(.933,.948)
    time.sleep(45);screenshot('character-selection.png')
    if any('error' in w['title'].lower() for w in windows(game.pid)):raise RuntimeError('Native error before character creation')
    click(.146,.893);time.sleep(10);screenshot('create-character-form.png')
    click(.12,.48)
    for char in 'StudioQA':
        user.PostMessageW(hwnd,0x102,ord(char),0);time.sleep(.12)
    screenshot('creation-name-entered.png')
    click(.266,.48);time.sleep(2);screenshot('creation-name-check.png');key(0x0D);time.sleep(1)
    click(.942,.96);time.sleep(8);screenshot('creation-submitted.png');key(0x0D);time.sleep(3)
    click(.70,.922);time.sleep(30);screenshot('after-game-start.png')
    report['steps'].append('Submitted StudioQA in the inspected native form, requested Game Start and captured result')
    report['characterSelectionObservedByAutomation']=False
    report['gate']='CHARACTER_SUBMISSION_AND_WORLD_CAPTURE_REQUIRES_REVIEW'
    # Test-created row only; never read or expose the users database or secrets.
    private=Path('private-native-slot/world.sqlite').resolve()
    if private.exists():
        with sqlite3.connect('file:'+private.as_posix()+'?mode=ro',uri=True) as db:
            names=[x[0] for x in db.execute("SELECT name FROM sqlite_master WHERE type='table'")]
            if 'characters' in names:
                columns=[x[1] for x in db.execute('PRAGMA table_info(characters)')]
                allowed=[x for x in ['Name','Level','Map','PosX','PosY','PosZ','Gold'] if x in columns]
                if allowed:
                    query='SELECT '+','.join('"'+x+'"' for x in allowed)+' FROM characters LIMIT 3'
                    report['testCharacters']=[dict(zip(allowed,row)) for row in db.execute(query)]
