"""Replace flutter_angle's debug ANGLE binaries with pinned release binaries.

The flutter_angle 0.4.2 Windows package currently bundles ANGLE DLLs built
against the MSVC debug CRT. Shipping those DLLs requires msvcp140d/ucrtbased
and is not suitable for a production redistributable.

This script uses the separately pinned comfy-angle wheel, which packages the
ANGLE DLLs from an Electron release, then verifies PE imports and required
exports before deleting the obsolete debug CRT payload.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import importlib.metadata
import json
import shutil
import struct
import sys
from pathlib import Path

DEBUG_CRT = {
    "msvcp140d.dll",
    "ucrtbased.dll",
    "vccorlib140d.dll",
    "vcruntime140_1d.dll",
    "vcruntime140d.dll",
}
OPTIONAL_OLD_ANGLE = {"libc++.dll", "zlib.dll"}
REQUIRED_EGL_EXPORTS = {
    "eglGetDisplay",
    "eglInitialize",
    "eglChooseConfig",
    "eglCreateContext",
    "eglCreatePbufferSurface",
    "eglMakeCurrent",
    "eglGetProcAddress",
    "eglGetError",
}
REQUIRED_GLES_EXPORTS = {
    "glGetString",
    "glGetError",
    "glGenBuffers",
    "glBindBuffer",
    "glBufferData",
    "glGenTextures",
    "glBindTexture",
    "glTexImage2D",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _read_c_string(data: bytes, offset: int) -> str:
    if offset < 0 or offset >= len(data):
        raise ValueError("PE string offset outside file")
    end = data.find(b"\0", offset)
    if end < 0:
        raise ValueError("Unterminated PE import name")
    return data[offset:end].decode("ascii", errors="strict")


def pe_imports(path: Path) -> set[str]:
    """Return normal + delay-load DLL imports from a PE32/PE32+ image."""

    data = path.read_bytes()
    if len(data) < 0x100 or data[:2] != b"MZ":
        return set()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if pe + 24 > len(data) or data[pe:pe + 4] != b"PE\0\0":
        return set()

    coff = pe + 4
    section_count = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    if opt + opt_size > len(data):
        raise ValueError(f"{path.name}: truncated optional header")
    magic = struct.unpack_from("<H", data, opt)[0]
    if magic == 0x20B:
        directory = opt + 112
    elif magic == 0x10B:
        directory = opt + 96
    else:
        raise ValueError(f"{path.name}: unsupported PE optional header {magic:#x}")

    sections_offset = opt + opt_size
    sections: list[tuple[int, int, int, int]] = []
    for i in range(section_count):
        s = sections_offset + i * 40
        if s + 40 > len(data):
            raise ValueError(f"{path.name}: truncated section table")
        virtual_size, virtual_address, raw_size, raw_ptr = struct.unpack_from(
            "<IIII", data, s + 8
        )
        sections.append((virtual_address, max(virtual_size, raw_size), raw_ptr, raw_size))

    def rva_offset(rva: int) -> int:
        if rva == 0:
            return 0
        for va, span, raw_ptr, raw_size in sections:
            if va <= rva < va + span:
                delta = rva - va
                if delta >= raw_size:
                    raise ValueError(f"{path.name}: RVA points outside raw section")
                return raw_ptr + delta
        # Header RVAs are legal too.
        if rva < sections_offset:
            return rva
        raise ValueError(f"{path.name}: unresolved RVA {rva:#x}")

    imports: set[str] = set()

    # IMAGE_DIRECTORY_ENTRY_IMPORT = 1
    if directory + 16 <= opt + opt_size:
        import_rva, import_size = struct.unpack_from("<II", data, directory + 8)
        if import_rva and import_size:
            cursor = rva_offset(import_rva)
            limit = min(len(data), cursor + import_size)
            while cursor + 20 <= limit:
                desc = struct.unpack_from("<IIIII", data, cursor)
                if not any(desc):
                    break
                name_rva = desc[3]
                imports.add(_read_c_string(data, rva_offset(name_rva)).lower())
                cursor += 20

    # IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT = 13
    delay_entry = directory + 13 * 8
    if delay_entry + 8 <= opt + opt_size:
        delay_rva, delay_size = struct.unpack_from("<II", data, delay_entry)
        if delay_rva and delay_size:
            cursor = rva_offset(delay_rva)
            limit = min(len(data), cursor + delay_size)
            while cursor + 32 <= limit:
                fields = struct.unpack_from("<IIIIIIII", data, cursor)
                if not any(fields):
                    break
                attrs, name_value = fields[0], fields[1]
                # Modern delay descriptors use RVAs (dlattrRva == 1). We reject
                # VA form instead of guessing ImageBase arithmetic.
                if attrs & 1 == 0:
                    raise ValueError(
                        f"{path.name}: unsupported VA-based delay import descriptor"
                    )
                imports.add(_read_c_string(data, rva_offset(name_value)).lower())
                cursor += 32

    return imports


def _verify_exports(path: Path, exports: set[str]) -> None:
    dll = ctypes.WinDLL(str(path))
    missing = [name for name in sorted(exports) if not hasattr(dll, name)]
    if missing:
        raise RuntimeError(
            f"{path.name} missing required exports: {', '.join(missing)}"
        )


def _copy_license_files(lib_dir: Path, release: Path) -> list[str]:
    target = release / "Docs" / "ThirdParty" / "ANGLE"
    target.mkdir(parents=True, exist_ok=True)
    copied: list[str] = []
    candidates = {
        "electron-LICENSE",
        "LICENSES.chromium.html",
        "LICENSE",
        "LICENSE.txt",
    }
    # comfy-angle stores licenses either beside platform_libs or in package data.
    roots = [lib_dir, *lib_dir.parents[:3]]
    seen: set[Path] = set()
    for root in roots:
        if root in seen or not root.exists():
            continue
        seen.add(root)
        for name in candidates:
            source = root / name
            if source.is_file():
                dest = target / name
                shutil.copy2(source, dest)
                copied.append(str(dest.relative_to(release)).replace("\\", "/"))
    return sorted(set(copied))


def main() -> None:
    if sys.platform != "win32":
        raise RuntimeError("ANGLE runtime hardening must run on Windows")

    parser = argparse.ArgumentParser()
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()

    release = args.release.resolve()
    evidence_path = args.evidence.resolve()
    if not (release / "herramienta_shaiya.exe").is_file():
        raise RuntimeError(f"Release directory is invalid: {release}")

    try:
        import comfy_angle
    except ImportError as exc:
        raise RuntimeError(
            "Pinned comfy-angle package is required before hardening"
        ) from exc

    version = importlib.metadata.version("comfy-angle")
    if version != "0.1.1":
        raise RuntimeError(f"Unexpected comfy-angle version: {version}")

    egl_source = Path(comfy_angle.get_egl_path()).resolve()
    gles_source = Path(comfy_angle.get_glesv2_path()).resolve()
    if not egl_source.is_file() or not gles_source.is_file():
        raise RuntimeError("comfy-angle did not expose Windows ANGLE DLLs")

    replacements = {
        "libEGL.dll": egl_source,
        "libGLESv2.dll": gles_source,
    }
    before = {
        name: sha256(release / name)
        for name in replacements
        if (release / name).is_file()
    }
    for name, source in replacements.items():
        shutil.copy2(source, release / name)

    # First verify that the replacement binaries themselves do not require the
    # debug CRT and expose the subset used by flutter_angle.
    egl_imports = pe_imports(release / "libEGL.dll")
    gles_imports = pe_imports(release / "libGLESv2.dll")
    debug_imports = sorted((egl_imports | gles_imports) & DEBUG_CRT)
    if debug_imports:
        raise RuntimeError(
            "Release ANGLE still imports debug CRT: " + ", ".join(debug_imports)
        )
    _verify_exports(release / "libEGL.dll", REQUIRED_EGL_EXPORTS)
    _verify_exports(release / "libGLESv2.dll", REQUIRED_GLES_EXPORTS)

    # Analyze all PE files before deleting legacy runtime DLLs.
    pe_files = sorted(
        p for p in release.iterdir()
        if p.is_file() and p.suffix.lower() in {".dll", ".exe"}
    )
    imports_by_file = {
        p.name: sorted(pe_imports(p))
        for p in pe_files
    }
    legacy_names = {name.lower() for name in DEBUG_CRT | OPTIONAL_OLD_ANGLE}

    # The upstream ANGLE payload is a dependency cluster: its own debug CRT
    # DLLs can import each other (for example vccorlib140d -> msvcp140d), and
    # libc++.dll can also import the debug CRT. Those internal edges must not
    # keep the obsolete cluster alive after libEGL/libGLESv2 are replaced.
    # Only imports from PE files that will remain in the release are relevant.
    retained_imports = {
        file: deps
        for file, deps in imports_by_file.items()
        if file.lower() not in legacy_names
    }

    removed: list[str] = []
    retained_legacy: dict[str, list[str]] = {}
    for name in sorted(DEBUG_CRT | OPTIONAL_OLD_ANGLE):
        path = release / name
        if not path.is_file():
            continue
        users = sorted(
            file
            for file, deps in retained_imports.items()
            if name.lower() in deps
        )
        if users:
            retained_legacy[name] = users
            if name in DEBUG_CRT:
                raise RuntimeError(
                    f"{name} still required by retained release PE(s): "
                    + ", ".join(users)
                )
            continue
        path.unlink()
        removed.append(name)

    # Re-scan after deletion and refuse a package with any debug-CRT reference.
    final_pe_files = sorted(
        p for p in release.iterdir()
        if p.is_file() and p.suffix.lower() in {".dll", ".exe"}
    )
    final_imports = {
        p.name: sorted(pe_imports(p))
        for p in final_pe_files
    }
    offenders = {
        file: sorted(set(deps) & DEBUG_CRT)
        for file, deps in final_imports.items()
        if set(deps) & DEBUG_CRT
    }
    if offenders:
        raise RuntimeError(f"Debug CRT imports remain after hardening: {offenders}")

    licenses = _copy_license_files(egl_source.parent, release)
    evidence = {
        "schema": 1,
        "provider": "comfy-angle",
        "providerVersion": version,
        "providerWheelSha256WinAmd64":
            "beddd2e3b9a67e55f5afaef4da73e3ac704fd88f0cbe6a6f67ce5718d7c7edeb",
        "upstream": "Electron ANGLE runtime packaged by Comfy-Org/comfy-angle",
        "oldDllSha256": before,
        "releaseDllSha256": {
            name: sha256(release / name) for name in replacements
        },
        "releaseDllImports": {
            "libEGL.dll": sorted(egl_imports),
            "libGLESv2.dll": sorted(gles_imports),
        },
        "requiredExportsVerified": {
            "libEGL.dll": sorted(REQUIRED_EGL_EXPORTS),
            "libGLESv2.dll": sorted(REQUIRED_GLES_EXPORTS),
        },
        "removedLegacyRuntime": removed,
        "retainedLegacyRuntime": retained_legacy,
        "debugCrtImports": offenders,
        "licensesBundled": licenses,
        "hardened": True,
    }
    evidence_path.parent.mkdir(parents=True, exist_ok=True)
    evidence_path.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(evidence, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
