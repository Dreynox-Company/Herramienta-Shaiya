"""One-time, checksummed source-only import of the reviewed local 0.3.1 delta.
The transfer capsule contains UTF-8 patches, not game assets or executables.
It is removed after materialization and passing tests. No network or credentials.
"""
from pathlib import Path
import base64, hashlib, lzma, re, subprocess, zlib
ROOT = Path(__file__).resolve().parents[1]
EXPECTED = 'e60f9795d332e9f43f2c4a58b0646347368aaaef375018d10d15f4fe21aee615'
COMPRESSED = 'cced24da48b2ffbe0ae92fc86a283bc71400198a119e9d597eca2e26dd8c41a4'
BASE = '58d23b3a24c089a95f1ba143c6ae32f7fb3cdbfe'

def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()

assert run('git', 'rev-parse', 'HEAD^') == BASE, 'Unexpected source base; no files were changed.'
chunks = sorted((ROOT / '.delivery').glob('part*.b64'))
assert len(chunks) == 13, 'The source transfer is incomplete.'
encoded = ''.join(p.read_text().strip() for p in chunks)
compressed = base64.b64decode(encoded, validate=True)
assert hashlib.sha256(compressed).hexdigest() == COMPRESSED, 'Compressed source checksum failed.'
patch = lzma.decompress(compressed, memlimit=128*1024*1024)
assert len(patch) < 600000 and hashlib.sha256(patch).hexdigest() == EXPECTED, 'Source checksum failed.'
paths = re.findall(r'^\+\+\+ b/(.+)$', patch.decode('utf-8'), re.M)
allowed_roots = {'lib', 'test', 'integration_test', 'tool', 'docs', 'platform', '.github'}
allowed_top = {'COMPILAR.ps1', 'PUBLICAR_GITHUB.ps1', 'ABRIR_WINDOWS.cmd', 'COMPILAR_ANDROID.cmd', 'INICIAR_WINDOWS.ps1', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', '.gitignore', 'README.md', 'INSTRUCCIONES.md', 'LEEME_WINDOWS.txt', 'THIRD_PARTY_NOTICES.md'}
for name in paths:
    p = Path(name)
    assert not p.is_absolute() and '..' not in p.parts, 'Unsafe patch path.'
    assert (len(p.parts) == 1 and name in allowed_top) or (p.parts[0] in allowed_roots), 'Non-source path in transfer.'
    assert p.suffix.lower() not in {'.rar', '.dds', '.3dc', '.apk', '.exe', '.ttf', '.otf'}, 'Assets are not publishable.'
target = ROOT / '.delivery' / 'verified.patch'
target.write_bytes(patch)
subprocess.run(['git', 'apply', '--check', str(target)], cwd=ROOT, check=True)
subprocess.run(['git', 'apply', str(target)], cwd=ROOT, check=True)
# Deterministically regenerate the standard CP950 / CP949 Unicode mappings.
# These are text-encoding tables, not proprietary game resources.
p = ROOT / 'lib/core/legacy_text.dart'
source = p.read_text(encoding='utf-8')
for codec, marker, expected in [
    ('cp950', '__GENERATE_CP950__', '0f4914669d5eadc1c7dbc2cfd21b7363f64539ef119efc675dbe22b8be203545'),
    ('cp949', '__GENERATE_CP949__', '93070983b2709f3136eebce1dc54fb3b810a4fe1715de9f9719f375cc2da8f68'),
]:
    table = bytearray()
    for hi in range(0x81, 0xff):
        for lo in range(0x40, 0xff):
            chars = bytes([hi, lo]).decode(codec, errors='replace')
            code = ord(chars) if len(chars) == 1 else 0xfffd
            table.extend(code.to_bytes(2, 'little'))
    assert hashlib.sha256(table).hexdigest() == expected, 'Encoding table verification failed.'
    assert source.count(marker) == 1, 'Missing encoding table placeholder.'
    source = source.replace(marker, base64.b64encode(zlib.compress(table, 9)).decode('ascii'))
p.write_text(source, encoding='utf-8')
print(f'Applied {len(paths)} verified source changes. DATA has not been uploaded or read by this workflow.')
