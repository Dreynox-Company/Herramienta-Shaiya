"""Package one checked-out commit; never mix an old binary into a new artifact."""
from pathlib import Path
import hashlib, json, os, re, shutil, struct, subprocess, zipfile
ROOT=Path(__file__).resolve().parents[1]
FLIGHT_RUNTIME_NAME='Shaiya_Studio_FlightV3_Runtime.zip'
FLIGHT_RUNTIME_SHA256='6d0422c69a0e5c4b7f2a42061e30a91a6c6b452afaacac53af1e7034267cb5ba'
REAL_INDEX_SHA256='a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f'
WING_POSITION_SHA256='8a2c376c898bb025550b5fe34b92a40dbbbb9e39063619cfee4756006908cd03'
WING_MON_SHA256='5fb05afe456e158f4343a904d6192efe427b9c764a058bd6be6afc688a3da94b'
PS0032_GAME_SHA256='509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d'
VEHICLE_MON_SHA256={
    'Hu':'b280b941076eb7067ed8001fce3b82d12f87eb9eff42778b6a2fd90b51ec7aab',
    'El':'a2ea784c162d11186e49cc4ba82086e02181b33bb0e22bde21a18f14cee85940',
    'Vi':'893a7c4a7c70aa93de01cd28415c164e6ea23dbe6ce5296bceab45c7afc1801b',
    'De':'ba23e03028aa99ef804402d2d0ee3dc975a45debf6e1a75e63e5fdef4e9aabf7',
}

def sha(p):
    with p.open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()
def git(*args): return subprocess.check_output(['git',*args],cwd=ROOT,text=True).strip()

def _sha256_text(value):
    return isinstance(value,str) and bool(re.fullmatch(r'[0-9a-fA-F]{64}',value))

def load_angle_hardening(release):
    evidence_path=ROOT/'qa-windows'/'angle-runtime.json'
    empty={
        'source':None,
        'hardened':False,
        'provider':None,
        'providerVersion':None,
        'releaseDllSha256':{},
        'debugCrtImports':{},
    }
    if not evidence_path.is_file():
        return empty
    data=json.loads(evidence_path.read_text(encoding='utf-8'))
    if data.get('schema')!=1:
        raise RuntimeError('ANGLE hardening evidence schema must be 1')
    if data.get('provider')!='comfy-angle' or data.get('providerVersion')!='0.1.1':
        raise RuntimeError('ANGLE hardening evidence provider/version mismatch')
    hashes=data.get('releaseDllSha256') or {}
    for name in ['libEGL.dll','libGLESv2.dll']:
        expected=str(hashes.get(name) or '').lower()
        target=release/name
        if not _sha256_text(expected) or not target.is_file() or sha(target)!=expected:
            raise RuntimeError(f'ANGLE hardening evidence does not match {name}')
    debug_imports=data.get('debugCrtImports') or {}
    hardened=(
        data.get('hardened') is True and
        isinstance(debug_imports,dict) and
        not debug_imports
    )
    return {
        'source':str(evidence_path),
        'hardened':hardened,
        'provider':data.get('provider'),
        'providerVersion':data.get('providerVersion'),
        'releaseDllSha256':hashes,
        'debugCrtImports':debug_imports,
    }

