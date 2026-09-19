#!/usr/bin/env python3
"""Provide a real DirectSound implementation on a CI host without audio devices.
The null output is explicitly limited to CI; audible playback is not claimed.
No Windows system directories or user installations are changed.
"""
from pathlib import Path
import hashlib,json,os,shutil,struct,subprocess,sys,urllib.request,zipfile
ROOT=Path(sys.argv[1]).resolve();PROOF=Path(sys.argv[2]).resolve()
if os.environ.get('GITHUB_ACTIONS')!='true':raise SystemExit('This silent audio probe is restricted to isolated CI.')
PIN='5c65e5fea13474a8bf346627e2944d28fe0c9cb5'
SHA='67a0c4b800bd860c93c04f38caf8cbe4875f9c84700ac430efc451f70e265434'
URL='https://github.com/kcat/openal-soft/releases/download/1.25.2/openal-soft-1.25.2-bin.zip'
work=PROOF.parent/'audio-probe-work';work.mkdir(exist_ok=True)
for name in ['dsound.dll','dsoal-aldrv.dll']:
 if (ROOT/name).exists():raise RuntimeError('Existing client audio wrapper is not overwritten: '+name)
def run(args):
 with (PROOF/'audio-build.log').open('ab') as log:subprocess.run(args,check=True,stdout=log,stderr=subprocess.STDOUT,timeout=240)
source=work/'dsoal';run(['git','clone','--no-checkout','https://github.com/kcat/dsoal.git',str(source)]);run(['git','-C',str(source),'checkout','--detach',PIN])
if subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()!=PIN:raise RuntimeError('Audio source fingerprint mismatch')
run(['cmake','-S',str(source),'-B',str(work/'build'),'-A','Win32','-DDSOAL_UPDATE_BUILD_VERSION=OFF'])
run(['cmake','--build',str(work/'build'),'--config','Release','--parallel','2'])
archive=work/'openal.zip'
with urllib.request.urlopen(URL,timeout=60) as response,archive.open('xb') as out:
 total=0
 while block:=response.read(1024*1024):
  total+=len(block)
  if total>24*1024*1024:raise RuntimeError('Audio archive exceeds expected download size')
  out.write(block)
if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA:raise RuntimeError('OpenAL release digest mismatch')
with zipfile.ZipFile(archive) as z:
 matches=[n for n in z.namelist() if '/Win32/' in n and n.endswith('/soft_oal.dll')]
 if len(matches)!=1:raise RuntimeError('Ambiguous x86 OpenAL library: '+repr(matches))
 body=z.read(matches[0]);pe=struct.unpack_from('<I',body,0x3c)[0]
 if body[:2]!=b'MZ' or body[pe:pe+4]!=b'PE\0\0' or struct.unpack_from('<H',body,pe+4)[0]!=0x14c:raise RuntimeError('OpenAL binary is not Windows x86')
 (ROOT/'dsoal-aldrv.dll').write_bytes(body)
 for n in z.namelist():
  if n.lower().endswith(('/copying','/license')) and z.getinfo(n).file_size<200000:(PROOF/('openal-'+Path(n).name+'.txt')).write_bytes(z.read(n))
built=list((work/'build').rglob('dsound.dll'))
if len(built)!=1:raise RuntimeError('Ambiguous compiled DirectSound library')
shutil.copy2(built[0],ROOT/'dsound.dll');shutil.copy2(source/'LICENSE',PROOF/'dsoal-LICENSE.txt')
(PROOF/'audio-probe.json').write_text(json.dumps({'dsoalCommit':PIN,'openalVersion':'1.25.2','openalArchiveSha256':SHA,'backend':'null','scope':'CI without audio hardware; real API processing, inaudible output','audiblePlaybackVerified':False},indent=2))
print('CI_AUDIO_BACKEND_READY; audible playback not tested')
