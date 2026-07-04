#!/usr/bin/env python3
"""Stress the Conductor API transport: error shapes, pagination semantics, live chat
edge cases, and the full workspace lifecycle. Every request/response pair is persisted
under dumps/stress/ as numbered JSON records for later analysis.

Stages (run individually or all):
    python3 tools/transport-probe/stress.py errors      # A: every failure shape (no side effects beyond one rejected POST)
    python3 tools/transport-probe/stress.py pagination SESSION_ID
    python3 tools/transport-probe/stress.py chat SESSION_ID   # C: sends real (cheap) messages — costs money
    python3 tools/transport-probe/stress.py workspace PROJECT_ID  # D: creates, renames, archives a probe workspace

The chat stage exercises: send without messageId, queued-state (second send while
working), cancel mid-turn, and a markdown-heavy reply.
"""

import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

BASE = "https://api.conductor.build"
REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
STRESS_DIR = pathlib.Path(__file__).resolve().parent / "dumps" / "stress"
COUNTER = {"n": 0}


def api_key() -> str:
    key_file = REPO_ROOT / ".conductor-api-key"
    if key_file.exists():
        return key_file.read_text().strip()
    import os

    if key := os.environ.get("CONDUCTOR_API_KEY"):
        return key.strip()
    sys.exit(f"No API key: create {key_file} or set CONDUCTOR_API_KEY.")


def call(label: str, method: str, path: str, body=None, params=None, token=None, expect_error=False):
    """Perform a request and persist {request, status, response} as a numbered record."""
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token if token is not None else api_key()}",
            "User-Agent": "nickel-transport-probe/1.0",
            "Accept": "application/json",
            **({"Content-Type": "application/json"} if data else {}),
        },
    )
    status, payload = None, None
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            status = response.status
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        status = error.code
        raw = error.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"_nonJsonBody": raw}
    except urllib.error.URLError as error:
        status = -1
        payload = {"_transportError": str(error)}

    COUNTER["n"] += 1
    record = {
        "label": label,
        "request": {"method": method, "path": path, "params": params, "body": body},
        "status": status,
        "response": payload,
    }
    STRESS_DIR.mkdir(parents=True, exist_ok=True)
    (STRESS_DIR / f"{COUNTER['n']:03d}-{label}.json").write_text(
        json.dumps(record, indent=2, ensure_ascii=False)
    )
    marker = "OK " if (status and 200 <= status < 300) != expect_error else "?! "
    print(f"  {marker}{COUNTER['n']:03d} {label}: {method} {path} -> {status}")
    return status, payload


def stage_errors():
    """A: catalogue every failure shape the app's ConductorError must map."""
    print("== Stage A: error shapes")
    call("404-session-status", "GET", "/v0/sessions/00000000-0000-0000-0000-000000000000/status", expect_error=True)
    call("404-project", "GET", "/v0/projects/00000000-0000-0000-0000-000000000000", expect_error=True)
    call("404-message", "GET", "/v0/messages/00000000-0000-0000-0000-000000000000", expect_error=True)
    call("401-bad-key", "GET", "/v0/projects", token="cond_invalid_key", expect_error=True)
    call("400-empty-rename", "POST", "/v0/sessions/00000000-0000-0000-0000-000000000000/rename", body={"name": ""}, expect_error=True)
    call("400-bad-body-create-ws", "POST", "/v0/workspaces", body={"projectId": "x", "repositoryUrl": "https://example.com"}, expect_error=True)
    call("400-session-create-sidecar", "POST", "/v0/sessions", body={"workspaceId": "be4d002c-1910-4299-baec-5f0fbbda2f0e", "agent": "claude"}, expect_error=True)
    call("400-unknown-agent", "POST", "/v0/sessions", body={"workspaceId": "be4d002c-1910-4299-baec-5f0fbbda2f0e", "agent": "not_an_agent"}, expect_error=True)
    call("400-bad-pagination", "GET", "/v0/projects", params={"limit": 0}, expect_error=True)


def stage_pagination(session_id: str):
    """B: ordering and offset semantics on a long transcript."""
    print("== Stage B: pagination semantics")
    _, full = call("page-full", "GET", f"/v0/sessions/{session_id}/messages", params={"limit": 100})
    _, first = call("page-first10", "GET", f"/v0/sessions/{session_id}/messages", params={"limit": 10, "offset": 0})
    _, second = call("page-second10", "GET", f"/v0/sessions/{session_id}/messages", params={"limit": 10, "offset": 10})
    _, again = call("page-first10-again", "GET", f"/v0/sessions/{session_id}/messages", params={"limit": 10, "offset": 0})

    full_ids = [m["id"] for m in full["data"]]
    paged_ids = [m["id"] for m in first["data"]] + [m["id"] for m in second["data"]]
    print(f"    ordering stable across calls: {[m['id'] for m in first['data']] == [m['id'] for m in again['data']]}")
    print(f"    offset slices match full fetch: {full_ids[:20] == paged_ids}")
    indexes = [m["sessionIndex"] for m in full["data"]]
    print(f"    sessionIndex sorted oldest-first: {indexes == sorted(indexes)}")
    print(f"    hasMore on first page: {first['hasMore']} (total {len(full_ids)})")


