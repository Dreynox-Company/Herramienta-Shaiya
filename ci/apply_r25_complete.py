"""One-time source transport for the owner's already delivered full R25 editor.

All transport chunks and the decoded git diff are independently SHA-256 checked.
Only the isolated release branch may be modified. Readable source is committed
before regression and Windows compilation; this is not a binary patch to an EXE.
"""
from pathlib import Path
import base64
import hashlib
import lzma
import subprocess

BRANCH = 'fix/studio-0625-items-release'
DIFF_SHA256 = '1a472d176eec39a489e6d9854b2dde4c2979560b0a189b2d07b19a6b82c39511'
DIFF_BYTES = 197618
PART_SHA256 = (
    '957c318fa4591023a3290e43b37b08a0784f0f871ab4700d338a9d3ea8a4d36b',
    '72e0144336bc997a9f7c46cf13d4f4d8216eda950cf5d43f93f837fa325eac15',
    '95f19d886eabee0de372ccb4ac4992939fb16c876fb8a0e7e044aec635dfd123',
    'c78ab68447db63603f551239212262a0c6810aad44a09b22eac9b72229af1634',
    'b6c5bf8c5495f2fd986e26a539f31ded987675981d13b19d73bb5136c0652e77',
    'ce9f715e4c52eecfbf996e4a99b97391db59b660fa383d217e98818772ea4e71',
    '5639a2101593443d48d4be52a497d34fe2521c74322349bcc131b47dae11a4da',
)
# Replaced by lib/data/item_workspace.dart and the shared native item editor.
OBSOLETE = {
    'lib/core/item_icon_layout.dart': '54c217dd7d381071f27d2719282fa74f06984248c45494afdac339fda22bae7b',
    'lib/editor/item_field_profile.dart': '7a5aeff2e82867a050aa1749643737472be05b9d58fe3f911d48b1542b2db53c',
    'lib/editor/item_workspace.dart': '0137d706532fda912575d3bc8247378ec15401bb0f715e0ea966581f6b964cd0',
    'lib/ui/item_workbench.dart': 'e6dffeb29b75cea2f022b511da6be35078428600c16fc1916b8037b12b4a81de',
}


def main():
    root = Path(__file__).resolve().parents[1]
    branch = subprocess.check_output(
        ['git', 'branch', '--show-current'], cwd=root, text=True,
    ).strip()
    if branch != BRANCH:
        raise RuntimeError(f'Refusing to change branch {branch!r}; expected {BRANCH}.')
    marker = root / '.studio-r25-complete-applied'
    if marker.exists():
        if marker.read_text().strip() != DIFF_SHA256:
            raise RuntimeError('A different R25 source patch is already present.')
        return
    parts = []
    for number, expected in enumerate(PART_SHA256, 1):
        part = (root / 'ci' / f'r25_complete_source.part{number}').read_text(encoding='ascii').strip()
        actual = hashlib.sha256(part.encode('ascii')).hexdigest()
        if actual != expected:
            raise RuntimeError(f'Chunk {number} integrity mismatch: {actual}; expected {expected}')
        parts.append(part)
    diff = lzma.decompress(base64.b64decode(''.join(parts), validate=True))
    if len(diff) != DIFF_BYTES or hashlib.sha256(diff).hexdigest() != DIFF_SHA256:
        raise RuntimeError('Decoded source diff integrity mismatch.')
    for relative, expected in OBSOLETE.items():
        path = root / relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise RuntimeError(f'Obsolete source changed; reconcile before removing {relative}.')
    subprocess.run(['git', 'apply', '--check', '-'], cwd=root, input=diff, check=True)
    subprocess.run(['git', 'apply', '-'], cwd=root, input=diff, check=True)
    for relative in OBSOLETE:
        (root / relative).unlink()
    marker.write_text(DIFF_SHA256 + '\n', encoding='ascii')
    print('R25 full source diff authenticated and applied. Compilation is NOT yet verified.')


if __name__ == '__main__':
    main()
