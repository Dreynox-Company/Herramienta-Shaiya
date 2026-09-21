import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/ui/spk_archive_browser.dart';

void main() {
  test('SPK profile discovery includes packaged profile beside executable', () {
    final paths = spkProfileCandidatePaths(
      r'C:\Games\Shaiya\data.spk',
      executablePath: r'C:\Tools\ShaiyaStudio\herramienta_shaiya.exe',
    );
    expect(
      paths,
      contains(
        r'C:\Tools\ShaiyaStudio\profiles\spk-crypto-profile.json',
      ),
    );
    expect(paths, contains(r'C:\Games\Shaiya\data.spk.profile.json'));
  });
}
