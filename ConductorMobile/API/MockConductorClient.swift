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
        "Done — I made the change and re-ran the tests, all green.",
        "I've pushed a fix for that. Let me know if you'd like me to open a PR.",
        "Took a look — here's what I found and the change I made to address it.",
        "That's fixed now. I also cleaned up a related warning while I was in there.",
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
            Project(id: "proj_retina", name: "retina", gitRemote: "git@github.com:photalabs/retina.git"),
            Project(id: "proj_conductor", name: "conductor-mobile", gitRemote: "git@github.com:mrbavio/conductor-mobile.git"),
            Project(id: "proj_site", name: "phota-site", gitRemote: "git@github.com:photalabs/phota-site.git"),
        ]

        // retina: 3 workspaces
        let wsRetina1 = Workspace(
            id: "ws_retina_1",
            name: "fix-vendor-cost-attribution",
            createdAt: iso(60 * 24 * 2),
            deepLink: "conductor://workspace/ws_retina_1",
            creatorId: "user_demo"
        )
        let wsRetina2 = Workspace(
            id: "ws_retina_2",
            name: "studio-chat-v2-search",
            createdAt: iso(60 * 5),
            deepLink: "conductor://workspace/ws_retina_2",
            creatorId: "user_demo"
        )
        let wsRetina3 = Workspace(
            id: "ws_retina_3",
            name: "grafana-cost-dashboard",
            createdAt: iso(60 * 24 * 10),
            deepLink: "conductor://workspace/ws_retina_3",
            creatorId: "user_demo"
        )

        // conductor-mobile: 2 workspaces
        let wsMobile1 = Workspace(
            id: "ws_mobile_1",
            name: "phase-1-scaffold",
            createdAt: iso(20),
            deepLink: "conductor://workspace/ws_mobile_1",
            creatorId: "user_demo"
        )
        let wsMobile2 = Workspace(
            id: "ws_mobile_2",
            name: "session-polling-bugfix",
            createdAt: iso(60 * 24 * 1),
            deepLink: "conductor://workspace/ws_mobile_2",
            creatorId: "user_demo"
        )

        // phota-site: 1 workspace
        let wsSite1 = Workspace(
            id: "ws_site_1",
            name: "update-pricing-copy",
            createdAt: iso(60 * 24 * 30),
            deepLink: "conductor://workspace/ws_site_1",
            creatorId: "user_demo"
        )

        let workspacesByProject: [String: [Workspace]] = [
            "proj_retina": [wsRetina1, wsRetina2, wsRetina3],
            "proj_conductor": [wsMobile1, wsMobile2],
            "proj_site": [wsSite1],
        ]

        let workspaceStatuses: [String: WorkspaceStatus] = [
            "ws_retina_1": WorkspaceStatus(workspaceId: "ws_retina_1", status: .ready, lifecycleStep: nil, updatedAt: iso(5), errorMessage: nil),
            "ws_retina_2": WorkspaceStatus(workspaceId: "ws_retina_2", status: .updating, lifecycleStep: .updating, updatedAt: iso(1), errorMessage: nil),
            "ws_retina_3": WorkspaceStatus(workspaceId: "ws_retina_3", status: .sleeping, lifecycleStep: nil, updatedAt: iso(60 * 6), errorMessage: nil),
            "ws_mobile_1": WorkspaceStatus(workspaceId: "ws_mobile_1", status: .initializing, lifecycleStep: .buildingSnapshot, updatedAt: iso(1), errorMessage: nil),
            "ws_mobile_2": WorkspaceStatus(workspaceId: "ws_mobile_2", status: .ready, lifecycleStep: nil, updatedAt: iso(60 * 20), errorMessage: nil),
            "ws_site_1": WorkspaceStatus(workspaceId: "ws_site_1", status: .archived, lifecycleStep: nil, updatedAt: iso(60 * 24 * 20), errorMessage: nil),
        ]

        let sessRetina1 = Session(id: "sess_retina_1", deepLink: "conductor://session/sess_retina_1", name: "Fix attribution gap", model: "claude-opus-4.6")
        let sessRetina2a = Session(id: "sess_retina_2a", deepLink: "conductor://session/sess_retina_2a", name: "Add search endpoint", model: "claude-sonnet-5")
        let sessRetina2b = Session(id: "sess_retina_2b", deepLink: "conductor://session/sess_retina_2b", name: "Vision paging follow-up", model: "claude-sonnet-5")
        let sessRetina3 = Session(id: "sess_retina_3", deepLink: "conductor://session/sess_retina_3", name: "Dashboard readability", model: "claude-sonnet-5")
        let sessMobile1 = Session(id: "sess_mobile_1", deepLink: "conductor://session/sess_mobile_1", name: "Scaffold project", model: "claude-sonnet-5")
        let sessMobile2 = Session(id: "sess_mobile_2", deepLink: "conductor://session/sess_mobile_2", name: "Fix polling race", model: "codex-5")
        let sessSite1 = Session(id: "sess_site_1", deepLink: "conductor://session/sess_site_1", name: "Pricing copy", model: nil)

        let sessionsByWorkspace: [String: [Session]] = [
            "ws_retina_1": [sessRetina1],
            "ws_retina_2": [sessRetina2a, sessRetina2b],
            "ws_retina_3": [sessRetina3],
            "ws_mobile_1": [sessMobile1],
            "ws_mobile_2": [sessMobile2],
            "ws_site_1": [sessSite1],
        ]

        let sessionWorkspaceIds: [String: String] = [
            "sess_retina_1": "ws_retina_1",
            "sess_retina_2a": "ws_retina_2",
            "sess_retina_2b": "ws_retina_2",
            "sess_retina_3": "ws_retina_3",
            "sess_mobile_1": "ws_mobile_1",
            "sess_mobile_2": "ws_mobile_2",
            "sess_site_1": "ws_site_1",
        ]

        let sessionStatuses: [String: SessionStatus] = [
            "sess_retina_1": SessionStatus(workspaceId: "ws_retina_1", sessionId: "sess_retina_1", status: .idle, updatedAt: iso(4), errorMessage: nil),
            "sess_retina_2a": SessionStatus(workspaceId: "ws_retina_2", sessionId: "sess_retina_2a", status: .working, updatedAt: iso(0), errorMessage: nil),
            "sess_retina_2b": SessionStatus(workspaceId: "ws_retina_2", sessionId: "sess_retina_2b", status: .idle, updatedAt: iso(45), errorMessage: nil),
            "sess_retina_3": SessionStatus(workspaceId: "ws_retina_3", sessionId: "sess_retina_3", status: .idle, updatedAt: iso(60 * 6), errorMessage: nil),
            "sess_mobile_1": SessionStatus(workspaceId: "ws_mobile_1", sessionId: "sess_mobile_1", status: .idle, updatedAt: iso(1), errorMessage: nil),
            "sess_mobile_2": SessionStatus(workspaceId: "ws_mobile_2", sessionId: "sess_mobile_2", status: .error, updatedAt: iso(60 * 19), errorMessage: "Agent crashed: workspace lost network connectivity."),
            "sess_site_1": SessionStatus(workspaceId: "ws_site_1", sessionId: "sess_site_1", status: .idle, updatedAt: iso(60 * 24 * 20), errorMessage: nil),
        ]

        // Realistic multi-message transcript mixing user text, agent text, and raw agent
        // tool-call/event JSON, for sess_retina_1.
        let transcriptRetina1: [TranscriptMessage] = [
            TranscriptMessage(
                id: "msg_r1_1",
                sessionId: "sess_retina_1",
                sessionIndex: 0,
                type: "user",
                content: .object(["text": .string("Vendor cost rows are landing unattributed for the new /images/filter-by-profile endpoint. Can you wire up VendorCallContext there?")]),
                receivedAt: iso(30)
            ),
            TranscriptMessage(
                id: "msg_r1_2",
                sessionId: "sess_retina_1",
                sessionIndex: 1,
                type: "agent_message",
                content: .object(["text": .string("Looking at the endpoint now — checking whether it wraps its Gemini call tree in a vendor_call_context.")]),
                receivedAt: iso(29)
            ),
            TranscriptMessage(
                id: "msg_r1_3",
                sessionId: "sess_retina_1",
                sessionIndex: 2,
                type: "tool_call",
                content: .object([
                    "tool": .string("read_file"),
                    "args": .object(["path": .string("api/routes/images.py")]),
                ]),
                receivedAt: iso(28)
            ),
            TranscriptMessage(
                id: "msg_r1_4",
                sessionId: "sess_retina_1",
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
                sessionId: "sess_retina_1",
                sessionIndex: 4,
                type: "agent_message",
                content: .object(["text": .string("Confirmed — it's missing the wrapper. Adding `vendor_call_context_if_unset(surface=.search)` around the handler body and a matching `VendorCallSurface` member.")]),
                receivedAt: iso(20)
            ),
            TranscriptMessage(
                id: "msg_r1_6",
                sessionId: "sess_retina_1",
                sessionIndex: 5,
                type: "user",
                content: .object(["text": .string("Sounds good. Run the surface audit when you're done.")]),
                receivedAt: iso(15)
            ),
            TranscriptMessage(
                id: "msg_r1_7",
                sessionId: "sess_retina_1",
                sessionIndex: 6,
                type: "agent_message",
                content: .object(["text": .string("Done — `vendor_surface_audit` shows zero NULL-surface rows for the endpoint over the last hour of test traffic.")]),
                receivedAt: iso(4)
            ),
        ]

        let transcriptMobile2: [TranscriptMessage] = [
            TranscriptMessage(
                id: "msg_m2_1",
                sessionId: "sess_mobile_2",
                sessionIndex: 0,
                type: "user",
                content: .object(["text": .string("The workspace status poll keeps firing after the view is gone. Can you check the .task cancellation?")]),
                receivedAt: iso(60 * 20)
            ),
            TranscriptMessage(
                id: "msg_m2_2",
                sessionId: "sess_mobile_2",
                sessionIndex: 1,
                type: "error",
                content: .object([
                    "message": .string("Agent crashed: workspace lost network connectivity."),
                    "code": .string("workspace_disconnected"),
                ]),
                receivedAt: iso(60 * 19)
            ),
        ]

        let messagesBySession: [String: [TranscriptMessage]] = [
            "sess_retina_1": transcriptRetina1,
            "sess_retina_2a": [
                TranscriptMessage(
                    id: "msg_r2a_1",
                    sessionId: "sess_retina_2a",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Add the person-filter search endpoint per the WEB-171 plan.")]),
                    receivedAt: iso(2)
                ),
                TranscriptMessage(
                    id: "msg_r2a_2",
                    sessionId: "sess_retina_2a",
                    sessionIndex: 1,
                    type: "agent_message",
                    content: .object(["text": .string("On it — starting with the DetectionRecord.resolved_profile_id lookup.")]),
                    receivedAt: iso(1)
                ),
            ],
            "sess_retina_2b": [
                TranscriptMessage(
                    id: "msg_r2b_1",
                    sessionId: "sess_retina_2b",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Follow up: paginate the vision tool so it doesn't blow the context window.")]),
                    receivedAt: iso(50)
                ),
                TranscriptMessage(
                    id: "msg_r2b_2",
                    sessionId: "sess_retina_2b",
                    sessionIndex: 1,
                    type: "agent_message",
                    content: .object(["text": .string("Added thumb540 paging via stash-by-toolCallId, keeping the client light.")]),
                    receivedAt: iso(45)
                ),
            ],
            "sess_retina_3": [
                TranscriptMessage(
                    id: "msg_r3_1",
                    sessionId: "sess_retina_3",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Cost dashboard labels are unreadable at the default zoom, can you fix the layout?")]),
                    receivedAt: iso(60 * 7)
                ),
                TranscriptMessage(
                    id: "msg_r3_2",
                    sessionId: "sess_retina_3",
                    sessionIndex: 1,
                    type: "agent_message",
                    content: .object(["text": .string("Fixed the units and label sizing, panel layout is cleaner now too.")]),
                    receivedAt: iso(60 * 6)
                ),
            ],
            "sess_mobile_1": [
                TranscriptMessage(
                    id: "msg_m1_1",
                    sessionId: "sess_mobile_1",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Scaffold the Phase 1 Xcode project per PLAN.md.")]),
                    receivedAt: iso(2)
                ),
            ],
            "sess_mobile_2": transcriptMobile2,
            "sess_site_1": [
                TranscriptMessage(
                    id: "msg_s1_1",
                    sessionId: "sess_site_1",
                    sessionIndex: 0,
                    type: "user",
                    content: .object(["text": .string("Update the pricing page copy for the new tier names.")]),
                    receivedAt: iso(60 * 24 * 20)
                ),
                TranscriptMessage(
                    id: "msg_s1_2",
                    sessionId: "sess_site_1",
                    sessionIndex: 1,
                    type: "agent_message",
                    content: .object(["text": .string("Updated all three tiers and re-ran the copy linter.")]),
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
