import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class OfflineBackend {
  Process? login,world;
  String? password,token,activeFaction;
  bool ready=false;
  final void Function(String) log;
  OfflineBackend(this.log);

  String get root=>File(Platform.resolvedExecutable).parent.path;
  String saveRootFor(String faction){
    final base=Platform.environment['LOCALAPPDATA']??Directory.systemTemp.path;
    final slot=faction=='fury'?'furia':'luz';
    return '$base${Platform.pathSeparator}Dreynox${Platform.pathSeparator}ShaiyaFlutter${Platform.pathSeparator}partidas${Platform.pathSeparator}$slot';
  }

  String _hex(int bytes){
    final r=Random.secure(),b=List<int>.generate(bytes,(_)=>r.nextInt(256));
    return b.map((x)=>x.toRadixString(16).padLeft(2,'0')).join();
  }

  Future<bool> start({String faction='light'}) async {
    if(faction!='light'&&faction!='fury')throw ArgumentError.value(faction,'faction','Debe ser light o fury');
    if(Platform.environment['SHAIYA_QA_DISABLE_BACKEND']=='1'){
      log('QA visual: backend desactivado; se usan SVMAP y metadatos empaquetados.');
      return false;
    }
    if(ready&&activeFaction==faction)return true;
    if(ready&&activeFaction!=faction)await stop();
    final loginExe=File('$root${Platform.pathSeparator}servicios${Platform.pathSeparator}login${Platform.pathSeparator}Imgeneus.Login.exe');
    final worldExe=File('$root${Platform.pathSeparator}servicios${Platform.pathSeparator}world${Platform.pathSeparator}Imgeneus.World.exe');
    if(!await loginExe.exists()||!await worldExe.exists()){log('Backend offline no empaquetado; se mantiene modo visual local.');return false;}
    final save=Directory(saveRootFor(faction));await save.create(recursive:true);
    password=_hex(8);token=_hex(24);
    final env={...Platform.environment,'SHAIYA_OFFLINE_SLOT':save.path,'SHAIYA_OFFLINE_FACTION':faction,'SHAIYA_OFFLINE_PASSWORD':password!,'SHAIYA_OFFLINE_TOKEN':token!};
    try{
      login=await Process.start(loginExe.path,const [],workingDirectory:loginExe.parent.path,environment:env,mode:ProcessStartMode.detachedWithStdio);
      unawaited(_pipe(login!,'Login'));
      await _waitReady(5000);
      world=await Process.start(worldExe.path,const [],workingDirectory:worldExe.parent.path,environment:env,mode:ProcessStartMode.detachedWithStdio);
      unawaited(_pipe(world!,'World'));
      await _waitReady(5001);
      ready=true;activeFaction=faction;log('Backend offline: Login + World listos en 127.0.0.1 · facción $faction.');return true;
    }catch(e){log('Backend offline: $e');await stop();return false;}
  }

  Future<void> _pipe(Process p,String name) async {
    await for(final line in p.stdout.transform(utf8.decoder).transform(const LineSplitter())){
      if(password!=null&&password!.isNotEmpty&&line.contains(password!))continue;
      if(line.toLowerCase().contains('error')||line.toLowerCase().contains('ready')||line.contains('World'))log('$name · $line');
    }
  }

  Future<void> _waitReady(int port) async {
    final deadline=DateTime.now().add(const Duration(seconds:45));
    while(DateTime.now().isBefore(deadline)){if(await _status(port))return;await Future<void>.delayed(const Duration(milliseconds:350));}
    throw TimeoutException('El servicio local $port no llegó a ready.');
  }

  Future<bool> _status(int port) async {
    final client=HttpClient();
    client.findProxy=(_)=>'DIRECT';
    client.connectionTimeout=const Duration(seconds:1);
    try{
      final req=await client.getUrl(Uri.parse('http://127.0.0.1:$port/offline/status'));
      req.headers.set(HttpHeaders.authorizationHeader,'Bearer $token');
      final res=await req.close().timeout(const Duration(seconds:2));
      final body=await res.transform(utf8.decoder).join();
      return res.statusCode==200&&body.contains('"ready":true');
    }catch(_){return false;}finally{client.close(force:true);}
  }

  Future<void> stop() async {
    ready=false;
    for(final p in [world,login]){if(p==null)continue;try{p.kill(ProcessSignal.sigterm);}catch(_){}}
    world=null;login=null;activeFaction=null;
  }
}
