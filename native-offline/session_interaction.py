"""Bounded interaction with our own public-reference CI client window only.
Positions come from inspected screenshots; captures do not prove full gameplay.
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
        p=wintypes.POINT(round((rect.right-rect.left)*x),round((rect.bottom-rect.top)*y))
        if not user.ClientToScreen(hwnd,ctypes.byref(p)):raise RuntimeError('Coordinate conversion failed')
        user.SetCursorPos(p.x,p.y);user.mouse_event(2,0,0,0,0);time.sleep(.1);user.mouse_event(4,0,0,0,0)
    click(.445,.855);time.sleep(15);screenshot('after-server-enter.png')
    report['steps'].append('Local server selected; original client reached faction screen in the previous inspected run')
    click(.79,.39);time.sleep(1);screenshot('faction-highlight.png')
    click(.933,.948);time.sleep(8);screenshot('after-faction-next.png')
    report['steps'].append('Selected Alliance of Light and pressed Next on the verified faction layout')
    report['characterSelectionObservedByAutomation']=False
    report['gate']='FACTION_SELECTION_ADVANCED_CAPTURE_REQUIRES_REVIEW'
