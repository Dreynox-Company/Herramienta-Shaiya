"""One-time, digest-checked transport of the reviewed R24 appearance diff.

Only the exact isolated branch can be changed. The resulting readable sources
are committed before the normal regression/build jobs. No assets or binaries
are imported. Remove transport files after the source checkpoint is verified.
"""
from pathlib import Path
import base64
import hashlib
import subprocess
import zlib

EXPECTED = 'f6c5caa929a4fdbe07203206cfa2de16623a8802ce6757102796096f61b36e41'
PART_HASHES = (
    'd5c9df72f755ca1a1364f39af22914d29a060e353f29ba4401840e9ae832faef',
    '9f1be1ff255759b739abcf256e323556217f0e1d7ef3020bdb5288a2f3e584f4',
)


def main():
    root = Path(__file__).resolve().parents[1]
    marker = root / '.studio-r24-appearance-applied'
    if marker.exists():
        if marker.read_text().strip() != EXPECTED:
            raise RuntimeError('Different appearance patch already applied.')
        return
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=root, text=True).strip()
    if branch != 'fix/studio-0624-flight-appearance-native':
        raise RuntimeError('Refusing to modify a different branch.')
    parts = [(root / 'ci' / f'r24_followup.part{i}').read_text().strip() for i in (1, 2)]
    # Correct five explicitly identified text-transport transcription errors.
    # Acceptance still requires BOTH original chunk digests and the diff digest.
    if hashlib.sha256(parts[0].encode('ascii')).hexdigest() != PART_HASHES[0]:
        for bad, good in (
            ('HiRhng0S01', 'HiRhng0R01'),
            ('n6WSQfBHrJr/L8', 'n6WSQfBHr/L8'),
            ('EyzCRQUUXi', 'EyzCRQU/Xi'),
            ('EnJbYYtrx', 'EnJbYtrx'),
            ('g0NKk9Iwf', 'g0NKk9wf'),
        ):
            parts[0] = parts[0].replace(bad, good)
    for part, expected in zip(parts, PART_HASHES):
        actual = hashlib.sha256(part.encode('ascii')).hexdigest()
        if actual != expected:
            raise RuntimeError(f'Transport integrity mismatch: {actual}; expected {expected}')
    diff = zlib.decompress(base64.b64decode(''.join(parts), validate=True))
    if len(diff) != 72414 or hashlib.sha256(diff).hexdigest() != EXPECTED:
        raise RuntimeError('Source patch integrity mismatch.')
    subprocess.run(['git', 'apply', '--check', '-'], cwd=root, input=diff, check=True)
    subprocess.run(['git', 'apply', '-'], cwd=root, input=diff, check=True)
    marker.write_text(EXPECTED + '\n')


if __name__ == '__main__':
    main()
