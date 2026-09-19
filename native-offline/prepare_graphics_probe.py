#!/usr/bin/env python3
"""Test-only renderer diagnostic. Does not change a user's installed client."""
from pathlib import Path
import os,subprocess,sys
root=Path(sys.argv[1]).resolve();proof=Path(sys.argv[2]).resolve();proof.mkdir(exist_ok=True)
config=root/'config.ini'
s=config.read_text(encoding='cp1252') if config.exists() else '[VIDEO]\n'
import re
for key,value in {'FULLSCREEN':'FALSE','SIZE_X':'1024','SIZE_Y':'768','COLOR':'32','SHADOW':'FALSE','GLOW_LEVEL':'0','TEXTURE':'LOW'}.items():
 pattern=r'(?im)^'+key+r'=.*$'
 if re.search(pattern,s):s=re.sub(pattern,key+'='+value,s)
 else:s=s.replace('[VIDEO]','[VIDEO]\n'+key+'='+value)
config.write_text(s,encoding='cp1252')
source=r'''#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <cstdio>
struct Args {BOOL enable;IUnknown* device;IUnknown* queues[2];UINT num;UINT mask;};
using CreateOn12=IDirect3D9* (WINAPI*)(UINT,Args*,UINT);
void inspect(IDirect3D9* d,HWND w,const char* mode){
 printf("MODE %s ptr=%p\n",mode,d);if(!d)return;
 for(UINT adapter=0;adapter<d->GetAdapterCount();adapter++){
  D3DADAPTER_IDENTIFIER9 id={};d->GetAdapterIdentifier(adapter,0,&id);printf("ADAPTER %u %s vendor=%x device=%x\n",adapter,id.Description,id.VendorId,id.DeviceId);
  D3DCAPS9 caps={};auto hr=d->GetDeviceCaps(adapter,D3DDEVTYPE_HAL,&caps);printf("CAPS %08x VS=%08x PS=%08x\n",hr,caps.VertexShaderVersion,caps.PixelShaderVersion);
  for(DWORD flags:{DWORD(D3DCREATE_SOFTWARE_VERTEXPROCESSING),DWORD(D3DCREATE_HARDWARE_VERTEXPROCESSING)}){
   D3DPRESENT_PARAMETERS p={};p.BackBufferWidth=800;p.BackBufferHeight=600;p.BackBufferFormat=D3DFMT_UNKNOWN;p.BackBufferCount=1;p.SwapEffect=D3DSWAPEFFECT_DISCARD;p.hDeviceWindow=w;p.Windowed=TRUE;p.PresentationInterval=D3DPRESENT_INTERVAL_IMMEDIATE;
   IDirect3DDevice9* v=nullptr;hr=d->CreateDevice(adapter,D3DDEVTYPE_HAL,w,flags,&p,&v);printf("CREATE flags=%x result=%08x\n",flags,hr);if(v){v->Clear(0,0,D3DCLEAR_TARGET,0xff174065,1,0);v->Present(0,0,0,0);v->Release();}
  }
 }d->Release();fflush(stdout);
}
int main(){
 auto w=CreateWindowExW(0,L"STATIC",L"D3D9 isolated diagnostic",WS_OVERLAPPEDWINDOW|WS_VISIBLE,0,0,820,640,0,0,GetModuleHandleW(0),0);
 wchar_t path[MAX_PATH];GetSystemDirectoryW(path,MAX_PATH);wcscat_s(path,L"\\d3d9.dll");auto module=LoadLibraryW(path);
 auto make=reinterpret_cast<IDirect3D9*(WINAPI*)(UINT)>(GetProcAddress(module,"Direct3DCreate9"));inspect(make?make(D3D_SDK_VERSION):nullptr,w,"original");
 auto on12=reinterpret_cast<CreateOn12>(GetProcAddress(module,"Direct3DCreate9On12"));printf("ON12=%p\n",on12);
 if(on12){Args a={TRUE};inspect(on12(D3D_SDK_VERSION,&a,1),w,"on12-any");
  IDXGIFactory4* factory=nullptr;IDXGIAdapter* warp=nullptr;ID3D12Device* device=nullptr;
  HRESULT hr=CreateDXGIFactory1(IID_PPV_ARGS(&factory));printf("DXGI=%08x\n",hr);
  if(factory){hr=factory->EnumWarpAdapter(IID_PPV_ARGS(&warp));printf("WARP=%08x\n",hr);if(warp){hr=D3D12CreateDevice(warp,D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device));printf("D12=%08x\n",hr);}}
  if(device){a.device=device;inspect(on12(D3D_SDK_VERSION,&a,1),w,"on12-warp");device->Release();}if(warp)warp->Release();if(factory)factory->Release();
 }
 DestroyWindow(w);return 0;
}
'''.replace('#include <cstdio>','#include <cstdio>\n#include <initializer_list>')
(proof/'graphics_probe.cpp').write_text(source)
vswhere=Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
vs=subprocess.check_output([str(vswhere),'-latest','-products','*','-property','installationPath'],text=True).strip()
vc=Path(vs)/'VC/Auxiliary/Build/vcvars32.bat';out=proof/'graphics_probe.exe'
batch=proof/'build-graphics.cmd';batch.write_text('@echo off\ncall "'+str(vc)+'"\nif errorlevel 1 exit /b %errorlevel%\ncl /nologo /EHsc /std:c++17 "'+str(proof/'graphics_probe.cpp')+'" /Fe:"'+str(out)+'" /link d3d9.lib d3d12.lib dxgi.lib user32.lib\n')
subprocess.run(['cmd','/c',str(batch)],cwd=proof,check=True,timeout=100,capture_output=True)
with (proof/'graphics-capabilities.txt').open('wb') as log:subprocess.run([str(out)],cwd=proof,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=40)
