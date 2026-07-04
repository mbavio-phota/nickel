import Foundation

/// In-memory `ConductorClient` conformance seeded with a small, realistic demo world.
/// Used for "Explore with demo data" mode and SwiftUI previews. All mutations
/// (create/rename/archive/cancel/send) operate on in-memory state only.
actor MockConductorClient: ConductorClient {
    /// How long `sendMessage` waits before appending the canned agent reply. Overridable
    /// so tests don't have to wait out the real (demo-realistic) delay.
    private let replyDelay: Duration

    private var projects: [Project]
    private var workspacesByProject: [String: [Workspace]]
    private var workspaceStatuses: [String: WorkspaceStatus]
    private var sessionsByWorkspace: [String: [Session]]
    private var sessionStatuses: [String: SessionStatus]
    private var sessionWorkspaceIds: [String: String]
    private var messagesBySession: [String: [TranscriptMessage]]
    private var nextId = 1000

    init(replyDelay: Duration = .seconds(6)) {
        self.replyDelay = replyDelay

        let seed = MockConductorClient.makeSeedData()
        self.projects = seed.projects
        self.workspacesByProject = seed.workspacesByProject
        self.workspaceStatuses = seed.workspaceStatuses
        self.sessionsByWorkspace = seed.sessionsByWorkspace
        self.sessionStatuses = seed.sessionStatuses
        self.sessionWorkspaceIds = seed.sessionWorkspaceIds
        self.messagesBySession = seed.messagesBySession
    }

    // MARK: - Projects

    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project> {
        paginate(projects, limit: limit, offset: offset)
    }

    func getProject(id: String) async throws -> Project {
        guard let project = projects.first(where: { $0.id == id }) else {
            throw notFound("Project \(id) not found.")
        }
        return project
    }

    // MARK: - Workspaces

    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> {
        paginate(workspacesByProject[projectId] ?? [], limit: limit, offset: offset)
    }

    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse {
        guard let projectId = request.projectId else {
            throw badRequest("Demo mode only supports creating workspaces from an existing project.")
        }
        let workspaceId = freshId(prefix: "ws")
        let sessionId = freshId(prefix: "sess")

        let workspace = Workspace(
            id: workspaceId,
            name: request.name ?? "New workspace",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            deepLink: "conductor://workspace/\(workspaceId)",
            creatorId: "demo-user"
        )
        workspacesByProject[projectId, default: []].insert(workspace, at: 0)
        workspaceStatuses[workspaceId] = WorkspaceStatus(
            workspaceId: workspaceId,
            status: .initializing,
            lifecycleStep: .preparing,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            errorMessage: nil
        )

        let session = Session(
            id: sessionId,
            deepLink: "conductor://session/\(sessionId)",
            name: request.name ?? "Session 1",
            model: request.model
        )
        sessionsByWorkspace[workspaceId] = [session]
        sessionWorkspaceIds[sessionId] = workspaceId
        sessionStatuses[sessionId] = SessionStatus(
            workspaceId: workspaceId,
            sessionId: sessionId,
            status: .idle,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            errorMessage: nil
        )
        messagesBySession[sessionId] = []

        // Demo workspaces "finish initializing" shortly after creation so the status
        // card visibly progresses, matching how a real workspace behaves.
        Task.detached { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.markWorkspaceReady(workspaceId)
        }

        return WorkspaceCreateResponse(workspaceId: workspaceId, sessionId: sessionId, deepLink: workspace.deepLink)
    }

    func getWorkspace(id: String) async throws -> Workspace {
        guard let workspace = allWorkspaces().first(where: { $0.id == id }) else {
            throw notFound("Workspace \(id) not found.")
        }
        return workspace
    }

    func renameWorkspace(id: String, name: String) async throws -> Workspace {
        for (projectId, workspaces) in workspacesByProject {
            if let index = workspaces.firstIndex(where: { $0.id == id }) {
                let existing = workspaces[index]
                let renamed = Workspace(
                    id: existing.id,
                    name: name,
                    createdAt: existing.createdAt,
                    deepLink: existing.deepLink,
                    creatorId: existing.creatorId
                )
                workspacesByProject[projectId]?[index] = renamed
                return renamed
            }
        }
        throw notFound("Workspace \(id) not found.")
    }

    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse {
        guard workspaceStatuses[id] != nil else {
            throw notFound("Workspace \(id) not found.")
        }
        workspaceStatuses[id] = WorkspaceStatus(
            workspaceId: id,
            status: .archived,
            lifecycleStep: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            errorMessage: nil
        )
        return WorkspaceArchiveResponse(workspaceId: id, status: "archived")
    }

    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus {
        guard let status = workspaceStatuses[id] else {
            throw notFound("Workspace \(id) not found.")
        }
        return status
    }

    // MARK: - Sessions

    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> {
        paginate(sessionsByWorkspace[workspaceId] ?? [], limit: limit, offset: offset)
    }

    func createSession(_ request: CreateSessionRequest) async throws -> Session {
        let sessionId = request.sessionId ?? freshId(prefix: "sess")
        let session = Session(
            id: sessionId,
            deepLink: "conductor://session/\(sessionId)",
            name: request.name,
            model: request.model
        )
        sessionsByWorkspace[request.workspaceId, default: []].append(session)
        sessionWorkspaceIds[sessionId] = request.workspaceId
        sessionStatuses[sessionId] = SessionStatus(
            workspaceId: request.workspaceId,
            sessionId: sessionId,
            status: .idle,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            errorMessage: nil
        )
        messagesBySession[sessionId] = []
        return session
    }

    func getSession(id: String) async throws -> Session {
        guard let session = allSessions().first(where: { $0.id == id }) else {
            throw notFound("Session \(id) not found.")
        }
        return session
    }

    func renameSession(id: String, name: String) async throws -> Session {
        for (workspaceId, sessions) in sessionsByWorkspace {
            if let index = sessions.firstIndex(where: { $0.id == id }) {
                let existing = sessions[index]
                let renamed = Session(id: existing.id, deepLink: existing.deepLink, name: name, model: existing.model)
                sessionsByWorkspace[workspaceId]?[index] = renamed
                return renamed
            }
        }
        throw notFound("Session \(id) not found.")
    }

    func getSessionStatus(id: String) async throws -> SessionStatus {
        guard let status = sessionStatuses[id] else {
            throw notFound("Session \(id) not found.")
        }
        return status
    }

    func cancelSession(id: String) async throws -> SessionCancelResponse {
        guard let workspaceId = sessionWorkspaceIds[id] else {
            throw notFound("Session \(id) not found.")
        }
        let wasWorking = sessionStatuses[id]?.status == .working
        sessionStatuses[id] = SessionStatus(
            workspaceId: workspaceId,
            sessionId: id,
            status: .idle,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            errorMessage: nil
        )
        return SessionCancelResponse(
            workspaceId: workspaceId,
            sessionId: id,
            status: .idle,
            canceledQueuedMessages: wasWorking ? 1 : 0
        )
    }

    // MARK: - Messages

    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> {
        paginate(messagesBySession[sessionId] ?? [], limit: limit, offset: offset)
    }

    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse {
        guard let workspaceId = sessionWorkspaceIds[sessionId] else {
            throw notFound("Session \(sessionId) not found.")
        }

        let id = messageId ?? freshId(prefix: "msg")
        let index = Double((messagesBySession[sessionId]?.count ?? 0))
        let userMessage = TranscriptMessage(
            id: id,
            sessionId: sessionId,
            sessionIndex: index,
            type: "user",
            content: .object(["text": .string(message)]),
            receivedAt: ISO8601DateFormatter().string(from: Date())
        )
        messagesBySession[sessionId, default: []].append(userMessage)
        sessionStatuses[sessionId] = SessionStatus(
            workspaceId: workspaceId,
            sessionId: sessionId,
            status: .working,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            errorMessage: nil
        )

        Task.detached { [weak self, replyDelay] in
            try? await Task.sleep(for: replyDelay)
            await self?.appendCannedReply(sessionId: sessionId, workspaceId: workspaceId)
        }

        return MessageCreateResponse(messageId: id, state: .sent)
    }

    func getMessage(id: String) async throws -> TranscriptMessage {
        guard let message = messagesBySession.values.flatMap({ $0 }).first(where: { $0.id == id }) else {
            throw notFound("Message \(id) not found.")
        }
        return message
    }

    // MARK: - Internal mutation helpers

    private func markWorkspaceReady(_ workspaceId: String) {
        guard workspaceStatuses[workspaceId]?.status == .initializing else {
            return
        }
        workspaceStatuses[workspaceId] = WorkspaceStatus(
            workspaceId: workspaceId,
            status: .ready,
            lifecycleStep: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            errorMessage: nil
        )
    }

    private func appendCannedReply(sessionId: String, workspaceId: String) {
        // Session may have moved on (e.g. cancelled) while we were "thinking".
        guard sessionStatuses[sessionId]?.status == .working else {
            return
        }
        let index = Double((messagesBySession[sessionId]?.count ?? 0))
        let reply = TranscriptMessage(
            id: freshId(prefix: "msg"),
            sessionId: sessionId,
            sessionIndex: index,
            type: "agent_message",
            content: .object(["text": .string(MockConductorClient.cannedReplies.randomElement()!)]),
            receivedAt: ISO8601DateFormatter().string(from: Date())
        )
        messagesBySession[sessionId, default: []].append(reply)
        sessionStatuses[sessionId] = SessionStatus(
            workspaceId: workspaceId,
            sessionId: sessionId,
            status: .idle,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            errorMessage: nil
        )
    }

    private func freshId(prefix: String) -> String {
        nextId += 1
        return "\(prefix)_demo_\(nextId)"
    }

    private func allWorkspaces() -> [Workspace] {
        workspacesByProject.values.flatMap { $0 }
    }

    private func allSessions() -> [Session] {
        sessionsByWorkspace.values.flatMap { $0 }
    }

    private func paginate<Element>(_ items: [Element], limit: Int?, offset: Int?) -> Page<Element> {
        let start = max(0, offset ?? 0)
        guard start < items.count else {
            return Page(data: [], offset: Double(start), hasMore: false)
        }
        let end = limit.map { min(items.count, start + $0) } ?? items.count
        let slice = Array(items[start..<end])
        return Page(data: slice, offset: Double(start), hasMore: end < items.count)
    }

    private func notFound(_ message: String) -> ConductorError {
        .server(statusCode: 404, structured: StructuredError(
            code: "not_found",
            userMessage: message,
            debugMessage: nil,
            retryable: false,
            source: nil,
            stack: nil,
            underlying: nil
        ))
    }

    private func badRequest(_ message: String) -> ConductorError {
        .server(statusCode: 400, structured: StructuredError(
            code: "bad_request",
            userMessage: message,
            debugMessage: nil,
            retryable: false,
            source: nil,
            stack: nil,
            underlying: nil
        ))
    }

    private static let cannedReplies = [
        "Done — I made the change and re-ran the tests, all green. There is no spoon.",
        "I've pushed a fix for that. Let me know if you'd like me to open a PR before the Sentinels find us.",
        "Took a look — here's what I found and the change I made to address it. The Oracle saw it coming.",
        "That's fixed now. I also cleaned up a residual glitch while I was in there — probably just a black cat.",
    ]
}

