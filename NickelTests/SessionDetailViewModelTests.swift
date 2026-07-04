import XCTest

@testable import Nickel

/// Behavior tests for the chat view model's optimistic-send reconciliation: the message
/// sent with a client-generated `messageId` must be superseded by the server's echo, never
/// duplicated, and transcript polling must only ever grow the message list.
@MainActor
final class SessionDetailViewModelTests: XCTestCase {
    private func makeViewModel(replyDelay: Duration = .milliseconds(50)) -> SessionDetailViewModel {
        let client = MockConductorClient(replyDelay: replyDelay)
        let session = Session(
            id: "sess_neb_1",
            deepLink: "conductor://session/sess_neb_1",
            name: "Follow the white rabbit",
            model: "claude-opus-4.6"
        )
        return SessionDetailViewModel(session: session, client: client)
    }

    func testSendShowsExactlyOneCopyOnceServerEchoes() async throws {
        let viewModel = makeViewModel()
        await viewModel.loadInitial()
        let countBefore = viewModel.messages.count
        XCTAssertGreaterThan(countBefore, 0, "seeded transcript expected")

        await viewModel.send("please also run the tests")

        let copies = viewModel.messages.filter { $0.content.displayText == "please also run the tests" }
        XCTAssertEqual(copies.count, 1, "optimistic copy must be superseded by the server echo, not duplicated")
        XCTAssertEqual(viewModel.messages.count, countBefore + 1)
        XCTAssertNil(viewModel.sendError)
    }

    func testPollPicksUpAgentReplyAndReturnsToIdle() async throws {
        let viewModel = makeViewModel(replyDelay: .milliseconds(50))
        await viewModel.loadInitial()

        await viewModel.send("kick off the migration")
        XCTAssertEqual(viewModel.status, .working)
        let countAfterSend = viewModel.messages.count

        try await Task.sleep(for: .milliseconds(200))
        await viewModel.pollStatusAndMessages()

        XCTAssertEqual(viewModel.status, .idle)
        XCTAssertEqual(viewModel.messages.count, countAfterSend + 1, "canned agent reply should arrive")
        // The transcript must be in index order after the incremental merge.
        let indices = viewModel.messages.map(\.sessionIndex)
        XCTAssertEqual(indices, indices.sorted())
    }

    func testFailedSendRemovesOptimisticCopyAndSurfacesError() async throws {
        let client = MockConductorClient(replyDelay: .milliseconds(50))
        // A session id the mock doesn't know → sendMessage throws notFound.
        let viewModel = SessionDetailViewModel(
            session: Session(id: "sess_missing", deepLink: "conductor://x", name: nil, model: nil),
            client: client
        )

        await viewModel.send("hello?")

        XCTAssertNotNil(viewModel.sendError)
        XCTAssertFalse(viewModel.messages.contains { $0.content.displayText == "hello?" })
    }

    /// The live API's echo does NOT reuse the client messageId as the transcript-event
    /// id — it lands at content.id (captured 2026-07-04). The optimistic copy must still
    /// be superseded.
    func testLiveStyleEchoWithClientIdInContentDedupes() async throws {
        let client = LiveEchoStubClient()
        let viewModel = SessionDetailViewModel(
            session: Session(id: "sess_live", deepLink: "conductor://x", name: nil, model: nil),
            client: client
        )

        await viewModel.send("Hello world?")

        let copies = viewModel.messages.filter { $0.content.displayText == "Hello world?" }
        XCTAssertEqual(copies.count, 1, "live-style echo (client id at content.id) must supersede the optimistic copy")
        XCTAssertEqual(copies.first?.id, "sess_live:1:0", "the surviving copy should be the server's")
    }

    /// `send` must record the delivery state the server reports (`queued`/`sent`) against
    /// the optimistic message, so the bubble can show a "Queued" footer. MockConductorClient
    /// always answers `.sent`, so this drives the state via a stub that answers `.queued`.
    func testSendTracksQueuedStateFromResponse() async throws {
        let client = QueuedSendStubClient()
        let viewModel = SessionDetailViewModel(
            session: Session(id: "sess_queue", deepLink: "conductor://x", name: nil, model: nil),
            client: client
        )

        await viewModel.send("will this queue?")

        let messageId = try XCTUnwrap(viewModel.messages.first { $0.content.displayText == "will this queue?" }?.id)
        XCTAssertEqual(viewModel.optimisticMessageStatesById[messageId], .queued)
    }

