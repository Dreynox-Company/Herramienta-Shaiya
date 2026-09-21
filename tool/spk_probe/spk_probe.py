from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import threading
import time

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import frida
import zstandard as zstd

MAGIC = 0x9E7BD34C
VERSION = 0x00030000
HEADER = 128
RECORD = 96
AUX = 32
ZSTD = bytes.fromhex("28b52ffd")

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("Perfil JSON inválido")
    return value

def profile_candidates(spk: Path) -> list[Path]:
    exe = Path(sys.executable).resolve().parent
    here = Path(__file__).resolve().parent
    return [
        Path(str(spk) + ".profile.json"),
        spk.parent / "data.spk.profile.json",
        spk.parent / "spk-crypto-profile.json",
        exe / "profiles" / "data.spk.profile.json",
        exe / "profiles" / "spk-crypto-profile.json",
        here.parent.parent / "profiles" / "spk-crypto-profile.json",
    ]

def load_profile(spk: Path, explicit: Path | None) -> tuple[Path, dict, bytes]:
    choices = [explicit] if explicit else profile_candidates(spk)
    for path in choices:
        if path is None or not path.is_file():
            continue
        data = read_json(path)
        index = data.get("index") if isinstance(data.get("index"), dict) else {}
        secret_hex = data.get("secretHex") or index.get("secretHex")
        expected = str(data.get("indexSha256") or "").lower()
        if not isinstance(secret_hex, str) or len(secret_hex.strip()) != 32:
            continue
        return path, data, bytes.fromhex(secret_hex)
    raise ValueError("No se encontró un perfil SPK con la clave de índice validada.")

def parse_spk(spk: Path, index_key: bytes, expected_hash: str) -> tuple[dict, list[dict], list[dict]]:
    size = spk.stat().st_size
    with spk.open("rb") as f:
        head = f.read(HEADER)
    if len(head) != HEADER:
        raise ValueError("Cabecera SPK incompleta")
    magic, version = struct.unpack_from("<II", head, 0)
    if magic != MAGIC or version != VERSION:
        raise ValueError("SPK v3 no reconocido")
    index_offset = struct.unpack_from("<Q", head, 8)[0]
    index_stored = struct.unpack_from("<Q", head, 16)[0]
    index_decoded = struct.unpack_from("<Q", head, 24)[0]
    record_count = struct.unpack_from("<I", head, 32)[0]
    block_bytes = struct.unpack_from("<I", head, 36)[0]
    nonce = head[40:52]
    tag = head[52:68]
    aux_offset = struct.unpack_from("<Q", head, 100)[0]
    aux_count = struct.unpack_from("<I", head, 108)[0]
    if index_decoded != record_count * RECORD:
        raise ValueError("Geometría del índice inconsistente")
    if index_offset + index_stored > size - 64:
        raise ValueError("Índice fuera del archivo")
    with spk.open("rb") as f:
        f.seek(index_offset)
        encrypted = f.read(index_stored)
        f.seek(aux_offset)
        aux_raw = f.read(aux_count * AUX)
    digest = sha(encrypted)
    if expected_hash and digest != expected_hash:
        raise ValueError("El perfil pertenece a otro DATA.SPK")
    packed = AESGCM(index_key).decrypt(nonce, encrypted + tag, None)
    if not packed.startswith(ZSTD):
        raise ValueError("La salida AES-GCM del índice no es Zstandard")
    decoded = zstd.ZstdDecompressor().decompress(packed, max_output_size=index_decoded)
    if len(decoded) != index_decoded:
        raise ValueError("Longitud del índice decodificado incorrecta")

    records: list[dict] = []
    for i in range(record_count):
        o = i * RECORD
        entry, offset, stored, mirror, clear = struct.unpack_from("<5Q", decoded, o)
        kind, aux_start = struct.unpack_from("<II", decoded, o + 40)
        meta = decoded[o + 48:o + 80]
        if stored != mirror or any(decoded[o + 80:o + 96]):
            raise ValueError(f"Registro {i} inválido")
        records.append({
            "ordinal": i,
            "entryId": entry,
            "offset": offset,
            "stored": stored,
            "decoded": clear,
            "kind": kind,
            "auxStart": aux_start,
            "chunkCount": struct.unpack_from("<I", meta, 28)[0] if kind == 3 else 0,
            "meta": meta,
        })

    aux: list[dict] = []
    if len(aux_raw) != aux_count * AUX:
        raise ValueError("Tabla auxiliar incompleta")
    for i in range(aux_count):
        o = i * AUX
        offset, stored, mirror = struct.unpack_from("<QII", aux_raw, o)
        if stored != mirror:
            raise ValueError(f"Fragmento auxiliar {i} inválido")
        aux.append({"ordinal": i, "offset": offset, "stored": stored, "tag": aux_raw[o + 16:o + 32]})

    return {
        "size": size,
        "indexSha256": digest,
        "indexOffset": index_offset,
        "indexStored": index_stored,
        "indexDecoded": index_decoded,
        "recordCount": record_count,
        "blockBytes": block_bytes,
        "auxOffset": aux_offset,
        "auxCount": aux_count,
        "decodedIndexSha256": sha(decoded),
    }, records, aux

