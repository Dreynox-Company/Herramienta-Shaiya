// Diagnostic only, installed in the public reference client on CI.
// Records message-box caller RVAs, forwards the original call unchanged.
#include <cstring>
using BoxA=int(WINAPI*)(HWND,LPCSTR,LPCSTR,UINT);
using BoxW=int(WINAPI*)(HWND,LPCWSTR,LPCWSTR,UINT);
static BoxA originalBoxA=nullptr;static BoxW originalBoxW=nullptr;
static void errorStack(){void* stack[24]={};auto n=CaptureStackBackTrace(0,24,stack,nullptr);auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));trace("Native image base=%p",reinterpret_cast<void*>(base));for(USHORT i=0;i<n;i++){HMODULE owner=nullptr;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(stack[i]),&owner);wchar_t name[MAX_PATH]={};GetModuleFileNameW(owner,name,MAX_PATH);trace("Stack[%u] addr=%p rva=%08x owner=%ls",i,stack[i],static_cast<unsigned>(reinterpret_cast<uintptr_t>(stack[i])-reinterpret_cast<uintptr_t>(owner)),name);}}
static int WINAPI diagnosticBoxA(HWND w,LPCSTR text,LPCSTR title,UINT flags){trace("MessageBoxA title=%s flags=%x",title?title:"",flags);errorStack();return originalBoxA(w,text,title,flags);}
static int WINAPI diagnosticBoxW(HWND w,LPCWSTR text,LPCWSTR title,UINT flags){trace("MessageBoxW title=%ls flags=%x",title?title:L"",flags);errorStack();return originalBoxW(w,text,title,flags);}
static void installErrors(){
 static bool done=false;if(done)return;done=true;
 auto base=reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));auto dos=reinterpret_cast<IMAGE_DOS_HEADER*>(base);if(dos->e_magic!=IMAGE_DOS_SIGNATURE)return;
 auto nt=reinterpret_cast<IMAGE_NT_HEADERS*>(base+dos->e_lfanew);if(nt->Signature!=IMAGE_NT_SIGNATURE)return;
 auto dir=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];if(!dir.VirtualAddress)return;
 for(auto descriptor=reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base+dir.VirtualAddress);descriptor->Name;descriptor++){
  if(!descriptor->OriginalFirstThunk)continue;
  auto names=reinterpret_cast<IMAGE_THUNK_DATA*>(base+descriptor->OriginalFirstThunk),iat=reinterpret_cast<IMAGE_THUNK_DATA*>(base+descriptor->FirstThunk);
  for(;names->u1.AddressOfData;names++,iat++){
   if(IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal))continue;
   auto symbol=reinterpret_cast<IMAGE_IMPORT_BY_NAME*>(base+names->u1.AddressOfData);void* replacement=nullptr;
   if(std::strcmp(reinterpret_cast<const char*>(symbol->Name),"MessageBoxA")==0){originalBoxA=reinterpret_cast<BoxA>(iat->u1.Function);replacement=reinterpret_cast<void*>(&diagnosticBoxA);}
   if(std::strcmp(reinterpret_cast<const char*>(symbol->Name),"MessageBoxW")==0){originalBoxW=reinterpret_cast<BoxW>(iat->u1.Function);replacement=reinterpret_cast<void*>(&diagnosticBoxW);}
   if(replacement){DWORD old=0;if(VirtualProtect(&iat->u1.Function,sizeof(void*),PAGE_READWRITE,&old)){iat->u1.Function=reinterpret_cast<ULONG_PTR>(replacement);DWORD ignored;VirtualProtect(&iat->u1.Function,sizeof(void*),old,&ignored);}}
  }
 }
}
