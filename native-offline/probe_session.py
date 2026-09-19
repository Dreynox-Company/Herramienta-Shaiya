#!/usr/bin/env python3
"""Bounded native-client probe; error dialogs never count as gameplay."""
import argparse,ctypes,json,os,re,secrets,subprocess,sys,time,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--client-root',required=True);p.add_argument('--package',required=True);p.add_argument('--proof',required=True);a=p.parse_args()
root=Path(a.client_root).resolve();package=Path(a.package).resolve();proof=Path(a.proof).resolve();proof.mkdir(exist_ok=True)
slot=proof.parent/'private-native-slot';slot.mkdir(exist_ok=True)
token=secrets.token_hex(24);password=secrets.token_hex(16);env=os.environ.copy()
env.update(SHAIYA_OFFLINE_SLOT=str(slot),SHAIYA_OFFLINE_FACTION='light',SHAIYA_OFFLINE_PASSWORD=password,SHAIYA_OFFLINE_TOKEN=token,ASPNETCORE_ENVIRONMENT='Production',DOTNET_ENVIRONMENT='Production',ALSOFT_DRIVERS='null',DSOAL_LOGLEVEL='2',DSOAL_LOGFILE=str(proof/'audio-session.log'))
processes=[];handles=[];report={'schema':3,'nativeGameEntered':False,'progressReloaded':False,'nativeLaunched':False,'audioOutput':'CI null backend','steps':[]};ok=False
user=ctypes.windll.user32;callback=ctypes.WINFUNCTYPE(ctypes.c_bool,ctypes.c_void_p,ctypes.c_void_p)
def text(hwnd):
 n=user.GetWindowTextLengthW(ctypes.c_void_p(hwnd));buf=ctypes.create_unicode_buffer(n+1);user.GetWindowTextW(ctypes.c_void_p(hwnd),buf,n+1);return buf.value

def screenshot(name):
 code='Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $r=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $b=New-Object System.Drawing.Bitmap $r.Width,$r.Height; $g=[System.Drawing.Graphics]::FromImage($b); $g.CopyFromScreen($r.Location,[System.Drawing.Point]::Empty,$r.Size); $b.Save('+"'"+str(proof/name).replace("'","''")+"'"+', [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose();$b.Dispose()'
 subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',code],timeout=20,check=True,capture_output=True)
def windows(pid):
 output=[]
 def collect(hwnd,_):
  process=ctypes.c_ulong();user.GetWindowThreadProcessId(ctypes.c_void_p(hwnd),ctypes.byref(process))
  if process.value==pid and user.IsWindowVisible(ctypes.c_void_p(hwnd)):
   children=[]
   def child(h,_):
    s=text(h)
    if s:children.append(s)
    return True
   user.EnumChildWindows(ctypes.c_void_p(hwnd),callback(child),0)
   output.append({'handle':hwnd,'title':text(hwnd),'children':children})
  return True
 user.EnumWindows(callback(collect),0);return output
try:
 config=root/'config.ini';s=config.read_text(encoding='cp1252')
 for key,value in {'FULLSCREEN':'FALSE','SIZE_X':'1024','SIZE_Y':'768','COLOR':'32'}.items():
  pattern=r'(?im)^'+key+r'=.*$'
  if re.search(pattern,s):s=re.sub(pattern,key+'='+value,s)
  else:s=s.replace('[VIDEO]','[VIDEO]\n'+key+'='+value)
 config.write_text(s,encoding='cp1252')
 subprocess.run([sys.executable,str(Path(__file__).with_name('prepare_audio_probe.py')),str(root),str(proof)],timeout=480,check=True)
 for name,http,tcp in [('login',5000,30800),('world',5001,30810)]:
  folder=package/'runtime'/name;exe=folder/('Imgeneus.'+name.title()+'.exe');log=(proof/(name+'-session.log')).open('wb');handles.append(log)
  process=subprocess.Popen([str(exe)],cwd=folder,env=env,stdout=log,stderr=subprocess.STDOUT);processes.append(process);deadline=time.monotonic()+100
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
  time.sleep(15);visible=windows(game.pid);report.setdefault('windows',[]).append({'t':15*(i+1),'exitCode':game.poll(),'visible':visible});screenshot('client-stage-'+str(i)+'.png')
  if any('error' in w['title'].lower() for w in visible):raise RuntimeError('Native error dialog: '+repr(visible))
  if game.poll() is not None:break
 report['gate']='NATIVE_SESSION_REQUIRES_INTERACTIVE_VALIDATION';ok=game.poll() is None and any(w['title']=='Shaiya' for w in windows(game.pid))
except Exception as error:report['error']=str(error)
finally:
 for process in reversed(processes):
  if process.poll() is None:
   process.terminate()
   try:process.wait(timeout=15)
   except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
 for handle in handles:handle.close()
 for path in proof.glob('*-session.log'):
  s=path.read_text(errors='replace');path.write_text(s.replace(password,'<session-secret>').replace(token,'<session-token>'),encoding='utf-8')
 report['launchGatePassed']=ok;(proof/'native-session.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2))
 if not ok:raise SystemExit(1)
