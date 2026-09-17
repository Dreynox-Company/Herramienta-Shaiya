"""Generate official Flutter runners while preserving application sources.

No game resources, global security settings, signing keys or SDKs are modified.
"""
from __future__ import annotations

from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def prepare(platforms: str = "windows,android") -> None:
    if not set(platforms.split(",")) <= {"windows", "android", "linux"}:
        raise ValueError("Plataforma de generación no permitida.")
    flutter = shutil.which("flutter")
    if not flutter:
        raise RuntimeError("No se encuentra Flutter. Añade flutter/bin al PATH y vuelve a abrir la consola.")

    # flutter create should retain existing files. Keep an explicit backup of the
    # product entrypoint/manifest too, rather than depending on that assumption.
    protected = {name: (ROOT / name).read_bytes() for name in (
        "lib/main.dart", "pubspec.yaml", "pubspec.lock", "analysis_options.yaml"
    ) if (ROOT / name).is_file()}
    test_path = ROOT / "test/widget_test.dart"
    previous_test = test_path.read_bytes() if test_path.exists() else None
    try:
        subprocess.run([
            flutter, "create", "--no-pub", f"--platforms={platforms}",
            "--org", "com.dreynox", "--project-name", "herramienta_shaiya", "."
        ], cwd=ROOT, check=True)
    finally:
        for name, content in protected.items():
            target = ROOT / name
            if not target.exists() or target.read_bytes() != content:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
        if previous_test is not None:
            test_path.write_bytes(previous_test)
        elif test_path.exists() and "counter increments" in test_path.read_text(encoding="utf-8"):
            test_path.unlink()

    if "android" in platforms.split(","):
        target = ROOT / "android/app/src/main/kotlin/com/dreynox/herramienta_shaiya/MainActivity.kt"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "platform/android/MainActivity.kt", target)
        manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
        text = manifest.read_text(encoding="utf-8").replace(
            'android:label="herramienta_shaiya"', 'android:label="Shaiya Studio"'
        )
        manifest.write_text(text, encoding="utf-8")
    if "windows" in platforms.split(","):
        runner = ROOT / "windows/runner/main.cpp"
        if runner.exists():
            text = runner.read_text(encoding="utf-8").replace(
                'L"herramienta_shaiya"', 'L"Shaiya Studio"'
            ).replace("1280, 720", "1440, 900")
            runner.write_text(text, encoding="utf-8")
    print("Plataformas preparadas. Las fuentes y los recursos DATA permanecen intactos.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platforms", default="windows,android")
    args = parser.parse_args()
    try:
        prepare(args.platforms)
    except (OSError, RuntimeError, subprocess.CalledProcessError, ValueError) as exc:
        print(f"No se pudo preparar el proyecto: {exc}", file=sys.stderr)
        raise SystemExit(1)
