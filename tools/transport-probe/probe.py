#!/usr/bin/env python3
"""Dump real Conductor API transcripts for transport-format analysis.

Reads the API key from the file `.conductor-api-key` at the repo root (gitignored) or
the CONDUCTOR_API_KEY environment variable. Read-only: only GET endpoints are called.

Usage:
    python3 tools/transport-probe/probe.py            # dump everything reachable
    python3 tools/transport-probe/probe.py --analyze  # also print an event-shape census

Output lands in tools/transport-probe/dumps/ (gitignored):
    projects.json, workspaces-<projectId>.json, sessions-<workspaceId>.json,
    messages-<sessionId>.json — raw API responses, pretty-printed.
"""

import argparse
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://api.conductor.build"
REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DUMPS = pathlib.Path(__file__).resolve().parent / "dumps"


def api_key() -> str:
    key_file = REPO_ROOT / ".conductor-api-key"
    if key_file.exists():
        return key_file.read_text().strip()
    import os

    if key := os.environ.get("CONDUCTOR_API_KEY"):
        return key.strip()
    sys.exit(f"No API key: create {key_file} or set CONDUCTOR_API_KEY.")


def get(path: str, params: dict | None = None) -> dict:
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    # Cloudflare rejects urllib's default Python-urllib UA with a 1010 signature ban.
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {api_key()}",
            "User-Agent": "nickel-transport-probe/1.0 (+https://github.com/mbavio-phota/nickel)",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        sys.exit(f"GET {path} -> {error.code}: {body}")


def get_all_pages(path: str) -> list:
    items, offset = [], 0
    while True:
        page = get(path, {"limit": 100, "offset": offset})
        items.extend(page["data"])
        if not page["hasMore"]:
            return items
        offset = len(items)


def dump(name: str, payload) -> None:
    DUMPS.mkdir(exist_ok=True)
    (DUMPS / f"{name}.json").write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    size = len(payload) if isinstance(payload, list) else 1
    print(f"  wrote dumps/{name}.json ({size} items)")


def shape_signature(value, depth=0) -> str:
    """Compact structural fingerprint of a JSON value, for the census."""
    if depth > 4:
        return "…"
    if isinstance(value, dict):
        keys = sorted(value.keys())
        return "{" + ",".join(keys[:8]) + ("…" if len(keys) > 8 else "") + "}"
    if isinstance(value, list):
        return f"[{shape_signature(value[0], depth + 1) if value else ''}×{len(value)}]"
    return type(value).__name__


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--analyze", action="store_true", help="print an event-shape census")
    args = parser.parse_args()

    projects = get_all_pages("/v0/projects")
    dump("projects", projects)

    all_messages = []
    index = []
    for project in projects:
        workspaces = get_all_pages(f"/v0/projects/{project['id']}/workspaces")
        dump(f"workspaces-{project['id']}", workspaces)
        for workspace in workspaces:
            sessions = get_all_pages(f"/v0/workspaces/{workspace['id']}/sessions")
            dump(f"sessions-{workspace['id']}", sessions)
            for session in sessions:
                messages = get_all_pages(f"/v0/sessions/{session['id']}/messages")
                dump(f"messages-{session['id']}", messages)
                all_messages.extend(messages)
                index.append({
                    "sessionId": session["id"],
                    "sessionName": session.get("name"),
                    "project": project["name"],
                    "workspace": workspace["name"],
                    "messageCount": len(messages),
                })

    dump("index", index)
    print(f"\nTotal messages dumped: {len(all_messages)}")

    if args.analyze:
        census: dict[str, int] = {}
        for message in all_messages:
            content = message.get("content")
            raw = content.get("rawPayload", {}) if isinstance(content, dict) else {}
            kind = (
                f"type={message.get('type')} rawType={raw.get('type')} "
                f"subtype={raw.get('subtype')} shape={shape_signature(content)}"
            )
            census[kind] = census.get(kind, 0) + 1
        print("\nEvent-shape census (count · signature):")
        for kind, count in sorted(census.items(), key=lambda pair: -pair[1]):
            print(f"  {count:4d} · {kind}")


if __name__ == "__main__":
    main()