// MARK: - Seed data

private struct SeedData {
    let projects: [Project]
    let workspacesByProject: [String: [Workspace]]
    let workspaceStatuses: [String: WorkspaceStatus]
    let sessionsByWorkspace: [String: [Session]]
    let sessionStatuses: [String: SessionStatus]
    let sessionWorkspaceIds: [String: String]
    let messagesBySession: [String: [TranscriptMessage]]
}

extension MockConductorClient {
    fileprivate static func makeSeedData() -> SeedData {
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        func iso(_ minutesAgo: Double) -> String {
            isoFormatter.string(from: now.addingTimeInterval(-minutesAgo * 60))
        }

        let projects = [
            Project(id: "proj_neb", name: "nebuchadnezzar", gitRemote: "git@github.com:zion-fleet/nebuchadnezzar.git"),
            Project(id: "proj_construct", name: "the-construct", gitRemote: "git@github.com:zion-fleet/the-construct.git"),
            Project(id: "proj_zion", name: "zion-mainframe", gitRemote: "git@github.com:zion-fleet/zion-mainframe.git"),
        ]

        // nebuchadnezzar: 3 workspaces
        let wsRetina1 = Workspace(
            id: "ws_neb_1",
            name: "free-the-mind",
            createdAt: iso(60 * 24 * 2),
            deepLink: "conductor://workspace/ws_neb_1",
            creatorId: "user_demo"
        )
        let wsRetina2 = Workspace(
            id: "ws_neb_2",
            name: "jack-in-protocol",
            createdAt: iso(60 * 5),
            deepLink: "conductor://workspace/ws_neb_2",
            creatorId: "user_demo"
        )
        let wsRetina3 = Workspace(
            id: "ws_neb_3",
            name: "sentinel-early-warning",
            createdAt: iso(60 * 24 * 10),
            deepLink: "conductor://workspace/ws_neb_3",
            creatorId: "user_demo"
        )

        // the-construct: 2 workspaces
        let wsMobile1 = Workspace(
            id: "ws_construct_1",
            name: "guns-lots-of-guns",
            createdAt: iso(20),
            deepLink: "conductor://workspace/ws_construct_1",
            creatorId: "user_demo"
        )
        let wsMobile2 = Workspace(
            id: "ws_construct_2",
            name: "deja-vu-patch",
            createdAt: iso(60 * 24 * 1),
            deepLink: "conductor://workspace/ws_construct_2",
            creatorId: "user_demo"
        )

        // zion-mainframe: 1 workspace
        let wsSite1 = Workspace(
            id: "ws_zion_1",
            name: "dock-defense-turrets",
            createdAt: iso(60 * 24 * 30),
            deepLink: "conductor://workspace/ws_zion_1",
            creatorId: "user_demo"
        )

        let workspacesByProject: [String: [Workspace]] = [
            "proj_neb": [wsRetina1, wsRetina2, wsRetina3],
            "proj_construct": [wsMobile1, wsMobile2],
            "proj_zion": [wsSite1],
        ]

        let workspaceStatuses: [String: WorkspaceStatus] = [
            "ws_neb_1": WorkspaceStatus(workspaceId: "ws_neb_1", status: .ready, lifecycleStep: nil, updatedAt: iso(5), errorMessage: nil),
            "ws_neb_2": WorkspaceStatus(workspaceId: "ws_neb_2", status: .updating, lifecycleStep: .updating, updatedAt: iso(1), errorMessage: nil),
            "ws_neb_3": WorkspaceStatus(workspaceId: "ws_neb_3", status: .sleeping, lifecycleStep: nil, updatedAt: iso(60 * 6), errorMessage: nil),
            "ws_construct_1": WorkspaceStatus(workspaceId: "ws_construct_1", status: .initializing, lifecycleStep: .buildingSnapshot, updatedAt: iso(1), errorMessage: nil),
            "ws_construct_2": WorkspaceStatus(workspaceId: "ws_construct_2", status: .ready, lifecycleStep: nil, updatedAt: iso(60 * 20), errorMessage: nil),
            "ws_zion_1": WorkspaceStatus(workspaceId: "ws_zion_1", status: .archived, lifecycleStep: nil, updatedAt: iso(60 * 24 * 20), errorMessage: nil),
        ]

        let sessRetina1 = Session(id: "sess_neb_1", deepLink: "conductor://session/sess_neb_1", name: "Follow the white rabbit", model: "claude-opus-4.6")
        let sessRetina2a = Session(id: "sess_neb_2a", deepLink: "conductor://session/sess_neb_2a", name: "Operator uplink", model: "claude-sonnet-5")
        let sessRetina2b = Session(id: "sess_neb_2b", deepLink: "conductor://session/sess_neb_2b", name: "Residual self image", model: "claude-sonnet-5")
        let sessRetina3 = Session(id: "sess_neb_3", deepLink: "conductor://session/sess_neb_3", name: "EMP readiness check", model: "claude-sonnet-5")
        let sessMobile1 = Session(id: "sess_construct_1", deepLink: "conductor://session/sess_construct_1", name: "Load the jump program", model: "claude-sonnet-5")
        let sessMobile2 = Session(id: "sess_construct_2", deepLink: "conductor://session/sess_construct_2", name: "Trace the black cat glitch", model: "codex-5")
        let sessSite1 = Session(id: "sess_zion_1", deepLink: "conductor://session/sess_zion_1", name: "Turret calibration", model: nil)

        let sessionsByWorkspace: [String: [Session]] = [
            "ws_neb_1": [sessRetina1],
            // Deliberately idle-first: the UI sorts working sessions to the top, and
            // tests rely on this seed order to prove the sort actually reorders.
            "ws_neb_2": [sessRetina2b, sessRetina2a],
            "ws_neb_3": [sessRetina3],
            "ws_construct_1": [sessMobile1],
            "ws_construct_2": [sessMobile2],
            "ws_zion_1": [sessSite1],
        ]

        let sessionWorkspaceIds: [String: String] = [
            "sess_neb_1": "ws_neb_1",
            "sess_neb_2a": "ws_neb_2",
            "sess_neb_2b": "ws_neb_2",
            "sess_neb_3": "ws_neb_3",
            "sess_construct_1": "ws_construct_1",
            "sess_construct_2": "ws_construct_2",
            "sess_zion_1": "ws_zion_1",
        ]

        let sessionStatuses: [String: SessionStatus] = [
            "sess_neb_1": SessionStatus(workspaceId: "ws_neb_1", sessionId: "sess_neb_1", status: .idle, updatedAt: iso(4), errorMessage: nil),
            "sess_neb_2a": SessionStatus(workspaceId: "ws_neb_2", sessionId: "sess_neb_2a", status: .working, updatedAt: iso(0), errorMessage: nil),
            "sess_neb_2b": SessionStatus(workspaceId: "ws_neb_2", sessionId: "sess_neb_2b", status: .idle, updatedAt: iso(45), errorMessage: nil),
            "sess_neb_3": SessionStatus(workspaceId: "ws_neb_3", sessionId: "sess_neb_3", status: .idle, updatedAt: iso(60 * 6), errorMessage: nil),
            "sess_construct_1": SessionStatus(workspaceId: "ws_construct_1", sessionId: "sess_construct_1", status: .idle, updatedAt: iso(1), errorMessage: nil),
            "sess_construct_2": SessionStatus(workspaceId: "ws_construct_2", sessionId: "sess_construct_2", status: .error, updatedAt: iso(60 * 19), errorMessage: "Connection severed: the operator dropped the landline."),
            "sess_zion_1": SessionStatus(workspaceId: "ws_zion_1", sessionId: "sess_zion_1", status: .idle, updatedAt: iso(60 * 24 * 20), errorMessage: nil),
        ]

        // Realistic multi-message transcript mixing user text, agent text, and raw agent
        // tool-call/event JSON, for sess_neb_1.
        let transcriptNeb1: [TranscriptMessage] = [
            TranscriptMessage(
                id: "msg_r1_1",
                sessionId: "sess_neb_1",
                sessionIndex: 0,
                type: "user",
                content: .object(["text": .string("Neo saw the same black cat twice in the Government Lobby sim — a déjà vu. I think the Agents changed something. Can you trace it?")]),
                receivedAt: iso(30)
            ),
            TranscriptMessage(
                id: "msg_r1_2",
                sessionId: "sess_neb_1",
                sessionIndex: 1,
                type: "agent_message",
                content: .object(["text": .string("Tracing it now — checking whether the lobby render loop recycles entity seeds when geometry gets rewritten.")]),
                receivedAt: iso(29)
            ),
            TranscriptMessage(
                id: "msg_r1_3",
                sessionId: "sess_neb_1",
                sessionIndex: 2,
                type: "tool_call",
                content: .object([
                    "tool": .string("read_file"),
                    "args": .object(["path": .string("simulacra/render/lobby_loop.c")]),
                ]),
                receivedAt: iso(28)
            ),
            TranscriptMessage(
                id: "msg_r1_4",
                sessionId: "sess_neb_1",
                sessionIndex: 3,
                type: "tool_result",
                content: .object([
                    "tool": .string("read_file"),
                    "result": .object(["lines": .number(212), "truncated": .bool(false)]),
                ]),
                receivedAt: iso(27)
            ),
            TranscriptMessage(
                id: "msg_r1_5",
                sessionId: "sess_neb_1",
                sessionIndex: 4,
                type: "agent_message",
                content: .object(["text": .string("Confirmed — geometry rewrites recycle the entity cache, so the cat respawns with the same seed. Patching the cache invalidation and adding a glitch telemetry hook.")]),
                receivedAt: iso(20)
            ),
            TranscriptMessage(
                id: "msg_r1_6",
                sessionId: "sess_neb_1",
                sessionIndex: 5,
                type: "user",
                content: .object(["text": .string("Sounds good. Run the full lobby sweep when you're done.")]),
                receivedAt: iso(15)
            ),
            TranscriptMessage(
                id: "msg_r1_7",
                sessionId: "sess_neb_1",
                sessionIndex: 6,
                type: "agent_message",
                content: .object(["text": .string("Done — `deja_vu_sweep` shows zero duplicate-entity frames across the last hour of lobby traffic.")]),
                receivedAt: iso(4)
            ),
        ]

        let transcriptConstruct2: [TranscriptMessage] = [
            TranscriptMessage(
                id: "msg_m2_1",
                sessionId: "sess_construct_2",
                sessionIndex: 0,
                type: "user",
                content: .object(["text": .string("The hardline exit at Wells & Lake keeps dropping mid-transfer. Can you check the uplink teardown?")]),
                receivedAt: iso(60 * 20)
            ),
            TranscriptMessage(
                id: "msg_m2_2",
                sessionId: "sess_construct_2",
                sessionIndex: 1,
                type: "error",
                content: .object([
                    "message": .string("Connection severed: the operator dropped the landline."),
                    "code": .string("hardline_disconnected"),
                ]),
                receivedAt: iso(60 * 19)
            ),
        ]

        let messagesBySession: [String: [TranscriptMessage]] = [
            "sess_neb_1": transcriptNeb1,
            "sess_neb_2a": [
                TranscriptMessage(
                    id: "msg_r2a_1",
                    sessionId: "sess_neb_2a",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Patch the operator uplink so we can broadcast the jump program to the whole crew at once.")]),
                    receivedAt: iso(2)
                ),
                TranscriptMessage(
                    id: "msg_r2a_2",
                    sessionId: "sess_neb_2a",
                    sessionIndex: 1,
                    type: "agent_message",
                    content: .object(["text": .string("On it — starting with the broadcast handshake in the Nebuchadnezzar's core relay.")]),
                    receivedAt: iso(1)
                ),
            ],
            "sess_neb_2b": [
                TranscriptMessage(
                    id: "msg_r2b_1",
                    sessionId: "sess_neb_2b",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Follow up: residual self image desyncs after long jacks — hair and clothes render a day stale.")]),
                    receivedAt: iso(50)
                ),
                TranscriptMessage(
                    id: "msg_r2b_2",
                    sessionId: "sess_neb_2b",
                    sessionIndex: 1,
                    type: "agent_message",
                    content: .object(["text": .string("Fixed — RSI now re-derives from the last stable avatar snapshot instead of accumulating deltas.")]),
                    receivedAt: iso(45)
                ),
            ],
            "sess_neb_3": [
                TranscriptMessage(
                    id: "msg_r3_1",
                    sessionId: "sess_neb_3",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Sentinels ping the hull every few hours. Can you audit the EMP arming checklist automation?")]),
                    receivedAt: iso(60 * 7)
                ),
                TranscriptMessage(
                    id: "msg_r3_2",
                    sessionId: "sess_neb_3",
                    sessionIndex: 1,
                    type: "agent_message",
                    content: .object(["text": .string("Audited — the arming interlock now refuses to charge while anyone is still jacked in.")]),
                    receivedAt: iso(60 * 6)
                ),
            ],
            "sess_construct_1": [
                TranscriptMessage(
                    id: "msg_m1_1",
                    sessionId: "sess_construct_1",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Load the jump program and stage the rooftop scenario. Guns. Lots of guns.")]),
                    receivedAt: iso(2)
                ),
            ],
            "sess_construct_2": transcriptConstruct2,
            "sess_zion_1": [
                TranscriptMessage(
                    id: "msg_s1_1",
                    sessionId: "sess_zion_1",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Recalibrate the dock turrets for the next wave — spread pattern was too tight in the last drill.")]),
                    receivedAt: iso(60 * 24 * 20)
                ),
                TranscriptMessage(
                    id: "msg_s1_2",
                    sessionId: "sess_zion_1",
                    sessionIndex: 1,
                    type: "agent_message",
                    content: .object(["text": .string("Recalibrated all quadrants and re-ran the drill sim — hit rate is up 18%.")]),
                    receivedAt: iso(60 * 24 * 20)
                ),
            ],
        ]

        return SeedData(
            projects: projects,
            workspacesByProject: workspacesByProject,
            workspaceStatuses: workspaceStatuses,
            sessionsByWorkspace: sessionsByWorkspace,
            sessionStatuses: sessionStatuses,
            sessionWorkspaceIds: sessionWorkspaceIds,
            messagesBySession: messagesBySession
        )
    }
}