def target_map(spk: Path, records: list[dict], aux: list[dict]) -> tuple[dict[str, int], dict[str, dict]]:
    prefixes: dict[str, int] = {}
    details: dict[str, dict] = {}
    with spk.open("rb") as f:
        for r in records:
            if r["kind"] == 1:
                f.seek(r["offset"])
                prefix = f.read(16)
                if len(prefix) != 16:
                    continue
                key = prefix.hex()
                if key in prefixes:
                    raise ValueError("Colisión de prefijo SPK simple")
                prefixes[key] = r["stored"]
                details[key] = {
                    "kind": "simple",
                    "ordinal": r["ordinal"],
                    "entryId": f'{r["entryId"]:016x}',
                    "offset": r["offset"],
                    "stored": r["stored"],
                    "decoded": r["decoded"],
                    "nonce": r["meta"][:12].hex(),
                    "tag": r["meta"][12:28].hex(),
                }
            elif r["kind"] == 3:
                start = r["auxStart"]
                for local in range(r["chunkCount"]):
                    a = aux[start + local]
                    f.seek(a["offset"])
                    prefix = f.read(16)
                    if len(prefix) != 16:
                        continue
                    key = prefix.hex()
                    if key in prefixes:
                        raise ValueError("Colisión de prefijo SPK fragmentado")
                    prefixes[key] = a["stored"]
                    details[key] = {
                        "kind": "chunk",
                        "ordinal": a["ordinal"],
                        "parentOrdinal": r["ordinal"],
                        "entryId": f'{r["entryId"]:016x}',
                        "entryInt": r["entryId"],
                        "localChunk": local,
                        "offset": a["offset"],
                        "stored": a["stored"],
                        "tag": a["tag"].hex(),
                    }
    return prefixes, details

def nonce_candidates(target: dict) -> dict[str, bytes]:
    out: dict[str, bytes] = {}
    entry = int(target["entryInt"])
    off = int(target["offset"])
    local = int(target["localChunk"])
    aux = int(target["ordinal"])
    parent = int(target["parentOrdinal"])
    stored = int(target["stored"])
    out["offset_le96"] = struct.pack("<QI", off, local)
    out["offset_aux_le96"] = struct.pack("<QI", off, aux)
    out["entry_id_chunk_le"] = struct.pack("<QI", entry, local)
    out["entry_id_aux_le"] = struct.pack("<QI", entry, aux)
    out["offset_chunk1_le96"] = struct.pack("<QI", off, local + 1)
    out["entry_id_chunk1_le"] = struct.pack("<QI", entry, local + 1)
    out["offset_stored_le96"] = struct.pack("<QI", off, stored & 0xffffffff)
    out["entry_id_stored_le"] = struct.pack("<QI", entry, stored & 0xffffffff)
    out["offset_be96"] = off.to_bytes(8, "big") + local.to_bytes(4, "big")
    out["entry_id_chunk_be"] = entry.to_bytes(8, "big") + local.to_bytes(4, "big")
    out["parent_local_aux_le"] = struct.pack("<III", parent & 0xffffffff, local, aux)
    return out

