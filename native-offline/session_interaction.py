"""Bounded UI interaction on the public reference client in isolated CI only.
Does not infer full gameplay from a visible window. Coordinates are normalized
against the verified 1024x768 reference capture, never an arbitrary user app.
"""
import ctypes, os, time
from ctypes import wintypes

def advance(game, windows, screenshot, report):
    if os.environ.get('GITHUB_ACTIONS')!='true':
        raise RuntimeError('Native UI probe is restricted to its isolated runner.')
    user=ctypes.windll.user32
    candidates=[w for w in windows(game.pid) if w['title']=='Shaiya']
    if len(candidates)!=1:raise RuntimeError('Expected exactly one native client window.')
    hwnd=wintypes.HWND(candidates[0]['handle'])
    rect=wintypes.RECT()
    if not user.GetClientRect(hwnd,ctypes.byref(rect)):raise RuntimeError('No client rectangle')
    user.SetForegroundWindow(hwnd);time.sleep(.3)
    # The actual previous screenshot shows Select Server and Partida local.
    point=wintypes.POINT(round((rect.right-rect.left)*.445),round((rect.bottom-rect.top)*.855))
    if not user.ClientToScreen(hwnd,ctypes.byref(point)):raise RuntimeError('No client coordinates')
    user.SetCursorPos(point.x,point.y);user.mouse_event(2,0,0,0,0);time.sleep(.08);user.mouse_event(4,0,0,0,0)
    report['steps'].append('Pressed Enter on the authenticated local-server selection screen')
    for i in range(2):
        time.sleep(10)
        screenshot('after-server-enter-'+str(i)+'.png')
        if game.poll() is not None:raise RuntimeError('Native client exited after server selection.')
    report['characterSelectionObservedByAutomation']=False
    report['gate']='SERVER_SELECTION_ADVANCED_CAPTURE_REQUIRES_REVIEW'
