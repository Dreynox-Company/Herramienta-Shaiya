"""Generate official Flutter runners while preserving application sources.

No game resources, global security settings, signing keys or SDKs are modified.
"""
from __future__ import annotations

from pathlib import Path
import argparse
import shutil
import subprocess
import sys
from prepare_branding import prepare as prepare_branding

ROOT = Path(__file__).resolve().parents[1]

WINDOWS_ICONS = r'''  // SHSTUDIO_RUNTIME_ICON: original supplied HQ icon, local only.
  struct ShStudioIcons {
    HICON large_icon = nullptr;
    HICON small_icon = nullptr;
    ~ShStudioIcons() {
      if (large_icon) DestroyIcon(large_icon);
      if (small_icon) DestroyIcon(small_icon);
    }
  } shstudio_icons;
  wchar_t executable_path[32768] = {};
  DWORD executable_length = GetModuleFileNameW(nullptr, executable_path, 32768);
  if (executable_length > 0 && executable_length < 32768) {
    std::wstring icon_path(executable_path, executable_length);
    auto slash = icon_path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
      icon_path.resize(slash + 1);
      icon_path += L"Extras\\Branding\\ShStudio_Logo_HQ.ico";
      shstudio_icons.large_icon = static_cast<HICON>(LoadImageW(nullptr, icon_path.c_str(),
        IMAGE_ICON, GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON), LR_LOADFROMFILE));
      shstudio_icons.small_icon = static_cast<HICON>(LoadImageW(nullptr, icon_path.c_str(),
        IMAGE_ICON, GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));
      if (shstudio_icons.large_icon) SendMessageW(window.GetHandle(), WM_SETICON, ICON_BIG,
        reinterpret_cast<LPARAM>(shstudio_icons.large_icon));
      if (shstudio_icons.small_icon) SendMessageW(window.GetHandle(), WM_SETICON, ICON_SMALL,
        reinterpret_cast<LPARAM>(shstudio_icons.small_icon));
    }
  }'''


def brand_windows_runner(text: str) -> str:
    """Replace only our generated block, including runners from earlier builds."""
    anchor = '  window.SetQuitOnClose(true);'
    marker = '  // SHSTUDIO_RUNTIME_ICON:'
    if text.count(anchor) != 1 or text.count(marker) > 1:
        raise RuntimeError('Unknown Flutter runner template; no file was written.')
    start = text.find(marker)
    end = text.index(anchor)
    if start >= 0:
        if start >= end:
            raise RuntimeError('Unexpected branding block order; no file was written.')
        text = text[:start] + WINDOWS_ICONS + '\n' + text[end:]
    else:
        text = text.replace(anchor, WINDOWS_ICONS + '\n' + anchor, 1)
    return text.replace('L"herramienta_shaiya"', 'L"ShStudio"').replace(
        'L"Shaiya Studio"', 'L"ShStudio"'
    ).replace('1280, 720', '1440, 900')


def prepare(platforms: str = 'windows,android') -> None:
    if not set(platforms.split(',')) <= {'windows', 'android', 'linux'}:
        raise ValueError('Plataforma de generación no permitida.')
    icon = prepare_branding(ROOT)
    flutter = shutil.which('flutter')
    if not flutter:
        raise RuntimeError('No se encuentra Flutter. Añade flutter/bin al PATH y vuelve a abrir la consola.')

    # Keep explicit backups even when flutter create promises to retain files.
    protected = {name: (ROOT / name).read_bytes() for name in (
        'lib/main.dart', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml'
    ) if (ROOT / name).is_file()}
    test_path = ROOT / 'test/widget_test.dart'
    previous_test = test_path.read_bytes() if test_path.exists() else None
    try:
        subprocess.run([
            flutter, 'create', '--no-pub', f'--platforms={platforms}',
            '--org', 'com.dreynox', '--project-name', 'herramienta_shaiya', '.'
        ], cwd=ROOT, check=True)
    finally:
        for name, content in protected.items():
            target = ROOT / name
            if not target.exists() or target.read_bytes() != content:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
        if previous_test is not None:
            test_path.write_bytes(previous_test)
        elif test_path.exists() and 'counter increments' in test_path.read_text(encoding='utf-8'):
            test_path.unlink()

    if 'android' in platforms.split(','):
        target = ROOT / 'android/app/src/main/kotlin/com/dreynox/herramienta_shaiya/MainActivity.kt'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / 'platform/android/MainActivity.kt', target)
        manifest = ROOT / 'android/app/src/main/AndroidManifest.xml'
        text = manifest.read_text(encoding='utf-8').replace(
            'android:label="herramienta_shaiya"', 'android:label="Shaiya Studio"'
        )
        manifest.write_text(text, encoding='utf-8')
    if 'windows' in platforms.split(','):
        runner = ROOT / 'windows/runner/main.cpp'
        if runner.exists():
            text = brand_windows_runner(runner.read_text(encoding='utf-8'))
            runner.write_text(text, encoding='utf-8')
            (ROOT / 'windows/runner/resources/app_icon.ico').write_bytes(icon)
    print('Plataformas preparadas. Las fuentes y los recursos DATA permanecen intactos.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platforms', default='windows,android')
    args = parser.parse_args()
    try:
        prepare(args.platforms)
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as exc:
        print(f'No se pudo preparar el proyecto: {exc}', file=sys.stderr)
        raise SystemExit(1)