    /// A successful send whose echo hasn't arrived yet must record `.sent` (not leave the
    /// message untracked) when the response reports `state: .sent`. Uses a stub that never
    /// echoes so the tracked state survives the post-send `refreshMessages()` call —
    /// against MockConductorClient the echo lands synchronously and reconcile() clears the
    /// entry immediately, which isn't what this test is after.
    func testSendTracksSentStateFromResponse() async throws {
        let client = QueuedSendStubClient(state: .sent)
        let viewModel = SessionDetailViewModel(
            session: Session(id: "sess_sent", deepLink: "conductor://x", name: nil, model: nil),
            client: client
        )

        await viewModel.send("this should send immediately")

        let messageId = try XCTUnwrap(
            viewModel.messages.first { $0.content.displayText == "this should send immediately" }?.id
        )
        XCTAssertEqual(viewModel.optimisticMessageStatesById[messageId], .sent)
    }

    /// Cancel must apply the response's status directly (no extra `loadStatus()` round
    /// trip) and, when the response reports canceled queued messages, mark any
    /// still-queued optimistic bubbles as `.canceled` rather than leaving them pending
    /// forever (they will never be echoed by the server).
    func testCancelAppliesResponseAndMarksQueuedMessagesCanceled() async throws {
        let client = CancelStubClient()
        let viewModel = SessionDetailViewModel(
            session: Session(id: "sess_cancel", deepLink: "conductor://x", name: nil, model: nil),
            client: client
        )
        await viewModel.loadInitial()

        await viewModel.send("first, queued")
        let queuedId = try XCTUnwrap(viewModel.messages.first { $0.content.displayText == "first, queued" }?.id)
        XCTAssertEqual(viewModel.optimisticMessageStatesById[queuedId], .queued)

        let statusCallsBeforeCancel = client.statusCallCount
        await viewModel.cancel()

        XCTAssertEqual(
            client.statusCallCount, statusCallsBeforeCancel,
            "cancel must not issue a follow-up loadStatus() GET"
        )
        XCTAssertEqual(viewModel.status, .idle, "status should come from the cancel response, not a follow-up GET")
        XCTAssertEqual(viewModel.optimisticMessageStatesById[queuedId], .canceled)
        XCTAssertTrue(
            viewModel.messages.contains { $0.id == queuedId },
            "the canceled bubble must stay in the transcript"
        )

        // Sending again is the moment the user moves on: the cancel-dropped bubble (and
        // its tracked state) get cleared instead of piling up for the whole visit.
        await viewModel.send("second, after cancel")
        XCTAssertFalse(viewModel.messages.contains { $0.id == queuedId })
        XCTAssertNil(viewModel.optimisticMessageStatesById[queuedId])
    }
}

/// Answers `sendMessage` with a configurable `MessageState` and never echoes the message
/// back through `listMessages`, so the optimistic copy (and its tracked delivery state)
/// stays put — letting tests exercise the queued/sent state-tracking path in isolation
/// (MockConductorClient always answers `.sent` and echoes synchronously).
private final class QueuedSendStubClient: ConductorClient, @unchecked Sendable {
    private let state: MessageState

    init(state: MessageState = .queued) {
        self.state = state
    }

    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse {
        MessageCreateResponse(messageId: messageId ?? UUID().uuidString, state: state)
    }

    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> {
        Page(data: [], offset: 0, hasMore: false)
    }

    func getSessionStatus(id: String) async throws -> SessionStatus {
        SessionStatus(workspaceId: "ws", sessionId: id, status: .working, updatedAt: "2026-07-04 14:28:19.429+00", errorMessage: nil)
    }

    // Unused by this test.
    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project> { Page(data: [], offset: 0, hasMore: false) }
    func getProject(id: String) async throws -> Project { fatalError("unused") }
    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> { Page(data: [], offset: 0, hasMore: false) }
    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse { fatalError("unused") }
    func getWorkspace(id: String) async throws -> Workspace { fatalError("unused") }
    func renameWorkspace(id: String, name: String) async throws -> Workspace { fatalError("unused") }
    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse { fatalError("unused") }
    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus { fatalError("unused") }
    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> { Page(data: [], offset: 0, hasMore: false) }
    func createSession(_ request: CreateSessionRequest) async throws -> Session { fatalError("unused") }
    func getSession(id: String) async throws -> Session { fatalError("unused") }
    func renameSession(id: String, name: String) async throws -> Session { fatalError("unused") }
    func cancelSession(id: String) async throws -> SessionCancelResponse { fatalError("unused") }
    func getMessage(id: String) async throws -> TranscriptMessage { fatalError("unused") }
}