def validate_simple(spk: Path, records: list[dict], key: bytes, limit: int = 24) -> tuple[int, int]:
    ok = 0
    attempted = 0
    aes = AESGCM(key)
    with spk.open("rb") as f:
        for r in records:
            if r["kind"] != 1:
                continue
            attempted += 1
            f.seek(r["offset"])
            ct = f.read(r["stored"])
            try:
                aes.decrypt(r["meta"][:12], ct + r["meta"][12:28], None)
                ok += 1
            except Exception:
                pass
            if attempted >= limit:
                break
    return ok, attempted

def derive_chunk_rule(spk: Path, records: list[dict], aux: list[dict], key: bytes) -> tuple[str, dict]:
    samples: list[dict] = []
    for r in records:
        if r["kind"] != 3:
            continue
        start = r["auxStart"]
        for local in range(min(r["chunkCount"], 2)):
            a = aux[start + local]
            samples.append({
                "entryInt": r["entryId"],
                "parentOrdinal": r["ordinal"],
                "localChunk": local,
                "ordinal": a["ordinal"],
                "offset": a["offset"],
                "stored": a["stored"],
                "tag": a["tag"],
            })
        if len(samples) >= 20:
            break
    if not samples:
        return "unsupported", {"attempted": 0}

    scores: dict[str, int] = {}
    aes = AESGCM(key)
    with spk.open("rb") as f:
        for target in samples:
            f.seek(target["offset"])
            ct = f.read(target["stored"])
            for name, nonce in nonce_candidates(target).items():
                try:
                    aes.decrypt(nonce, ct + target["tag"], None)
                    scores[name] = scores.get(name, 0) + 1
                except Exception:
                    scores.setdefault(name, 0)
    winners = [name for name, score in scores.items() if score == len(samples)]
    if len(winners) == 1:
        return winners[0], {"attempted": len(samples), "scores": scores}
    return "unsupported", {"attempted": len(samples), "scores": scores, "winners": winners}

class Sink:
    def __init__(self, details: dict[str, dict]):
        self.details = details
        self.events: list[dict] = []
        self.profiles: list[dict] = []
        self.lock = threading.Lock()

    def accept(self, message, data):
        with self.lock:
            payload = message.get("payload") if isinstance(message, dict) else None
            if message.get("type") == "error":
                self.events.append({"code": "AGENT_ERROR", "message": str(message.get("description", ""))[:500]})
                return
            if message.get("type") != "send" or not isinstance(payload, dict):
                return
            if payload.get("kind") == "event":
                if len(self.events) < 200:
                    self.events.append(payload)
                return
            if payload.get("kind") != "resource-profile":
                return
            target = self.details.get(payload.get("prefix"))
            if target is None:
                return
            self.profiles.append({"target": target, **payload})
            print(f'RECURSO SPK: {target["kind"]} {target["entryId"]} ({target["stored"]} bytes)', flush=True)

def run_probe(client: Path, spk: Path, prefixes: dict[str, int], details: dict[str, dict], seconds: int) -> tuple[Sink, str | None]:
    agent_path = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent)) / "capture_resources.js"
    source = agent_path.read_text(encoding="utf-8").replace(
        "__CONFIG__", json.dumps({"resourcePrefixes": prefixes}, separators=(",", ":"))
    )
    sink = Sink(details)
    device = frida.get_local_device()
    session = script = None
    pid = None
    failure = None
    detached = threading.Event()
    try:
        pid = device.spawn([str(client)], cwd=str(client.parent))
        session = device.attach(pid)
        session.on("detached", lambda *args: detached.set())
        script = session.create_script(source)
        script.on("message", sink.accept)
        script.load()
        device.resume(pid)
        print("Cliente abierto. El aviso de servidor sin conexión es esperado; no introduzcas credenciales.", flush=True)
        detached.wait(seconds)
    except KeyboardInterrupt:
        pass
    except Exception as e:
        failure = str(e)
    finally:
        if script is not None:
            try:
                script.exports_sync.stop()
                script.unload()
            except Exception:
                pass
        if session is not None:
            try:
                session.detach()
            except Exception:
                pass
    return sink, failure

