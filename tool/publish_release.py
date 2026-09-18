"""Publish native outputs only in the gated GitHub Actions release job.

This program is NOT a local publisher: it requires the ephemeral Actions token,
a push on the explicit delivery branch, and artifacts from the current run.
It never reads the user's Git credentials and never uploads DATA.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.parse import quote
from urllib.request import Request, urlopen
import zipfile

REPOSITORY = 'Dreynox-Company/Herramienta-Shaiya'
VERSION = '0.5.0+7'
PREFIX = 'Shaiya_Studio_0_5_0'
API = f'https://api.github.com/repos/{REPOSITORY}'


def validate_environment(env: dict) -> tuple[str, int, str]:
    sha = env.get('GITHUB_SHA', '')
    if (env.get('GITHUB_ACTIONS') != 'true' or env.get('GITHUB_EVENT_NAME') != 'push'
            or env.get('GITHUB_REPOSITORY') != REPOSITORY
            or not re.fullmatch(r'refs/heads/feat/studio-05-[a-zA-Z0-9-]{8,80}', env.get('GITHUB_REF', ''))
            or not re.fullmatch(r'[0-9a-f]{40}', sha)
            or not re.fullmatch(r'\d+', env.get('GITHUB_RUN_ID', ''))):
        raise RuntimeError('La publicación solo se permite en la ejecución autorizada de entrega.')
    return sha, int(env['GITHUB_RUN_ID']), f'studio-0.5.0-{sha[:12]}'


def main() -> None:
    sha, run_id, tag = validate_environment(dict(os.environ))
    token = os.environ.get('GITHUB_TOKEN')
    if not token:
        raise RuntimeError('El job de publicación no recibió su token efímero de Actions.')
    output = Path('release-out')
    output.mkdir(exist_ok=True)
    windows = Path('cloud-artifacts/windows')
    apk = Path('cloud-artifacts/android/app-debug.apk')
    for needed in ['herramienta_shaiya.exe', 'flutter_windows.dll', 'data/app.so']:
        if not (windows / needed).is_file():
            raise RuntimeError('No está completo el artefacto de Windows: ' + needed)
    if not apk.is_file():
        raise RuntimeError('No está el artefacto Android de esta ejecución.')
    win_zip = output / f'{PREFIX}_Windows.zip'
    with zipfile.ZipFile(win_zip, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(windows.rglob('*')):
            if path.is_symlink():
                raise RuntimeError('El artefacto de Windows contiene un enlace inesperado.')
            if path.is_file():
                z.write(path, path.relative_to(windows).as_posix())
    with zipfile.ZipFile(win_zip) as z:
        if z.testzip() is not None:
            raise RuntimeError('El paquete de Windows está dañado.')
    android = output / f'{PREFIX}_Android_PRUEBAS.apk'
    android.write_bytes(apk.read_bytes())
    with zipfile.ZipFile(android) as z:
        if z.testzip() is not None or 'AndroidManifest.xml' not in z.namelist():
            raise RuntimeError('El APK no supera la comprobación de estructura.')
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [win_zip, android]}
    proof = output / 'compilacion-verificada.json'
    proof.write_text(json.dumps({
        'version': VERSION, 'repository': REPOSITORY, 'commit': sha, 'workflow_run': run_id,
        'sha256': hashes,
        'scope': 'Análisis y pruebas de fuentes; integración Windows con datos sintéticos; compilación Windows release y Android debug. No acredita todos los recursos originales ni un Android físico.',
    }, ensure_ascii=False, indent=2), encoding='utf-8')

    def api(method: str, url: str, data: bytes, mime: str = 'application/json') -> dict:
        req = Request(url, method=method, data=data, headers={
            'Authorization': f'Bearer {token}', 'User-Agent': 'Dreynox-Shaiya-Release/0.5.0',
            'Accept': 'application/vnd.github+json', 'Content-Type': mime,
            'X-GitHub-Api-Version': '2022-11-28',
        })
        with urlopen(req, timeout=180) as response:
            return json.load(response)

    # A draft is invisible to the unauthenticated downloader until all uploads
    # succeed. Never replace/delete an existing published release on a rerun.
    release = api('POST', f'{API}/releases', json.dumps({
        'tag_name': tag, 'target_commitish': sha,
        'name': f'Shaiya Studio 0.5.0 · {sha[:12]}', 'draft': True, 'prerelease': True, 'make_latest': 'false',
        'body': f'Revisión {sha}.\n\nCompilación y pruebas: https://github.com/{REPOSITORY}/actions/runs/{run_id}\n\nWindows: extraer todo el ZIP. Android: APK de depuración; puede requerir una instalación separada si la firma anterior es distinta. DATA no está incluido y no se modifica. Cuerpo base original disponible; no se añaden texturas nude inexistentes. Efectos de encantamiento son una previsualización, no una homologación de cada nivel del juego.',
    }).encode('utf-8'))
    upload = release['upload_url'].split('{', 1)[0]
    if not upload.startswith(f'https://uploads.github.com/repos/{REPOSITORY}/releases/'):
        raise RuntimeError('GitHub no devolvió un destino de subida válido.')
    for path in [win_zip, android, proof]:
        mime = 'application/json' if path.suffix == '.json' else 'application/octet-stream'
        api('POST', upload + '?name=' + quote(path.name), path.read_bytes(), mime)
    api('PATCH', f'{API}/releases/{release["id"]}', b'{"draft":false}')
    print(f'Publicada la versión preliminar {tag}, commit {sha}. No se fusionó con main.')


if __name__ == '__main__':
    main()
