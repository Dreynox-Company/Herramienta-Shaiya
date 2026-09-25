"""Apply reviewed follow-up fixes to the materialized R27 sources only.

All anchors are checked before writing. No gates or authentication are removed.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / '.studio-r27-review-applied'
changes = {}


def replace(path, old, new):
    text = changes.get(path, (ROOT / path).read_text(encoding='utf-8'))
    if text.count(old) != 1:
        raise RuntimeError(f'Expected exactly one reviewed anchor in {path}: {old[:100]}')
    changes[path] = text.replace(old, new, 1)


def main():
    if subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip() != 'fix/studio-0627-spk-navigation-orbit-brand':
        raise RuntimeError('Refusing a different branch.')
    if MARKER.exists():
        return
    replace('test/fixtures/resource_spk_fixture.dart',
        'final source = SpkArchiveSource.fromValidatedIndexForTesting(',
        'final source = await SpkArchiveSource.fromValidatedIndexForTesting(')
    replace('test/r27_resource_workspace_test.dart',
        'source.verifyNamesFromDirectory(root, progress: (_, _, _) {}),',
        'source.verifyNamesFromDirectory(root, control: SpkExtractControl(), progress: (_, _, _) {}),')
    replace('lib/editor/catalog_document.dart',
        """          magic.startsWith('pandaIT2'))
        p = '$p.itm';
      else if (magic.startsWith('MO2') || magic.startsWith('MO4'))
        p = '$p.mon';""",
        """          magic.startsWith('pandaIT2')) {
        p = '$p.itm';
      } else if (magic.startsWith('MO2') || magic.startsWith('MO4')) {
        p = '$p.mon';
      }""")
    replace('lib/ui/spk_archive_browser.dart',
        '    geometry.setIndex(mesh.indices.toList());',
        """    // Preserve the actual mesh UVs; a map without UVs is not a textured preview.
    if (mesh.uv.length != mesh.vertices * 2) {
      geometry.dispose();
      throw const FormatException('Coordenadas UV incompletas en la malla.');
    }
    geometry.setAttributeFromString(
      'uv', t.Float32BufferAttribute.fromList(mesh.uv.toList(), 2));
    geometry.setIndex(mesh.indices.toList());""")
    replace('lib/ui/resource_workspace.dart',
        '    return FutureBuilder<ResourceRead>(\n      future: load,',
        """    return FutureBuilder<ResourceRead>(
      // A new selection must never reuse the previous snapshot while loading.
      key: ValueKey((widget.index, e.key, request)),
      future: load,""")
    path = 'lib/data/library.dart'
    replace(path,
        """    if (replacements.isEmpty) return;

    final verified =""",
        """    if (replacements.isEmpty) return;

    // Capture the manifest BEFORE resource validation. An external edit during
    // asynchronous decryption must not become a new baseline we overwrite.
    final manifestFile = File('$spkOverlayRoot${Platform.pathSeparator}_SPK_OVERLAY.json');
    if (await manifestFile.exists() && await manifestFile.length() > 64 * 1024 * 1024) {
      throw const FormatException('Manifiesto overlay demasiado grande.');
    }
    final oldManifest = await manifestFile.exists() ? await manifestFile.readAsBytes() : null;
    final verified =""")
    replace(path,
        """    final manifestFile = File(
      '${root.path}${Platform.pathSeparator}_SPK_OVERLAY.json',
    );
    final oldManifest = await manifestFile.exists()
        ? await manifestFile.readAsBytes()
        : null;
    Map<String, dynamic> manifest = {""",
        """    final currentManifest = await manifestFile.exists() ? await manifestFile.readAsBytes() : null;
    if ((oldManifest == null) != (currentManifest == null) ||
        (oldManifest != null && FileSave.hash(oldManifest) != FileSave.hash(currentManifest!))) {
      throw const FormatException('El overlay cambió durante la verificación. Vuelve a abrir el recurso.');
    }
    Map<String, dynamic> manifest = {""")
    replace(path,
        """    if (await manifestFile.exists()) {
      try {
        final raw = jsonDecode(await manifestFile.readAsString());
        if (raw is Map &&
            raw['indexSha256']?.toString().toLowerCase() ==
                spk!.index.encryptedIndexSha256.toLowerCase()) {
          manifest = Map<String, dynamic>.from(raw);
        }
      } catch (_) {""",
        """    if (oldManifest != null) {
      try {
        final raw = jsonDecode(utf8.decode(oldManifest));
        if (raw is! Map || raw['entries'] is! Map ||
            raw['indexSha256']?.toString().toLowerCase() !=
                spk!.index.encryptedIndexSha256.toLowerCase()) {
          throw const FormatException('El manifiesto no corresponde al SPK.');
        }
        manifest = Map<String, dynamic>.from(raw);
      } catch (_) {""")
    for path, text in changes.items():
        (ROOT / path).write_text(text, encoding='utf-8')
    MARKER.write_text('R27 review: awaited fixtures, controls, UVs, independent selection and manifest baseline\n')


if __name__ == '__main__':
    main()
