"""Package one checked-out commit; never mix an old binary into a new artifact."""
from pathlib import Path
import hashlib, json, os, re, struct, subprocess, zipfile
ROOT=Path(__file__).resolve().parents[1]
def sha(p):
    with p.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()
def git(*args): return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()
def main():
    release=ROOT/'build/windows/x64/runner/Release'
    for relative in ['herramienta_shaiya.exe','flutter_windows.dll','data/app.so','Extras/SPK/Shaiya_SPK_ResourceProbe.exe']:
        if not (release/relative).is_file(): raise RuntimeError('Missing release component: '+relative)
    exe=(release/'herramienta_shaiya.exe').read_bytes()
    pe=struct.unpack_from('<I',exe,0x3c)[0]
    if exe[:2]!=b'MZ' or exe[pe:pe+4]!=b'PE\x00\x00' or struct.unpack_from('<H',exe,pe+4)[0]!=0x8664:
        raise RuntimeError('Expected native Windows AMD64 PE executable')
    native=json.loads((ROOT/'qa-native/result.json').read_text())
    startup=json.loads((ROOT/'qa-windows/resultado.json').read_text(encoding='utf-8-sig'))
    profiles=ROOT/'profiles'
    if profiles.is_dir():
        import shutil
        target=release/'profiles'
        if target.exists(): shutil.rmtree(target)
        shutil.copytree(profiles,target)
    if native.get('native_render') is not True: raise RuntimeError('Native integration did not report rendering')
    # The smoke script already fails on a missing or closed window. Preserve its
    # raw result; do not invent field names or reinterpret it as gameplay testing.
    version=re.search(r'^version:\s*(\S+)',(ROOT/'pubspec.yaml').read_text(),re.M).group(1)
    commit=git('rev-parse','HEAD')
    files={p.relative_to(release).as_posix():{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(release.rglob('*')) if p.is_file()}
    result={'schema':1,'version':version,'commit':commit,'tree':git('rev-parse','HEAD^{tree}'),
        'repository':os.environ.get('GITHUB_REPOSITORY'),'run':os.environ.get('GITHUB_RUN_ID'),
        'platform':'windows-x64','mode':'release','files':files,
        'nativeChecks':len(native.get('checks',[])),'nativeFixture':'synthetic resources only',
        'startupResult':startup,'editor06WorkbenchDelivered':True,'completeOriginalGameRecreation':False,'offlineGameDelivered':False}
    (release/'build-provenance.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    readme=f'''SHAIYA STUDIO {version} - DATA.SPK V12
Version: {version}
Commit: {commit}

Extrae TODO el ZIP y abre herramienta_shaiya.exe. Conserva sus DLL y la
carpeta data de Flutter; NO reemplaces esa carpeta por la DATA del juego.
Abre el DATA.SPK desde la aplicacion.

FLUJO RECOMENDADO:
  1. Abre DATA.SPK.
  2. Pulsa Desbloquear SPK / AutoPerfil.
  3. ResourceProbe V12 intenta primero un barrido estatico fail-closed:
     ninguna clave se acepta si no autentica payloads reales por AES-GCM.
  4. Si no encuentra coincidencia, instrumenta una copia local de game.exe
     x86/x64. Hazlo offline y no introduzcas credenciales.
  5. Solo cuando simples + fragmentados + auditoria integral pasan, Studio
     habilita Objetos/trade, Mobs/drops, Skills, Studio 3D y repack.

TRABAJO VISIBLE:
  - texturas autenticadas tienen preview;
  - 3DC/3DO tienen visor 3D y textura asociada cuando es inequívoca;
  - SData se abre en filas/columnas;
  - Objetos/trade abre directamente Requisitos (ReqOg/Og);
  - Mobs/drops abre directamente Botin y oro;
  - Skills abre directamente Habilidades;
  - los cambios se guardan en overlay: DATA.SPK original no se modifica;
  - Construir nuevo DATA.SPK crea un archivo separado y lo reabre/audita antes
    de considerarlo valido.

DIAGNOSTICO:
Extras/SPK/Shaiya_SPK_ResourceProbe.exe genera evidencia reproducible. Si el
AutoPerfil no cierra la clave revisa probe-console.log, probe-diagnosis.json,
resource-observations.json, candidate-keys.json y static-key-sweep.json.

La integracion Windows usa fixtures sinteticos para regresion. La validacion
final del cliente original exige probar este build contra el par exacto
game.exe + data.spk del usuario.
'''
    (release/'LEEME_ACTUALIZACION.txt').write_text(readme,encoding='utf-8')
    dest=ROOT/'dist';dest.mkdir(exist_ok=True)
    output=dest/f'Shaiya-Studio-Windows-{commit[:12]}.zip'
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(release.rglob('*')):
            if p.is_file(): z.write(p,p.relative_to(release).as_posix())
    with zipfile.ZipFile(output) as z:
        if z.testzip() is not None: raise RuntimeError('ZIP verification failed')
    (dest/'SHA256.txt').write_text(f'{sha(output)}  {output.name}\n',encoding='utf-8')
    print('WINDOWS_PACKAGE_VERIFIED',output.name)
if __name__=='__main__': main()