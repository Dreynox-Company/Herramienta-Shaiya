#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>
#include <cstdio>
#include <cstdarg>
#include <atomic>
// Test-only forwarding object: the system's device and internal COM tables
// remain untouched. No global device pointers, truncated tables or hooks.
static SRWLOCK guard=SRWLOCK_INIT;
static void trace(const char* fmt,...){AcquireSRWLockExclusive(&guard);FILE* f=nullptr;fopen_s(&f,"native-d3d9-trace.txt","a");if(f){va_list a;va_start(a,fmt);vfprintf(f,fmt,a);va_end(a);fputc('\n',f);fclose(f);}ReleaseSRWLockExclusive(&guard);}
class D3DTrace final:public IDirect3D9 {
 IDirect3D9* value;std::atomic<ULONG> references{1};
 public:
 explicit D3DTrace(IDirect3D9* v):value(v){}
 HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** out) override {
  if(!out)return E_POINTER;*out=nullptr;
  if(IsEqualGUID(id,__uuidof(IUnknown))||IsEqualGUID(id,__uuidof(IDirect3D9))){*out=static_cast<IDirect3D9*>(this);AddRef();return S_OK;}
  return E_NOINTERFACE;
 }
 ULONG STDMETHODCALLTYPE AddRef() override{return ++references;}
 ULONG STDMETHODCALLTYPE Release() override{ULONG n=--references;if(!n){value->Release();delete this;}return n;}
 HRESULT STDMETHODCALLTYPE RegisterSoftwareDevice(void* f) override{return value->RegisterSoftwareDevice(f);}
 UINT STDMETHODCALLTYPE GetAdapterCount() override {auto n=value->GetAdapterCount();trace("AdapterCount %u",n);return n;}
 HRESULT STDMETHODCALLTYPE GetAdapterIdentifier(UINT a,DWORD f,D3DADAPTER_IDENTIFIER9* id) override{auto hr=value->GetAdapterIdentifier(a,f,id);trace("Adapter %u result=%08x description=%s",a,hr,SUCCEEDED(hr)?id->Description:"");return hr;}
 UINT STDMETHODCALLTYPE GetAdapterModeCount(UINT a,D3DFORMAT f) override {auto n=value->GetAdapterModeCount(a,f);trace("ModeCount adapter=%u format=%u count=%u",a,f,n);return n;}
 HRESULT STDMETHODCALLTYPE EnumAdapterModes(UINT a,D3DFORMAT f,UINT n,D3DDISPLAYMODE* m) override{return value->EnumAdapterModes(a,f,n,m);}
 HRESULT STDMETHODCALLTYPE GetAdapterDisplayMode(UINT a,D3DDISPLAYMODE* m) override {auto hr=value->GetAdapterDisplayMode(a,m);trace("DisplayMode result=%08x %ux%u f=%u",hr,SUCCEEDED(hr)?m->Width:0,SUCCEEDED(hr)?m->Height:0,SUCCEEDED(hr)?m->Format:0);return hr;}
 HRESULT STDMETHODCALLTYPE CheckDeviceType(UINT a,D3DDEVTYPE t,D3DFORMAT f,D3DFORMAT b,BOOL w) override {auto hr=value->CheckDeviceType(a,t,f,b,w);trace("CheckDeviceType %u %u %u %u %d hr=%08x",a,t,f,b,w,hr);return hr;}
 HRESULT STDMETHODCALLTYPE CheckDeviceFormat(UINT a,D3DDEVTYPE t,D3DFORMAT f,DWORD u,D3DRESOURCETYPE r,D3DFORMAT q) override {auto hr=value->CheckDeviceFormat(a,t,f,u,r,q);if(FAILED(hr))trace("CheckDeviceFormat f=%u u=%x r=%u q=%u hr=%08x",f,u,r,q,hr);return hr;}
 HRESULT STDMETHODCALLTYPE CheckDeviceMultiSampleType(UINT a,D3DDEVTYPE t,D3DFORMAT f,BOOL w,D3DMULTISAMPLE_TYPE m,DWORD* q) override {auto hr=value->CheckDeviceMultiSampleType(a,t,f,w,m,q);trace("MultiSample f=%u window=%d ms=%u hr=%08x",f,w,m,hr);return hr;}
 HRESULT STDMETHODCALLTYPE CheckDepthStencilMatch(UINT a,D3DDEVTYPE t,D3DFORMAT f,D3DFORMAT b,D3DFORMAT d) override {auto hr=value->CheckDepthStencilMatch(a,t,f,b,d);trace("DepthMatch f=%u b=%u depth=%u hr=%08x",f,b,d,hr);return hr;}
 HRESULT STDMETHODCALLTYPE CheckDeviceFormatConversion(UINT a,D3DDEVTYPE t,D3DFORMAT s,D3DFORMAT d) override{return value->CheckDeviceFormatConversion(a,t,s,d);}
 HRESULT STDMETHODCALLTYPE GetDeviceCaps(UINT a,D3DDEVTYPE t,D3DCAPS9* c) override{auto hr=value->GetDeviceCaps(a,t,c);trace("Caps hr=%08x vs=%08x ps=%08x",hr,SUCCEEDED(hr)?c->VertexShaderVersion:0,SUCCEEDED(hr)?c->PixelShaderVersion:0);return hr;}
 HMONITOR STDMETHODCALLTYPE GetAdapterMonitor(UINT a) override{return value->GetAdapterMonitor(a);}
 HRESULT STDMETHODCALLTYPE CreateDevice(UINT a,D3DDEVTYPE t,HWND h,DWORD flags,D3DPRESENT_PARAMETERS* p,IDirect3DDevice9** out) override {
  trace("CreateDevice flags=%x size=%ux%u format=%u count=%u swap=%u window=%d depth=%u auto=%d",flags,p->BackBufferWidth,p->BackBufferHeight,p->BackBufferFormat,p->BackBufferCount,p->SwapEffect,p->Windowed,p->AutoDepthStencilFormat,p->EnableAutoDepthStencil);
  auto hr=value->CreateDevice(a,t,h,flags,p,out);trace("CreateDevice result=%08x",hr);return hr;
 }
};
extern "C" __declspec(dllexport) IDirect3D9* WINAPI Direct3DCreate9(UINT version){
 trace("Direct3DCreate9 sdk=%u",version);wchar_t path[MAX_PATH]={};GetSystemDirectoryW(path,MAX_PATH);wcscat_s(path,L"\\d3d9.dll");
 static HMODULE module=LoadLibraryW(path);if(!module)return nullptr;
 using Make=IDirect3D9*(WINAPI*)(UINT);auto fn=reinterpret_cast<Make>(GetProcAddress(module,"Direct3DCreate9"));
 auto value=fn?fn(version):nullptr;return value?new D3DTrace(value):nullptr;
}
