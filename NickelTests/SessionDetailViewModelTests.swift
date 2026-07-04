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
