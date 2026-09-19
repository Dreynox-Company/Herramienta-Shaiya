"""Generate a trace-only IDirect3DDevice9 wrapper from the installed SDK header.
All arguments and returns pass through unchanged. No success code is fabricated.
"""
from pathlib import Path
import os,re

def instrument(source):
 base=Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Windows Kits/10/Include'
 headers=sorted([*base.glob('*/shared/d3d9.h'),*base.glob('*/um/d3d9.h')])
 if not headers:raise RuntimeError('Direct3D SDK header unavailable: '+str(base))
 header=headers[-1].read_text(errors='replace')
 start=re.search(r'DECLARE_INTERFACE_\s*\(\s*IDirect3DDevice9\s*,\s*IUnknown\s*\)',header)
 if not start:raise RuntimeError('Unrecognized Direct3D header syntax')
 text=header[start.end():];text=text[:text.index('};')]
 pattern=r'STDMETHOD(?:_\s*\(\s*([^,]+),\s*(\w+)\s*\)|\s*\(\s*(\w+)\s*\))\s*\((.*?)\)\s*PURE'
 methods=re.findall(pattern,text,re.S)
 if len(methods)!=119:raise RuntimeError('Expected 119 IDirect3DDevice9 methods; got '+str(len(methods)))
 code=['#include <intrin.h>','class DiagnosticDevice final : public IDirect3DDevice9 {','IDirect3DDevice9* d; std::atomic<ULONG> refs{1}; unsigned calls=0;','public: explicit DiagnosticDevice(IDirect3DDevice9* p):d(p){}']
 for return_type,under_name,name,args in methods:
  name=under_name or name;ret=return_type.strip() or 'HRESULT'
  args=re.sub(r'\bTHIS_\b','',args).strip()
  if args=='THIS':args=''
  args=' '.join(args.split())
  names=[]
  for arg in args.split(',') if args else []:
   clean=re.sub(r'\[.*?\]','',arg).strip();m=re.search(r'(\w+)\s*$',clean)
   if not m:raise RuntimeError('Cannot parse SDK argument: '+arg)
   names.append(m[1])
  prefix=ret+' STDMETHODCALLTYPE '+name+'('+args+') override {'
  if name=='QueryInterface':
   body=f'if(!{names[1]})return E_POINTER;*{names[1]}=nullptr;if({names[0]}==__uuidof(IUnknown)||{names[0]}==__uuidof(IDirect3DDevice9)){{*{names[1]}=this;AddRef();return S_OK;}}return E_NOINTERFACE;'
  elif name=='AddRef':body='return ++refs;'
  elif name=='Release':body='auto n=--refs;if(!n){d->Release();delete this;}return n;'
  else:
   call='d->'+name+'('+','.join(names)+')'
   if ret=='void':body=call+';'
   else:
    body='auto result='+call+';'
    if ret=='HRESULT':body+='if(FAILED(result)||calls++<180)trace("'+name+' hr=%08x caller=%p",result,_ReturnAddress());'
    if name=='GetAvailableTextureMem':body+='trace("TextureMemory %u",result);'
    body+='return result;'
  code.append(prefix+body+'}')
 code.append('};')
 source=source.replace('class Diagnostic9 final:', '\n'.join(code)+'\nclass Diagnostic9 final:',1)
 needle='trace("Device=%08x",h);return h;'
 if source.count(needle)!=1:raise RuntimeError('Diagnostic CreateDevice contract changed')
 return source.replace(needle,'trace("Device=%08x",h);if(SUCCEEDED(h)&&o&&*o)*o=new DiagnosticDevice(*o);return h;')
