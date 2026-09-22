"""One-time, hash-verified source import. Does not publish or execute app code."""
from pathlib import Path
import base64, gzip, hashlib, importlib.util, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = Path(__file__).parent
EXPECTED_PATCH = '06cadee93d4d3aaf1a7d1205cf772c8db39d78a08c18cc5fc6b9b9b63cc2db94'
EXPECTED_GZIP = 'de02100ae7c6d5129be862a8b21000e00f7df1587c7b4837ec3998a9d20aab79'
EXPECTED_SOURCES = '295492fc4d7978f43cffc88920610861b7b5850ecdeae338f681e533669fc7d9'
BASE = 'c457c6b172e76f1b453776d8c861cf705b15cdfe'
PART_HASHES = (
 'c8f43e5a088008be3c649967cd2dfb100cba3ba72860b0232ab5985fd6f2109b',
 '793559f0ded243c9dbd8c221fdbd71e4f276d9c0f7db82bb074bff2c69f6685d',
 'c162c86136625e9ebbabff94bf6991e7f201076f6d3f7e49889978fcde3fef3f',
 '9e3ad7a123c1eb46967a7a5871c9aa51d248dcc4e3be670092163df84e87e2d9',
 'c5f672ff79f4bd0e02fec9a4a9f48b5a70b60ea49b401b58c5381626f0990d61',
 '419afb58da6d7ab3cd3a65edcad78109b2af9f5e838a4cb580d8aa1449b09260',
)

def digest(b): return hashlib.sha256(b).hexdigest()
def git(*args, **kwargs): return subprocess.run(['git', *args], cwd=ROOT, check=True, **kwargs)
def require(condition, message):
    if not condition: raise RuntimeError(message)

def main():
    require(ROOT.name != '', 'Repository root required')
    if '--local-fixture' not in sys.argv:
        git('merge-base', '--is-ancestor', BASE, 'HEAD')
    pieces = []
    for i, wanted in enumerate(PART_HASHES):
        b = (BUNDLE / f'part-{i}.b64').read_bytes()
        # Explicit recovery of a single documented transport insertion. Both the
        # corrected segment and the entire decompressed patch must match the
        # locally audited checkpoint. No source-level repairs are made here.
        if i == 3 and len(b) == 8001 and b.count(b'YPP3rYb767') == 1:
            b = b.replace(b'YPP3rYb767', b'YPP3rY767', 1)
        require(digest(b) == wanted, f'Transport part {i} failed SHA-256')
        pieces.append(b)
    compressed = base64.b64decode(b''.join(pieces), validate=True)
    require(digest(compressed) == EXPECTED_GZIP, 'Compressed patch failed SHA-256')
    patch = gzip.decompress(compressed)
    require(len(patch) == 115246 and digest(patch) == EXPECTED_PATCH, 'Patch failed SHA-256')
    paths = re.findall(r'^\+\+\+ b/(.+)$', patch.decode('utf-8'), re.M)
    require(len(paths) == 29 and len(set(paths)) == 29, 'Unexpected patch inventory')
    for p in paths:
        require(not Path(p).is_absolute() and '..' not in Path(p).parts and '\\' not in p, 'Unsafe patch path')
        require(p.startswith(('lib/', 'test/', 'tool/', 'integration_test/', 'docs/', 'platform/')) or p in ('pubspec.yaml','pubspec.lock'), 'Unexpected patch target')
    git('apply', '--check', '-', input=patch)
    git('apply', '-', input=patch)
    spec = importlib.util.spec_from_file_location('source_manifest', ROOT/'tool/package_sources.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    files = module.collect()
    files.pop('.github/workflows/build.yml')
    computed = digest(''.join(f'{p}\0{digest(b)}\n' for p,b in sorted(files.items())).encode())
    require(len(files) == 122 and computed == EXPECTED_SOURCES, 'Materialized sources differ from audited checkpoint')
    report = {'schema':1, 'base':BASE, 'patchSha256':EXPECTED_PATCH,
              'sourceAggregateExcludingBuildWorkflow':computed, 'sourceFiles':len(files),
              'changedPaths':paths, 'sourceVersion':'0.5.0+7',
              'scope':'Audited Spanish and manual-flight corrections. Not completed editor 0.6 or offline game.'}
    (ROOT/'ci/checkpoint-provenance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for file in BUNDLE.glob('part-*.b64'): file.unlink()
    print(f'CHECKPOINT_VERIFIED: {len(files)} exact application sources, {len(paths)} changed paths.')

if __name__ == '__main__': main()
