# Conductor transport schema — observed behavior

Everything below was captured from the live API (2026-07-04) via `probe.py` / `stress.py`
against a real account. The OpenAPI spec types message `content` as untyped JSON; this
document is the actual contract the Nickel renderer is built against. Re-run
`probe.py --analyze` after Conductor updates to diff the census.

## Transcript message envelope

`GET /v0/sessions/{id}/messages` items:

```
{ id, sessionId, sessionIndex, type, content, receivedAt }
```

- `id` — transcript-event id, `<sessionId>:<turn>:<n>`. NOT the client messageId.
- `sessionIndex` — monotonically increasing but **with gaps**. Sort by it for display.
- `type` — `"userMessage"` (human) or `"agent"` (every SDK event).
- `receivedAt` — **Postgres-style** timestamp `2026-07-04 14:27:40.002976+00`
  (micro/milli/no-fraction variants all observed). Not ISO 8601.

## Human messages (`type: "userMessage"`)

```
content = { eventId, type: "userMessage", senderId, id, message, state, turnId, config? , resume? }
```

- `content.id` **is the client-supplied `messageId`** from `POST .../messages` — this is
  the only place the echo carries it (dedup key for optimistic sends).
- `content.message` — plain string.
- `content.state` — `"sent"` observed; `"queued"` exists in the create-response enum but
  two rapid sends both returned `sent` and were **batched into a single agent turn**.
- `config` — `{collaborationMode, model, thinkingLevel}` (session settings snapshot).

## Agent events (`type: "agent"`)

```
content = { eventId, rawPayload, turnId, type: "agent", userMessageId }
```

`rawPayload` is a Claude Code SDK event. Observed taxonomy:

| rawPayload.type | subtype | meaning | render |
|---|---|---|---|
| `assistant` | — | agent turn; `message.content` = typed blocks (`text`, `tool_use`, `thinking`) | bubble if it has text blocks and is un-parented |
| `user` | — | tool results (`message.content[].type == tool_result`), role "user" — NOT the human | chip |
| `system` | `init` | session boot (tools, skills, model, cwd…) | chip |
| `system` | `task_started/progress/updated/notification` | Task (sub-agent) lifecycle; `description`/`summary` fields | chip + detail |
| `system` | `thinking_tokens` | streaming thinking-token estimates | chip |
| `result` | `success` | turn summary: `result` (duplicate of final text), `total_cost_usd`, `duration_ms`, `usage` | chip + cost/duration |

**Sub-agent multiplexing:** Task turns are interleaved into the same transcript as
ordinary `user`/`assistant` events distinguished ONLY by a non-null
`rawPayload.parent_tool_use_id` — including the task prompt as a user-role *text* event.
Never render parented events as prose (they read as the agent/user speaking).

**Provider errors surface as normal turns:** a 429 from Anthropic arrives as assistant
text ("API Error: Request rejected (429)…") followed by `result · success`.

## Send / cancel semantics

- `POST .../messages` without `messageId` → server generates a UUID for `messageId`.
- Response `state` is `sent` even when the agent is mid-turn; rapid sends may be batched
  into one turn that answers both.
- `POST .../cancel` is **async**: the response can still say `status: "working"`
  (`canceledQueuedMessages` may be 0); poll status until `idle`. No special transcript
  event marks the cancellation.

## Pagination guarantees (verified)

Ordering is stable across calls, oldest-first, `offset` slices are consistent with a
full fetch, `sessionIndex` sorted ascending. Incremental fetch from
`offset = messages already held` is safe (append-only).

## Workspace lifecycle (verified)

`POST /v0/workspaces {projectId, name?, agent?, model?}` → 201
`{workspaceId, sessionId, deepLink}` — **the initial session is created here**; status
transitions observed: `initializing/preparing` → `ready` (seconds). Archive is
idempotent; sends to sessions of archived workspaces → 400 `WORKSPACE_NOT_READY`.

## Error body catalogue (all decode as `StructuredError`)

| case | status | code | userMessage |
|---|---|---|---|
| unknown ids | 404 | `NOT_FOUND` | "Session not found" etc. |
| bad key | 401 | `UNAUTHORIZED` | "Unauthorized client request" |
| schema violations | 400 | `FST_ERR_VALIDATION` | readable ("body/name must NOT have fewer than 1 characters") |
| archived workspace | 400 | `WORKSPACE_NOT_READY` | "Workspace not ready (state: archived)" |
| sidecar rejection | 400 | `INVALID_REQUEST` | flat "Invalid request"; details in `underlying[]` (Zod dump) |

## ⚠ Upstream bug: `POST /v0/sessions` is unusable (2026-07-04)

Every schema-conforming body fails. The public schema (`additionalProperties: false`)
accepts only `{workspaceId, agent, sessionId?, name?, model?}`, but the sidecar's Zod
validation requires `config.collaborationMode`, `config.model`, `config.thinkingLevel`.
Top-level `model` maps into `config.model`, the other two have no top-level source and no
defaults, and a `config` object sent by the client is stripped by the API layer before
the sidecar sees it. Repro:

```bash
curl -s -X POST -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"workspaceId": "<ready-ws>", "agent": "claude", "model": "sonnet"}' \
  https://api.conductor.build/v0/sessions
# → 400 INVALID_REQUEST, underlying ZodError paths: config.collaborationMode, config.thinkingLevel
```

Until fixed, sessions can only be created via `workspace.create`. Worth reporting to the
Conductor team.
