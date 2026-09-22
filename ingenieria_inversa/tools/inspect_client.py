#!/usr/bin/env python3
"""Bounded, read-only PE inventory and hash-specific ps0032 evidence extraction.
No executable is launched, patched, injected, transmitted or converted to Dart.
"""
from __future__ import annotations
import argparse, collections, hashlib, json, math, re
from pathlib import Path
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
PIN = '509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d'
RANGES = {
 'native_launch_callsite': (0x542C10, 0x542CB0),
 'file_metadata_writer_A114': (0x5606F0, 0x560770),
 'credentials_writer_A110': (0x560780, 0x5607D0),
}
def entropy(body: bytes) -> float:
 if not body: return 0.0
 counts=collections.Counter(body);n=len(body)
 return round(-sum((x/n)*math.log2(x/n) for x in counts.values()),4)
def inventory(path: Path) -> dict:
 if path.is_symlink() or not path.is_file():raise ValueError('Se requiere un archivo regular local.')
 if not 64<=path.stat().st_size<=64*1024*1024:raise ValueError('Tamaño fuera del límite de 64 MiB.')
 body=path.read_bytes();sha=hashlib.sha256(body).hexdigest()
 pe=pefile.PE(data=body,fast_load=False)
 try:
  if len(pe.sections)>96:raise ValueError('Número de secciones fuera del límite.')
  image_base=pe.OPTIONAL_HEADER.ImageBase
  sections=[]
  for section in pe.sections:
   data=section.get_data()
   sections.append({'name':section.Name.rstrip(b'\0').decode('ascii','replace'),
    'rva':hex(section.VirtualAddress),'virtualBytes':section.Misc_VirtualSize,
    'fileOffset':section.PointerToRawData,'rawBytes':section.SizeOfRawData,
    'sha256':hashlib.sha256(data).hexdigest(),'entropy':entropy(data),
    'executable':bool(section.Characteristics&0x20000000),'writable':bool(section.Characteristics&0x80000000)})
  imports=[]
  for dll in getattr(pe,'DIRECTORY_ENTRY_IMPORT',[]):
   imports.append({'dll':dll.dll.decode('ascii','replace'),'functions':[
    {'name':item.name.decode('ascii','replace') if item.name else None,'ordinal':item.ordinal,'iatAddress':hex(item.address)}
    for item in dll.imports]})
  resources=[]
  def walk(node,parts,depth=0):
   if depth>5:return
   for item in getattr(node,'entries',[]):
    label=str(item.name) if item.name else str(item.id)
    if hasattr(item,'directory'):walk(item.directory,parts+[label],depth+1)
    elif hasattr(item,'data'):
     d=item.data.struct;data=pe.get_data(d.OffsetToData,d.Size)
     resources.append({'path':'/'.join(parts+[label]),'rva':hex(d.OffsetToData),'bytes':d.Size,'sha256':hashlib.sha256(data).hexdigest()})
  if hasattr(pe,'DIRECTORY_ENTRY_RESOURCE'):walk(pe.DIRECTORY_ENTRY_RESOURCE,[])
  versions={}
  for group in getattr(pe,'FileInfo',[]):
   for info in group:
    for table in getattr(info,'StringTable',[]):
     versions.update({k.decode('utf-8','replace'):v.decode('utf-8','replace') for k,v in table.entries.items()})
  wanted=re.compile(rb'(?:\.sdata|\.svmap|\.saf|\.sah|\.3dc|\.3do|\.ani|\.ini|_spn|game\.exe|direct3d|sound manager|winsock)',re.I)
  strings=[]
  for match in re.finditer(rb'[\x20-\x7e]{5,384}',body):
   if wanted.search(match[0]):
    try:va=hex(image_base+pe.get_rva_from_offset(match.start()))
    except pefile.PEFormatError:va=None
    strings.append({'fileOffset':match.start(),'virtualAddress':va,'text':match[0].decode('ascii')})
    if len(strings)>=1500:break
  instructions={}
  if sha==PIN:
   md=Cs(CS_ARCH_X86,CS_MODE_32)
   for name,(start,end) in RANGES.items():
    raw=pe.get_data(start-image_base,end-start)
    instructions[name]=[{'address':hex(i.address),'bytes':i.bytes.hex(),'mnemonic':i.mnemonic,'operands':i.op_str} for i in md.disasm(raw,start)]
  return {'schema':1,'fileName':path.name,'sha256':sha,'bytes':len(body),'readOnly':True,
   'profile':'ps0032-observed' if sha==PIN else 'unrecognized-no-address-assumptions',
   'machine':hex(pe.FILE_HEADER.Machine),'imageBase':hex(image_base),'entryPoint':hex(image_base+pe.OPTIONAL_HEADER.AddressOfEntryPoint),
   'sectionCount':len(sections),'sections':sections,'imports':imports,'resources':resources,'versionStrings':versions,
   'selectedStrings':strings,'knownDisassembly':instructions,
   'limits':['La entropía no prueba cifrado ni empaquetado.','Las cadenas no prueban que una función sea ejecutada.','Sin símbolos no se recuperan nombres ni código fuente originales.','La reconstrucción Flutter se desarrolla independientemente con lectores verificados.']}
 finally:pe.close()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--client',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 result=inventory(a.client)
 if a.out.exists() and (a.out.is_symlink() or not a.out.is_dir()):raise ValueError('Directorio de salida inválido.')
 a.out.mkdir(parents=True,exist_ok=True)
 output=a.out/'pe_inventory.json'
 with output.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2,ensure_ascii=False)
 print(json.dumps({'report':str(output),'sha256':result['sha256'],'profile':result['profile'],'sections':result['sectionCount'],'importedDlls':len(result['imports'])},ensure_ascii=False))
if __name__=='__main__':main()
