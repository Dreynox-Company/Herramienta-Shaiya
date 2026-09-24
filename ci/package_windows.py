"""Package one checked-out commit; never mix an old binary into a new artifact."""
from pathlib import Path
import hashlib, json, os, re, shutil, struct, subprocess, zipfile
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
        target=release/'profiles'
        if target.exists(): shutil.rmtree(target)
        shutil.copytree(profiles,target)
    if native.get('native_render') is not True: raise RuntimeError('Native integration did not report rendering')
    docs_target=release/'Docs'
    docs_target.mkdir(parents=True,exist_ok=True)
    for name in [
        'STUDIO_0620_SPK_WINGS.md',
        'EXCELXML_STUDIO_AUDIT.md',
        'GAME_PS0032_VEHICLE_BRIDGE.md',
        'SPK_REAL_READER_STATUS.md',
        'DATA_CAPABILITY_MATRIX.md',
    ]:
        source=ROOT/'docs'/name
        if source.is_file(): shutil.copy2(source,docs_target/name)
    flight_target=release/'Extras'/'FlightV3'
    flight_target.mkdir(parents=True,exist_ok=True)
    (flight_target/'LEEME_RUNTIME.txt').write_text(
        'Shaiya Studio Flight V3 Runtime\n'
        'Archivo recomendado: Shaiya_Studio_FlightV3_Runtime.zip\n'
        'SHA-256 runtime auditado: '
        '6d0422c69a0e5c4b7f2a42061e30a91a6c6b452afaacac53af1e7034267cb5ba\n'
        'Fuente completa auditada SHA-256: '
        '7f720a9e339d96a6e47cdce11094ecb64663c2f80f102de179f76e7f0b2c8a44\n'
        'Importa el ZIP desde Alas y monturas > Vuelo suplementario. '
        'Studio valida SHA256SUMS, RUNTIME_MANIFEST, ANI y rig antes de usarlo.\n',
        encoding='utf-8',
    )
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
    readme=f'''SHAIYA STUDIO {version} - DATA.SPK V13
Flight V3 + Wing/Vehicle MON + ExcelXml Lab
Version: {version}
Commit: {commit}

Extrae TODO el ZIP y abre herramienta_shaiya.exe. Conserva sus DLL y la
carpeta data de Flutter; NO reemplaces esa carpeta por la DATA del juego.

NOVEDADES 0.6.22:
  - WingPosition.xml real (SpreadsheetML): FAMILY/JOB/SEX/BONE_IDX,
    posición XYZ y rotación XYZ con guardado/revalidación.
  - Wing.MON MO2/MO4 completo: ANI, sonidos, EFT/3DE, efecto adjunto,
    partes 3DC/3DO y texturas con escritura lossless.
  - sincronización completa de slots Wing.MON: reposo, respirar, caminar,
    correr, ataques 1-3, daño y caída.
  - Flight V3: 26 transiciones, neutral/escudo, combate ON/DU/TH/SP,
    destino/fase declarados y visor de todas las secuencias.
  - ExcelXml Lab: tablas reales de DATA, celdas sparse, ss:Type,
    validación en vivo, reparación XML fail-closed y accesos por dominio.
  - Vehicle.MON completo + ps0032 VehiclePosition Studio Bridge 6DoF.
  - documentación técnica incluida en Docs/.

FLIGHT V3:
  Importa Shaiya_Studio_FlightV3_Runtime.zip desde
  Alas y monturas > Vuelo suplementario. Studio no ejecuta HTML/JS/BAT:
  verifica SHA256SUMS, RUNTIME_MANIFEST, ANI y compatibilidad de rig.
  Consulta Extras/FlightV3/LEEME_RUNTIME.txt.

DATA.SPK:
  1. Abre DATA.SPK.
  2. Pulsa Desbloquear SPK / AutoPerfil.
  3. ResourceProbe V13 usa un oráculo AES-GCM fail-closed; una candidata no
     habilita lectura si no autentica ciphertext/tag reales.
  4. Si el barrido estático no cierra el perfil, instrumenta una copia local
     de game.exe x86/x64 offline y sin credenciales.
  5. Solo simples + fragmentados + auditoría integral sin fallos habilitan
     lectura/repack; el DATA.SPK original nunca se modifica.

TRABAJO VISIBLE:
  - texturas autenticadas: preview;
  - 3DC/3DO: visor 3D y textura inequívoca;
  - SData: filas/columnas y workbench;
  - ExcelXml: editor estructurado o reparación validada;
  - Alas: WingPosition + Wing.MON completo;
  - Monturas: Vehicle.MON + calibración/bridge;
  - Mundo: mapas, agua/shader y recursos;
  - cambios SPK: overlay y construcción de un SPK separado reabierto/auditado.

DIAGNÓSTICO:
  Extras/SPK/Shaiya_SPK_ResourceProbe.exe genera evidencia reproducible.
  Revisa probe-console.log, probe-diagnosis.json, resource-observations.json,
  candidate-keys.json y static-key-sweep.json cuando AutoPerfil no cierre.

La integración Windows usa fixtures sintéticos para regresión. La aceptación
final del cliente original exige probar este build contra el par exacto
game.exe + data.spk del usuario y los recursos DATA reales.
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