/// Reproduces a cancel that reports one dropped queued message, and counts how many
/// times `getSessionStatus` is called so tests can assert `cancel()` doesn't issue a
/// follow-up status GET.
private final class CancelStubClient: ConductorClient, @unchecked Sendable {
    private(set) var statusCallCount = 0
    private var echoed: [TranscriptMessage] = []

    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse {
        // Never echoed, simulating a message that's still queued when cancel arrives.
        MessageCreateResponse(messageId: messageId ?? UUID().uuidString, state: .queued)
    }

    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> {
        Page(data: echoed, offset: 0, hasMore: false)
    }

    func getSessionStatus(id: String) async throws -> SessionStatus {
        statusCallCount += 1
        return SessionStatus(workspaceId: "ws", sessionId: id, status: .working, updatedAt: "2026-07-04 14:28:19.429+00", errorMessage: nil)
    }

    func cancelSession(id: String) async throws -> SessionCancelResponse {
        SessionCancelResponse(workspaceId: "ws", sessionId: id, status: .idle, canceledQueuedMessages: 1)
    }

    // Unused by this test.
    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project> { Page(data: [], offset: 0, hasMore: false) }
    func getProject(id: String) async throws -> Project { fatalError("unused") }
    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> { Page(data: [], offset: 0, hasMore: false) }
    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse { fatalError("unused") }
    func getWorkspace(id: String) async throws -> Workspace { fatalError("unused") }
    func renameWorkspace(id: String, name: String) async throws -> Workspace { fatalError("unused") }
    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse { fatalError("unused") }
    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus { fatalError("unused") }
    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> { Page(data: [], offset: 0, hasMore: false) }
    func createSession(_ request: CreateSessionRequest) async throws -> Session { fatalError("unused") }
    func getSession(id: String) async throws -> Session { fatalError("unused") }
    func renameSession(id: String, name: String) async throws -> Session { fatalError("unused") }
    func getMessage(id: String) async throws -> TranscriptMessage { fatalError("unused") }
}

/// Minimal stub reproducing the live API's send/list behavior: the echoed transcript
/// message gets a server-generated event id, and the client `messageId` is embedded at
/// `content.id` inside a `userMessage` envelope.
private final class LiveEchoStubClient: ConductorClient, @unchecked Sendable {
    private var echoed: [TranscriptMessage] = []

    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse {
        let clientId = messageId ?? UUID().uuidString
        echoed.append(TranscriptMessage(
            id: "\(sessionId):1:\(echoed.count)",
            sessionId: sessionId,
            sessionIndex: Double(echoed.count),
            type: "userMessage",
            content: .object([
                "eventId": .string("\(sessionId):1:\(echoed.count)"),
                "type": .string("userMessage"),
                "id": .string(clientId),
                "message": .string(message),
                "state": .string("sent"),
                "turnId": .string(clientId),
            ]),
            receivedAt: "2026-07-04 14:28:19.429+00"
        ))
        return MessageCreateResponse(messageId: clientId, state: .sent)
    }

    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> {
        let start = min(offset ?? 0, echoed.count)
        return Page(data: Array(echoed[start...]), offset: Double(start), hasMore: false)
    }

    func getSessionStatus(id: String) async throws -> SessionStatus {
        SessionStatus(workspaceId: "ws", sessionId: id, status: .idle, updatedAt: "2026-07-04 14:28:19.429+00", errorMessage: nil)
    }

    // Unused by these tests.
    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project> { Page(data: [], offset: 0, hasMore: false) }
    func getProject(id: String) async throws -> Project { fatalError("unused") }
    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> { Page(data: [], offset: 0, hasMore: false) }
    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse { fatalError("unused") }
    func getWorkspace(id: String) async throws -> Workspace { fatalError("unused") }
    func renameWorkspace(id: String, name: String) async throws -> Workspace { fatalError("unused") }
    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse { fatalError("unused") }
    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus { fatalError("unused") }
    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> { Page(data: [], offset: 0, hasMore: false) }
    func createSession(_ request: CreateSessionRequest) async throws -> Session { fatalError("unused") }
    func getSession(id: String) async throws -> Session { fatalError("unused") }
    func renameSession(id: String, name: String) async throws -> Session { fatalError("unused") }
    func cancelSession(id: String) async throws -> SessionCancelResponse { fatalError("unused") }
    func getMessage(id: String) async throws -> TranscriptMessage { fatalError("unused") }
}
