"""Generate a trace-only COM wrapper using the installed SDK declarations.
Anonymous parameters in SDK method declarations receive local names; their
original types, argument ordering, return values and calling convention remain.
"""
from pathlib import Path
import os,re

def parameters(text):
 text=re.sub(r'\bTHIS_\b','',text).strip()
 if text in ('','THIS','void'):return '',[]
 text=re.sub(r'/\*.*?\*/','',text,flags=re.S)
 declarations=[];names=[]
 for i,part in enumerate(text.split(',')):
  arg=' '.join(part.split());clean=re.sub(r'\[.*?\]','',arg).strip()
  words=re.findall(r'\b\w+\b',clean)
  if not words:raise RuntimeError('Empty COM parameter: '+repr(part))
  match=re.search(r'([A-Za-z_]\w*)\s*$',clean)
  # A lone type, or a declaration ending in pointer/reference, has no name.
  qualifiers={'const','CONST','volatile','unsigned','signed','struct'}
  significant=[w for w in words if w not in qualifiers]
  anonymous=match is None or len(significant)==1
  if anonymous:
   name=f'arg{i}';arg=arg+' '+name
  else:name=match[1]
  declarations.append(arg);names.append(name)
 return ', '.join(declarations),names

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
  name=under_name or name;ret=return_type.strip() or 'HRESULT';args,names=parameters(args)
  prefix=ret+' STDMETHODCALLTYPE '+name+'('+args+') override {'
  if name=='QueryInterface':body=f'if(!{names[1]})return E_POINTER;*{names[1]}=nullptr;if({names[0]}==__uuidof(IUnknown)||{names[0]}==__uuidof(IDirect3DDevice9)){{*{names[1]}=this;AddRef();return S_OK;}}return E_NOINTERFACE;'
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
 if source.count('class Diagnostic9 final:')!=1:raise RuntimeError('Diagnostic object contract changed')
 source=source.replace('class Diagnostic9 final:', '\n'.join(code)+'\nclass Diagnostic9 final:',1)
 needle='trace("Device=%08x",h);return h;'
 if source.count(needle)!=1:raise RuntimeError('Diagnostic CreateDevice contract changed')
 return source.replace(needle,'trace("Device=%08x",h);if(SUCCEEDED(h)&&o&&*o)*o=new DiagnosticDevice(*o);return h;')

if __name__=='__main__':
 assert parameters('THIS_ D3DTRANSFORMSTATETYPE State, CONST D3DMATRIX*') == ('D3DTRANSFORMSTATETYPE State, CONST D3DMATRIX* arg1',['State','arg1'])
 assert parameters('THIS_ UINT, IDirect3DSurface9** ppSurface')[1]==['arg0','ppSurface']
 assert parameters('THIS')==('',[])
 print('COM parameter-generation regression passed.')