def load_real_acceptance():
    configured=os.environ.get('SHAIYA_REAL_QA_ACCEPTANCE')
    candidates=[]
    if configured:
        candidates.append(Path(configured).expanduser())
    candidates.append(ROOT/'qa-real'/'acceptance.json')
    source=next((p for p in candidates if p.is_file()),None)
    empty={
        'source':None,
        'wingPositionGameExe':False,
        'wingMonExactInstall':False,
        'vehicleMonExactInstall':False,
        'vehicleBridgeGameExe':False,
        'spkFullAuditComplete':False,
        'spkRepackReopened':False,
        'spkGameExeAccepted':False,
    }
    if source is None:
        return empty
    data=json.loads(source.read_text(encoding='utf-8'))
    if data.get('schema')!=1:
        raise RuntimeError('qa-real acceptance schema must be 1')
    wing=data.get('wing') or {}
    vehicle=data.get('vehicle') or {}
    spk=data.get('spk') or {}
    game_sha=str(data.get('gameExeSha256') or '').lower()
    if game_sha and not _sha256_text(game_sha):
        raise RuntimeError('qa-real gameExeSha256 is invalid')
    vehicle_hashes=vehicle.get('monSha256') or {}
    real_vehicle_hashes=all(
        str(vehicle_hashes.get(key) or '').lower()==expected
        for key,expected in VEHICLE_MON_SHA256.items()
    )
    wing_position_ok=(
        wing.get('positionGameExe') is True and
        str(wing.get('positionSha256') or '').lower()==WING_POSITION_SHA256
    )
    wing_mon_ok=(
        wing.get('monExactInstall') is True and
        str(wing.get('monSha256') or '').lower()==WING_MON_SHA256
    )
    vehicle_mon_ok=(
        vehicle.get('monExactInstall') is True and
        real_vehicle_hashes
    )
    ps0032_game_ok=game_sha==PS0032_GAME_SHA256
    bridge_ok=(
        vehicle.get('bridgeGameExe') is True and
        ps0032_game_ok
    )
    wing_position_ok=wing_position_ok and ps0032_game_ok
    wing_mon_ok=wing_mon_ok and ps0032_game_ok
    vehicle_mon_ok=vehicle_mon_ok and ps0032_game_ok
    spk_game_sha=str(spk.get('gameExeSha256') or '').lower()
    spk_index_ok=str(spk.get('indexSha256') or '').lower()==REAL_INDEX_SHA256
    validated_resources=spk.get('validatedResources')
    failures=spk.get('failures')
    spk_audit_ok=(
        spk_index_ok and
        spk.get('canReadSimpleResources') is True and
        spk.get('canReadFragmentedResources') is True and
        spk.get('canExtractAll') is True and
        isinstance(validated_resources,int) and
        not isinstance(validated_resources,bool) and
        validated_resources==50135 and
        isinstance(failures,int) and
        not isinstance(failures,bool) and
        failures==0
    )
    return {
        'source':str(source),
        'gameExeSha256':game_sha or None,
        'wingPositionGameExe':wing_position_ok,
        'wingMonExactInstall':wing_mon_ok,
        'vehicleMonExactInstall':vehicle_mon_ok,
        'vehicleBridgeGameExe':bridge_ok,
        'spkFullAuditComplete':spk_audit_ok,
        'spkRepackReopened':spk_audit_ok and spk.get('repackReopened') is True,
        'spkGameExeAccepted':(
            spk_audit_ok and
            spk.get('gameExeAccepted') is True and
            _sha256_text(spk_game_sha)
        ),
        'spkGameExeSha256':spk_game_sha or None,
    }

