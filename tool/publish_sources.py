"""Publish the verified source package to a new branch of the user's repository.

Runs only when explicitly launched by the user. No force push or merge.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[1]
BASE = "748d612a00bd8ef9f417bb38604f8dd4fe920aab"
REPOSITORY = "Dreynox-Company/Herramienta-Shaiya"
BASE_BRANCH = "feat/studio-04-audited-release"


def verified_sources() -> dict[str, bytes]:
    manifest = json.loads((SOURCE / "manifest-entrega.json").read_text(encoding="utf-8"))
    if manifest.get("base_commit") != BASE or manifest.get("version") != "0.5.0+7":
        raise RuntimeError("El manifiesto no pertenece a esta entrega.")
    result = {}
    for name, expected in manifest["files"].items():
        rel = PurePosixPath(name)
        if rel.is_absolute() or ".." in rel.parts or "\\" in name or ":" in name:
            raise RuntimeError(f"Ruta no permitida en el manifiesto: {name}")
        path = SOURCE.joinpath(*rel.parts)
        if path.is_symlink() or SOURCE.resolve() not in path.resolve().parents:
            raise RuntimeError(f"El archivo escapa del paquete: {name}")
        contents = path.read_bytes()
        if hashlib.sha256(contents).hexdigest() != expected:
            raise RuntimeError(f"El archivo se modificó desde la entrega: {name}. Revisa los cambios antes de publicar.")
        result[name] = contents
    if not all(name in result for name in ("lib/main.dart", "lib/data/catalog.dart", "lib/data/game_names.dart", "pubspec.yaml")):
        raise RuntimeError("El paquete no contiene las fuentes necesarias.")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", help="Ruta de un clon limpio de Dreynox-Company/Herramienta-Shaiya")
    parser.add_argument("--branch", default="feat/studio-05-integration")
    parser.add_argument("--no-push", action="store_true", help="Crear el commit local sin enviarlo a GitHub")
    parser.add_argument("--yes", action="store_true", help="Confirmar la publicación explícitamente")
    args = parser.parse_args()
    if not re.fullmatch(r"feat/[a-zA-Z0-9][a-zA-Z0-9._/-]{2,100}", args.branch) or ".." in args.branch or args.branch == BASE_BRANCH:
        raise RuntimeError("Usa una rama nueva feat/...; no main ni la rama base.")
    repo = Path(args.repository).resolve()
    if not repo.is_dir() or not (repo / ".git").exists():
        raise RuntimeError("La ruta no es un clon Git existente.")
    if repo == SOURCE.resolve() or repo in SOURCE.resolve().parents:
        raise RuntimeError("Extrae la entrega fuera del clon antes de ejecutar el publicador.")
    git = shutil.which("git")
    if not git:
        raise RuntimeError("Instala Git e inicia sesión en tu cuenta antes de publicar.")
    def run(*parts: str, allow_failure: bool = False) -> str:
        p = subprocess.run([git, *parts], cwd=repo, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if p.returncode != 0 and not allow_failure:
            raise RuntimeError(f"git {parts[0]}: {p.stderr.strip() or p.stdout.strip()}")
        return p.stdout.strip()
    origin = run("remote", "get-url", "origin").rstrip("/")
    valid = {f"https://github.com/{REPOSITORY}", f"https://github.com/{REPOSITORY}.git", f"git@github.com:{REPOSITORY}.git", f"ssh://git@github.com/{REPOSITORY}.git"}
    if origin not in valid:
        raise RuntimeError("El origen no coincide exactamente con el repositorio autorizado.")
    if run("status", "--porcelain", "--untracked-files=all"):
        raise RuntimeError("El clon tiene cambios sin guardar. Consérvalos antes de publicar; el script no los borra ni hace stash.")
    for key in ("user.name", "user.email"):
        if not run("config", "--get", key, allow_failure=True):
            raise RuntimeError(f"Configura tu identidad Git ({key}) en el clon. El script no inventa una identidad.")
    files = verified_sources()
    print(f"Repositorio: {REPOSITORY}\nNueva rama: {args.branch}\nFuentes: {len(files)}\nBase exigida: {BASE}")
    if not args.yes and input("Escribe PUBLICAR para continuar: ").strip() != "PUBLICAR":
        print("Operación cancelada sin cambiar el repositorio.")
        return
    run("fetch", "origin", f"refs/heads/{BASE_BRANCH}")
    if run("rev-parse", "FETCH_HEAD") != BASE:
        raise RuntimeError("La rama remota cambió desde esta entrega. Se detiene para no sobrescribir trabajo posterior. Integra los cambios mediante revisión de diff.")
    if run("branch", "--list", args.branch) or run("ls-remote", "--heads", "origin", f"refs/heads/{args.branch}"):
        raise RuntimeError("La rama de destino ya existe. Elige otro nombre; no se reemplazará.")
    for name in files:
        target = repo / name
        if any(p.is_symlink() for p in [target, *target.parents] if p != repo.parent):
            raise RuntimeError(f"Ruta de destino con enlace simbólico: {name}")
        if repo not in target.resolve().parents:
            raise RuntimeError(f"Ruta de destino fuera del clon: {name}")
    run("switch", "--no-track", "-c", args.branch, "FETCH_HEAD")
    for name, content in files.items():
        target = repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    # Stage only manifest files. No git add ., raw game assets, secrets or SDKs.
    names = sorted(files)
    for i in range(0, len(names), 30):
        run("add", "--", *names[i:i+30])
    diff_names = run("diff", "--cached", "--name-only").splitlines()
    if any(name not in files for name in diff_names):
        raise RuntimeError("Hay cambios en el índice ajenos al paquete. Se detiene antes del commit.")
    run("commit", "-m", "feat: integrate Shaiya Studio 0.5.0 archive support, equipment rules and streamed scenes")
    sha = run("rev-parse", "HEAD")
    if args.no_push:
        print(f"Commit LOCAL creado: {sha}. No se ha enviado a GitHub.")
    else:
        run("push", "--set-upstream", "origin", f"HEAD:refs/heads/{args.branch}")
        print(f"Rama publicada: {args.branch}\nCommit: {sha}\nNo se ha fusionado con main. Revisa GitHub Actions antes de distribuir los binarios.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, EOFError, subprocess.CalledProcessError) as exc:
        print(f"PUBLICACIÓN DETENIDA: {exc}", file=sys.stderr)
        raise SystemExit(1)
