#!/usr/bin/env python3
"""Reproducible native-client patch. No client binary or assets are included.
This patch alone is not an offline world; a compatible localhost backend is required.
"""
import argparse,hashlib,json,struct
from pathlib import Path
import pefile
EXPECTED='509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d'
PATCHES=[(0x5aa4eb,'0f84c5000000','e9c600000090','existing native loose-file reader'),(0x69368e,'ff157c648000','58b87f000001','loopback sockaddr and preserved stdcall stack')]
def patch(source,dest):
 source,dest=Path(source),Path(dest)
 if source.resolve()==dest.resolve() or dest.exists():raise ValueError('Refusing overwrite')
 original=source.read_bytes()
 if hashlib.sha256(original).hexdigest()!=EXPECTED:raise ValueError('Wrong native fingerprint')
 pe=pefile.PE(data=original);b=bytearray(original);changes=[];ranges=[]
 if pe.FILE_HEADER.Machine!=0x14c:raise ValueError('Expected x86 client')
 for va,old,new,reason in PATCHES:
  rva=va-pe.OPTIONAL_HEADER.ImageBase;o=pe.get_offset_from_rva(rva);old,new=bytes.fromhex(old),bytes.fromhex(new)
  if b[o:o+len(old)]!=old or len(old)!=len(new):raise ValueError('Instruction contract changed')
  b[o:o+len(new)]=new;ranges.append((rva,rva+len(new)));changes.append({'va':hex(va),'offset':o,'before':old.hex(),'after':new.hex(),'reason':reason})
 removed=[]
 for block in pe.DIRECTORY_ENTRY_BASERELOC:
  for e in block.entries:
   if e.type and any(a<e.rva+4 and e.rva<z for a,z in ranges):
    if e.type!=3:raise ValueError('Unexpected relocation')
    struct.pack_into('<H',b,e.struct.get_file_offset(),0);removed.append(e.rva)
 if removed!=[0x293690]:raise ValueError('Wrong relocation set')
 cert=pe.OPTIONAL_HEADER.DATA_DIRECTORY[4]
 if cert.VirtualAddress+cert.Size!=len(b):raise ValueError('Unexpected overlay')
 b=b[:cert.VirtualAddress];struct.pack_into('<II',b,cert.get_file_offset(),0,0)
 off=pe.OPTIONAL_HEADER.get_field_absolute_offset('CheckSum');struct.pack_into('<I',b,off,0);struct.pack_into('<I',b,off,pefile.PE(data=bytes(b)).generate_checksum())
 dest.write_bytes(b)
 manifest={'original_sha256':EXPECTED,'patched_sha256':hashlib.sha256(b).hexdigest(),'patches':changes,'neutralized_relocations':removed,'original_signature_removed':True,'aslr_retained':True,'native_world_entry_claimed':False}
 dest.with_suffix('.manifest.json').write_text(json.dumps(manifest,indent=2));return manifest
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('source');ap.add_argument('dest');a=ap.parse_args();print(json.dumps(patch(a.source,a.dest),indent=2))
