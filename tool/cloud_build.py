"""Publish verified sources and retrieve fresh, successful Windows/Android builds.

Uses Git's own credential flow, never reads a token or modifies global Git config.
The repository is public, so build/release checks use the public GitHub API.
Run only by the user: the confirmation also authorizes a public prerelease and
GitHub Actions usage. Raw DATA, credentials and SDKs are never uploaded.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlparse
from urllib.request import Request, urlopen
import uuid
import zipfile

import publish_sources

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = publish_sources.REPOSITORY
VERSION = '0.3.1+5'
PREFIX = 'Shaiya_Studio_0_3_1'
EXPECTED_OUTPUTS = {f'{PREFIX}_Windows.zip', f'{PREFIX}_Android_PRUEBAS.apk'}
API = f'https://api.github.com/repos/{REPOSITORY}'
POLL_SECONDS = 90  # Keep public API use below its unauthenticated rate limit.


def check_sha(sha: str) -> str:
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise RuntimeError('El identificador del commit no es válido.')
    return sha


def release_tag(sha: str) -> str:
    return f'studio-0.3.1-{check_sha(sha)[:12]}'


def safe_url(url: str) -> str:
    parsed = urlparse(url)
    if (parsed.scheme != 'https' or parsed.username or parsed.password
            or parsed.hostname not in {'api.github.com', 'github.com'}):
        raise RuntimeError('La respuesta contiene una dirección de descarga no autorizada.')
    return url


def get_json(url: str, *, not_found_ok: bool = False) -> dict | None:
    request = Request(safe_url(url), headers={
        'Accept': 'application/vnd.github+json', 'User-Agent': 'Dreynox-Shaiya-Build/0.3.1',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    try:
        with urlopen(request, timeout=40) as response:
            data = response.read(8 * 1024 * 1024 + 1)
            if len(data) > 8 * 1024 * 1024:
                raise RuntimeError('La respuesta de GitHub supera el límite esperado.')
            result = json.loads(data)
            if not isinstance(result, dict):
                raise RuntimeError('La respuesta de GitHub no tiene el formato esperado.')
            return result
    except HTTPError as exc:
        if exc.code == 404 and not_found_ok:
            return None
        if exc.code in (403, 429):
            reset = exc.headers.get('X-RateLimit-Reset', '')
            raise RuntimeError(
                'GitHub limitó las consultas públicas. La solicitud ya está guardada; '
                f'vuelve a usar --resume cuando se restablezca la cuota ({reset or "consulta la página de Actions"}).'
            ) from exc
        raise RuntimeError(f'GitHub respondió HTTP {exc.code}. No se descargan binarios antiguos.') from exc


def choose_run(payload: dict, sha: str, branch: str) -> dict | None:
    matching = [run for run in payload.get('workflow_runs', [])
                if run.get('head_sha') == check_sha(sha)
                and run.get('head_branch') == branch and run.get('event') == 'push'
                and run.get('path') == '.github/workflows/build.yml']
    return max(matching, key=lambda run: int(run['id']), default=None)


def validate_receipt(receipt: dict) -> None:
    if receipt.get('repository') != REPOSITORY or receipt.get('version') != VERSION:
        raise RuntimeError('La solicitud guardada no pertenece a esta entrega y repositorio.')
    check_sha(receipt.get('commit', ''))
    if not re.fullmatch(r'feat/studio-031-[a-zA-Z0-9-]{8,80}', receipt.get('branch', '')):
        raise RuntimeError('La rama de la solicitud no tiene el nombre autorizado.')


def validate_release(release: dict, sha: str) -> dict[str, dict]:
    if release.get('tag_name') != release_tag(sha) or release.get('draft') is True:
        raise RuntimeError('La versión publicada no coincide con el commit solicitado.')
    assets = {}
    for asset in release.get('assets', []):
        name = asset.get('name', '')
        if name in assets:
            raise RuntimeError('Hay nombres de descarga duplicados en la publicación.')
        assets[name] = asset
    required = EXPECTED_OUTPUTS | {'compilacion-verificada.json'}
    if not required.issubset(assets):
        raise RuntimeError('La publicación no incluye ambos binarios y su comprobante.')
    for name in required:
        asset = assets[name]
        if not 0 < asset.get('size', 0) <= 1024 * 1024 * 1024:
            raise RuntimeError(f'Tamaño de descarga inesperado: {name}')
        url = safe_url(asset.get('browser_download_url', ''))
        expected = f'https://github.com/{REPOSITORY}/releases/download/{release_tag(sha)}/'
        if not url.startswith(expected):
            raise RuntimeError('El archivo no pertenece a esta versión del repositorio.')
    return assets


def download(asset: dict, target: Path, expected_hash: str | None = None) -> str:
    url = safe_url(asset['browser_download_url'])
    temporary = target.with_suffix(target.suffix + '.partial')
    digest = hashlib.sha256()
    total = 0
    try:
        request = Request(url, headers={'User-Agent': 'Dreynox-Shaiya-Build/0.3.1'})
        with urlopen(request, timeout=90) as response, temporary.open('wb') as output:
            final = urlparse(response.geturl())
            if final.scheme != 'https' or not (
                    final.hostname == 'github.com'
                    or (final.hostname or '').endswith('.githubusercontent.com')):
                raise RuntimeError('GitHub redirigió la descarga a un destino inesperado.')
            while block := response.read(1024 * 1024):
                total += len(block)
                if total > asset['size']:
                    raise RuntimeError('La descarga supera el tamaño publicado.')
                output.write(block)
                digest.update(block)
        actual = digest.hexdigest()
        if total != asset['size'] or (expected_hash and actual != expected_hash):
            raise RuntimeError(f'La integridad de {target.name} no coincide. No se instalará.')
        if str(asset.get('digest', '')).startswith('sha256:') and asset['digest'][7:] != actual:
            raise RuntimeError('La firma de integridad publicada por GitHub no coincide.')
        temporary.replace(target)
        return actual
    finally:
        if temporary.exists():
            temporary.unlink()  # Only our incomplete download, never user DATA.


def verify_archive(archive: Path, *, windows: bool) -> None:
    with zipfile.ZipFile(archive) as package:
        names = set()
        total = 0
        for info in package.infolist():
            name = info.filename
            relative = PurePosixPath(name)
            if (relative.is_absolute() or '..' in relative.parts or '\\' in name
                    or ':' in name or ((info.external_attr >> 16) & 0o170000) == 0o120000):
                raise RuntimeError('Ruta no segura en el paquete compilado.')
            if name in names:
                raise RuntimeError('Entradas duplicadas en el paquete compilado.')
            names.add(name)
            total += info.file_size
            if total > 2 * 1024 * 1024 * 1024:
                raise RuntimeError('El contenido descomprimido supera el límite permitido.')
        if package.testzip() is not None:
            raise RuntimeError(f'Archivo comprimido corrupto: {archive.name}')
        needed = {'herramienta_shaiya.exe', 'flutter_windows.dll', 'data/app.so'} if windows else {
            'AndroidManifest.xml', 'classes.dex',
        }
        if not needed.issubset(names):
            raise RuntimeError('El paquete no contiene la aplicación compilada completa.')
        if windows and not package.read('herramienta_shaiya.exe')[:2] == b'MZ':
            raise RuntimeError('El ejecutable no es un archivo Windows válido.')


def validate_proof(proof: dict, sha: str, run_id: int) -> dict:
    if (proof.get('commit') != sha or proof.get('workflow_run') != run_id
            or proof.get('version') != VERSION or proof.get('repository') != REPOSITORY):
        raise RuntimeError('El comprobante de compilación pertenece a otra revisión.')
    hashes = proof.get('sha256', {})
    if set(hashes) != EXPECTED_OUTPUTS or any(not isinstance(h, str) or not re.fullmatch(r'[0-9a-f]{64}', h)
                                             for h in hashes.values()):
        raise RuntimeError('Faltan hashes SHA-256 de los resultados solicitados.')
    return hashes


def wait_and_download(receipt: dict, timeout_minutes: int, output: Path) -> None:
    validate_receipt(receipt)
    sha, branch = receipt['commit'], receipt['branch']
    deadline = time.monotonic() + timeout_minutes * 60
    run_id = None
    while time.monotonic() < deadline:
        if run_id is None:
            query = urlencode({'head_sha': sha, 'branch': branch, 'event': 'push', 'per_page': 30})
            payload = get_json(f'{API}/actions/runs?{query}')
            run = choose_run(payload or {}, sha, branch)
            if run is not None:
                run_id = int(run['id'])
                print(f'Compilación: https://github.com/{REPOSITORY}/actions/runs/{run_id}', flush=True)
        else:
            run = get_json(f'{API}/actions/runs/{run_id}')
        if run is not None:
            if run.get('head_sha') != sha:
                raise RuntimeError('La ejecución ya no corresponde al commit esperado.')
            print(f'GitHub Actions: {run.get("status", "esperando")}', flush=True)
            if run.get('status') == 'completed':
                if run.get('conclusion') != 'success':
                    raise RuntimeError(
                        f'La compilación no terminó correctamente ({run.get("conclusion")}). '
                        f'Revisa Actions, ejecución {run_id}. No se sustituyen sus resultados por la versión 0.2.'
                    )
                break
        print('La ventana puede permanecer abierta; vuelve a comprobar en 90 s. Ctrl+C guarda el punto de reanudación.', flush=True)
        time.sleep(min(POLL_SECONDS, max(0, deadline - time.monotonic())))
    else:
        raise RuntimeError('Se alcanzó el tiempo de espera. Reanuda la solicitud guardada; no se vuelve a publicar.')
    release = get_json(f'{API}/releases/tags/{quote(release_tag(sha), safe="")}')
    assets = validate_release(release or {}, sha)
    output.mkdir(parents=True, exist_ok=True)
    proof_path = output / 'compilacion-verificada.json'
    download(assets[proof_path.name], proof_path)
    hashes = validate_proof(json.loads(proof_path.read_text(encoding='utf-8')), sha, run_id)
    for name in sorted(EXPECTED_OUTPUTS):
        print(f'Descargando {name}…', flush=True)
        target = output / name
        download(assets[name], target, hashes[name])
        verify_archive(target, windows=name.endswith('_Windows.zip'))
    print(f'\nWindows y Android generados y comprobados. Archivos en:\n{output}')
    print('Extrae TODO el ZIP de Windows. El APK Android es una compilación de prueba firmada con la clave de depuración de Actions.')


def publish_new(*, yes: bool = False) -> tuple[dict, Path]:
    publish_sources.verified_sources()
    git = shutil.which('git')
    if not git:
        raise RuntimeError('No se encuentra Git. Instala Git for Windows o usa COMPILAR.ps1 con tu SDK Flutter.')
    print(f'Repositorio: {REPOSITORY}\nVersión: {VERSION}')
    print('Se enviarán SOLO las fuentes verificadas a una rama nueva. DATA no se copia.')
    print('GitHub Actions compilará Windows/Android y publicará una versión preliminar pública. Puede consumir minutos de tu cuenta.')
    print('Git usa tu sesión habitual y puede pedir que inicies sesión. No se leen ni copian contraseñas o tokens.')
    if not yes and input('Escribe PUBLICAR para autorizar este proceso: ').strip() != 'PUBLICAR':
        raise RuntimeError('Operación cancelada sin publicar ni iniciar compilaciones.')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6]
    work = Path(os.environ.get('LOCALAPPDATA') or str(Path.home() / '.local/share')) / 'Dreynox/ShaiyaStudio/compilaciones' / stamp
    work.mkdir(parents=True, exist_ok=False)
    repo = work / 'repositorio'
    branch = f'feat/studio-031-{stamp}'
    subprocess.run([git, 'clone', '--single-branch', '--branch', publish_sources.BASE_BRANCH,
                    f'https://github.com/{REPOSITORY}.git', str(repo)], check=True)
    subprocess.run([sys.executable, str(ROOT / 'tool/publish_sources.py'), str(repo),
                    '--branch', branch, '--yes'], check=True)
    sha = subprocess.check_output([git, 'rev-parse', 'HEAD'], cwd=repo, text=True).strip()
    check_sha(sha)
    receipt = {'version': VERSION, 'repository': REPOSITORY, 'commit': sha,
               'branch': branch, 'clone': str(repo), 'created_at': datetime.now(timezone.utc).isoformat()}
    folder = ROOT / '.build-cloud'
    folder.mkdir(exist_ok=True)
    receipt_path = folder / f'solicitud-{stamp}.json'
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding='utf-8')
    return receipt, receipt_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--yes', action='store_true', help='Autorizar explícitamente publicación y compilación remota')
    parser.add_argument('--resume', type=Path, help='Reanudar una solicitud sin publicar de nuevo')
    parser.add_argument('--timeout-minutes', type=int, default=90)
    args = parser.parse_args()
    if not 5 <= args.timeout_minutes <= 180:
        raise RuntimeError('El tiempo de espera debe estar entre 5 y 180 minutos.')
    if args.resume:
        receipt_path = args.resume.resolve()
        receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
        validate_receipt(receipt)
    else:
        receipt, receipt_path = publish_new(yes=args.yes)
    print(f'\nReanudar sin volver a publicar:\n{sys.executable} tool/cloud_build.py --resume "{receipt_path}"\n', flush=True)
    destination = ROOT / 'dist' / check_sha(receipt['commit'])[:12]
    wait_and_download(receipt, args.timeout_minutes, destination)
    if os.name == 'nt':
        os.startfile(destination)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\nEspera cancelada. Una compilación ya iniciada en GitHub no se cancela automáticamente; usa el comando de reanudación mostrado.')
        raise SystemExit(130)
    except (OSError, RuntimeError, ValueError, KeyError, EOFError, URLError, subprocess.CalledProcessError) as exc:
        print(f'\nPROCESO DETENIDO: {exc}', file=sys.stderr)
        raise SystemExit(1)
