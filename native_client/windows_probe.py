"""Private per-run native compatibility probe; publish proof, never game assets."""
from pathlib import Path, PurePosixPath
import ctypes,hashlib,json,os,shutil,socket,struct,subprocess,sys,tarfile,time,urllib.request,secrets,traceback
from ctypes import wintypes as W
from PIL import ImageGrab
from patch_native import patch,EXPECTED
ROOT=Path(os.environ['RUNNER_TEMP'])/'native-public-test'; ROOT.mkdir(exist_ok=True)
CLIENT=ROOT/'client';CLIENT.mkdir(exist_ok=True)
PROOF=Path.cwd()/'native-proof';PROOF.mkdir(exist_ok=True)
REPORT={'public_source':'https://archive.openshaiya.org/api/build/shaiya-ga-ps0032.tar.gz','user_files_uploaded':False,'native_world_entry_verified':False,'stages':[]}
USER=ctypes.WinDLL('user32',use_last_error=True);KERNEL=ctypes.WinDLL('kernel32',use_last_error=True)
USER.SetProcessDPIAware();USER.GetWindowTextW.argtypes=[W.HWND,W.LPWSTR,ctypes.c_int];USER.GetWindowRect.argtypes=[W.HWND,ctypes.POINTER(W.RECT)];USER.IsWindowVisible.argtypes=[W.HWND];USER.SetForegroundWindow.argtypes=[W.HWND]
CALLBACK=ctypes.WINFUNCTYPE(W.BOOL,W.HWND,W.LPARAM)
PROCESSES=[]
def save(): (PROOF/'status.json').write_text(json.dumps(REPORT,indent=2),encoding='utf-8')
def stage(s): REPORT['stages'].append(s);save();print(s,flush=True)
def windows():
 out=[]
 @CALLBACK
 def visit(h,p):
  if USER.IsWindowVisible(h):
   title=ctypes.create_unicode_buffer(512);USER.GetWindowTextW(h,title,512);pid=W.DWORD();USER.GetWindowThreadProcessId(h,ctypes.byref(pid));r=W.RECT();USER.GetWindowRect(h,ctypes.byref(r));out.append({'hwnd':int(h),'pid':pid.value,'title':title.value,'rect':[r.left,r.top,r.right,r.bottom]})
  return True
 USER.EnumWindows(visit,0);return out

def snap(name):
 try:ImageGrab.grab(all_screens=True).save(PROOF/(name+'.png'))
 except Exception as e:REPORT.setdefault('capture_errors',[]).append(str(e))
 REPORT.setdefault('window_states',{})[name]=windows();save()
def click(x,y):
 USER.SetCursorPos(x,y);USER.mouse_event(2,0,0,0,0);USER.mouse_event(4,0,0,0,0);time.sleep(.2)
def key(code):USER.keybd_event(code,0,0,0);USER.keybd_event(code,0,2,0)
def text(s):
 # Send Unicode keyboard messages, without logging credentials.
 class KI(ctypes.Structure):_fields_=[('vk',W.WORD),('scan',W.WORD),('flags',W.DWORD),('time',W.DWORD),('extra',ctypes.c_void_p)]
 class MI(ctypes.Structure):_fields_=[('dx',W.LONG),('dy',W.LONG),('mouseData',W.DWORD),('flags',W.DWORD),('time',W.DWORD),('extra',ctypes.c_void_p)]
 class U(ctypes.Union):_fields_=[('ki',KI),('mi',MI)]
 class I(ctypes.Structure):_anonymous_=['u'];_fields_=[('type',W.DWORD),('u',U)]
 for c in s:
  for flags in [4,6]:
   obj=I(type=1,ki=KI(0,ord(c),flags,0,None));USER.SendInput(1,ctypes.byref(obj),ctypes.sizeof(obj))
 time.sleep(.3)
