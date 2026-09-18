"""Synthetic 3DC/ANI/MLT/MON/WLD fixtures. No proprietary game assets."""
from pathlib import Path
import struct,sys
root=Path(sys.argv[1])
u=lambda n:struct.pack('<I',n)
i=lambda n:struct.pack('<i',n)
f=lambda *v:struct.pack('<'+'f'*len(v),*v)
s=lambda t:u(len(t)+1)+t.encode()+b'\0'
fixed=lambda t:t.encode()+bytes(256-len(t))
identity=[1 if k%5==0 else 0 for k in range(16)]
def write(path,data):
 p=root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
def geometry(sx=1,sy=1,sz=1):
 vertices=[];indices=[]
 def box(x,y,z,w,h,d):
  corners=[((x+a*w/2)*sx,(y+b*h/2)*sy,(z+c*d/2)*sz) for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
  base=len(vertices)
  for n,p in enumerate(corners):vertices.append((p,(n%2,(n//2)%2)))
  for a,b,c,d in [(0,1,2,3),(4,7,6,5),(0,4,5,1),(3,2,6,7),(0,3,7,4),(1,5,6,2)]:indices.extend([base+a,base+b,base+c,base+a,base+c,base+d])
 box(0,1.35,0,.65,.7,.35);box(0,1.94,0,.38,.4,.38)
 for sign in [-1,1]:box(sign*.2,.55,0,.24,1,.28);box(sign*.51,1.25,0,.22,.8,.25)
 return vertices,indices
verts,inds=geometry()
def mesh(vertices,indices):
 return u(0)+u(1)+f(*identity)+u(len(vertices))+b''.join(f(*p)+f(1)+bytes(4)+f(0,1,0)+f(*uv) for p,uv in vertices)+u(len(indices)//3)+struct.pack('<'+'H'*len(indices),*indices)
def texture(rgb):
 h=bytearray(128);struct.pack_into('<4s7I',h,0,b'DDS ',124,0x100f,4,4,16,0,1);struct.pack_into('<8I',h,76,32,0x41,0,32,0xff,0xff00,0xff0000,0xff000000)
 return h+bytes([*rgb,255])*16
def animation(bob):
 return i(0)+i(30)+struct.pack('<H',1)+i(-1)+f(*identity)+u(1)+i(0)+f(0,0,0,1)+u(3)+i(0)+f(0,0,0)+i(15)+f(0,bob,0)+i(30)+f(0,0,0)
def selected_boxes(boxes):
 v=[]; idx=[]
 for box in boxes:
  base=len(v); v.extend(verts[box*8:box*8+8]);idx.extend(base+j-box*8 for j in inds[box*36:box*36+36])
 return v,idx
upper_v,upper_i=selected_boxes([0,1,3,5]);lower_v,lower_i=selected_boxes([2,4])
write('Character/Human/3dc/humf_lower000.3dc',mesh(lower_v,lower_i))
write('Character/Human/dds/humf_lower000.dds',texture((95,168,222)))
write('Character/Human/humf_lower.mlt',b'MLT'+u(1)+s('humf_lower000.3dc')+u(1)+s('humf_lower000.dds')+u(1)+u(0)+u(0)+u(1))
write('Character/Human/3dc/humf_upper000.3dc',mesh(upper_v,upper_i));write('Character/Human/dds/humf_upper000.dds',texture((95,168,222)))
write('Character/Human/humf_upper.mlt',b'MLT'+u(1)+s('humf_upper000.3dc')+u(1)+s('humf_upper000.dds')+u(1)+u(0)+u(0)+u(1))
for name,bob in [('000_normal',0),('001_walk',.02),('002_run',.08),('006_swnormal',.3),('007_swim',.5),('008_jump',.09),('020_veh_run',.05),('021_veh_br',0),('034_onready',0),('035_onattack01',.15),('040_onrun',.11),('048_spready',0),('049_spattack01',.2),('054_sprun',.14),('039_ondamage',.04),('009_die',.03)]:write('Character/Human/ani/humf_'+name+'.ani',animation(bob))
def creature_record(name):
 anim=[name+'_walk.ani',name+'_run.ani',name+'_attack.ani','','',name+'_idle.ani',name+'_idle.ani',name+'_idle.ani',name+'_idle.ani']
 return s(name)+bytes(1)+b''.join(s(a) for a in anim)+b''.join(s('') for _ in range(8))+u(1)+s(name+'.3dc')+s(name+'.dds')+f(2)+u(0)
for folder,names in [('Vehicle',['test_mount_a','test_mount_b']),('Monster',['test_enemy']),('Character/Wing',['test_wing'])]:
 for j,name in enumerate(names):
  a,b=geometry(1.6 if folder=='Vehicle' else 1,.55+j*.3 if folder=='Vehicle' else .6,2 if folder=='Vehicle' else .3)
  write(folder+'/3dc/'+name+'.3dc',mesh(a,b));write(folder+'/dds/'+name+'.dds',texture((210,125,85) if folder=='Vehicle' else (175,135,235)))
  for suffix,bob in [('walk',.02),('run',.06),('idle',0),('attack',.1)]:write(folder+'/ani/'+name+'_'+suffix+'.ani',animation(bob))
 write(folder+'/Fixture.MON',b'MO2'+u(len(names))+b''.join(creature_record(n) for n in names))
# Synthetic exterior, using the same wire formats as the production parser.
write('Terrain/fixture.dds',texture((88,119,85)))
size=128;n=(size//2+1)**2
world=b'FLD\0'+u(size)+struct.pack('<'+'H'*n,*([10000]*n))+bytes(n)+u(1)+fixed('fixture.dds')+f(4)+fixed('')+fixed('')+bytes(7*8)
write('world/fixture.wld',world)
# Original-to-this-test sky cube, not a copied Shaiya sky.
pts=[(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]
tri=[0,1,2,0,2,3,4,7,6,4,6,5,0,4,5,0,5,1,3,2,6,3,6,7,0,3,7,0,7,4,1,5,6,1,6,2]
sky=s('fixture.dds')+u(8)+b''.join(f(*p)+f(0,1,0)+f(k%2,(k//2)%2) for k,p in enumerate(pts))+u(len(tri)//3)+struct.pack('<'+'H'*len(tri),*tri)
write('Sky/sky.3do',sky+bytes(8));write('Sky/fixture.dds',texture((100,157,219)))
# Test the exact 3DO zero footer and an opaque IT2 material, without game assets.
sword=s('fixture_sword.dds')+u(8)+b''.join(f(x*.065,(y+1)*.45,z*.035)+f(0,1,0)+f(k%2,(k//2)%2) for k,(x,y,z) in enumerate(pts))+u(len(tri)//3)+struct.pack('<'+'H'*len(tri),*tri)+bytes(8)
write('Item/3do/fixture_sword.3do',sword)
write('Item/dds/fixture_sword.dds',texture((225,215,160)))
attachment=i(0)+f(.5,1.15,0)+f(0,0,0,1)
empty=i(0)+f(0,0,0)+f(0,0,0,1)
itm=b'IT2'+u(1)+s('fixture_sword.3do')+u(1)+s('fixture_sword.dds')+u(1)
itm+=u(0)+u(0)+i(-1)+i(0)+i(0)+i(0)+(attachment+empty)*16
write('Item/01.itm',itm)
print('Synthetic fixture prepared:',root)

# Shield + spear exercise independent offhand, class restrictions and run family.
for typ,name,sx,sy,attach in [(19,'fixture_shield',.28,.32,i(0)+f(-.5,1.15,0)+f(0,0,0,1)),(6,'fixture_spear',.025,1.0,attachment)]:
 data=s(name+'.dds')+u(8)+b''.join(f(x*sx,(y+1)*sy,z*.04)+f(0,1,0)+f(k%2,(k//2)%2) for k,(x,y,z) in enumerate(pts))+u(len(tri)//3)+struct.pack('<'+'H'*len(tri),*tri)+bytes(8)
 write('Item/3do/'+name+'.3do',data);write('Item/dds/'+name+'.dds',texture((185,201,225)))
 write('Item/'+str(typ).zfill(2)+'.itm',b'IT2'+u(1)+s(name+'.3do')+u(1)+s(name+'.dds')+u(1)+u(0)+u(0)+i(-1)+i(0)+i(0)+i(0)+(attach+empty)*16)
# A large terrain stresses resident sector eviction without proprietary content.
size=2048;n=(size//2+1)**2
write('world/stream.wld',b'FLD\0'+u(size)+struct.pack('<H',10000)*n+bytes(n)+u(1)+fixed('fixture.dds')+f(4)+fixed('')+fixed('')+bytes(7*8))
# Supplemental fixture matches this test's one-bone male rig. Never replaces original files.
import gzip,hashlib,json,base64
clips={}
for name,bob in [('hover',.08),('flight',.12),('mounted_sword',.12),('mounted_spear',.15)]:
 data=animation(bob);clips[name]={'data':base64.b64encode(data).decode(),'sha256':hashlib.sha256(data).hexdigest()}
pack={'schema':1,'profiles':[{'archetype':'humf','sex':'Masculino','parents':[-1],'clips':clips}]}
write('Extras/flight.json.gz',gzip.compress(json.dumps(pack).encode(),mtime=0))
# Client table wire header + signed 64-bit records; all 18 loot slots remain visible.
columns=['id','money1','money2','hp']+[s for i in range(1,19) for s in (f'item{i}',f'itemdroprate{i}')]
header=bytes(128)+u(len(columns))+b''.join(bytes([len(c)])+c.encode('utf-16-le') for c in columns)
rows=[[1,10,20,400]+[v for i in range(1,19) for v in (200+i,10)], [2,30,50,600]+[0]*36]
write('BinarySData/DBMonsterData.SData',header+u(len(rows))+b''.join(struct.pack('<q',v) for r in rows for v in r))
# Build real SAH/SAF wire format from the same synthetic tree, including subdirectories.
payload=bytearray()
all_files=sorted(p for p in root.rglob('*') if p.is_file())
offsets={}
for path in all_files:
 data=path.read_bytes();offsets[path]=(len(payload),len(data));payload.extend(data)
def directory(path):
 files=sorted(p for p in path.iterdir() if p.is_file());dirs=sorted(p for p in path.iterdir() if p.is_dir())
 data=s(path.name)+u(len(files))
 for file in files:
  offset,length=offsets[file];data+=s(file.name)+struct.pack('<Q',offset)+i(length)+i(0)
 data+=u(len(dirs))
 for child in dirs:data+=directory(child)
 return data
# Stored beside DATA, not inside it; snapshot must not include its own archive.
(root.parent/(root.name+'.sah')).write_bytes(b'SAH'+i(0)+u(len(all_files))+bytes(40)+directory(root))
(root.parent/(root.name+'.saf')).write_bytes(payload)
