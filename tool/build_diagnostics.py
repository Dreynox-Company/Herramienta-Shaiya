"""Deterministic toolchain preflight and useful failure reports for local builds.

These helpers never upgrade dependencies, mutate PATH, disable checks, or access
DATA. The original command's exit status and diagnostic tail remain available.
"""
from __future__ import annotations

from collections import deque
import json
from pathlib import Path
import re
import subprocess
from typing import TextIO

PINNED_FLUTTER = '3.47.4'
MINIMUM_DART = (3, 12, 0)


def version_tuple(value: str) -> tuple[int, int, int]:
    match = re.match(r'^(\d+)\.(\d+)\.(\d+)(?:[+\-\s].*)?$', value.strip())
    if not match:
        raise ValueError(f'No se reconoce la versión del SDK: {value!r}')
    return tuple(int(x) for x in match.groups())


def validate_toolchain(metadata: dict) -> None:
    framework = str(metadata.get('frameworkVersion', ''))
    dart = str(metadata.get('dartSdkVersion', ''))
    if framework != PINNED_FLUTTER or version_tuple(dart) < MINIMUM_DART:
        raise RuntimeError(
            f'SDK incompatible con la compilación verificada. Detectado Flutter '
            f'{framework or "desconocido"}, Dart {dart or "desconocido"}. '
            f'Usa Flutter {PINNED_FLUTTER} con su Dart incluido (el lockfile '
            'requiere Dart >=3.12 y Flutter >=3.44). No se regeneró ni borró '
            'pubspec.lock. Para usar Studio no necesitas SDK: abre el paquete Windows compilado.'
        )


def classify_pub_failure(output: str) -> str:
    text = output.casefold()
    if any(x in text for x in ('current dart sdk version', 'requires sdk version',
                               'requires flutter sdk version', 'sdk version solving')):
        return 'sdk-incompatible'
    if any(x in text for x in ('socketexception', 'host lookup', 'tls',
                               'connection timed out', 'unable to access', 'network is unreachable')):
        return 'network-or-download'
    if any(x in text for x in ('content-hash', 'content hash', 'checksum', 'hash mismatch')):
        return 'package-integrity'
    if any(x in text for x in ('enforce-lockfile', 'lockfile', 'version solving failed')):
        return 'dependency-resolution'
    return 'unclassified-see-original-diagnostic'


def run_logged(command: list[str], *, cwd: Path, log: TextIO, log_path: Path,
               env: dict[str, str] | None = None) -> None:
    title = '\n> ' + subprocess.list2cmdline(command)
    print(title, flush=True)
    log.write(title + '\n')
    log.flush()
    tail: deque[str] = deque(maxlen=60)
    process = subprocess.Popen(command, cwd=cwd, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True,
                               encoding='utf-8', errors='replace')
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end='', flush=True)
        log.write(line)
        tail.append(line)
    code = process.wait()
    log.flush()
    if code == 0:
        return
    diagnostic = ''.join(tail).strip()
    stage = ' '.join(command[1:3]) if len(command) > 1 else command[0]
    category = classify_pub_failure(diagnostic) if 'pub' in command else 'command-failed'
    report = {'success': False, 'stage': stage, 'exitCode': code,
              'category': category, 'command': command, 'log': str(log_path),
              'diagnosticTail': diagnostic}
    log_path.with_suffix('.failure.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    raise RuntimeError(
        f'Falló {stage} (salida {code}, {category}).\n'
        f'DIAGNÓSTICO ORIGINAL:\n{diagnostic}\nRegistro completo: {log_path}'
    )
