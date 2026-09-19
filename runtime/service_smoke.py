#!/usr/bin/env python3
"""Run real reference services on loopback; no native client execution claim."""
from pathlib import Path
import json, os, secrets, socket, subprocess, sys, tempfile, time, urllib.request, urllib.error
root=Path(sys.argv[1]).resolve(); output=Path(sys.argv[2]).resolve();output.mkdir(parents=True,exist_ok=True)
checks=[]; processes=[]; logs=[]
with tempfile.TemporaryDirectory(prefix='shaiya-runtime-smoke-') as slot:
 env=os.environ.copy();token=secrets.token_hex(24)
 env.update(SHAIYA_OFFLINE_SLOT=slot,SHAIYA_OFFLINE_FACTION='light',SHAIYA_OFFLINE_PASSWORD=secrets.token_hex(16),SHAIYA_OFFLINE_TOKEN=token,DOTNET_ENVIRONMENT='Production',ASPNETCORE_ENVIRONMENT='Production')
 try:
  for name,port,tcp in [('Login',5000,30800),('World',5001,30810)]:
   base=root/'src'/('Imgeneus.'+name);dll=base/'bin/SHAIYA_ps0032/net10.0'/('Imgeneus.'+name+'.dll')
   if not dll.exists():raise RuntimeError('Compiled service missing: '+str(dll))
   log=(output/(name.lower()+'-boot.log')).open('wb');logs.append(log)
   process=subprocess.Popen(['dotnet',str(dll)],cwd=base,env=env,stdout=log,stderr=subprocess.STDOUT);processes.append(process)
   deadline=time.monotonic()+100
   while time.monotonic()<deadline:
    if process.poll() is not None:raise RuntimeError(name+' exited during startup with code '+str(process.returncode))
    try:
     request=urllib.request.Request(f'http://127.0.0.1:{port}/offline/status',headers={'Authorization':'Bearer '+token})
     with urllib.request.urlopen(request,timeout=2) as response:result=json.load(response)
     if result.get('ready') is not True:raise RuntimeError('Unexpected readiness payload')
     with socket.create_connection(('127.0.0.1',tcp),timeout=2):pass
     checks.append(name+' HTTP and native TCP available on loopback');break
    except (OSError,ValueError):time.sleep(1)
   else:raise RuntimeError(name+' startup exceeded 100 seconds')
   try:urllib.request.urlopen(f'http://127.0.0.1:{port}/offline/status',timeout=3);raise RuntimeError('Unprotected status endpoint')
   except urllib.error.HTTPError as e:
    if e.code!=401:raise
    checks.append(name+' rejects missing session token')
   request=urllib.request.Request(f'http://127.0.0.1:{port}/offline/status',headers={'Authorization':'Bearer '+token,'Origin':'https://untrusted.invalid'})
   try:urllib.request.urlopen(request,timeout=3);raise RuntimeError('Browser origin was accepted')
   except urllib.error.HTTPError as e:
    if e.code!=403:raise
    checks.append(name+' rejects browser-origin calls')
  time.sleep(3)
  if any(p.poll() is not None for p in processes):raise RuntimeError('Service stopped after readiness')
  for database in ['world.sqlite','users.sqlite']:
   if not (Path(slot)/database).exists():raise RuntimeError('Missing persistent database '+database)
  checks.append('Both per-slot databases exist and services remain alive')
  (output/'service-smoke.json').write_text(json.dumps({'status':'passed','scope':'real backend services with upstream reference definitions; native client not executed','checks':checks},indent=2))
  print('SERVICE_SMOKE_PASSED',len(checks))
 finally:
  for p in reversed(processes):
   if p.poll() is None:
    p.terminate()
    try:p.wait(timeout=20)
    except subprocess.TimeoutExpired:p.kill();p.wait(timeout=5)
  for log in logs:log.close()
