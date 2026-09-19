#!/usr/bin/env python3
"""Isolated CI diagnostic; never changes user installations or system DLLs."""
from pathlib import Path
import os,re,subprocess,sys
root=Path(sys.argv[1]).resolve();proof=Path(sys.argv[2]).resolve();proof.mkdir(exist_ok=True)
if os.environ.get('GITHUB_ACTIONS')!='true':raise SystemExit('Isolated CI only.')
config=root/'config.ini';s=config.read_text(encoding='cp1252') if config.exists() else '[VIDEO]\n'
for key,value in {'FULLSCREEN':'FALSE','SIZE_X':'1024','SIZE_Y':'768','COLOR':'32','SHADOW':'FALSE','GLOW_LEVEL':'0','TEXTURE':'LOW'}.items():
 pattern=r'(?im)^'+key+r'=.*$'
 if re.search(pattern,s):s=re.sub(pattern,key+'='+value,s)
 else:s=s.replace('[VIDEO]','[VIDEO]\n'+key+'='+value)
config.write_text(s,encoding='cp1252')
source=r'''#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>
#include <cstdio>
#include <cstdarg>
#include <atomic>
static void trace(const char* f,...){FILE* out=nullptr;fopen_s(&out,"native-d3d9-trace.txt","a");if(out){va_list a;va_start(a,f);vfprintf(out,f,a);va_end(a);fputc('\n',out);fclose(out);}}
class Diagnostic9 final: public IDirect3D9 {
 IDirect3D9* d;std::atomic<ULONG> refs{1};
 public: explicit Diagnostic9(IDirect3D9* input):d(input){}
 HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override {if(!out)return E_POINTER;*out=nullptr;if(id==__uuidof(IUnknown)||id==__uuidof(IDirect3D9)){*out=this;AddRef();return S_OK;}return E_NOINTERFACE;}
 ULONG STDMETHODCALLTYPE AddRef() override {return ++refs;}
 ULONG STDMETHODCALLTYPE Release() override {auto n=--refs;if(!n){d->Release();delete this;}return n;}
 HRESULT STDMETHODCALLTYPE RegisterSoftwareDevice(void* p) override{return d->RegisterSoftwareDevice(p);}
 UINT STDMETHODCALLTYPE GetAdapterCount() override {auto n=d->GetAdapterCount();trace("Adapters %u",n);return n;}
 HRESULT STDMETHODCALLTYPE GetAdapterIdentifier(UINT a,DWORD f,D3DADAPTER_IDENTIFIER9* o) override {auto h=d->GetAdapterIdentifier(a,f,o);trace("Adapter %u hr=%08x %s",a,h,SUCCEEDED(h)?o->Description:"");return h;}
 UINT STDMETHODCALLTYPE GetAdapterModeCount(UINT a,D3DFORMAT f) override {auto n=d->GetAdapterModeCount(a,f);trace("ModeCount %u %u -> %u",a,f,n);return n;}
 HRESULT STDMETHODCALLTYPE EnumAdapterModes(UINT a,D3DFORMAT f,UINT m,D3DDISPLAYMODE* o) override{return d->EnumAdapterModes(a,f,m,o);}
 HRESULT STDMETHODCALLTYPE GetAdapterDisplayMode(UINT a,D3DDISPLAYMODE* o) override {auto h=d->GetAdapterDisplayMode(a,o);trace("Display %u hr=%08x %ux%u f=%u",a,h,SUCCEEDED(h)?o->Width:0,SUCCEEDED(h)?o->Height:0,SUCCEEDED(h)?o->Format:0);return h;}
 HRESULT STDMETHODCALLTYPE CheckDeviceType(UINT a,D3DDEVTYPE t,D3DFORMAT f,D3DFORMAT b,BOOL w) override {auto h=d->CheckDeviceType(a,t,f,b,w);trace("CheckType %u %u/%u w=%d hr=%08x",a,f,b,w,h);return h;}
 HRESULT STDMETHODCALLTYPE CheckDeviceFormat(UINT a,D3DDEVTYPE t,D3DFORMAT f,DWORD u,D3DRESOURCETYPE r,D3DFORMAT c) override {auto h=d->CheckDeviceFormat(a,t,f,u,r,c);trace("Format f=%u use=%x r=%u c=%u hr=%08x",f,u,r,c,h);return h;}
 HRESULT STDMETHODCALLTYPE CheckDeviceMultiSampleType(UINT a,D3DDEVTYPE t,D3DFORMAT f,BOOL w,D3DMULTISAMPLE_TYPE m,DWORD* q) override{return d->CheckDeviceMultiSampleType(a,t,f,w,m,q);}
 HRESULT STDMETHODCALLTYPE CheckDepthStencilMatch(UINT a,D3DDEVTYPE t,D3DFORMAT f,D3DFORMAT r,D3DFORMAT z) override {auto h=d->CheckDepthStencilMatch(a,t,f,r,z);trace("Depth f=%u r=%u z=%u hr=%08x",f,r,z,h);return h;}
 HRESULT STDMETHODCALLTYPE CheckDeviceFormatConversion(UINT a,D3DDEVTYPE t,D3DFORMAT s,D3DFORMAT f) override{return d->CheckDeviceFormatConversion(a,t,s,f);}
 HRESULT STDMETHODCALLTYPE GetDeviceCaps(UINT a,D3DDEVTYPE t,D3DCAPS9* c) override {auto h=d->GetDeviceCaps(a,t,c);trace("Caps hr=%08x VS=%x PS=%x",h,SUCCEEDED(h)?c->VertexShaderVersion:0,SUCCEEDED(h)?c->PixelShaderVersion:0);return h;}
 HMONITOR STDMETHODCALLTYPE GetAdapterMonitor(UINT a) override{return d->GetAdapterMonitor(a);}
 HRESULT STDMETHODCALLTYPE CreateDevice(UINT a,D3DDEVTYPE t,HWND w,DWORD f,D3DPRESENT_PARAMETERS* p,IDirect3DDevice9** o) override {trace("Create a=%u t=%u flags=%x width=%u height=%u format=%u window=%u depth=%u",a,t,f,p->BackBufferWidth,p->BackBufferHeight,p->BackBufferFormat,p->Windowed,p->AutoDepthStencilFormat);auto h=d->CreateDevice(a,t,w,f,p,o);trace("Device=%08x",h);return h;}
};
extern "C" __declspec(dllexport) IDirect3D9* WINAPI ProbeCreate9(UINT version){wchar_t p[MAX_PATH]={};GetSystemDirectoryW(p,MAX_PATH);wcscat_s(p,L"\\d3d9.dll");auto m=LoadLibraryW(p);using F=IDirect3D9*(WINAPI*)(UINT);auto f=m?reinterpret_cast<F>(GetProcAddress(m,"Direct3DCreate9")):nullptr;auto d=f?f(version):nullptr;trace("Create9 %u -> %p",version,d);return d?new Diagnostic9(d):nullptr;}
'''
cpp=proof/'d3d9_trace.cpp';cpp.write_text(source)
vswhere=Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Microsoft Visual Studio/Installer/vswhere.exe'
vs=subprocess.check_output([str(vswhere),'-latest','-products','*','-property','installationPath'],text=True).strip();vc=Path(vs)/'VC/Auxiliary/Build/vcvars32.bat'
exports=proof/'d3d9.def';exports.write_text('LIBRARY d3d9\nEXPORTS\nDirect3DCreate9=_ProbeCreate9@4\n')
out=root/'d3d9.dll'
if out.exists():raise RuntimeError('Existing wrapper refused.')
batch=proof/'build-d3d-trace.cmd';batch.write_text('@echo off\ncall "'+str(vc)+'"\nif errorlevel 1 exit /b %errorlevel%\ncl /nologo /EHsc /MT /O2 /std:c++17 /LD "'+str(cpp)+'" /Fe:"'+str(out)+'" /link /DEF:"'+str(exports)+'"\n')
with (proof/'graphics-build.txt').open('wb') as log:subprocess.run(['cmd','/c',str(batch)],cwd=proof,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=100)
trace=root/'native-d3d9-trace.txt';trace.touch();os.link(trace,proof/'native-d3d9-trace.txt')
