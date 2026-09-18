"""Build and verify Shaiya Studio locally. Requires an installed Flutter toolchain."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile

from prepare import ROOT, prepare


def cmake_version(executable: str) -> tuple[int, int, int] | None:
    try:
        result = subprocess.run([executable, "--version"], check=True, capture_output=True, text=True)
        match = re.search(r"cmake version (\d+)\.(\d+)\.(\d+)", result.stdout)
        return tuple(map(int, match.groups())) if match else None
    except (OSError, subprocess.CalledProcessError):
        return None


def check_android_cmake() -> None:
    """Prefer installed tools; do not silently install or alter system PATH."""
    candidates = []
    installed = shutil.which("cmake")
    if installed:
        candidates.append(installed)
    roots = [os.environ.get(k) for k in ("ANDROID_SDK_ROOT", "ANDROID_HOME")]
    if os.name == "nt":
        roots.append(str(Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk"))
    else:
        roots.append(str(Path.home() / "Android/Sdk"))
    for folder in roots:
        if folder:
            candidates.extend(str(p) for p in Path(folder).glob("cmake/*/bin/cmake*"))
    for candidate in candidates:
        version = cmake_version(candidate)
        if version is not None and version >= (3, 31, 0):
            os.environ["PATH"] = str(Path(candidate).parent) + os.pathsep + os.environ.get("PATH", "")
            print(f"CMake disponible: {version[0]}.{version[1]}.{version[2]}")
            return
    raise RuntimeError(
        "El backend Android requiere CMake 3.31 o superior. Instálalo con Android Studio "
        "(SDK Manager > SDK Tools > CMake) o con la distribución oficial, y vuelve a ejecutar. "
        "El script no instala herramientas ni cambia ajustes globales."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("windows", "android", "both", "test"), default="windows")
    parser.add_argument("--run", action="store_true", help="Abrir Windows solo después de una compilación correcta")
    parser.add_argument("--integration", action="store_true", help="Probar una ventana Windows con recursos sintéticos")
    args = parser.parse_args()
    flutter = shutil.which("flutter")
    if not flutter:
        raise RuntimeError("No se encuentra Flutter en PATH. Consulta INSTRUCCIONES.md.")
    if args.platform in ("windows", "both") and os.name != "nt":
        raise RuntimeError("El ejecutable Windows debe compilarse en Windows, no en Linux/macOS.")
    if args.integration and os.name != "nt":
        raise RuntimeError("La prueba de ventana Windows requiere Windows.")
    if args.platform in ("android", "both"):
        check_android_cmake()
    logs = ROOT / ".build-logs"
    logs.mkdir(exist_ok=True)
    log_path = logs / (time.strftime("compilacion_%Y%m%d_%H%M%S") + ".log")
    commands = []
    with log_path.open("w", encoding="utf-8") as log:
        def run(command: list[str], env: dict[str, str] | None = None) -> None:
            commands.append(command)
            title = "\n> " + subprocess.list2cmdline(command)
            print(title)
            log.write(title + "\n")
            log.flush()
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
            assert process.stdout is not None
            for line in process.stdout:
                print(line, end="", flush=True)
                log.write(line)
            if process.wait() != 0:
                raise RuntimeError(f"Falló {command[1] if len(command)>1 else command[0]}. Registro: {log_path}")
            log.flush()

        run([flutter, "--version"])
        if args.platform != "test" or args.integration:
            platforms = "windows,android" if args.platform == "both" else (
                "windows" if args.integration else args.platform)
            prepare(platforms)
        run([flutter, "pub", "get", "--enforce-lockfile"])
        # Informational legacy style hints do not mask errors or warnings.
        run([flutter, "analyze", "--no-fatal-infos"])
        run([flutter, "test", "--reporter", "expanded"])
        run([sys.executable, "-m", "unittest", "discover", "-s", "tool/tests", "-v"])
        if args.integration:
            fixture = logs / "fixture-sintetica"
            run([sys.executable, "tool/make_native_fixture.py", str(fixture)])
            env = dict(os.environ, SHAIYA_FIXTURE_PATH=str(fixture), SHAIYA_QA_PATH=str(logs / "qa-native"))
            run([flutter, "test", "integration_test/native_studio_test.dart", "-d", "windows", "--reporter", "expanded"], env)
        dist = ROOT / "dist"
        dist.mkdir(exist_ok=True)
        produced = []
        if args.platform in ("windows", "both"):
            run([flutter, "build", "windows", "--release"])
            folder = ROOT / "build/windows/x64/runner/Release"
            executable = folder / "herramienta_shaiya.exe"
            if not executable.is_file() or not (folder / "data").is_dir():
                raise RuntimeError("La compilación no produjo un paquete Windows completo; no se generará el ZIP.")
            shutil.copy2(ROOT / "LEEME_WINDOWS.txt", folder / "LEEME.txt")
            target = dist / "Shaiya_Studio_0_4_0_Windows.zip"
            temporary = target.with_suffix(".zip.tmp")
            with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as z:
                for item in sorted(folder.rglob("*")):
                    if item.is_file() and not item.is_symlink():
                        z.write(item, item.relative_to(folder).as_posix())
            with zipfile.ZipFile(temporary) as z:
                if z.testzip() is not None:
                    raise RuntimeError("El ZIP de Windows no supera la comprobación de integridad.")
            temporary.replace(target)
            produced.append(str(target))
        if args.platform in ("android", "both"):
            run([flutter, "build", "apk", "--debug"])
            apk = ROOT / "build/app/outputs/flutter-apk/app-debug.apk"
            if not apk.is_file():
                raise RuntimeError("La compilación no produjo el APK; no se generará un archivo de entrega.")
            target = dist / "Shaiya_Studio_0_4_0_Android_PRUEBAS.apk"
            shutil.copy2(apk, target)
            produced.append(str(target))
        report = {"version": "0.4.0+6", "platform": args.platform, "commands": commands,
                  "outputs": produced, "finished": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                  "native_window_integration": args.integration, "log": str(log_path)}
        (dist / "compilacion_local.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print("\nProceso completado.\n" + ("\n".join(produced) if produced else "Pruebas y análisis correctos."))
        if args.run and args.platform in ("windows", "both"):
            subprocess.Popen([str(executable)], cwd=executable.parent)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"\nCOMPILACIÓN INTERRUMPIDA: {exc}", file=sys.stderr)
        raise SystemExit(1)
