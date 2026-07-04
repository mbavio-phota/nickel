# Conductor Mobile — iOS MVP Implementation Plan

An iOS companion app for [Conductor](https://www.conductor.build) (Mac app for running
fleets of coding agents in cloud workspaces). The mobile app lets you monitor and manage
your Conductor projects, workspaces, and agent sessions from your phone: check what your
agents are doing, send them follow-up messages, cancel runaway turns, create new
workspaces, and archive finished ones.

## Product scope (MVP)

1. **Onboarding** — paste a Conductor API key (bearer token), validated with a live call,
   stored in Keychain. A "Explore with demo data" button enters a fully mocked demo mode.
2. **Projects list** — all projects (name + git remote), pull-to-refresh, pagination.
3. **Project detail** — the project's workspaces with live status badges
   (initializing / ready / sleeping / archived / updating), create-workspace button.
4. **Create workspace** — form: name (optional), branch (optional), agent picker
   (claude / codex / cursor / acp), model (optional free text). POSTs and navigates to it.
5. **Workspace detail** — status card that auto-polls, sessions list, rename, archive
   (with confirmation), copy/share deep link (opens Conductor on the Mac).
6. **Session detail (chat)** — message transcript (newest at bottom), composer to send a
   message to the agent, session status (idle / working / error) with polling while
   working, cancel button for in-flight turns, rename.
7. **Settings** — masked API key display, replace key, sign out (wipes Keychain), about.

Non-goals for MVP: push notifications, widgets, multi-account, creating projects
(API has no endpoint), opening deep links on-device (they target the desktop app —
we show copy/share instead).

## Tech choices

- **SwiftUI**, iOS 17 deployment target, Swift 5.10+ (Xcode 26.2, iphonesimulator26.2 SDK).
- **Observation framework** (`@Observable`) for view models — no Combine, no third-party deps.
- **async/await + URLSession** for networking. No external packages at all.
- **XcodeGen** (`project.yml`) generates the `.xcodeproj`; the pbxproj is never edited by hand.
  Regenerate with `xcodegen generate` after adding files.
- **Keychain** via a small `KeychainStore` wrapper (SecItem APIs) for the API key.
- Unit tests with XCTest for model decoding, request building, and error mapping.

Build command (must stay green after every phase):

```bash
cd /Users/mrbavio/dev/conductor-mobile && xcodegen generate && \
xcodebuild -project ConductorMobile.xcodeproj -scheme ConductorMobile \
  -sdk iphonesimulator26.2 -destination 'generic/platform=iOS Simulator' build
```

(Do not try to boot a simulator during phases 1–2; the runtime may still be downloading.
`-destination 'generic/platform=iOS Simulator'` compiles without needing a booted device.)

Tests (only once a runtime exists — otherwise compile-check the test target with `build-for-testing`):

```bash
xcodebuild -project ConductorMobile.xcodeproj -scheme ConductorMobile \
  -sdk iphonesimulator26.2 -destination 'generic/platform=iOS Simulator' build-for-testing
```

## Directory layout

```
/Users/mrbavio/dev/conductor-mobile
├── PLAN.md                      # this file
├── openapi.json                 # Conductor API spec snapshot
├── project.yml                  # XcodeGen manifest
├── ConductorMobile/             # app sources
│   ├── App/                     # @main, root routing, AppState, Theme
│   ├── API/                     # client protocol, live client, mock client, models, errors
│   ├── Support/                 # KeychainStore, helpers, formatters
│   └── Features/
│       ├── Onboarding/
│       ├── Projects/
│       ├── Workspaces/
│       ├── Sessions/
│       └── Settings/
└── ConductorMobileTests/
```

## Architecture

- `ConductorClient` **protocol** with every API operation; two conformances:
  - `LiveConductorClient(baseURL: URL = https://api.conductor.build, tokenProvider: () -> String?)`
  - `MockConductorClient` — in-memory seeded demo data (3 projects, ~6 workspaces in
    varied statuses, sessions with a realistic agent transcript; send-message appends and
    flips session to `working` for ~6s then back to `idle` with a canned agent reply, so
    the demo feels alive). Mock create/rename/archive mutate the in-memory store.
- `AppSession` (@Observable, app-wide): auth state
  (`unauthenticated | live(client) | demo(client)`), sign-in/out, keychain access.
  Injected via `.environment(...)`.
- Per-screen @Observable view models own loading state:
  `enum Loadable<T> { idle, loading, loaded(T), failed(ConductorError) }`.
- **Polling**: a small `PollingTask` helper — `.task`-scoped async loop with sleep
  interval, cancelled automatically when the view disappears. Workspace status polls
  every 5s while `initializing`/`updating`; session status + messages poll every 3s
  while `working`, 10s while idle-but-visible.
- **Errors**: decode `StructuredError` (`userMessage` is the display string; `retryable`
  drives a Retry button). 401 anywhere → surface "check your API key" state.
- **Pagination**: `offset`/`hasMore` — infinite scroll via `.onAppear` of last row.

## Condensed API reference (auth: `Authorization: Bearer <key>`, base `https://api.conductor.build`)

All list responses: `{ data: [...], offset: number, hasMore: bool }`.
Error body (any 4xx/5xx): `StructuredError { code?, userMessage!, debugMessage?, retryable?, source?, details?, stack?, underlying? }`.

