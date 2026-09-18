"""Create a source-only ZIP with integrity manifest; never include DATA/SDK/fonts."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.5.0+7'
BASE = '748d612a00bd8ef9f417bb38604f8dd4fe920aab'
TOP_FILES = (
    '.gitignore', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
    'README.md', 'INSTRUCCIONES.md', 'LEEME_WINDOWS.txt', 'THIRD_PARTY_NOTICES.md',
    'COMPILAR.ps1', 'PUBLICAR_GITHUB.ps1', 'ABRIR_WINDOWS.cmd',
    'COMPILAR_ANDROID.cmd', 'INICIAR_WINDOWS.ps1',
    'OBTENER_EXE_Y_APK.cmd', 'GENERAR_LOCAL_WINDOWS_Y_ANDROID.cmd',
)
ALLOWED = {'.dart', '.py', '.ps1', '.cmd', '.kt', '.md', '.txt', '.json', '.yaml', '.yml', '.lock'}


def collect() -> dict[str, bytes]:
    paths = [ROOT / n for n in TOP_FILES]
    paths.append(ROOT / '.github/workflows/build.yml')
    for directory in ('lib', 'test', 'integration_test', 'platform', 'docs', 'tool'):
        for p in (ROOT / directory).rglob('*'):
            if p.is_file() and not p.is_symlink() and '__pycache__' not in p.parts and p.suffix.lower() in ALLOWED:
                paths.append(p)
    output = {}
    for p in sorted(set(paths)):
        if not p.is_file() or p.is_symlink():
            raise RuntimeError(f'Falta un archivo de la entrega: {p.name}')
        output[p.relative_to(ROOT).as_posix()] = p.read_bytes()
    for name in ('lib/data/catalog.dart', 'lib/data/library.dart', 'lib/data/game_names.dart'):
        if name not in output:
            raise RuntimeError(f'Falta código de datos, no debe excluirse como DATA: {name}')
    return output


def package(destination: Path) -> None:
    files = collect()
    manifest = json.dumps({
        'version': VERSION, 'base_commit': BASE,
        'repository': 'Dreynox-Company/Herramienta-Shaiya',
        'kind': 'sources-with-build-scripts; not precompiled Windows/Android',
        'files': {name: hashlib.sha256(data).hexdigest() for name, data in files.items()},
    }, ensure_ascii=False, indent=2).encode('utf-8')
    (ROOT / 'manifest-entrega.json').write_bytes(manifest)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix(destination.suffix + '.tmp')
    with zipfile.ZipFile(temp, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name, data in files.items():
            z.writestr('Shaiya_Studio_0_5_0/' + name, data)
        z.writestr('Shaiya_Studio_0_5_0/manifest-entrega.json', manifest)
    with zipfile.ZipFile(temp) as z:
        if z.testzip() is not None:
            raise RuntimeError('La integridad del ZIP no es correcta.')
    temp.replace(destination)
    print(f'Fuentes: {len(files)} archivos · {destination.stat().st_size:,} bytes · {destination}')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('destination', nargs='?', default=str(ROOT / 'dist/Shaiya_Studio_0_5_0_Flutter.zip'))
    package(Path(p.parse_args().destination))
