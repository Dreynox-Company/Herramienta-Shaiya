"""Apply a small readable, idempotent save-boundary correction on R25 only."""
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parents[1]
    branch = subprocess.check_output(['git', 'branch', '--show-current'], cwd=root, text=True).strip()
    if branch != 'fix/studio-0625-items-release':
        raise RuntimeError('Refusing to modify another branch.')
    path = root / 'lib/data/catalog.dart'
    source = path.read_text(encoding='utf-8')
    if 'validateNativeWingProfile(profile);' not in source:
        old = '''    document.update(profile);
    final bytes = document.encode();
    document.validateEncoded(bytes);
    await library.writeResource(path, bytes);
    wingPositions = WingPositionDocument.parse(bytes, path);'''
        new = '''    validateNativeWingProfile(profile);
    // Stage a separate document: an I/O failure must not change mounted DATA
    // metadata or make the next save inherit an uncommitted profile.
    final candidate = WingPositionDocument.parse(document.encode(), path);
    candidate.update(profile);
    final bytes = candidate.encode();
    candidate.validateEncoded(bytes);
    await library.writeResource(path, bytes);
    wingPositions = WingPositionDocument.parse(bytes, path);'''
        if source.count(old) != 1:
            raise RuntimeError('Wing save boundary changed; review before applying.')
        source = source.replace(old, new)
        source = "import '../core/native_wing_profile.dart';\n" + source
        path.write_text(source, encoding='utf-8')
    runner = root / 'tool/run_all_local.dart'
    source = runner.read_text(encoding='utf-8')
    if 'native_wing_profile_test.dart' not in source:
        source = "import '../test/native_wing_profile_test.dart' as nativeWingProfileSuite;\n" + source
        if source.count('void main() {') != 1:
            raise RuntimeError('Unexpected local test runner.')
        source = source.replace('void main() {', 'void main() {\n  nativeWingProfileSuite.main();')
        runner.write_text(source, encoding='utf-8')


if __name__ == '__main__':
    main()
