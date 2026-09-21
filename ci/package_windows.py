"""Package one checked-out commit; never mix an old binary into a new artifact."""
from pathlib import Path
import hashlib, json, os, re, struct, subprocess, zipfile
ROOT=Path(__file__).resolve().parents[1]
def sha(p):
    with p.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()
def git(*args): return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()
def main():
    release=ROOT/'build/windows/x64/runner/Release'
    for relative in ['herramienta_shaiya.exe','flutter_windows.dll','data/app.so']:
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
    readme=f'''SHAIYA STUDIO 0.6 - EDITOR VISUAL Y LABORATORIO\nVersion: {version}\nCommit: {commit}\n\nExtrae TODO el ZIP y abre herramienta_shaiya.exe. Conserva sus DLL y la\ncarpeta data de Flutter; NO reemplaces esa carpeta por la DATA del juego.\nLa biblioteca original se selecciona dentro de la aplicacion.\n\nEsta revision integra las correcciones auditadas de idioma espanol,\nvuelo manual < y continuidad del movimiento. No es una\nversion 0.6 terminada ni incluye un nuevo game.exe offline.\nLos suplementos de animacion y los datos originales no estan incluidos.\nLa integracion Windows utiliza recursos sinteticos; no certifica cada\ncombinacion de modelos del cliente original.\n'''
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
