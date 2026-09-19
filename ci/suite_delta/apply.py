"""One-time checked transfer. This script never reads or uploads game DATA."""
from pathlib import Path, PurePosixPath
import base64, hashlib, lzma, re, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
EXPECTED='6082d4348a3ac5d5d0e8bde144dd8408c96d9b5e48fa130c6c52851924ed2ea8'
def main():
 encoded=''.join((Path(__file__).parent/f'p{i}').read_text().strip() for i in range(4))
 raw=base64.b64decode(encoded,validate=True);decoder=lzma.LZMADecompressor(memlimit=128*1024*1024)
 patch=decoder.decompress(raw,max_length=1024*1024)
 if not decoder.eof or decoder.unused_data or hashlib.sha256(patch).hexdigest()!=EXPECTED:raise RuntimeError('Source transfer incomplete or altered.')
 paths=[]
 for line in patch.decode('utf-8').splitlines():
  if line.startswith('diff --git '):
   m=re.fullmatch(r'diff --git a/(\S+) b/(\S+)',line)
   if not m or m[1]!=m[2]:raise RuntimeError('Unexpected patch path')
   p=PurePosixPath(m[1]);name=str(p)
   if p.is_absolute() or '..' in p.parts or '\\' in name or not(name in {'README_SUITE.md','Shaiya-Suite.code-workspace','COMPILAR_CLIENTE_FLUTTER.cmd'} or p.parts[0] in {'lib','test','integration_test','tool','ci','ingenieria_inversa'}):raise RuntimeError('Out-of-scope source path')
   paths.append(name)
 if len(paths)!=23 or len(set(paths))!=23:raise RuntimeError('Expected 23 unique source files.')
 with tempfile.TemporaryDirectory() as temp:
  f=Path(temp)/'source.patch';f.write_bytes(patch)
  subprocess.run(['git','apply','--check',str(f)],cwd=ROOT,check=True)
  subprocess.run(['git','apply',str(f)],cwd=ROOT,check=True)
 subprocess.run(['git','add','--',*paths],cwd=ROOT,check=True)
 print('Transferred',len(paths),'source files; SHA-256',EXPECTED)
if __name__=='__main__':main()
