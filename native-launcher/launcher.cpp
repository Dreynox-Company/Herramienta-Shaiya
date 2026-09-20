// Native launcher for the original ps0032 client. Does not embed a browser.
// No network destination other than loopback is used by this launcher.
#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#include <winhttp.h>
#include <bcrypt.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <winioctl.h>
#include <commctrl.h>
#include <shellapi.h>
#include <filesystem>
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <thread>
#include <atomic>
#include <stdexcept>
#include <algorithm>
namespace fs=std::filesystem;
const wchar_t *APP=L"Shaiya · Partida local",*HASH=L"509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d";
const UINT STATUS=WM_APP+1,DONE=WM_APP+2;
HWND wnd,pathBox,statusBox,startBtn,browseBtn,factionBox,bar;
HFONT font,titleFont;fs::path root,home,dataPath;std::atomic_bool running(false);
std::wstring lastError;HANDLE oneInstance=nullptr;
struct Handle{HANDLE v=nullptr;~Handle(){if(v&&v!=INVALID_HANDLE_VALUE)CloseHandle(v);}Handle(){}explicit Handle(HANDLE h):v(h){}Handle(const Handle&)=delete;};
struct Child{HANDLE process=nullptr;DWORD pid=0;};
std::wstring wide(const std::string& s){if(s.empty())return L"";int n=MultiByteToWideChar(CP_UTF8,0,s.data(),(int)s.size(),nullptr,0);std::wstring t(n,0);MultiByteToWideChar(CP_UTF8,0,s.data(),(int)s.size(),t.data(),n);return t;}
std::string utf8(const std::wstring& s){int n=WideCharToMultiByte(CP_UTF8,0,s.data(),(int)s.size(),nullptr,0,nullptr,nullptr);std::string t(n,0);WideCharToMultiByte(CP_UTF8,0,s.data(),(int)s.size(),t.data(),n,nullptr,nullptr);return t;}
[[noreturn]] void fail(const std::wstring& s){throw std::runtime_error(utf8(s));}
void require(bool b,const std::wstring& s){if(!b)fail(s);}
std::wstring systemError(){wchar_t* b=nullptr;DWORD e=GetLastError();FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER|FORMAT_MESSAGE_FROM_SYSTEM|FORMAT_MESSAGE_IGNORE_INSERTS,nullptr,e,0,(LPWSTR)&b,0,nullptr);std::wstring r=b?b:L"Error de Windows";if(b)LocalFree(b);return r+L" ("+std::to_wstring(e)+L")";}
void status(const std::wstring& s,int step=0){PostMessageW(wnd,STATUS,step,(LPARAM)new std::wstring(s));}
std::wstring quote(const std::wstring& s){std::wstring o=L"\"";size_t slashes=0;for(auto c:s){if(c==L'\\'){slashes++;continue;}if(c==L'\"')o.append(slashes*2+1,L'\\');else o.append(slashes,L'\\');slashes=0;o+=c;}o.append(slashes*2,L'\\');return o+L'\"';}
std::wstring hashFile(const fs::path& p){
 BCRYPT_ALG_HANDLE a=nullptr;BCRYPT_HASH_HANDLE h=nullptr;DWORD len=0,ret=0;std::vector<unsigned char> obj,digest(32);std::ifstream f(p,std::ios::binary);
 require(bool(f),L"No se puede leer: "+p.wstring());
 require(BCryptOpenAlgorithmProvider(&a,BCRYPT_SHA256_ALGORITHM,nullptr,0)>=0,L"SHA-256 no disponible.");
 bool ok=BCryptGetProperty(a,BCRYPT_OBJECT_LENGTH,(PUCHAR)&len,sizeof(len),&ret,0)>=0;obj.resize(len);
 ok=ok&&BCryptCreateHash(a,&h,obj.data(),len,nullptr,0,0)>=0;
 char block[65536];while(ok&&f){f.read(block,sizeof(block));auto n=f.gcount();if(n)ok=BCryptHashData(h,(PUCHAR)block,(ULONG)n,0)>=0;}
 ok=ok&&!f.bad()&&BCryptFinishHash(h,digest.data(),32,0)>=0;
 if(h){BCryptDestroyHash(h);}
 BCryptCloseAlgorithmProvider(a,0);require(ok,L"No se pudo verificar SHA-256.");
 std::wstring s;for(auto x:digest){s+=L"0123456789abcdef"[x>>4];s+=L"0123456789abcdef"[x&15];}return s;
}
std::wstring randomHex(int bytes){std::vector<UCHAR>b(bytes);require(BCryptGenRandom(nullptr,b.data(),bytes,BCRYPT_USE_SYSTEM_PREFERRED_RNG)>=0,L"No se pudo generar la sesión local.");std::wstring s;for(auto c:b){s+=L"0123456789abcdef"[c>>4];s+=L"0123456789abcdef"[c&15];}return s;}
std::vector<wchar_t> environment(const std::map<std::wstring,std::wstring>& overrides){
 struct CI{bool operator()(const std::wstring&a,const std::wstring&b)const{return _wcsicmp(a.c_str(),b.c_str())<0;}};
 std::map<std::wstring,std::wstring,CI> m;LPWCH e=GetEnvironmentStringsW();require(e!=nullptr,L"No se pudo leer el entorno.");
 for(auto p=e;*p;p+=wcslen(p)+1){std::wstring line=p;auto i=line.find(L'=',line[0]==L'='?1:0);if(i==std::wstring::npos)continue;auto k=line.substr(0,i);if(_wcsnicmp(k.c_str(),L"SHAIYA_OFFLINE_",15)!=0)m[k]=line.substr(i+1);}
 FreeEnvironmentStringsW(e);for(auto&[k,v]:overrides)m[k]=v;
 std::vector<wchar_t>b;for(auto&[k,v]:m){auto s=k+L"="+v;b.insert(b.end(),s.begin(),s.end());b.push_back(0);}b.push_back(0);return b;
}
bool validData(const fs::path& p){std::error_code e;return fs::is_directory(p/L"Character",e)&&fs::is_directory(p/L"World",e)&&fs::is_directory(p/L"Interface",e);}
fs::path chooseFolder(){
 fs::path p;IFileDialog*d=nullptr;if(SUCCEEDED(CoCreateInstance(CLSID_FileOpenDialog,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&d)))){
 DWORD flags=0;d->GetOptions(&flags);d->SetOptions(flags|FOS_PICKFOLDERS|FOS_FORCEFILESYSTEM|FOS_PATHMUSTEXIST);d->SetTitle(L"Selecciona DATA_Español o DATA: contiene Character, World e Interface");
 if(SUCCEEDED(d->Show(wnd))){IShellItem*i=nullptr;if(SUCCEEDED(d->GetResult(&i))){PWSTR s=nullptr;if(SUCCEEDED(i->GetDisplayName(SIGDN_FILESYSPATH,&s))){p=s;CoTaskMemFree(s);}i->Release();}}d->Release();}return p;
}
// A directory junction references resources without copying or modifying them.
void junction(const fs::path& link,const fs::path& target){
 if(GetFileAttributesW(link.c_str())!=INVALID_FILE_ATTRIBUTES){std::error_code ec;if(fs::equivalent(link,target,ec)&&!ec)return;DWORD a=GetFileAttributesW(link.c_str());require((a&FILE_ATTRIBUTE_REPARSE_POINT)!=0,L"Ya existe una carpeta data normal dentro de cliente. No se sustituirá.");
  Handle old(CreateFileW(link.c_str(),0,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_BACKUP_SEMANTICS,nullptr));
  BYTE buffer[MAXIMUM_REPARSE_DATA_BUFFER_SIZE];DWORD n=0;require(old.v!=INVALID_HANDLE_VALUE&&DeviceIoControl(old.v,FSCTL_GET_REPARSE_POINT,nullptr,0,buffer,sizeof(buffer),&n,nullptr),L"No se pudo inspeccionar la unión data.");
  require(*(DWORD*)buffer==IO_REPARSE_TAG_MOUNT_POINT,L"data no es una unión de directorio creada para recursos.");CloseHandle(old.v);old.v=nullptr;
  require(RemoveDirectoryW(link.c_str()),L"No se pudo quitar la unión anterior; no se modificó DATA.");
 }
 auto t=fs::absolute(target).lexically_normal().wstring();require(t.rfind(L"\\\\",0)!=0&&t.size()<1000,L"Selecciona una carpeta local; rutas de red no admitidas.");
 require(CreateDirectoryW(link.c_str(),nullptr),L"No se pudo crear la unión de recursos: "+systemError());
 std::wstring sub=L"\\??\\"+t;size_t sb=sub.size()*2,pb=t.size()*2,total=16+sb+2+pb+2;std::vector<BYTE>buf(total,0);
 *(DWORD*)(buf.data())=IO_REPARSE_TAG_MOUNT_POINT;*(USHORT*)(buf.data()+4)=(USHORT)(total-8);
 *(USHORT*)(buf.data()+8)=0;*(USHORT*)(buf.data()+10)=(USHORT)sb;*(USHORT*)(buf.data()+12)=(USHORT)(sb+2);*(USHORT*)(buf.data()+14)=(USHORT)pb;
 memcpy(buf.data()+16,sub.data(),sb);memcpy(buf.data()+16+sb+2,t.data(),pb);
 Handle h(CreateFileW(link.c_str(),GENERIC_WRITE,0,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_BACKUP_SEMANTICS,nullptr));DWORD n=0;
 bool ok=h.v!=INVALID_HANDLE_VALUE&&DeviceIoControl(h.v,FSCTL_SET_REPARSE_POINT,buf.data(),(DWORD)buf.size(),nullptr,0,&n,nullptr);
 auto err=systemError();if(!ok){CloseHandle(h.v);h.v=nullptr;RemoveDirectoryW(link.c_str());fail(L"No se pudo enlazar DATA. Usa una unidad NTFS local. "+err);}
}
bool portFree(USHORT port){SOCKET s=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(s==INVALID_SOCKET)return false;BOOL x=TRUE;setsockopt(s,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,(const char*)&x,sizeof(x));sockaddr_in a{};a.sin_family=AF_INET;a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);a.sin_port=htons(port);bool ok=bind(s,(sockaddr*)&a,sizeof(a))==0;closesocket(s);return ok;}
std::wstring timestamp(){SYSTEMTIME t;GetLocalTime(&t);wchar_t b[40];swprintf(b,40,L"%04u%02u%02u-%02u%02u%02u-%lu",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond,GetCurrentProcessId());return b;}
Child spawn(const fs::path& exe,const std::wstring& args,const fs::path& cwd,const std::map<std::wstring,std::wstring>& env,const fs::path& log,HANDLE job){
 SECURITY_ATTRIBUTES sa{sizeof(sa),nullptr,TRUE};Handle file(CreateFileW(log.c_str(),GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE,&sa,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr));
 Handle input(CreateFileW(L"NUL",GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,&sa,OPEN_EXISTING,0,nullptr));require(file.v!=INVALID_HANDLE_VALUE&&input.v!=INVALID_HANDLE_VALUE,L"No se pudieron abrir los registros locales.");
 STARTUPINFOW si{};si.cb=sizeof(si);si.dwFlags=STARTF_USESTDHANDLES|STARTF_USESHOWWINDOW;si.wShowWindow=(exe.filename()==L"game.exe")?SW_SHOWNORMAL:SW_HIDE;si.hStdOutput=file.v;si.hStdError=file.v;si.hStdInput=input.v;
 PROCESS_INFORMATION pi{};auto en=environment(env);auto cmd=quote(exe.wstring())+L" "+args;
 if(!CreateProcessW(exe.c_str(),cmd.data(),nullptr,nullptr,TRUE,CREATE_UNICODE_ENVIRONMENT|CREATE_NEW_PROCESS_GROUP|CREATE_SUSPENDED,en.data(),cwd.c_str(),&si,&pi)){fail(L"No se pudo iniciar "+exe.filename().wstring()+L": "+systemError());}
 if(job&&!AssignProcessToJobObject(job,pi.hProcess)){TerminateProcess(pi.hProcess,1);CloseHandle(pi.hProcess);CloseHandle(pi.hThread);fail(L"No se pudo aislar el proceso local: "+systemError());}
 ResumeThread(pi.hThread);CloseHandle(pi.hThread);return{pi.hProcess,pi.dwProcessId};
}
bool alive(const Child& c){return c.process&&WaitForSingleObject(c.process,0)==WAIT_TIMEOUT;}
bool ready(int port,const std::wstring& token){
 auto h=WinHttpOpen(L"Dreynox-Shaiya-Offline/0.1",WINHTTP_ACCESS_TYPE_NO_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0);if(!h)return false;WinHttpSetTimeouts(h,800,800,800,800);
 auto c=WinHttpConnect(h,L"127.0.0.1",(INTERNET_PORT)port,0);auto r=c?WinHttpOpenRequest(c,L"GET",L"/offline/status",nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,0):nullptr;
 DWORD code=0,n=sizeof(code);std::string body;bool ok=false;
 if(r){auto auth=L"Authorization: Bearer "+token+L"\r\n";if(WinHttpSendRequest(r,auth.c_str(),(DWORD)auth.size(),nullptr,0,0,0)&&WinHttpReceiveResponse(r,nullptr)&&WinHttpQueryHeaders(r,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,nullptr,&code,&n,nullptr)&&code==200){char b[512];DWORD read=0;while(WinHttpReadData(r,b,sizeof(b),&read)&&read&&body.size()<4096)body.append(b,read);ok=body.find("\"ready\":true")!=std::string::npos&&body.find("imgeneus-offline")!=std::string::npos;}WinHttpCloseHandle(r);}if(c)WinHttpCloseHandle(c);WinHttpCloseHandle(h);return ok;
}
void waitReady(const Child& c,int port,const std::wstring& token){for(int i=0;i<120;i++){require(alive(c),L"El servicio terminó antes de estar listo. Revisa los registros de esta sesión.");if(ready(port,token))return;Sleep(500);}fail(L"El servicio no respondió a tiempo. Revisa los registros; no se inició el juego.");}
bool stop(Child& c){if(!c.process)return true;bool clean=true;if(alive(c)){GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT,c.pid);if(WaitForSingleObject(c.process,20000)!=WAIT_OBJECT_0){clean=false;TerminateProcess(c.process,2);WaitForSingleObject(c.process,5000);}}CloseHandle(c.process);c={};return clean;}
void play(fs::path data,std::wstring faction){
 Child login,world,game;Handle job(CreateJobObjectW(nullptr,nullptr));fs::path logs;bool ok=false;
 try{
  require(job.v!=nullptr,L"No se pudo crear el grupo de procesos.");JOBOBJECT_EXTENDED_LIMIT_INFORMATION ji{};ji.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;require(SetInformationJobObject(job.v,JobObjectExtendedLimitInformation,&ji,sizeof(ji)),L"No se pudo aislar la partida.");
  status(L"Comprobando cliente ps0032 y recursos originales…",10);
  require(validData(data),L"La carpeta seleccionada no contiene Character, World e Interface.");
  require(hashFile(root/L"cliente/game.exe")==HASH,L"El game.exe no coincide con ps0032. No se ejecutó ni modificó.");
  for(auto p:{30800,30810,5000,5001})require(portFree((USHORT)p),L"El puerto local "+std::to_wstring(p)+L" ya está ocupado. Cierra la otra instancia; no se finalizarán procesos ajenos.");
  require(fs::exists(root/L"servicios/login/Imgeneus.Login.exe")&&fs::exists(root/L"servicios/world/Imgeneus.World.exe"),L"Faltan los servicios. Extrae todo el ZIP, no solo el EXE.");
  junction(root/L"cliente/data",data);
  auto slot=home/L"partidas"/(faction==L"light"?L"luz":L"furia");fs::create_directories(slot);logs=home/L"registros"/timestamp();fs::create_directories(logs);
  std::ofstream journal(logs/L"sesion.txt");journal<<"native ps0032 original; loopback only; launcher 0.1\n";
  auto pass=randomHex(8),token=randomHex(24);std::map<std::wstring,std::wstring> env{{L"SHAIYA_OFFLINE_SLOT",slot.wstring()},{L"SHAIYA_OFFLINE_FACTION",faction},{L"SHAIYA_OFFLINE_PASSWORD",pass},{L"SHAIYA_OFFLINE_TOKEN",token}};
  status(L"Iniciando cuenta local y abriendo la partida guardada…",30);
  login=spawn(root/L"servicios/login/Imgeneus.Login.exe",L"",root/L"servicios/login",env,logs/L"login.log",job.v);waitReady(login,5000,token);journal<<"login ready\n";journal.flush();
  status(L"Cargando mapas, personajes no jugadores y criaturas…",55);
  world=spawn(root/L"servicios/world/Imgeneus.World.exe",L"",root/L"servicios/world",env,logs/L"mundo.log",job.v);waitReady(world,5001,token);Sleep(2500);require(alive(login)&&alive(world),L"Un servicio se detuvo antes de abrir el juego.");journal<<"world ready\n";journal.flush();
  status(L"Abriendo el juego nativo. Selecciona el servidor local si aparece la lista.",85);
  // This is the client's own documented startup command, not a login-screen hack.
  game=spawn(root/L"cliente/game.exe",L"start 127.0.0.1 "+quote(L"localplayer:"+pass),root/L"cliente",{},logs/L"cliente.log",nullptr);
  auto started=GetTickCount64();status(L"Juego abierto. Cierra Shaiya desde su menú para guardar y terminar.",100);
  while(alive(game)){require(alive(world)&&alive(login),L"Un servicio local se cerró mientras el juego estaba abierto. Cierra Shaiya y consulta los registros.");Sleep(500);}
  DWORD exit=0;GetExitCodeProcess(game.process,&exit);auto duration=GetTickCount64()-started;journal<<"native exit code="<<exit<<" duration_ms="<<duration<<"\n";CloseHandle(game.process);game={};
  status(L"Guardando la partida. Espera 15 segundos antes de cerrar…",90);Sleep(15000);bool a=stop(world),b=stop(login);journal<<"clean service shutdown="<<(a&&b)<<"\n";
  require(a&&b,L"Un servicio no completó su cierre normal. Revisa los registros antes de volver a abrir.");require(exit==0,L"El cliente terminó con un error de Windows ("+std::to_wstring(exit)+L"). Los originales no se modificaron.");
  if(duration<12000)status(L"El cliente se cerró enseguida. Revisa su mensaje y los registros; no se confirma entrada al mundo.",0);
  else status(L"Sesión finalizada. Los servicios locales están cerrados.",0);
  ok=true;
 }catch(const std::exception&e){
  // Never terminate the player's game silently. Close its visible window first.
  if(alive(game)){lastError=L"Cierra la ventana de Shaiya para terminar la sesión con seguridad. "+wide(e.what());status(lastError,0);while(alive(game))Sleep(500);}
  if(game.process){CloseHandle(game.process);if(alive(world))Sleep(15000);}
  stop(world);stop(login);lastError=wide(e.what());if(!logs.empty())lastError+=L"\r\n\r\nRegistros: "+logs.wstring();status(L"La sesión se detuvo: "+wide(e.what()),0);
 }
 running=false;PostMessageW(wnd,DONE,ok?1:0,0);
}
void setData(const fs::path& p){dataPath=p;SetWindowTextW(pathBox,p.c_str());WritePrivateProfileStringW(L"Recursos",L"Data",p.c_str(),(home/L"launcher.ini").c_str());}
HWND control(const wchar_t* cls,const wchar_t* text,DWORD style,int x,int y,int w,int h,int id){auto c=CreateWindowExW(0,cls,text,WS_CHILD|WS_VISIBLE|style,x,y,w,h,wnd,(HMENU)(INT_PTR)id,GetModuleHandleW(nullptr),nullptr);SendMessageW(c,WM_SETFONT,(WPARAM)font,TRUE);return c;}
LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){
 switch(m){case WM_CREATE:{wnd=h;font=CreateFontW(-16,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI");titleFont=CreateFontW(-29,0,0,0,FW_SEMIBOLD,FALSE,FALSE,FALSE,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,L"Segoe UI");
 auto title=control(L"STATIC",L"Shaiya · Partida local",0,26,20,600,46,0);SendMessageW(title,WM_SETFONT,(WPARAM)titleFont,TRUE);
 control(L"STATIC",L"Cliente nativo ps0032 · Recursos del juego · Sin servidor externo",0,28,71,624,27,0);
 control(L"STATIC",L"Carpeta DATA_Español / DATA",0,28,116,600,24,0);pathBox=control(L"EDIT",L"",WS_BORDER|ES_READONLY|ES_AUTOHSCROLL,28,146,483,32,0);browseBtn=control(L"BUTTON",L"Seleccionar…",WS_TABSTOP,525,146,132,32,101);
 control(L"STATIC",L"Partida guardada",0,28,200,190,24,0);factionBox=control(WC_COMBOBOXW,L"",CBS_DROPDOWNLIST|WS_TABSTOP,210,195,235,160,0);SendMessageW(factionBox,CB_ADDSTRING,0,(LPARAM)L"Alianza de la Luz");SendMessageW(factionBox,CB_ADDSTRING,0,(LPARAM)L"Unión de la Furia");SendMessageW(factionBox,CB_SETCURSEL,0,0);
 control(L"STATIC",L"Cada facción tiene un guardado separado. Los personajes se crean dentro de Shaiya.",0,28,241,620,40,0);
 startBtn=control(L"BUTTON",L"Entrar al juego offline",BS_DEFPUSHBUTTON|WS_TABSTOP,28,294,264,44,102);control(L"BUTTON",L"Guardados y registros",WS_TABSTOP,308,294,221,44,103);control(L"BUTTON",L"Leer notas",WS_TABSTOP,541,294,116,44,104);
 bar=control(PROGRESS_CLASSW,L"",0,28,363,628,8,0);SendMessageW(bar,PBM_SETRANGE,0,MAKELPARAM(0,100));statusBox=control(L"STATIC",L"Preparado. Selecciona tus recursos y pulsa Entrar al juego offline.",0,28,389,626,60,0);
 control(L"STATIC",L"No reemplaza ni modifica tu instalación original. Mantén este paquete completo.",0,28,462,630,35,0);
 HICON icon=ExtractIconW(GetModuleHandleW(nullptr),(root/L"cliente/game.exe").c_str(),0);if(icon&&(UINT_PTR)icon>1){SendMessageW(h,WM_SETICON,ICON_BIG,(LPARAM)icon);SendMessageW(h,WM_SETICON,ICON_SMALL,(LPARAM)icon);}return 0;}
 case WM_COMMAND:switch(LOWORD(w)){case 101:{auto p=chooseFolder();if(!p.empty()){if(validData(p))setData(p);else MessageBoxW(h,L"Selecciona la carpeta que contiene Character, World e Interface, no la carpeta Character sola.",APP,MB_ICONWARNING);}break;}
 case 102:if(!running){if(!validData(dataPath)){auto p=chooseFolder();if(p.empty())break;if(!validData(p)){MessageBoxW(h,L"No se encontraron Character, World e Interface en esa carpeta.",APP,MB_ICONWARNING);break;}setData(p);}running=true;EnableWindow(startBtn,FALSE);EnableWindow(browseBtn,FALSE);EnableWindow(factionBox,FALSE);auto fac=SendMessageW(factionBox,CB_GETCURSEL,0,0)==1?L"fury":L"light";std::thread(play,dataPath,std::wstring(fac)).detach();}break;
 case 103:ShellExecuteW(h,L"open",home.c_str(),nullptr,nullptr,SW_SHOWNORMAL);break;
 case 104:ShellExecuteW(h,L"open",(root/L"LEEME.txt").c_str(),nullptr,nullptr,SW_SHOWNORMAL);break;}return 0;
 case STATUS:{auto*s=(std::wstring*)l;SetWindowTextW(statusBox,s->c_str());delete s;SendMessageW(bar,PBM_SETPOS,w,0);return 0;}
 case DONE:EnableWindow(startBtn,TRUE);EnableWindow(browseBtn,TRUE);EnableWindow(factionBox,TRUE);if(!w)MessageBoxW(h,lastError.c_str(),APP,MB_OK|MB_ICONWARNING);return 0;
 case WM_CLOSE:if(running){MessageBoxW(h,L"Cierra primero Shaiya desde su menú. Así se guarda la partida y los servicios se cierran en orden.",APP,MB_ICONINFORMATION);return 0;}DestroyWindow(h);return 0;
 case WM_DESTROY:PostQuitMessage(0);return 0;
 }return DefWindowProcW(h,m,w,l);
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,PWSTR command,int show){
 try{
  SYSTEM_INFO si;GetNativeSystemInfo(&si);require(si.wProcessorArchitecture!=PROCESSOR_ARCHITECTURE_INTEL,L"Los servicios requieren Windows de 64 bits.");
  wchar_t path[32768];DWORD n=GetModuleFileNameW(nullptr,path,32768);require(n>0&&n<32768,L"Ruta del lanzador no válida.");root=fs::path(path).parent_path();
  PWSTR appdata=nullptr;require(SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&appdata)),L"No se encontró la carpeta local de usuario.");home=fs::path(appdata)/L"Dreynox/ShaiyaOffline";CoTaskMemFree(appdata);fs::create_directories(home);
  oneInstance=CreateMutexW(nullptr,TRUE,L"Local\\DreynoxShaiyaOfflinePs0032");require(oneInstance&&GetLastError()!=ERROR_ALREADY_EXISTS,L"El lanzador offline ya está abierto en esta sesión.");
  WSADATA ws;require(WSAStartup(MAKEWORD(2,2),&ws)==0,L"No se pudo inicializar la conexión local.");
  // A private hidden console lets .NET handle targeted CTRL_BREAK cleanly.
  require(AllocConsole()!=0,L"No se pudo preparar el cierre ordenado de los servicios.");ShowWindow(GetConsoleWindow(),SW_HIDE);
  CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);SetProcessDPIAware();INITCOMMONCONTROLSEX cc{sizeof(cc),ICC_PROGRESS_CLASS};InitCommonControlsEx(&cc);
  WNDCLASSW wc{};wc.lpfnWndProc=proc;wc.hInstance=instance;wc.lpszClassName=L"DreynoxShaiyaOffline";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);wc.hbrBackground=(HBRUSH)(COLOR_WINDOW+1);RegisterClassW(&wc);
  RECT rect{0,0,685,515};AdjustWindowRect(&rect,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX,FALSE);
  wnd=CreateWindowW(wc.lpszClassName,APP,WS_OVERLAPPED|WS_CAPTION|WS_SYSMENU|WS_MINIMIZEBOX,CW_USEDEFAULT,CW_USEDEFAULT,rect.right-rect.left,rect.bottom-rect.top,nullptr,nullptr,instance,nullptr);require(wnd!=nullptr,L"No se pudo abrir el lanzador.");
  wchar_t saved[32768]={0};GetPrivateProfileStringW(L"Recursos",L"Data",L"",saved,32768,(home/L"launcher.ini").c_str());
  std::vector<fs::path> candidates{fs::path(saved),root/L"DATA_Español",root/L"data",root.parent_path()/L"DATA_Español",root.parent_path()/L"DATA"};for(auto&p:candidates)if(!p.empty()&&validData(p)){setData(p);break;}
  ShowWindow(wnd,show);UpdateWindow(wnd);if(command&&std::wstring(command)==L"--autostart"){PostMessageW(wnd,WM_COMMAND,102,0);}
  MSG msg;while(GetMessageW(&msg,nullptr,0,0)>0){if(!IsDialogMessageW(wnd,&msg)){TranslateMessage(&msg);DispatchMessageW(&msg);}}
  CoUninitialize();WSACleanup();FreeConsole();ReleaseMutex(oneInstance);CloseHandle(oneInstance);DeleteObject(font);DeleteObject(titleFont);return 0;
 }catch(const std::exception&e){MessageBoxW(nullptr,wide(e.what()).c_str(),APP,MB_ICONERROR);return 1;}
}
