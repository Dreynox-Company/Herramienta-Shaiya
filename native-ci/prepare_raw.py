"""Extract the pinned public reference SAH/SAF for direct-DATA native QA.
No uploaded user assets are read or uploaded by this CI utility.
Layout: Parsec/Shaiya/Data/{Sah,SFolder,SFile}.cs at the pinned reference.
"""
import pathlib,struct,sys,json,time
base=pathlib.Path(sys.argv[1]).resolve().parent
index=(base/'data.sah').read_bytes();pos=51;entries=[]
def read(fmt):
 global pos
 s=struct.Struct('<'+fmt)
 if pos+s.size>len(index):raise ValueError('Truncated SAH')
 v=s.unpack_from(index,pos);pos+=s.size
 return v[0] if len(v)==1 else v
def text():
 global pos
 n=read('i')
 if not 0<=n<=1024 or pos+n>len(index):raise ValueError('Invalid SAH name')
 v=index[pos:pos+n].split(b'\0')[0].decode('cp1252');pos+=n
 if '/' in v or '\\' in v or ':' in v or v in ('.','..'):raise ValueError('Unsafe SAH name')
 return v
def folder(parent,depth=0):
 if depth>64:raise ValueError('SAH hierarchy too deep')
 name=text();parts=parent+([name] if name else [])
 nf=read('i')
 if not 0<=nf<=100000:raise ValueError('Invalid file count')
 for _ in range(nf):
  name=text();offset,size,version=read('qii')
  if offset<0 or size<0:raise ValueError('Invalid SAF span')
  entries.append((parts+[name],offset,size))
 nd=read('i')
 if not 0<=nd<=10000:raise ValueError('Invalid folder count')
 for _ in range(nd):folder(parts,depth+1)
folder([])
assert entries
out=base/'data';out.mkdir(exist_ok=True);size=(base/'data.saf').stat().st_size;total=0
with (base/'data.saf').open('rb') as source:
 for parts,offset,length in entries:
  if parts and parts[0].lower()=='data':parts=parts[1:]
  if not parts or offset+length>size:raise ValueError('Out of range SAF entry')
  p=out.joinpath(*parts);p.parent.mkdir(parents=True,exist_ok=True)
  source.seek(offset);remaining=length
  with p.open('xb') as f:
   while remaining:
    chunk=source.read(min(1024*1024,remaining))
    if not chunk:raise ValueError('Truncated SAF')
    f.write(chunk);remaining-=len(chunk)
  total+=length
(base/'gsconfig.cfg').write_text('[framework]\nIP=127.0.0.1\nSAH=false\n\n[gsCommon]\nLogDefaultListener=1\nLogLevel=3\n')
# Rename the archive index so an accidental fallback cannot pass the test.
(base/'data.sah').rename(base/'data.sah.not-used-by-raw-test')
pathlib.Path('proof').mkdir(parents=True,exist_ok=True)
pathlib.Path('proof/raw-data.json').write_text(json.dumps({'files':len(entries),'bytes':total,'mode':'original native direct DATA reader, SAH=false','archiveFallbackAvailable':False},indent=2))
print('Raw public DATA prepared:',len(entries),'files',total,'bytes')
