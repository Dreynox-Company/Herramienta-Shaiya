"""Genera los runners oficiales sin reemplazar el código de la aplicación."""
from pathlib import Path
import os, shutil, subprocess, sys
root = Path(__file__).resolve().parents[1]
os.chdir(root)
flutter = shutil.which('flutter')
if not flutter:
    raise SystemExit('Instala Flutter estable y añade flutter/bin a PATH antes de continuar.')
# flutter create solo añade archivos ausentes; --no-pub evita resolver dos veces.
subprocess.run([flutter, 'create', '--no-pub', '--platforms=windows,android', '--org', 'com.dreynox', '--project-name', 'herramienta_shaiya', '.'], check=True)
target = root / 'android/app/src/main/kotlin/com/dreynox/herramienta_shaiya/MainActivity.kt'
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'platform/android/MainActivity.kt', target)
manifest = root / 'android/app/src/main/AndroidManifest.xml'
text = manifest.read_text(encoding='utf-8').replace('android:label="herramienta_shaiya"', 'android:label="Shaiya"')
manifest.write_text(text, encoding='utf-8')
runner = root / 'windows/runner/main.cpp'
if runner.exists():
    s = runner.read_text(encoding='utf-8').replace('L"herramienta_shaiya"', 'L"Shaiya"').replace('1280, 720', '1024, 768')
    runner.write_text(s, encoding='utf-8')
# La prueba del contador generada por flutter create no pertenece a este programa.
generated_test = root / 'test/widget_test.dart'
if generated_test.exists() and 'counter increments' in generated_test.read_text(encoding='utf-8'):
    generated_test.unlink()
print('Runners Windows y Android preparados. Ejecuta flutter pub get.')
