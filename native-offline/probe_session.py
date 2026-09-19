#!/usr/bin/env python3
"""Bounded native-client probe on an isolated CI Windows desktop.
An open error/login window is never treated as playable offline.
"""
import argparse,ctypes,json,os,secrets,subprocess,sys,time,urllib.request,urllib.error
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--client-root',required=True);p.add_argument('--package',required=True);p.add_argument('--proof',required=True);a=p.parse_args()
root=Path(a.client_root).resolve();package=Path(a.package).resolve();proof=Path(a.proof).resolve();proof.mkdir(exist_ok=True)
slot=proof.parent/'private-native-slot';slot.mkdir(exist_ok=True)
token=secrets.token_hex(24);password=secrets.token_hex(16);env=os.environ.copy()
env.update(SHAIYA_OFFLINE_SLOT=str(slot),SHAIYA_OFFLINE_FACTION='light',SHAIYA_OFFLINE_PASSWORD=password,SHAIYA_OFFLINE_TOKEN=token,ASPNETCORE_ENVIRONMENT='Production',DOTNET_ENVIRONMENT='Production')
processes=[];handles=[];report={'schema':2,'nativeGameEntered':False,'progressReloaded':False,'nativeLaunched':False,'steps':[]};ok=False

def screenshot(name):
 code='Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $r=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $b=New-Object System.Drawing.Bitmap $r.Width,$r.Height; $g=[System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($r.Location,[System.Drawing.Point]::Empty,$r.Size); $b.Save('+"'"+str(proof/name).replace("'","''")+"'"+', [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose();$b.Dispose()'
 subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',code],timeout=20,check=True,capture_output=True)

def windows(pid):
 output=[];user=ctypes.windll.user32
 callback=ctypes.WINFUNCTYPE(ctypes.c_bool,ctypes.c_void_p,ctypes.c_void_p)
 def collect(hwnd,_):
  process=ctypes.c_ulong();user.GetWindowThreadProcessId(ctypes.c_void_p(hwnd),ctypes.byref(process))
  if process.value==pid:
   length=user.GetWindowTextLengthW(ctypes.c_void_p(hwnd));buf=ctypes.create_unicode_buffer(length+1);user.GetWindowTextW(ctypes.c_void_p(hwnd),buf,length+1)
   if user.IsWindowVisible(ctypes.c_void_p(hwnd)):output.append({'handle':hwnd,'title':buf.value})
  return True
 user.EnumWindows(callback(collect),0);return output

try:
 graphics=Path(__file__).with_name('prepare_graphics_probe.py')
 with (proof/'graphics-setup.txt').open('wb') as out:
  subprocess.run([sys.executable,str(graphics),str(root),str(proof)],stdout=out,stderr=subprocess.STDOUT,timeout=160,check=True)
 for name,http,tcp in [('login',5000,30800),('world',5001,30810)]:
  folder=package/'runtime'/name;exe=folder/('Imgeneus.'+name.title()+'.exe')
  log=(proof/(name+'-session.log')).open('wb');handles.append(log)
  process=subprocess.Popen([str(exe)],cwd=folder,env=env,stdout=log,stderr=subprocess.STDOUT);processes.append(process)
  deadline=time.monotonic()+100
  while time.monotonic()<deadline:
   if process.poll() is not None:raise RuntimeError(name+' exited at boot: '+str(process.returncode))
   try:
    req=urllib.request.Request(f'http://127.0.0.1:{http}/offline/status',headers={'Authorization':'Bearer '+token})
    with urllib.request.urlopen(req,timeout=2) as response:data=json.load(response)
    if data.get('ready') is not True:raise RuntimeError('Bad readiness response')
    import socket
    with socket.create_connection(('127.0.0.1',tcp),timeout=2):pass
    report['steps'].append(name+' listening');break
   except (OSError,ValueError):time.sleep(1)
  else:raise RuntimeError(name+' readiness timeout')
 game=subprocess.Popen([str(root/'game.exe'),'start','127.0.0.1','localplayer:'+password],cwd=root,env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);processes.append(game);report['nativeLaunched']=True
 for i in range(3):
  time.sleep(12);visible=windows(game.pid);report.setdefault('windows',[]).append({'t':12*(i+1),'exitCode':game.poll(),'visible':visible});screenshot('client-stage-'+str(i)+'.png')
  if any('error' in w['title'].lower() for w in visible):raise RuntimeError('Native error dialog detected; client gate failed')
  if game.poll() is not None:break
 report['steps'].append('native client launch inspected')
 report['gate']='NATIVE_SESSION_REQUIRES_INTERACTIVE_VALIDATION'
 ok=game.poll() is None and any(w['title']=='Shaiya' for w in windows(game.pid))
except Exception as error:report['error']=str(error)
finally:
 for process in reversed(processes):
  if process.poll() is None:
   process.terminate()
   try:process.wait(timeout=15)
   except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
 for handle in handles:handle.close()
 for path in proof.glob('*-session.log'):
  text=path.read_text(errors='replace');path.write_text(text.replace(password,'<session-secret>').replace(token,'<session-token>'),encoding='utf-8')
 report['launchGatePassed']=ok;(proof/'native-session.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
 print(json.dumps(report,indent=2))
 if not ok:raise SystemExit(1)
