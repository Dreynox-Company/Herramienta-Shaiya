#!/usr/bin/env python3
"""Isolated CI diagnostic. Never installs a DLL into system directories."""
from pathlib import Path
import os,re,subprocess,sys
root=Path(sys.argv[1]).resolve();proof=Path(sys.argv[2]).resolve();proof.mkdir(exist_ok=True)
if os.environ.get('GITHUB_ACTIONS')!='true':raise SystemExit('This diagnostic only runs in the isolated CI job.')
config=root/'config.ini';s=config.read_text(encoding='cp1252') if config.exists() else '[VIDEO]\n'
for key,value in {'FULLSCREEN':'FALSE','SIZE_X':'1024','SIZE_Y':'768','COLOR':'32','SHADOW':'FALSE','GLOW_LEVEL':'0','TEXTURE':'LOW'}.items():
 pattern=r'(?im)^'+key+r'=.*$'
 if re.search(pattern,s):s=re.sub(pattern,key+'='+value,s)
 else:s=s.replace('[VIDEO]','[VIDEO]\n'+key+'='+value)
config.write_text(s,encoding='cp1252')
cpp=Path(__file__).with_name('d3d9_probe.cpp').resolve()
vswhere=Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
vs=subprocess.check_output([str(vswhere),'-latest','-products','*','-property','installationPath'],text=True).strip();vc=Path(vs)/'VC/Auxiliary/Build/vcvars32.bat'
exports=proof/'d3d9.def';exports.write_text('LIBRARY d3d9\nEXPORTS\nDirect3DCreate9=_Direct3DCreate9@4\n')
out=root/'d3d9.dll'
if out.exists():raise RuntimeError('Refusing to overwrite an existing client graphics wrapper.')
batch=proof/'build-d3d-trace.cmd';batch.write_text('@echo off\ncall "'+str(vc)+'"\nif errorlevel 1 exit /b %errorlevel%\ncl /nologo /EHsc /MT /O2 /std:c++17 /LD "'+str(cpp)+'" /Fe:"'+str(out)+'" /link /DEF:"'+str(exports)+'"\n')
with (proof/'graphics-build.txt').open('wb') as log:subprocess.run(['cmd','/c',str(batch)],cwd=proof,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=100)
# Link only our trace output back to the artifact folder. The client executable,
# game resources and SQLite private slot are never added to the evidence ZIP.
trace=root/'native-d3d9-trace.txt';trace.touch();os.link(trace,proof/'native-d3d9-trace.txt')
