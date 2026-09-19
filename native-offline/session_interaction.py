"""Bounded interaction with the owned reference-client window in isolated CI.
Capture state for review; never claim gameplay from a successful process start.
"""
import ctypes, os, time
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
    click(.445,.855);time.sleep(15);screenshot('after-server-enter.png')
    click(.79,.39);time.sleep(1);screenshot('faction-highlight.png')
    click(.933,.948)
    for i in range(3):
        time.sleep(15)
        if game.poll() is not None:raise RuntimeError('Client exited while loading character selection.')
        visible=windows(game.pid)
        if any('error' in w['title'].lower() for w in visible):raise RuntimeError('Native error dialog during character load: '+repr(visible))
        screenshot('character-loading-'+str(i)+'.png')
    click(.146,.893);time.sleep(10);screenshot('create-character-form.png')
    report['steps'].append('Opened Create Character using the inspected reference-client selection layout')
    report['characterSelectionObservedByAutomation']=False
    report['gate']='CHARACTER_CREATION_FORM_REQUIRES_REVIEW'
