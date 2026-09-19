"""Package only the independently compiled Flutter game, not the original PE."""
from pathlib import Path
import hashlib, json, struct, subprocess, zipfile
ROOT=Path(__file__).resolve().parents[1]
def digest(p):
    with p.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def main():
    release=ROOT/'ingenieria_inversa/flutter_game/build/windows/x64/runner/Release'
    for name in ['game.exe','flutter_windows.dll','data/app.so']:
        if not (release/name).is_file():raise RuntimeError('Falta '+name)
    b=(release/'game.exe').read_bytes();o=struct.unpack_from('<I',b,60)[0]
    if b[:2]!=b'MZ' or b[o:o+4]!=b'PE\0\0' or struct.unpack_from('<H',b,o+4)[0]!=0x8664:raise RuntimeError('PE x64 inválido')
    checks=json.loads((ROOT/'qa-game/local-game/result.json').read_text())
    if checks.get('native_render') is not True:raise RuntimeError('Falta integración nativa')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    provenance={'schema':1,'name':'Shaiya Local','version':'0.1.0+1','commit':revision,'engine':'Flutter independent reconstruction','originalExecutableModified':False,'completeShaiyaReconstruction':False,'nativeChecks':checks,'files':{p.relative_to(release).as_posix():{'sha256':digest(p),'bytes':p.stat().st_size} for p in sorted(release.rglob('*')) if p.is_file()}}
    (release/'build-provenance.json').write_text(json.dumps(provenance,indent=2,ensure_ascii=False),encoding='utf-8')
    (release/'LEEME_CLIENTE.txt').write_text('''SHAIYA LOCAL 0.1 — CLIENTE FLUTTER INDEPENDIENTE
Extrae en una carpeta NUEVA y ejecuta game.exe con todas sus DLL/data juntas.
NO reemplaces con él el game.exe original ni mezcles las carpetas data.
Selecciona la DATA extraída o el par SAH/SAF del juego desde el menú.
Crea una partida Luz/Furia, abre el panel, elige mapa y añade encuentros.
WASD: movimiento; Shift: correr; Espacio: salto; Shift+Espacio: alternar
vuelo únicamente con alas y suplemento ANI compatible. 1-4: atacar.
El editor de datos abre desde la sesión. Al volver, recarga lo guardado.
El laboratorio exporta una escena JSON que el cliente puede seguir localmente
para aplicar equipo, anclajes y posición. No modifica archivos ANI/3DC.

Esta reconstrucción utiliza los lectores de formatos y el motor 3D del editor.
El combate, oro, experiencia, pociones y partidas son reglas locales explícitas.
No incluye todas las misiones, IA, habilidades ni balance del servidor original.
Los recursos gráficos originales y suplementos se seleccionan localmente.
Las partidas se guardan bajo soporte de aplicación/ShaiyaLocal/partidas.
El cierre solicita guardar; un conflicto evita sobrescribir otra revisión.
El otro paquete nativo ps0032 contiene servicios de compatibilidad separados.
''',encoding='utf-8')
    out=ROOT/'dist-game';out.mkdir(exist_ok=True)
    target=out/f'Shaiya-Local-Flutter-Windows-{revision[:12]}.zip'
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for p in sorted(release.rglob('*')):
            if p.is_file():z.write(p,p.relative_to(release))
    with zipfile.ZipFile(target) as z:
        if z.testzip():raise RuntimeError('ZIP inválido')
    (out/'SHA256.txt').write_text(f'{digest(target)}  {target.name}\n')
    print('INDEPENDENT_GAME_PACKAGE_VERIFIED',target)
if __name__=='__main__':main()
