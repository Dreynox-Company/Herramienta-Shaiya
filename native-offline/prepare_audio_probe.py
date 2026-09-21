#!/usr/bin/env python3
"""CI-only DirectSound null mixer. Does not patch the game or Windows.
Mixer/buffer behavior is real; inaudible CI output is not an audio quality test.
"""
from pathlib import Path
import hashlib,json,os,shutil,struct,subprocess,sys,urllib.request,zipfile
ROOT=Path(sys.argv[1]).resolve();PROOF=Path(sys.argv[2]).resolve()
if os.environ.get('GITHUB_ACTIONS')!='true':raise SystemExit('Isolated CI only.')
PIN='5c65e5fea13474a8bf346627e2944d28fe0c9cb5'
SHA='67a0c4b800bd860c93c04f38caf8cbe4875f9c84700ac430efc451f70e265434'
URL='https://github.com/kcat/openal-soft/releases/download/1.25.2/openal-soft-1.25.2-bin.zip'
work=PROOF.parent/'audio-probe-work';work.mkdir(exist_ok=True)
for name in ['dsound.dll','dsoal-aldrv.dll']:
 if (ROOT/name).exists():raise RuntimeError('Existing client wrapper refused: '+name)
def run(args):
 with (PROOF/'audio-build.log').open('ab') as log:subprocess.run(args,check=True,stdout=log,stderr=subprocess.STDOUT,timeout=240)
source=work/'dsoal';run(['git','clone','--no-checkout','https://github.com/kcat/dsoal.git',str(source)]);run(['git','-C',str(source),'checkout','--detach',PIN])
if subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()!=PIN:raise RuntimeError('Audio reference mismatch')
changes=[]
def patch(path,before,after):
 p=source/path;s=p.read_text();
 if s.count(before)!=1:raise RuntimeError('Audio adaptation contract changed: '+path)
 s=s.replace(before,after);p.write_text(s);changes.append(path)
# The current DSOAL matches OpenAL devices through MMDevice GUIDs. CI has no
# Windows endpoint even though the real OpenAL null mixer is present. Resolve
# default playback to a private virtual endpoint and open that mixer directly.
patch('src/dsoal.cpp','HRESULT WINAPI GetDeviceID(const GUID &guidSrc, GUID &guidDst) noexcept\n{','HRESULT WINAPI GetDeviceID(const GUID &guidSrc, GUID &guidDst) noexcept\n{\n    if(guidSrc == DSDEVID_DefaultPlayback || guidSrc == DSDEVID_DefaultVoicePlayback) { guidDst = DSDEVID_DefaultPlayback; return DS_OK; }')
patch('src/dsoundoal.cpp','    ComWrapper com;\n    auto device = GetMMDevice(com, eRender, guid);\n    if(auto config = GetSpeakerConfig(device.get()))\n        speakerconf = *config;\n    device = nullptr;','    // CI virtual stereo endpoint; no MMDevice device exists on this runner.\n    speakerconf = DSSPEAKER_STEREO;')
patch('src/dsoundoal.cpp','ALCdevicePtr aldev{alcOpenDevice(drv_name.c_str())};','ALCdevicePtr aldev{alcOpenDevice(nullptr)};')
run(['cmake','-S',str(source),'-B',str(work/'build'),'-A','Win32','-DDSOAL_UPDATE_BUILD_VERSION=OFF'])
run(['cmake','--build',str(work/'build'),'--config','Release','--parallel','2'])
archive=work/'openal.zip'
with urllib.request.urlopen(URL,timeout=60) as response,archive.open('xb') as out:
 total=0
 while block:=response.read(1024*1024):
  total+=len(block)
  if total>24*1024*1024:raise RuntimeError('Audio release download exceeded budget')
  out.write(block)
if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA:raise RuntimeError('OpenAL digest mismatch')
with zipfile.ZipFile(archive) as z:
 matches=[n for n in z.namelist() if '/Win32/' in n and n.endswith('/soft_oal.dll')]
 if len(matches)!=1:raise RuntimeError('Ambiguous x86 OpenAL library')
 body=z.read(matches[0]);pe=struct.unpack_from('<I',body,0x3c)[0]
 if body[:2]!=b'MZ' or body[pe:pe+4]!=b'PE\0\0' or struct.unpack_from('<H',body,pe+4)[0]!=0x14c:raise RuntimeError('Expected x86 PE')
 (ROOT/'dsoal-aldrv.dll').write_bytes(body)
 for n in z.namelist():
  if n.lower().endswith(('/copying','/license')) and z.getinfo(n).file_size<200000:(PROOF/('openal-'+Path(n).name+'.txt')).write_bytes(z.read(n))
built=list((work/'build').rglob('dsound.dll'))
if len(built)!=1:raise RuntimeError('Ambiguous compiled DirectSound library')
shutil.copy2(built[0],ROOT/'dsound.dll');shutil.copy2(source/'LICENSE',PROOF/'dsoal-LICENSE.txt')
with zipfile.ZipFile(PROOF/'dsoal-ci-corresponding-source.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in source.rglob('*'):
  if p.is_file() and '.git' not in p.relative_to(source).parts:z.write(p,p.relative_to(source).as_posix())
(PROOF/'audio-probe.json').write_text(json.dumps({'dsoalCommit':PIN,'modifiedSourceFiles':changes,'openalVersion':'1.25.2','openalArchiveSha256':SHA,'backend':'null','scope':'CI private virtual endpoint using real OpenAL mixing. Not installed into a user client.','audiblePlaybackVerified':False},indent=2))
print('CI_AUDIO_MIXER_READY; audible playback not tested')