| Op | Method & path | Notes |
|---|---|---|
| projects.list | GET `/v0/projects?limit&offset` | item: `{id, name, gitRemote}` |
| project.get | GET `/v0/projects/{projectId}` | `{id, name, gitRemote}` |
| project.workspaces.list | GET `/v0/projects/{projectId}/workspaces?limit&offset&channel` | item: `{id, name, createdAt, deepLink, creatorId?}` |
| workspace.create | POST `/v0/workspaces?channel` | body: `{projectId, branch?, name?, agent?, model?}` (or `repositoryUrl` instead of `projectId` — exactly one). agent ∈ claude\|codex\|cursor\|acp. → 201 `{workspaceId, sessionId, deepLink}` |
| workspace.get | GET `/v0/workspaces/{id}?channel` | `{id, name, createdAt, deepLink, creatorId?}` |
| workspace.rename | POST `/v0/workspaces/{id}/rename` | body `{name}` (minLength 1) → workspace |
| workspace.archive | POST `/v0/workspaces/{id}/archive` | idempotent → `{workspaceId, status:"archived"}` |
| workspace.status.get | GET `/v0/workspaces/{id}/status` | `{workspaceId, status, lifecycleStep?, updatedAt, errorMessage?}`; status ∈ initializing\|ready\|sleeping\|archived\|deleted\|updating; lifecycleStep ∈ building_snapshot\|preparing\|setting_up\|updating |
| workspace.sessions.list | GET `/v0/workspaces/{id}/sessions?limit&offset&channel` | item: `{id, deepLink, name?, model?}` |
| session.create | POST `/v0/sessions?channel` | body `{workspaceId, agent, sessionId?, name?, model?}` → 201 `{id, deepLink, name?, model?}` |
| session.get | GET `/v0/sessions/{id}?channel` | `{id, deepLink, name?, model?}` |
| session.rename | POST `/v0/sessions/{id}/rename` | body `{name}` → session |
| session.status.get | GET `/v0/sessions/{id}/status` | `{workspaceId, sessionId, status, updatedAt, errorMessage?}`; status ∈ idle\|working\|error |
| session.cancel | POST `/v0/sessions/{id}/cancel` | async cancel; → `{workspaceId, sessionId, status, canceledQueuedMessages}` |
| session.messages.list | GET `/v0/sessions/{id}/messages?limit&offset` | item: `{id, sessionId, sessionIndex, type, content(any JSON), receivedAt}` |
| message.create | POST `/v0/sessions/{id}/messages` | body `{message, messageId?}` → 201 `{messageId, state: queued\|sent}` |
| message.get | GET `/v0/messages/{id}` | message item |

Message `content` is **untyped JSON** (agent transcript events). Decode into a
`JSONValue` enum (string/number/bool/null/array/object) and render best-effort:
if `type == "user"` or content contains obvious text fields (`text`, `message`,
`content` string), show as chat bubbles; otherwise show a compact "event" row with the
`type` and a disclosure to view raw JSON. Do not assume a schema; never crash on
unknown shapes.

`deepLink` opens the **desktop** app (custom scheme) — on iOS render as
"Open on Mac" contextual action: copy to clipboard + share sheet, plus attempt
`UIApplication.open` as best-effort if the scheme is somehow registered.

`channel` query param: omit entirely in MVP (server default).

## Design direction

Native iOS, dark-mode-first but supporting both. Conductor is a developer tool — the app
should feel like a precise instrument: SF Pro + **SF Mono for identifiers** (branch
names, git remotes, models, IDs), generous whitespace, status conveyed with small
colored dots + labels, not loud banners.

- Accent: Conductor orange `#FF5C0A` (buttons, active states, the working spinner).
- Status colors: ready=green, initializing/updating=orange (animated pulse), sleeping=indigo,
  working=orange, idle=secondary, error=red, archived=gray.
- Lists: `insetGrouped`, rows with a leading status dot, title, monospaced subtitle.
- Session chat: user messages right-aligned filled bubbles (accent), agent/events
  left-aligned neutral; timestamp footers; "agent is working…" animated indicator row.
- Empty states: friendly icon + one-liner + primary action.
- Errors: inline `ContentUnavailableView` with Retry (uses `userMessage`).
- App icon: generated 1024pt PNG — orange rounded background, white conductor
  baton/waveform glyph (asset catalog single-size).

## Phases

**Phase 1 — scaffold + core (sub-agent, sonnet)**
project.yml (app + test targets, iOS 17, bundle id `dev.mrbavio.conductor-mobile`,
`GENERATE_INFOPLIST_FILE=YES` with the needed INFOPLIST_KEY_* settings), app entry,
Theme, KeychainStore, JSONValue, all Codable models, ConductorError, ConductorClient
protocol, LiveConductorClient (request building, decoding, error mapping),
MockConductorClient (seeded demo world per above), AppSession, Loadable, PollingTask.
Unit tests: model decoding fixtures (embed JSON strings), live-client request building
(URLProtocol stub), error mapping, mock-client behaviors. Build + build-for-testing green.

**Phase 2 — UI (sub-agent, sonnet)**
All screens listed in Product scope, wired to `ConductorClient` via AppSession; SwiftUI
previews using MockConductorClient; navigation via NavigationStack; the app must be fully
usable in demo mode. Build green.

**Phase 3 — review + polish (orchestrator)**
Code review of both phases; design pass; fix polling/pagination/error handling; run tests.

**Phase 4 — simulator verification (orchestrator)**
Boot simulator, install, walk every flow in demo mode, screenshots.
