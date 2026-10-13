#!/usr/bin/env python3
"""Private local Savoria backend client. No UI automation or direct database writes."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import unicodedata
import urllib.parse
import urllib.request
import uuid
import time

ROOT = Path.home() / "Library/Application Support/SmartKitchen/Agent"
PROJECTS = {"pantry": "EkM2RWfGfqwi9UWk6cTr3r", "reserve": "XvLVUvoV8SQDtG5xjsrFso", "grocery": "UCATLPsfbWV4ZMQQ2AKTrb"}


def rpc(method, **payload):
    request = {"requestID": str(uuid.uuid4()), "method": method, **payload}
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(90)
        try:
            client.connect(str(ROOT / "backend.sock"))
        except (FileNotFoundError, ConnectionRefusedError):
            if method == "shutdown":
                raise
            # Connect-only retry: never resend a mutation whose result is uncertain.
            subprocess.run(["open", "-g", "-a", "/Applications/Savoria.app", "--args", "--agent-service"], check=True)
            deadline = time.monotonic() + 20
            while True:
                try:
                    client.connect(str(ROOT / "backend.sock"))
                    break
                except (FileNotFoundError, ConnectionRefusedError):
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Headless backend did not become ready; no request was sent")
                    time.sleep(.2)
        client.sendall(json.dumps(request, ensure_ascii=False, allow_nan=False).encode() + b"\n")
        chunks = bytearray()
        while b"\n" not in chunks:
            part = client.recv(65536)
            if not part:
                raise RuntimeError("Backend closed without receipt; inspect snapshot before retry")
            chunks.extend(part)
            if len(chunks) > 16 * 1024 * 1024:
                raise RuntimeError("Response exceeds safety limit")
    response = json.loads(chunks.split(b"\n", 1)[0])
    if not response.get("ok"):
        raise RuntimeError(f"{response.get('status')}: {response.get('error')}")
    return response["result"]


def things_get(path):
    base = "http://127.0.0.1:8765"
    request = urllib.request.Request(base + path, headers={"Origin": base})
    with urllib.request.urlopen(request, timeout=30) as response:
        value = json.load(response)
    if value.get("ok") is not True:
        raise RuntimeError("Things API did not confirm read")
    return value


def export_things():
    source = {}
    for kind, project_id in PROJECTS.items():
        project = things_get("/api/items?id=" + project_id)
        if project.get("kind") != "project":
            raise RuntimeError("Source must be the named Things project")
        if project.get("order_synced") is not True:
            raise RuntimeError("Things native order was not confirmed; refusing approximate ordering")
        ids = [x["uuid"] for x in project.get("items", []) if x.get("type") == "to-do"]
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            details = list(pool.map(lambda item_id: things_get("/api/item?id=" + item_id)["item"], ids))
        if any(x.get("status") != "incomplete" or x.get("trashed") for x in details):
            raise RuntimeError("Things changed while reading; take a fresh snapshot")
        project["details"] = details
        source[kind] = project
    return source


def name_key(name):
    plain = unicodedata.normalize("NFKD", name.casefold())
    return "".join(x for x in plain if x.isalnum())


def strip_title_icons(name):
    """Remove pictographs from item text while preserving accents, numbers and punctuation."""
    return "".join(c for c in name if not (unicodedata.category(c) == "So" and
                   (0x1F000 <= ord(c) <= 0x1FAFF or 0x2300 <= ord(c) <= 0x27BF))
                   and c not in "\ufe0e\ufe0f\u200d\u20e3"
                   and not (0x1F3FB <= ord(c) <= 0x1F3FF or 0xE0020 <= ord(c) <= 0xE007F)).strip()


def managed_id(source_id):
    """UUIDv8 with a reserved prefix and source hash: stable independent identity."""
    raw = bytearray(b"\x5a\x76\x0a\x1a" + hashlib.sha256(("things:" + source_id).encode()).digest()[:12])
    raw[6] = (raw[6] & 15) | 0x80
    raw[8] = (raw[8] & 63) | 0x80
    return str(uuid.UUID(bytes=bytes(raw)))


def manifest_from_things(source, snapshot, keep_duplicates=True, strip_icons=False):
    existing = snapshot["items"]
    by_id = {x["id"].lower(): x for x in existing}
    used = set()
    entries = []
    categories = []
    aliases = {"paofrances": "pao", "leiteintegral": "leite", "ovos": "ovo", "macarraofettuccine": "macarrao"}
    seen = set()
    for kind in PROJECTS:
        project = source[kind]
        for heading in project.get("headings", []):
            if heading["title"] not in categories:
                categories.append(heading["title"])
        for order, item in enumerate(project["details"]):
            identity = (kind, item["title"], item.get("notes") or "", item.get("heading_title") or "Outros")
            if not keep_duplicates and identity in seen:
                continue
            seen.add(identity)
            target_id = managed_id(item["uuid"])
            candidate = by_id.get(target_id)
            if candidate is None:
                key = name_key(item["title"])
                keys = {key, aliases.get(key, key)}
                candidates = [x for x in existing if x["id"].lower() not in used and name_key(x["name"]) in keys]
                # The same food can have independent pantry/reserve records after titles lose emoji.
                same_list = [x for x in candidates if kind in x.get("lists", [])]
                if len(same_list) == 1:
                    candidates = same_list
                # A unique previous identity retains photos/expiry/links. Ambiguous matches stay archived.
                if len(candidates) == 1:
                    candidate = candidates[0]
                    target_id = candidate["id"]
            if target_id.lower() in used:
                raise RuntimeError("Source identity collision")
            used.add(target_id.lower())
            notes = item.get("notes") or ""
            checklist = item.get("checklist") or []
            if checklist:
                rendered = "\n".join(f"- [{'x' if x.get('status') == 'completed' else ' '}] {x['title']}" for x in checklist)
                notes += ("\n\n" if notes else "") + rendered
            entries.append({"id": target_id, "name": strip_title_icons(item["title"]) if strip_icons else item["title"], "notes": notes,
                            "category": item.get("heading_title") or "Outros",
                            "quantity": None, "unit": None, "iconName": candidate.get("iconName") if candidate else None,
                            "isChecked": False, "lists": [kind], "orders": {kind: order},
                            "thingsID": item["uuid"], "thingsTags": item.get("tags") or [], "thingsChecklist": checklist})
    return {"mode": "replaceLists", "source": "Things: Cozinha/Despensa, Backlog, Mercado", "items": entries,
            "categories": categories, "showReserve": True, "grouping": {"pantry": "category", "grocery": "category"}}


def write_private(path, value):
    path = Path(path)
    with open(path, "x", encoding="utf-8", opener=lambda filename, flags: os.open(filename, flags, 0o600)) as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
    os.chmod(path, 0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ["health", "snapshot", "backup", "shutdown", "start", "self-test"]:
        sub.add_parser(name)
    plan = sub.add_parser("plan")
    plan.add_argument("manifest")
    plan.add_argument("--revision")
    plan.add_argument("--request-id")
    apply = sub.add_parser("apply")
    apply.add_argument("plan_id")
    apply.add_argument("--revision", required=True)
    apply.add_argument("--request-id", required=True)
    raw = sub.add_parser("request")
    raw.add_argument("file")
    source = sub.add_parser("from-things")
    source.add_argument("--output", required=True)
    source.add_argument("--deduplicate", action="store_true")
    source.add_argument("--strip-title-icons", action="store_true", help="Remove emoji/pictographs from titles, preserving descriptions")
    source.add_argument("--source-file", help="Use an already captured Things source snapshot")
    vault = sub.add_parser("from-vault", help="Capture local recipe notes and build an additive reviewed manifest")
    vault.add_argument("--output", required=True)
    vault.add_argument("--vault", default="/Volumes/PS-Externo/PS Vault")
    vault.add_argument("--snapshot-file")
    args = parser.parse_args()
    if args.command == "start":
        subprocess.run(["open", "-g", "-a", "/Applications/Savoria.app", "--args", "--agent-service"], check=True)
        print("Backend start requested; confirm with health.")
        return
    if args.command == "from-vault":
        from savoria_vault import manifest_from_vault
        snapshot = json.loads(Path(args.snapshot_file).read_text()) if args.snapshot_file else rpc("snapshot")
        manifest, capture = manifest_from_vault(Path(args.vault), snapshot)
        write_private(args.output, manifest)
        write_private(str(args.output) + ".source.json", capture)
        print(json.dumps({"manifest": str(Path(args.output).absolute()), "revision": snapshot["revision"], "recipes": len(manifest["recipes"]), "covers": sum("coverPath" in x for x in manifest["recipes"]), "warnings": capture["warnings"]}, ensure_ascii=False, indent=2))
        return
    if args.command in ["health", "snapshot", "backup", "shutdown", "self-test"]:
        result = rpc(args.command)
    elif args.command == "plan":
        payload = {"manifest": json.loads(Path(args.manifest).read_text()),
                   "expectedRevision": args.revision or rpc("snapshot")["revision"]}
        if args.request_id:
            payload["requestID"] = args.request_id
        result = rpc("plan", **payload)
    elif args.command == "apply":
        result = rpc("apply", planID=args.plan_id, expectedRevision=args.revision, requestID=args.request_id)
    elif args.command == "request":
        payload = json.loads(Path(args.file).read_text())
        result = rpc(payload.pop("method"), **payload)
    else:
        source = json.loads(Path(args.source_file).read_text()) if args.source_file else export_things()
        snapshot = rpc("snapshot")
        manifest = manifest_from_things(source, snapshot, keep_duplicates=not args.deduplicate, strip_icons=args.strip_title_icons)
        write_private(args.output, manifest)
        write_private(str(args.output) + ".source.json", source)
        result = {"manifest": str(Path(args.output).absolute()), "revision": snapshot["revision"],
                  "counts": {kind: sum(kind in x["lists"] for x in manifest["items"]) for kind in PROJECTS}}
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