def get_public():
 total=0;start=time.monotonic();count=0
 with urllib.request.urlopen(REPORT['public_source'],timeout=90) as response:
  with tarfile.open(fileobj=response,mode='r|gz') as tf:
   for m in tf:
    if not m.isfile():continue
    parts=PurePosixPath(m.name.replace('\\','/')).parts
    if not parts or any(x in ('..','') or ':' in x for x in parts) or parts[0]=='/':raise ValueError('Unsafe public archive path')
    total+=m.size;count+=1
    if total>12*1024**3 or time.monotonic()-start>700:raise ValueError('Public inspection size/time bound exceeded')
    target=CLIENT.joinpath(*parts);target.parent.mkdir(parents=True,exist_ok=True)
    with tf.extractfile(m) as inp,target.open('wb') as out:shutil.copyfileobj(inp,out,1024*1024)
 exe=CLIENT/'game.exe'
 if not exe.exists():raise ValueError('Expected game.exe at public archive root')
 digest=hashlib.sha256(exe.read_bytes()).hexdigest();REPORT.update(public_client_sha256=digest,public_archive_unpacked_bytes=total,public_archive_files=count)
 if digest!=EXPECTED:raise ValueError('Public exe does not match user profile; do not execute')
 stage('Independently downloaded public client matches exact fingerprint')
def loose_data():
 sah=CLIENT/'data.sah';saf=CLIENT/'data.saf'
 if (CLIENT/'data'/'Character').is_dir():return
 if not sah.is_file() or not saf.is_file():raise ValueError('Public archive has neither loose data nor SAH/SAF')
 b=sah.read_bytes();offset=51;files=[];total=saf.stat().st_size
 def u32():
  nonlocal offset
  val=struct.unpack_from('<I',b,offset)[0];offset+=4;return val
 def string():
  nonlocal offset
  n=u32()
  if n>4096 or offset+n>len(b):raise ValueError('Invalid SAH string')
  val=b[offset:offset+n].split(b'\0',1)[0].decode('cp1252');offset+=n;return val
 def folder(parent,depth=0):
  nonlocal offset
  if depth>32:raise ValueError('SAH depth limit')
  name=string().replace('\\','/');parts=[x for x in name.split('/') if x]
  if any(x in ('.','..') or ':' in x for x in parts):raise ValueError('Unsafe SAH path')
  here=parent.joinpath(*parts);n=u32()
  if n>100000:raise ValueError('Unsupported SAH file count')
  for _ in range(n):
   name=string();pos=struct.unpack_from('<Q',b,offset)[0];offset+=8;size=u32();version=u32()
   if '/' in name or '\\' in name or name in ('.','..') or ':' in name or pos+size>total:raise ValueError('Invalid SAH file record')
   files.append((here/name,pos,size))
  n=u32()
  if n>10000:raise ValueError('Unsupported SAH folder count')
  for _ in range(n):folder(here,depth+1)
 folder(Path())
 data=CLIENT/'data';data.mkdir(exist_ok=True)
 with saf.open('rb') as f:
  for rel,pos,size in files:
   target=data/rel;target.parent.mkdir(parents=True,exist_ok=True);f.seek(pos)
   with target.open('wb') as out:
    left=size
    while left:
     chunk=f.read(min(left,1048576))
     if not chunk:raise ValueError('Truncated SAF')
     out.write(chunk);left-=len(chunk)
 REPORT['loose_assets_extracted']=len(files);stage('Extracted original public SAH/SAF with bounded native paths')
def health(port,token):
 req=urllib.request.Request(f'http://127.0.0.1:{port}/offline/status',headers={'Authorization':'Bearer '+token})
 try:
  with urllib.request.urlopen(req,timeout=2) as response:return response.status==200
 except Exception:return False

