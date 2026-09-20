"""Extend the public Windows probe with the verified native argv contract.
No private uploaded client/assets are accessed by this test.
"""
import json,time,traceback
import windows_probe as q
OriginalPopen=q.subprocess.Popen

def native_popen(args,*pos,**kwargs):
 if isinstance(args,list) and args and str(args[0]).endswith('game.local.exe'):
  secret=kwargs['env']['SHAIYA_OFFLINE_PASSWORD']
  args=[args[0],'start','127.0.0.1','localplayer:'+secret]
  q.REPORT['native_argument_contract']='start + loopback IP + local OAuth credential; secret not recorded'
 return OriginalPopen(args,*pos,**kwargs)

q.subprocess.Popen=native_popen
try:
 q.run()
 if q.PROCESSES and q.PROCESSES[-1].poll() is None:
  q.stage('Native process is still alive; testing initial Enter interaction only')
  candidates=[w for w in q.windows() if w['pid']==q.PROCESSES[-1].pid]
  if candidates:q.USER.SetForegroundWindow(candidates[0]['hwnd'])
  q.key(13);time.sleep(15);q.snap('04-native-enter')
  q.REPORT['native_exit_code']=q.PROCESSES[-1].poll()
except Exception as e:
 q.REPORT['error']=str(e);q.REPORT['traceback']=traceback.format_exc();print(traceback.format_exc(),flush=True);q.snap('failure')
finally:
 q.save()
 for p in reversed(q.PROCESSES):
  if p.poll() is None:
   try:p.terminate();p.wait(timeout=5)
   except Exception:p.kill()
