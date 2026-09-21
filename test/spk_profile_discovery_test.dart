import 'package:flutter_test/flutter_test.dart';
import 'package:herramienta_shaiya/ui/spk_archive_browser.dart';

void main() {
  test('SPK profile discovery includes packaged profile beside executable', () {
    final paths = spkProfileCandidatePaths(
      r'C:\Games\Shaiya\data.spk',
      executablePath: r'C:\Tools\ShaiyaStudio\herramienta_shaiya.exe',
      separatorOverride: r'\',
    );
    expect(
      paths,
      contains(r'C:\Tools\ShaiyaStudio\profiles\spk-crypto-profile.json'),
    );
    expect(paths, contains(r'C:\Games\Shaiya\data.spk.profile.json'));
  });

  test('SPK name map discovery includes packaged and hash-specific maps', () {
    final paths = spkNameMapCandidatePaths(
      r'C:\\Games\\Shaiya\\data.spk',
      'a3ea7e3b6d6fa0012956dab15f0c8e02198d7a4fa6d40f2f39428af13e3bd20f',
      executablePath: r'C:\\Tools\\ShaiyaStudio\\herramienta_shaiya.exe',
      separatorOverride: r'\\',
    );
    expect(
      paths,
      contains(r'C:\\Tools\\ShaiyaStudio\\profiles\\spk-name-map.json'),
    );
    expect(
      paths,
      contains(
        r'C:\\Tools\\ShaiyaStudio\\profiles\\spk-name-map-a3ea7e3b.json',
      ),
    );
    expect(paths, contains(r'C:\\Games\\Shaiya\\data.spk.names.json'));
  });
}
