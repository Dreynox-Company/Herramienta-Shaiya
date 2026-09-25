"""Recover the interrupted four-part source transfer into ordinary tracked files."""
from pathlib import Path, PurePosixPath
import base64, hashlib, lzma, re, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
EXPECTED='2b9365226200b82f914cbba652a0b8eacc7a299fbedf983fde8aba3719618666'
def main():
    encoded=''.join((Path(__file__).parent/f'part{i}.b64').read_text().strip() for i in range(4))
    raw=base64.b64decode(encoded,validate=True)
    decoder=lzma.LZMADecompressor(memlimit=128*1024*1024)
    patch=decoder.decompress(raw,max_length=2*1024*1024)
    if not decoder.eof or decoder.unused_data or hashlib.sha256(patch).hexdigest()!=EXPECTED:
        raise RuntimeError('Incomplete or altered source transfer; nothing applied.')
    paths=[]
    for line in patch.decode('utf-8').splitlines():
        if line.startswith('diff --git '):
            m=re.fullmatch(r'diff --git a/(\S+) b/(\S+)',line)
            if not m or m[1]!=m[2]:raise RuntimeError('Unexpected patch path')
            p=PurePosixPath(m[1]);name=str(p)
            if p.is_absolute() or '..' in p.parts or '\\' in name or not(name in {'README.md','pubspec.yaml','pubspec.lock'} or p.parts[0] in {'lib','test','integration_test','tool','docs'}):
                raise RuntimeError('Source outside audited application: '+name)
            paths.append(name)
    with tempfile.TemporaryDirectory() as temp:
        f=Path(temp)/'source.patch';f.write_bytes(patch)
        subprocess.run(['git','apply','--check',str(f)],cwd=ROOT,check=True)
        subprocess.run(['git','apply',str(f)],cwd=ROOT,check=True)
    subprocess.run(['git','add','--',*paths],cwd=ROOT,check=True)
    print('Recovered ordinary source files:',len(paths),'patch sha256:',EXPECTED)
if __name__=='__main__':main()