def wait_status(session_id: str, want: str, timeout: float = 90) -> str:
    deadline = time.time() + timeout
    status = "?"
    while time.time() < deadline:
        _, payload = call(f"poll-status-{want}", "GET", f"/v0/sessions/{session_id}/status")
        status = payload.get("status", "?")
        if status == want:
            return status
        time.sleep(3)
    return status


def stage_chat(session_id: str):
    """C: live conversation edge cases. Sends real messages — costs money."""
    print("== Stage C: live chat battery")

    print("  C1: send WITHOUT client messageId")
    call("send-no-id", "POST", f"/v0/sessions/{session_id}/messages",
         body={"message": "Reply with just: ACK1"})

    print("  C2: send a second message immediately (expect state=queued)")
    call("send-while-working", "POST", f"/v0/sessions/{session_id}/messages",
         body={"message": "Reply with just: ACK2", "messageId": f"probe-queued-{uuid.uuid4()}"})

    wait_status(session_id, "idle", timeout=180)
    call("transcript-after-queue", "GET", f"/v0/sessions/{session_id}/messages", params={"limit": 100})

    print("  C3: cancel mid-turn (send long task, cancel while working)")
    call("send-then-cancel", "POST", f"/v0/sessions/{session_id}/messages",
         body={"message": "Count slowly from 1 to 50, one number per line, thinking carefully about each."})
    wait_status(session_id, "working", timeout=60)
    call("queue-behind-cancel", "POST", f"/v0/sessions/{session_id}/messages",
         body={"message": "This should get dropped by the cancel."})
    call("cancel", "POST", f"/v0/sessions/{session_id}/cancel")
    wait_status(session_id, "idle", timeout=120)
    call("transcript-after-cancel", "GET", f"/v0/sessions/{session_id}/messages", params={"limit": 100})

    print("  C4: markdown-heavy reply")
    call("send-markdown", "POST", f"/v0/sessions/{session_id}/messages",
         body={"message": "Show a tiny markdown demo: a heading, a 2-item bullet list, a one-line python code block, and a table with 2 rows. Keep it minimal."})
    wait_status(session_id, "idle", timeout=180)
    call("transcript-final", "GET", f"/v0/sessions/{session_id}/messages", params={"limit": 100})


def stage_workspace(project_id: str):
    """D: full workspace lifecycle with status-transition capture."""
    print("== Stage D: workspace lifecycle")
    status, created = call("ws-create", "POST", "/v0/workspaces",
                           body={"projectId": project_id, "name": "nickel-probe", "agent": "claude", "model": "sonnet"})
    if status != 201:
        print("    create failed; aborting stage")
        return
    workspace_id = created["workspaceId"]
    print(f"    created {workspace_id} with initial session {created['sessionId']}")

    seen = []
    deadline = time.time() + 600
    while time.time() < deadline:
        _, payload = call("ws-status-poll", "GET", f"/v0/workspaces/{workspace_id}/status")
        snapshot = (payload.get("status"), payload.get("lifecycleStep"))
        if not seen or seen[-1] != snapshot:
            seen.append(snapshot)
            print(f"    status transition: {snapshot}")
        if payload.get("status") in ("ready", "deleted"):
            break
        time.sleep(5)

    call("ws-rename", "POST", f"/v0/workspaces/{workspace_id}/rename", body={"name": "nickel-probe-renamed"})
    call("ws-get-after-rename", "GET", f"/v0/workspaces/{workspace_id}")
    call("ws-sessions", "GET", f"/v0/workspaces/{workspace_id}/sessions")
    call("ws-archive", "POST", f"/v0/workspaces/{workspace_id}/archive")
    call("ws-archive-again-idempotent", "POST", f"/v0/workspaces/{workspace_id}/archive")
    call("ws-status-after-archive", "GET", f"/v0/workspaces/{workspace_id}/status")
    call("send-to-archived", "POST", f"/v0/sessions/{created['sessionId']}/messages",
         body={"message": "should fail: archived"}, expect_error=True)


if __name__ == "__main__":
    stage = sys.argv[1] if len(sys.argv) > 1 else "errors"
    if stage == "errors":
        stage_errors()
    elif stage == "pagination":
        stage_pagination(sys.argv[2])
    elif stage == "chat":
        stage_chat(sys.argv[2])
    elif stage == "workspace":
        stage_workspace(sys.argv[2])
    else:
        sys.exit(f"unknown stage {stage}")
