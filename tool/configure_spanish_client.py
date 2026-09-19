"""Configure LANGUAGE=6 for the audited native client only; never execute or patch it.

Default: inspect without writes. Use --apply to update config.ini after preserving
an exact backup. This selects Spanish resources; it does NOT create offline mode.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

AUDITED_EXE_SHA256 = '509c4a8fbe4d5292961fdfb6d1045795a7bb5970fcf2560fd1070aee18273c2d'


def update_language_bytes(raw: bytes) -> tuple[bytes, str]:
    if len(raw) > 1024 * 1024:
        raise ValueError('config.ini supera 1 MiB.')
    bom, encoding = b'', 'cp1252'
    if raw.startswith(b'\xff\xfe'):
        bom, encoding = raw[:2], 'utf-16-le'
    elif raw.startswith(b'\xfe\xff'):
        bom, encoding = raw[:2], 'utf-16-be'
    elif raw.startswith(b'\xef\xbb\xbf'):
        bom, encoding = raw[:3], 'utf-8'
    text = raw[len(bom):].decode(encoding, errors='strict')
    lines = text.splitlines(keepends=True)
    in_login = False
    found = 0
    previous = ''
    output: list[str] = []
    for line in lines:
        heading = re.match(r'^\s*\[([^]]+)\]', line)
        if heading:
            in_login = heading.group(1).casefold() == 'login'
        match = re.match(r'^(\s*LANGUAGE\s*=\s*)([0-9]+)([ \t]*(?:[;#].*)?)(\r?\n|\r)?$', line, re.I) if in_login else None
        if match:
            found += 1
            previous = match.group(2)
            line = match.group(1) + '6' + match.group(3) + (match.group(4) or '')
        output.append(line)
    if found != 1:
        raise ValueError('Se exige exactamente un campo LANGUAGE numérico dentro de [LOGIN]; no se adivina otro esquema.')
    return bom + ''.join(output).encode(encoding), previous


def configure(root: Path, apply: bool = False) -> dict:
    root = root.resolve(strict=True)
    exe, config = root/'game.exe', root/'config.ini'
    if exe.is_symlink() or config.is_symlink():
        raise ValueError('No se aceptan enlaces en game.exe o config.ini.')
    with exe.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != AUDITED_EXE_SHA256:
        raise ValueError('Este ejecutable no coincide con el auditado; no se aplica el valor de idioma de otro cliente.')
    raw = config.read_bytes()
    updated, previous = update_language_bytes(raw)
    before = hashlib.sha256(raw).hexdigest()
    result = {'schema': 1, 'operation': 'native-spanish-locale', 'exe_sha256': digest,
              'old_language': previous, 'new_language': '6', 'exe_modified': False,
              'config_before_sha256': before, 'config_after_sha256': hashlib.sha256(updated).hexdigest(),
              'mode': 'inspect', 'offline_game_created': False}
    if not apply or updated == raw:
        result['mode'] = 'unchanged' if updated == raw else 'inspect'
        return result
    # O_EXCL retains a pre-existing backup, never overwrites a possibly useful one.
    backup = config.with_name('config.ini.before-spanish-' + before[:16] + '.bak')
    try:
        with backup.open('xb') as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError:
        if backup.is_symlink() or backup.read_bytes() != raw:
            raise ValueError('El respaldo existente no coincide con la configuración de origen.')
    handle, temporary = tempfile.mkstemp(prefix='.config-spanish-', dir=root)
    temp_path = Path(temporary)
    try:
        with os.fdopen(handle, 'wb') as stream:
            stream.write(updated)
            stream.flush()
            os.fsync(stream.fileno())
        if config.is_symlink() or hashlib.sha256(config.read_bytes()).hexdigest() != before:
            raise ValueError('config.ini cambió durante la operación. Cierra el juego antes de guardar.')
        os.replace(temp_path, config)
    finally:
        temp_path.unlink(missing_ok=True)
    result.update(mode='updated', backup_name=backup.name)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('client_directory', type=Path)
    parser.add_argument('--apply', action='store_true', help='Modificar solo config.ini, con respaldo verificado.')
    args = parser.parse_args()
    try:
        print(json.dumps(configure(args.client_directory, args.apply), ensure_ascii=False, indent=2))
        return 0
    except (ValueError, OSError, UnicodeError) as error:
        print(json.dumps({'status': 'error', 'error': str(error)}, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