def choose_resource_key(spk: Path, records: list[dict], profiles: list[dict]) -> tuple[bytes | None, dict]:
    candidates: dict[str, bytes] = {}
    for p in profiles:
        info = p.get("keyInfo")
        if not isinstance(info, dict):
            continue
        secret = info.get("secretHex")
        if isinstance(secret, str) and len(secret) == 32:
            candidates[secret.lower()] = bytes.fromhex(secret)
    evidence = {"candidates": []}
    best = None
    best_ok = -1
    for secret_hex, key in candidates.items():
        ok, attempted = validate_simple(spk, records, key)
        evidence["candidates"].append({"secretSha256": sha(key), "simpleAuthenticated": ok, "attempted": attempted})
        if ok > best_ok:
            best_ok = ok
            best = key
    if best is None or best_ok < 4:
        return None, evidence
    evidence["selectedSimpleAuthenticated"] = best_ok
    return best, evidence

def write_profile(
    output: Path,
    original: dict,
    geometry: dict,
    index_key: bytes,
    resource_key: bytes,
    chunk_rule: str,
    probe_evidence: dict,
    chunk_evidence: dict,
) -> None:
    result = {
        "profileId": f'shaiya-spk-v3-auto-{geometry["indexSha256"][:8]}',
        "indexSha256": geometry["indexSha256"],
        "index": {"algorithm": "AES-GCM", "secretHex": index_key.hex()},
        "resources": {
            "algorithm": "AES-GCM",
            "secretHex": resource_key.hex(),
            "useIndexKey": resource_key == index_key,
            "simpleNonceRule": "record_metadata_nonce12_tag16",
            "chunkNonceRule": chunk_rule,
            "evidence": {
                "probe": probe_evidence,
                "chunkRule": chunk_evidence,
            },
        },
    }
    tmp = output.with_suffix(output.suffix + ".partial")
    tmp.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, output)

def main() -> int:
    ap = argparse.ArgumentParser(description="Aprende el perfil de recursos del DATA.SPK del cliente local.")
    ap.add_argument("--client", type=Path, required=True)
    ap.add_argument("--spk", type=Path, required=True)
    ap.add_argument("--profile", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--seconds", type=int, default=90)
    args = ap.parse_args()

    client = args.client.resolve()
    spk = args.spk.resolve()
    out = args.out.resolve()
    if not client.is_file() or not spk.is_file():
        raise ValueError("game.exe o data.spk no existen")
    if not 20 <= args.seconds <= 180:
        raise ValueError("Tiempo permitido: 20–180 segundos")

    profile_path, original, index_key = load_profile(spk, args.profile.resolve() if args.profile else None)
    expected_hash = str(original.get("indexSha256") or "").lower()
    print("Leyendo y validando índice SPK…", flush=True)
    geometry, records, aux = parse_spk(spk, index_key, expected_hash)
    print(f'Índice: {len(records):,} registros · {len(aux):,} fragmentos auxiliares.', flush=True)
    prefixes, details = target_map(spk, records, aux)
    print(f'Objetivos criptográficos exactos: {len(prefixes):,}.', flush=True)

    sink, failure = run_probe(client, spk, prefixes, details, args.seconds)
    if failure:
        print("Observación: " + failure, file=sys.stderr)
    resource_key, evidence = choose_resource_key(spk, records, sink.profiles)
    if resource_key is None:
        report = {
            "schema": 1,
            "status": "resource_key_not_validated",
            "profilesObserved": len(sink.profiles),
            "events": sink.events[-80:],
            "evidence": evidence,
        }
        out.with_suffix(".probe.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print("No se pudo validar todavía una clave común de recursos.", file=sys.stderr)
        return 4

    chunk_rule, chunk_evidence = derive_chunk_rule(spk, records, aux, resource_key)
    write_profile(out, original, geometry, index_key, resource_key, chunk_rule, evidence, chunk_evidence)
    report = {
        "schema": 1,
        "status": "complete" if chunk_rule != "unsupported" else "simple_resources_validated",
        "profile": str(out),
        "profilesObserved": len(sink.profiles),
        "resourceSecretSha256": sha(resource_key),
        "chunkNonceRule": chunk_rule,
        "events": sink.events[-80:],
        "evidence": evidence,
        "chunkEvidence": chunk_evidence,
    }
    out.with_suffix(".probe.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f'Perfil guardado: {out}', flush=True)
    print(f'Recursos simples validados; nonce fragmentado: {chunk_rule}.', flush=True)
    return 0 if chunk_rule != "unsupported" else 5

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print("DETENIDO:", e, file=sys.stderr)
        raise SystemExit(1)
