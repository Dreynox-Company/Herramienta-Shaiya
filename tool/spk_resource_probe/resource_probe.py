from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, struct, sys, threading, time

MAGIC=0x9e7bd34c; VERSION=0x00030000; HEADER=128; FOOTER=64; RECORD=96; AUX=32
EXPECTED_INDEX='a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f'
BUNDLE_ROOT=Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parent))
HERE=Path(__file__).resolve().parent
INDEX_PROFILE=BUNDLE_ROOT/'index-profile.json' if getattr(sys,'frozen',False) else HERE/'index-profile.json'
AGENT_FILE=BUNDLE_ROOT/'resource_probe.js' if getattr(sys,'frozen',False) else HERE/'resource_probe.js'

def sha256(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def hx(b:bytes)->str:return b.hex()
def u32(b,o):return struct.unpack_from('<I',b,o)[0]
def u64(b,o):return struct.unpack_from('<Q',b,o)[0]

def read_range(path:Path, off:int, n:int)->bytes:
    size=path.stat().st_size
    if off<0 or n<0 or off+n>size:raise ValueError('Rango fuera de data.spk')
    with path.open('rb') as f:f.seek(off); b=f.read(n)
    if len(b)!=n:raise IOError('Lectura SPK incompleta')
    return b

def pe_arch(path:Path)->str:
    with path.open('rb') as f:
      mz=f.read(64)
      if len(mz)<64 or mz[:2]!=b'MZ':return 'unknown'
      pe=struct.unpack_from('<I',mz,0x3c)[0]
      f.seek(pe); head=f.read(6)
      if len(head)<6 or head[:4]!=b'PE\0\0':return 'unknown'
      machine=struct.unpack_from('<H',head,4)[0]
    return {0x014c:'x86',0x8664:'x64',0xaa64:'arm64'}.get(machine,f'0x{machine:04x}')

def parse_spk(spk:Path):
    size=spk.stat().st_size
    head=read_range(spk,0,HEADER)
    if u32(head,0)!=MAGIC or u32(head,4)!=VERSION:raise ValueError('SPK distinto del perfil v3 observado')
    idx_off=u64(head,8); idx_stored=u64(head,16); idx_dec=u64(head,24); count=u32(head,32); block=u32(head,36); aux_off=u64(head,100); aux_count=u32(head,108)
    if idx_dec!=count*RECORD or aux_off+aux_count*AUX!=idx_off or idx_off+idx_stored!=size-FOOTER:raise ValueError('Geometría SPK no coincide')
    enc=read_range(spk,idx_off,idx_stored)
    if sha256(enc)!=EXPECTED_INDEX:raise ValueError('Índice SPK distinto; no se aplicará este perfil')
    prof=json.loads(INDEX_PROFILE.read_text(encoding='utf-8'))
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    key=bytes.fromhex(prof['secretHex']); nonce=head[40:52]; tag=head[52:68]
    packed=AESGCM(key).decrypt(nonce,enc+tag,None)
    if not packed.startswith(b'\x28\xb5\x2f\xfd'):raise ValueError('Salida índice no es Zstandard')
    import zstandard as zstd
    decoded=zstd.ZstdDecompressor().decompress(packed,max_output_size=idx_dec)
    if len(decoded)!=idx_dec:raise ValueError('Longitud índice inválida')
    records=[]
    for i in range(count):
        r=decoded[i*RECORD:(i+1)*RECORD]
        entry,off,stored,mirror,dec=struct.unpack_from('<5Q',r,0); typ,auxstart=struct.unpack_from('<2I',r,40); meta=r[48:80]
        if stored!=mirror:raise ValueError('Registro espejo inválido')
        chunks=struct.unpack_from('<I',meta,28)[0] if typ==3 else 0
        records.append(dict(ordinal=i,entryId=f'{entry:016x}',entryInt=entry,dataOffset=off,storedBytes=stored,decodedBytes=dec,recordType=typ,auxStart=auxstart,chunkCount=chunks,metadataHex=meta.hex()))
    auxraw=read_range(spk,aux_off,aux_count*AUX); aux=[]
    for i in range(aux_count):
        r=auxraw[i*AUX:(i+1)*AUX]; off,stored,mirror=struct.unpack_from('<QII',r,0)
        if stored!=mirror:raise ValueError('Aux espejo inválido')
        aux.append(dict(ordinal=i,dataOffset=off,storedBytes=stored,metadataHex=r[16:32].hex()))
    return dict(size=size,indexOffset=idx_off,indexStored=idx_stored,indexDecoded=idx_dec,indexCount=count,auxOffset=aux_off,auxCount=aux_count,records=records,aux=aux)

def build_targets(spk:Path, cat:dict):
    prefix={}; details={}; total=0
    with spk.open('rb') as f:
        for r in cat['records']:
            if r['recordType']==1:
                f.seek(r['dataOffset']); p=f.read(6).hex(); total+=1
                if len(p)!=12 or p in prefix:raise ValueError('Colisión/prefijo simple inválido')
                prefix[p]=r['storedBytes'];details[p]={**r,'kind':'simple'}
        for r in cat['records']:
            if r['recordType']!=3:continue
            for j in range(r['chunkCount']):
                a=cat['aux'][r['auxStart']+j]; f.seek(a['dataOffset']); p=f.read(6).hex(); total+=1
                if len(p)!=12 or p in prefix:raise ValueError('Colisión/prefijo chunk inválido')
                prefix[p]=a['storedBytes'];details[p]={**a,'kind':'chunk','parentOrdinal':r['ordinal'],'entryId':r['entryId'],'localChunk':j,'parentDecodedBytes':r['decodedBytes']}
    if total!=55457:raise ValueError(f'Se esperaban 55.457 objetivos y hay {total}')
    return prefix,details


def _spread_simple_records(cat:dict, count:int=3):
    rows=[r for r in cat['records'] if r['recordType']==1 and r['storedBytes']>0]
    if len(rows)<=count:return rows
    picks=[]
    for i in range(count):
      at=round(i*(len(rows)-1)/(count-1))
      row=rows[at]
      if row not in picks:picks.append(row)
    return picks

def _key_authenticates_samples(spk:Path, records:list, key:bytes):
    if len(key) not in (16,32) or len(records)<2:return False
    try:
      from cryptography.hazmat.primitives.ciphers.aead import AESGCM
      aes=AESGCM(key)
      for r in records[:3]:
        meta=bytes.fromhex(r['metadataHex'])
        nonce,tag=meta[:12],meta[12:28]
        ct=read_range(spk,r['dataOffset'],r['storedBytes'])
        aes.decrypt(nonce,ct+tag,None)
      return True
    except Exception:
      return False

def _derived_index_candidates(index_key:bytes,index_hash:str):
    digest=hashlib.sha256(index_key).digest()
    reverse=index_key[::-1]
    hash_bytes=bytes.fromhex(index_hash)
    candidates=[
      ('index-key-direct',index_key),
      ('sha256-index-first16',digest[:16]),
      ('sha256-index-last16',digest[16:]),
      ('md5-index',hashlib.md5(index_key).digest()),
      ('reverse-index',reverse),
      ('xor-ff-index',bytes(x^0xff for x in index_key)),
      ('index-hash-first16',hash_bytes[:16]),
      ('index-hash-last16',hash_bytes[16:]),
      ('sha256-index-hash-text-first16',hashlib.sha256(index_hash.encode('ascii')).digest()[:16]),
    ]
    seen=set()
    for label,key in candidates:
      if key in seen:continue
      seen.add(key);yield label,key

def _nearby_binary_candidates(path:Path,index_key:bytes,max_candidates:int=30000):
    try:
      size=path.stat().st_size
      if size<=0 or size>256*1024*1024:return
      blob=path.read_bytes()
    except OSError:
      return
    seen=set();emitted=0
    anchors=[]
    raw=index_key
    ascii_hex=index_key.hex().encode('ascii')
    ascii_upper=index_key.hex().upper().encode('ascii')
    for needle,label in (
      (raw,'index-key'),
      (ascii_hex,'index-key-hex'),
      (ascii_upper,'index-key-HEX'),
      (b'ChainingModeGCM','gcm-string'),
      (b'data.spk','data-spk-string'),
      (b'DATA.SPK','DATA-SPK-string'),
    ):
      start=0
      while True:
        at=blob.find(needle,start)
        if at<0:break
        anchors.append((at,label))
        start=at+1
        if len(anchors)>=64:break
      if len(anchors)>=64:break
    for at,label in anchors:
      lo=max(0,at-2048);hi=min(len(blob),at+2048)
      region=blob[lo:hi]
      for match in re.finditer(rb'(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{32}|[0-9A-Fa-f]{64})(?![0-9A-Fa-f])',region):
        try:key=bytes.fromhex(match.group(0).decode('ascii'))
        except ValueError:continue
        if len(key) not in (16,32) or key in seen:continue
        seen.add(key);emitted+=1
        yield f'{path.name}:{label}:hex@0x{lo+match.start():x}',key
        if emitted>=max_candidates:return
      # Raw constants close to an observed crypto/string anchor. Step 4 keeps
      # the sweep bounded while covering normal constant-pool alignment.
      for width in (16,32):
        end=max(lo,hi-width+1)
        for pos in range(lo,end,4):
          key=blob[pos:pos+width]
          if len(key)!=width or key in seen:continue
          if len(set(key))<6:continue
          seen.add(key);emitted+=1
          yield f'{path.name}:{label}:raw@0x{pos:x}',key
          if emitted>=max_candidates:return

def discover_static_resource_key(game:Path,spk:Path,cat:dict,index_key:bytes,index_hash:str,out:Path):
    samples=_spread_simple_records(cat,3)
    report={'schema':1,'samples':[r['entryId'] for r in samples],'modules':[],'tested':0,'match':None}
    def test(label,key):
      report['tested']+=1
      if _key_authenticates_samples(spk,samples,key):
        report['match']={'source':label,'secretHex':key.hex(),'secretBytes':len(key)}
        return key
      return None
    for label,key in _derived_index_candidates(index_key,index_hash):
      found=test(label,key)
      if found:
        (out/'static-key-sweep.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        return found,label,report
    modules=[game]
    try:
      modules += sorted(
        [p for p in game.parent.iterdir() if p.is_file() and p.suffix.lower()=='.dll'],
        key=lambda p:p.stat().st_size,
      )
    except OSError:
      pass
    for module in modules[:64]:
      try:size=module.stat().st_size
      except OSError:continue
      if size>256*1024*1024:continue
      item={'file':module.name,'bytes':size,'testedBefore':report['tested']}
      for label,key in _nearby_binary_candidates(module,index_key):
        found=test(label,key)
        if found:
          item['testedAfter']=report['tested'];report['modules'].append(item)
          (out/'static-key-sweep.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
          return found,label,report
      item['testedAfter']=report['tested'];report['modules'].append(item)
      if report['tested']>=120000:break
    (out/'static-key-sweep.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    return None,None,report

def static_resource_profile(key:bytes,source_label:str):
    return {
      'schema':4,
      'profileId':'shaiya-spk-v3-resources-a3ea7e3b-v11-static',
      'indexSha256':EXPECTED_INDEX,
      'offlineValidated':3,
      'simpleValidated':3,
      'chunksValidated':0,
      'resourceKeys':[key.hex()],
      'keySources':['static-key-sweep:'+source_label],
      'modes':['ChainingModeGCM'],
      'chunkNonceRules':[],
      'simpleMetadataLayout':'nonce12-tag16-flags4',
      'chunkTagRule':'unverified',
      'readyForSimple':True,
      'readyForFragmented':False,
      'readyForAll':False,
      'aadRule':'none',
      'resourceSecretHex':key.hex(),
      'resourceSecretBytes':len(key),
      'algorithm':'AES-GCM',
      'validatedSamples':[],
    }

def nonce_rules(t:dict):
    if t['kind']!='chunk':return {}
    off=t['dataOffset']; local=t['localChunk']; aux=t['ordinal']; entry=int(t['entryId'],16)
    def q(v,n):return struct.pack('<QI',v,n)
    parent=t['parentOrdinal']
    return {
      'offset_chunk0_le96':q(off,local), 'entry_id_chunk0_le':q(entry,local),
      'offset_aux_le96':q(off,aux), 'entry_id_aux_le':q(entry,aux),
      'offset_chunk1_le96':q(off,local+1), 'entry_id_chunk1_le':q(entry,local+1),
      'record_ordinal_chunk_le96':q(parent,local),
      'record_ordinal_aux_le96':q(parent,aux),
      'record_ordinal_chunk1_le96':q(parent,local+1),
      'aux_ordinal_chunk_le96':q(aux,local),
      'aux_ordinal_zero_le96':q(aux,0),
    }

class Sink:
    def __init__(self,out:Path,spk:Path,details):self.out=out;self.spk=spk;self.details=details;self.events=[];self.rows=[];self.lock=threading.Lock();self.valid_simple=[];self.valid_chunks=[]
    def accept(self,m,data):
      with self.lock:
       if m.get('type')=='error':
        self.events.append({'code':'AGENT_ERROR','message':str(m.get('description',''))[:500]});return
       if m.get('type')!='send' or not isinstance(m.get('payload'),dict):return
       p=m['payload'];kind=p.get('kind')
       if kind=='event':
        if len(self.events)<250:self.events.append(p)
        print('EVENT',p.get('code','?'),json.dumps(p.get('details') or {},ensure_ascii=False,separators=(',',':')),flush=True)
        return
       if kind!='resource':return
       pref=p.get('prefix');target=self.details.get(pref)
       if not target:raise ValueError('Objetivo fuera del catálogo')
       with self.spk.open('rb') as f:f.seek(target['dataOffset']);ct=f.read(target['storedBytes'])
       if sha256(ct)!=p.get('inputSha256'):raise ValueError('Ciphertext observado no coincide')
       row={'target':target,'caller':p.get('caller'),'flags':p.get('flags'),'key':p.get('key'),'auth':p.get('auth'),'ivHex':p.get('ivHex'),'outputBytes':p.get('outputBytes'),'outputSha256':p.get('outputSha256'),'nativeCapture':None,'offlineValid':False,'decodedValid':False,'format':'UNKNOWN','nonceRule':None}
       blob=bytes(data or b'')
       if blob:
        name=f"native-{len(self.rows)+1:02d}.bin";(self.out/name).write_bytes(blob);row['nativeCapture']=name
       try:
        keyinfo=row['key'] or {}; auth=row['auth'] or {}; secret=bytes.fromhex(keyinfo.get('secretHex','')); nonce=bytes.fromhex(auth.get('nonceHex','')); tag=bytes.fromhex(auth.get('tagHex','')); aad=bytes.fromhex(auth['authDataHex']) if auth.get('authDataHex') else None
        if len(secret) in (16,32) and len(nonce)==12 and len(tag)==16:
         from cryptography.hazmat.primitives.ciphers.aead import AESGCM
         plain=AESGCM(secret).decrypt(nonce,ct+tag,aad);row['offlineValid']=True;row['plainSha256']=sha256(plain);row['plainBytes']=len(plain)
         if blob:row['matchesNative']=plain==blob
         if target['kind']=='simple':
          meta=bytes.fromhex(target['metadataHex']);row['metadataNonceMatch']=meta[:12]==nonce;row['metadataTagMatch']=meta[12:28]==tag;row['metadataFlags']=struct.unpack_from('<I',meta,28)[0]
         else:
          meta=bytes.fromhex(target['metadataHex']);row['metadataTagMatch']=meta==tag
          for rn,rv in nonce_rules(target).items():
           if rv==nonce:row['nonceRule']=rn;break
         decoded=plain
         if plain.startswith(b'\x28\xb5\x2f\xfd'):
          import zstandard as zstd
          lim=target.get('decodedBytes') or target.get('parentDecodedBytes') or 256*1024*1024
          try:decoded=zstd.ZstdDecompressor().decompress(plain,max_output_size=max(int(lim),1024));row['wasZstd']=True
          except Exception as e:row['zstdError']=str(e)[:300]
         row['decodedBytesObserved']=len(decoded);row['decodedSha256']=sha256(decoded);row['format']=detect(decoded)
         if target['kind']=='simple':row['decodedValid']=len(decoded)==target['decodedBytes']
         if len(decoded)<=8*1024*1024:
          fn=f"decoded-{len(self.rows)+1:02d}.{ext(row['format'])}";(self.out/fn).write_bytes(decoded);row['decodedFile']=fn
       except Exception as e:row['offlineError']=type(e).__name__+': '+str(e)[:300]
       self.rows.append(row);(self.out/'resource-observations.json').write_text(json.dumps({'schema':2,'rows':self.rows,'events':self.events},ensure_ascii=False,indent=2),encoding='utf-8')
       if row['offlineValid']:
        if target['kind']=='simple':self.valid_simple.append(row)
        else:self.valid_chunks.append(row)
       print('CAPTURA',target['kind'],target.get('entryId'),target['ordinal'],'offline=',row['offlineValid'],'fmt=',row['format'],'nonceRule=',row['nonceRule'],flush=True)

def detect(b:bytes):
    if b.startswith(b'DDS '):return 'DDS'
    if b.startswith(b'\x89PNG\r\n\x1a\n'):return 'PNG'
    if b.startswith(b'BM'):return 'BMP'
    if b.startswith(b'\xff\xd8\xff'):return 'JPG'
    if b.startswith(b'OggS'):return 'OGG'
    if b.startswith(b'RIFF'):return 'WAV'
    if b.startswith(b'PK\x03\x04'):return 'ZIP'
    if b.startswith(b'MZ'):return 'PE'
    if b.startswith((b'MLT',b'ML2',b'ML3',b'ML4')):return 'MLT'
    if b.startswith((b'ITM',b'IT2',b'pandaIT2')):return 'ITM'
    if b.startswith((b'MO2',b'MO4')):return 'MON'
    if len(b)>=18 and b[2] in (1,2,3,9,10,11) and b[16] in (8,16,24,32):return 'TGA'
    try:
      s=b[:512].decode('utf-8').lstrip()
      if s.startswith('<'):return 'XML'
    except:pass
    return 'BIN'
def ext(f):return {'DDS':'dds','PNG':'png','BMP':'bmp','JPG':'jpg','OGG':'ogg','WAV':'wav','ZIP':'zip','TGA':'tga','XML':'xml','PE':'exe','MLT':'mlt','ITM':'itm','MON':'mon'}.get(f,'bin')

def canonical_nonce_rule(value):
    return {
      'offset_chunk0_le96':'offset_le96',
      'entry_id_chunk0_le':'entry_id_chunk_le',
    }.get(value,value)

def derive_profile(rows):
    valid=[r for r in rows if r.get('offlineValid')]
    simple=[r for r in valid if r['target']['kind']=='simple']
    chunks=[r for r in valid if r['target']['kind']=='chunk']
    keys={r.get('key',{}).get('secretHex') for r in valid if r.get('key',{}).get('secretHex')}
    modes={r.get('key',{}).get('chainingMode') for r in valid if r.get('key')}
    key_sources={r.get('key',{}).get('source') for r in valid if r.get('key',{}).get('source')}
    rules={canonical_nonce_rule(r.get('nonceRule')) for r in chunks if r.get('nonceRule')}
    aad_values=[]
    for r in valid:
      auth=r.get('auth') or {}
      aad_values.append((auth.get('authDataHex') or '').lower())
    aad_set=set(aad_values)
    simple_meta=bool(simple) and all(r.get('metadataNonceMatch') and r.get('metadataTagMatch') for r in simple)
    chunk_tags=bool(chunks) and all(r.get('metadataTagMatch') for r in chunks)
    result={
      'schema':4,
      'profileId':'shaiya-spk-v3-resources-a3ea7e3b-v11',
      'indexSha256':EXPECTED_INDEX,
      'offlineValidated':len(valid),
      'simpleValidated':len(simple),
      'chunksValidated':len(chunks),
      'resourceKeys':sorted(keys),
      'keySources':sorted(x for x in key_sources if x),
      'modes':sorted(x for x in modes if x),
      'chunkNonceRules':sorted(rules),
      'simpleMetadataLayout':'nonce12-tag16-flags4' if simple_meta else 'unverified',
      'chunkTagRule':'metadata16' if chunk_tags else 'unverified',
      'readyForSimple':bool(len(simple)>=2 and len(keys)==1 and simple_meta),
      'readyForFragmented':bool(len(chunks)>=2 and len(keys)==1 and len(rules)==1 and chunk_tags),
      'validatedSamples':[{
        'kind':r['target']['kind'],
        'entryId':r['target'].get('entryId'),
        'ordinal':r['target'].get('ordinal'),
        'parentOrdinal':r['target'].get('parentOrdinal'),
        'format':r.get('format'),
        'plainSha256':r.get('plainSha256'),
        'matchesNative':r.get('matchesNative'),
      } for r in valid],
    }
    if len(aad_set)==1:
      aad=next(iter(aad_set))
      result['aadRule']='none' if not aad else 'constant'
      if aad:result['aadHex']=aad
    else:
      result['aadRule']='per-resource-or-unresolved'
    if result['readyForSimple']:
      result['resourceSecretHex']=next(iter(keys))
      result['resourceSecretBytes']=len(bytes.fromhex(result['resourceSecretHex']))
      result['algorithm']='AES-GCM'
    if result['readyForFragmented']:
      result['chunkNonceRule']=next(iter(rules))
    result['readyForAll']=result['readyForSimple'] and result['readyForFragmented']
    return result

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--client',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);ap.add_argument('--seconds',type=int,default=120);ap.add_argument('--noninteractive',action='store_true');a=ap.parse_args()
    if sys.platform!='win32':raise RuntimeError('Esta fase requiere Windows.')
    import struct as _s
    if _s.calcsize('P')!=8:raise RuntimeError('Usa Python 64 bits.')
    try:import frida,zstandard,cryptography
    except ImportError as e:raise RuntimeError('Ejecuta PREPARAR.cmd con Internet primero: '+str(e))
    exe=a.client.resolve();spk=exe.parent/'data.spk'
    if not exe.is_file() or not spk.is_file():raise FileNotFoundError('game.exe y data.spk deben estar juntos')
    arch=pe_arch(exe)
    if arch not in ('x86','x64'):raise RuntimeError('Arquitectura de game.exe no compatible: '+arch)
    out=a.out.resolve()
    if out.exists():raise FileExistsError('La carpeta de salida debe ser nueva')
    try:
      out.relative_to(exe.parent)
      raise ValueError('La salida debe quedar fuera de la instalación del juego')
    except ValueError as e:
      if str(e)=='La salida debe quedar fuera de la instalación del juego': raise
    out.mkdir(parents=True)
    print('Leyendo índice y construyendo mapa de 55.457 ciphertexts…',flush=True)
    cat=parse_spk(spk);prefix,details=build_targets(spk,cat);(out/'target-summary.json').write_text(json.dumps({'spkBytes':cat['size'],'targets':len(prefix),'simple':48668,'chunks':6789,'gameArch':arch},indent=2),encoding='utf-8')
    print('game.exe detectado como',arch,'· objetivos SPK:',len(prefix),flush=True)
    index_profile=json.loads(INDEX_PROFILE.read_text(encoding='utf-8'))
    index_key=bytes.fromhex(index_profile['secretHex'])
    print('Probando derivaciones y constantes estáticas contra tags GCM reales…',flush=True)
    static_key,static_source,static_report=discover_static_resource_key(
      exe,spk,cat,index_key,EXPECTED_INDEX,out
    )
    if static_key is not None:
      prof=static_resource_profile(static_key,static_source)
      (out/'derived-resource-profile.json').write_text(json.dumps(prof,ensure_ascii=False,indent=2),encoding='utf-8')
      (out/'resource-observations.json').write_text(json.dumps({'schema':2,'rows':[],'events':[{'kind':'event','code':'STATIC_KEY_SWEEP_MATCH','details':{'source':static_source,'tested':static_report['tested']}}]},ensure_ascii=False,indent=2),encoding='utf-8')
      print('ÉXITO estático: clave de recursos autenticada contra 3 muestras ·',static_source,flush=True)
      return 4
    print('Barrido estático sin coincidencias · candidatos probados:',static_report['tested'],flush=True)
    print('Desconecta Internet. Se abrirá game.exe; NO inicies sesión.',flush=True)
    if not a.noninteractive:
      print('Escribe CAPTURAR para continuar:',flush=True)
      if input().strip()!='CAPTURAR':print('Cancelado');return 2
    cfg={'prefixes':prefix};agent=AGENT_FILE.read_text(encoding='utf-8').replace('__CONFIG__',json.dumps(cfg,separators=(',',':')))
    sink=Sink(out,spk,details);dev=frida.get_local_device();pid=None;sess=None;script=None;done=threading.Event();failure=None;grace_started=False
    def onmsg(m,d):
      nonlocal failure,grace_started
      try:
       sink.accept(m,d)
       # Si ya hay clave/AAD reproducibles, damos una ventana corta para capturar
       # chunks nativos. Si no aparecen, Studio deriva la regla offline después.
       if len(sink.valid_simple)>=4:
        if len(sink.valid_chunks)>=2:done.set()
        elif not grace_started:
         grace_started=True
         timer=threading.Timer(20.0,done.set);timer.daemon=True;timer.start()
      except Exception as e:failure=str(e);done.set()
    try:
      pid=dev.spawn([str(exe)],cwd=str(exe.parent));sess=dev.attach(pid);sess.on('detached',lambda *x:done.set());script=sess.create_script(agent);script.on('message',onmsg);script.load();dev.resume(pid)
      print('Juego abierto. El aviso de servidor sin conexión es esperado. Esperando recursos…',flush=True);done.wait(max(20,min(a.seconds,180)))
    finally:
      if script:
       try:script.exports_sync.stop();script.unload()
       except:pass
      if sess:
       try:sess.detach()
       except:pass
    prof=derive_profile(sink.rows);prof['failure']=failure;(out/'derived-resource-profile.json').write_text(json.dumps(prof,ensure_ascii=False,indent=2),encoding='utf-8');(out/'resource-observations.json').write_text(json.dumps({'schema':2,'rows':sink.rows,'events':sink.events},ensure_ascii=False,indent=2),encoding='utf-8')
    print('RESUMEN capturas=',len(sink.rows),'simples_validas=',len(sink.valid_simple),'chunks_validos=',len(sink.valid_chunks),'fallo=',failure,flush=True)
    print(json.dumps(prof,ensure_ascii=False,indent=2));
    if prof['readyForFragmented']:print('ÉXITO: simples + fragmentos reproducidos offline.');return 0
    if prof['readyForSimple']:print('Simples autenticados; Shaiya Studio revalidará la clave y derivará los chunks offline.');return 4
    print('No se capturó aún un perfil de recurso válido.');return 3
if __name__=='__main__':
  try:raise SystemExit(main())
  except Exception as e:print('DETENIDO:',e,file=sys.stderr);raise SystemExit(1)