def start_services():
 backend=Path.cwd()/'backend';archives=list(backend.glob('*.tar.zst'))
 if len(archives)!=1:raise ValueError('Expected one self-contained backend archive')
 import zstandard
 with archives[0].open('rb') as f,zstandard.ZstdDecompressor().stream_reader(f) as reader,tarfile.open(fileobj=reader,mode='r|') as tf:tf.extractall(backend,filter='data')
 slot=ROOT/'slot';slot.mkdir(exist_ok=True);secret=secrets.token_hex(8);token=secrets.token_hex(24)
 whitelist=['SystemRoot','WINDIR','SystemDrive','TEMP','TMP','PATH','USERPROFILE','APPDATA','LOCALAPPDATA','COMSPEC','PROGRAMDATA','PROGRAMFILES','PROGRAMFILES(X86)']
 env={k:v for k,v in os.environ.items() if k.upper() in [w.upper() for w in whitelist]}
 env.update(SHAIYA_OFFLINE_SLOT=str(slot),SHAIYA_OFFLINE_PASSWORD=secret,SHAIYA_OFFLINE_TOKEN=token,SHAIYA_OFFLINE_FACTION='light',DOTNET_EnableDiagnostics='0')
 for kind,title,port in [('login','Imgeneus.Login.exe',5000),('world','Imgeneus.World.exe',5001)]:
  f=(PROOF/(kind+'-backend.log')).open('wb');p=subprocess.Popen([str(backend/kind/title)],cwd=backend/kind,env=env,stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW);PROCESSES.append(p);f.close()
  for _ in range(150):
   if p.poll() is not None:raise ValueError(kind+' backend exited '+str(p.returncode))
   if health(port,token):break
   time.sleep(1)
  else:raise ValueError(kind+' backend health timeout')
  stage(kind+' service alive and responding on loopback')
 return env,secret

def run():
 get_public();loose_data();manifest=patch(CLIENT/'game.exe',CLIENT/'game.local.exe');REPORT['patch']=manifest
 (CLIENT/'gsconfig.cfg').write_text('[framework]\nIP=127.0.0.1\nSAH=false\n[gsCommon]\nLogDefaultListener=1\nLogLevel=255\n')
 (CLIENT/'config.ini').write_text('[VIDEO]\nSIZE_X=1024\nSIZE_Y=768\nCOLOR=32\nTEXTURE=LOW\nRANGE=LOW\nWATER=FALSE\nGLOW_LEVEL=0\nGAMMA=2\nSHADOW=FALSE\nCLOAK=FALSE\nHELMET=TRUE\nFULLSCREEN=FALSE\n[LOGIN]\nLANGUAGE=0\nSERVER=0\nNOLTOSITE=FALSE\nID=localplayer\nTEST_IP=ENGLISH\n[INTERFACE]\nLOGIN_ID_SAVE=TRUE\n[SOUND]\nVOL_BGM=0\nVOL_EFFECT=0\nVOL_WORLD=0\nVOICE_CHAR=FALSE\nVOICE_NPC=FALSE\n')
 env,secret=start_services();snap('00-before-native')
 game=subprocess.Popen([str(CLIENT/'game.local.exe'),'start','game'],cwd=CLIENT,env=env);PROCESSES.append(game);REPORT['native_pid']=game.pid
 for n in [1,2,3]:
  time.sleep(12);snap(f'0{n}-native');REPORT['native_exit_code']=game.poll();save()
  if game.poll() is not None:break
 stage('Native launch attempt captured; screenshots require inspection, world entry is not inferred')
 for p in CLIENT.glob('*.log'):
  if p.stat().st_size<20*1024**2:shutil.copy2(p,PROOF/('native-'+p.name))
 for p in CLIENT.glob('*.txt'):
  if p.name.lower() in ('log.txt','error.txt') and p.stat().st_size<1024**2:shutil.copy2(p,PROOF/('native-'+p.name))
if __name__=='__main__':
 try:run()
 except Exception as e:REPORT['error']=str(e);REPORT['traceback']=traceback.format_exc();print(traceback.format_exc(),flush=True);snap('failure')
 finally:
  save()
  for p in reversed(PROCESSES):
   if p.poll() is None:
    try:p.terminate();p.wait(timeout=5)
    except Exception:p.kill()