def install_flight_runtime(release):
    candidates=[]
    configured=os.environ.get('SHAIYA_FLIGHT_V3_RUNTIME')
    if configured:
        candidates.append(Path(configured).expanduser())
    candidates.extend([
        ROOT/'qa-assets'/FLIGHT_RUNTIME_NAME,
        ROOT/'Extras'/'FlightV3'/FLIGHT_RUNTIME_NAME,
    ])
    source=next((p for p in candidates if p.is_file()),None)
    if source is None:
        return None
    actual=sha(source)
    if actual!=FLIGHT_RUNTIME_SHA256:
        raise RuntimeError(
            'Flight V3 runtime hash mismatch: '
            f'{source} -> {actual}'
        )
    target=release/'Extras'/'FlightV3'/FLIGHT_RUNTIME_NAME
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)
    if sha(target)!=FLIGHT_RUNTIME_SHA256:
        raise RuntimeError('Flight V3 runtime copy verification failed')
    return target

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
        'FLIGHT_V3_REAL_RUNTIME_AUDIT.md',
        'GAME_PS0032_VEHICLE_BRIDGE.md',
        'PS0032_REAL_BINARY_CROSSCHECK.md',
        'SPK_REAL_READER_STATUS.md',
        'DATA_CAPABILITY_MATRIX.md',
        'WINDOWS_RELEASE_AUDIT.md',
        'WING_REAL_DATA_AUDIT.md',
        'VEHICLE_REAL_DATA_AUDIT.md',
        'REAL_QA_ACCEPTANCE.md',
    ]:
        source=ROOT/'docs'/name
        if source.is_file(): shutil.copy2(source,docs_target/name)
    flight_target=release/'Extras'/'FlightV3'
    flight_target.mkdir(parents=True,exist_ok=True)
    bundled_flight_runtime=install_flight_runtime(release)
    (flight_target/'LEEME_RUNTIME.txt').write_text(
        'Shaiya Studio Flight V3 Runtime\n'
        'Archivo recomendado: Shaiya_Studio_FlightV3_Runtime.zip\n'
        'SHA-256 runtime auditado: '
        f'{FLIGHT_RUNTIME_SHA256}\n'
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

    debug_crt_names={
        'msvcp140d.dll','ucrtbased.dll','vccorlib140d.dll',
        'vcruntime140_1d.dll','vcruntime140d.dll',
    }
    debug_crt=sorted(
        p.name for p in release.iterdir()
        if p.is_file() and p.name.lower() in debug_crt_names
    )
    angle_hardening=load_angle_hardening(release)
    crypto_profile={}
    profile_path=ROOT/'profiles'/'spk-crypto-profile.json'
    if profile_path.is_file():
        crypto_profile=json.loads(profile_path.read_text(encoding='utf-8'))
    resource_key_validated=bool(
        crypto_profile.get('evidence',{}).get('resourceKeyValidated') is True
    )
    real_acceptance=load_real_acceptance()
    delivery_status={
        'schema':1,
        'version':version,
        'commit':commit,
        'windows':{
            'releaseBuild':True,
            'nativeIntegration':native.get('native_render') is True,
            'startupSmoke':bool(
                startup.get('process_alive') is True and
                startup.get('native_window') is True
            ),
            'debugCrtBundled':debug_crt,
            'graphicsRuntimeHardeningEvidence':angle_hardening['source'],
            'graphicsRuntimeProvider':angle_hardening['provider'],
            'graphicsRuntimeProviderVersion':angle_hardening['providerVersion'],
            'graphicsRuntimeDllSha256':angle_hardening['releaseDllSha256'],
            'graphicsRuntimeHardeningComplete':(
                not debug_crt and angle_hardening['hardened']
            ),
        },
        'flightV3':{
            'runtimeExpectedSha256':FLIGHT_RUNTIME_SHA256,
            'sourceExpectedSha256':
                '7f720a9e339d96a6e47cdce11094ecb64663c2f80f102de179f76e7f0b2c8a44',
            'realRuntimeAuditDocumented':(ROOT/'docs'/'FLIGHT_V3_REAL_RUNTIME_AUDIT.md').is_file(),
            'runtimeBundled':bundled_flight_runtime is not None,
        },
        'spk':{
            'resourceKeyValidated':resource_key_validated,
            'fullRealAuditComplete':real_acceptance['spkFullAuditComplete'],
            'realRepackReopened':real_acceptance['spkRepackReopened'],
            'gameExeAccepted':real_acceptance['spkGameExeAccepted'],
            'gameExeSha256':real_acceptance.get('spkGameExeSha256'),
        },
        'realDataQa':{
            'evidenceSource':real_acceptance['source'],
            'gameExeSha256':real_acceptance.get('gameExeSha256'),
            'wingPositionGameExe':real_acceptance['wingPositionGameExe'],
            'wingMonExactInstall':real_acceptance['wingMonExactInstall'],
            'vehicleMonExactInstall':real_acceptance['vehicleMonExactInstall'],
            'vehicleBridgeGameExe':real_acceptance['vehicleBridgeGameExe'],
        },
    }
    blocking=[]
    if not delivery_status['windows']['graphicsRuntimeHardeningComplete']:
        blocking.append('windows-angle-release-runtime')
    if not delivery_status['flightV3']['runtimeBundled']:
        blocking.append('flight-v3-runtime-not-bundled')
    if not resource_key_validated:
        blocking.append('spk-payload-key')
    real_data_complete=all(
        delivery_status['realDataQa'][key] is True
        for key in [
            'wingPositionGameExe',
            'wingMonExactInstall',
            'vehicleMonExactInstall',
            'vehicleBridgeGameExe',
        ]
    )
    if not real_data_complete:
        blocking.append('real-data-visual-qa')
    if not (
        delivery_status['spk']['fullRealAuditComplete'] and
        delivery_status['spk']['realRepackReopened'] and
        delivery_status['spk']['gameExeAccepted']
    ):
        blocking.append('spk-50135-full-audit-and-reopen')
    delivery_status['blockingGates']=blocking
    delivery_status['productionComplete100']=not blocking
    (release/'distribution-status.json').write_text(
        json.dumps(delivery_status,ensure_ascii=False,indent=2)+'\n',
        encoding='utf-8',
    )

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
  - auditoría real del runtime Flight V3 incluida en Docs/.
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
  distribution-status.json documenta de forma automática qué gates de
  producción siguen abiertos en este ZIP concreto.

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