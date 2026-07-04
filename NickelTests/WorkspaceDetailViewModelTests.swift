import XCTest

@testable import Nickel

/// Session ordering on the workspace screen: working sessions surface above idle ones
/// once their (eagerly fetched) statuses arrive; unknown statuses keep original order.
@MainActor
final class WorkspaceDetailViewModelTests: XCTestCase {
    private func makeViewModel(workspaceId: String, name: String) -> WorkspaceDetailViewModel {
        WorkspaceDetailViewModel(
            workspace: Workspace(
                id: workspaceId, name: name, createdAt: "2026-07-04 14:27:40.002976+00",
                deepLink: "conductor://workspace?id=\(workspaceId)", creatorId: nil
            ),
            client: MockConductorClient(replyDelay: .milliseconds(50))
        )
    }

    func testWorkingSessionSortsAboveIdle() async {
        // ws_neb_2 is seeded idle-first ([2b idle, 2a working]) precisely so this test
        // proves the reorder.
        let viewModel = makeViewModel(workspaceId: "ws_neb_2", name: "jack-in-protocol")
        await viewModel.loadSessionsInitial()

        XCTAssertEqual(viewModel.sessions.map(\.id), ["sess_neb_2b", "sess_neb_2a"], "raw order from API")
        XCTAssertEqual(
            viewModel.orderedSessions.map(\.id),
            ["sess_neb_2a", "sess_neb_2b"],
            "working session must surface above the idle one"
        )
        XCTAssertEqual(viewModel.sessionStatusesById["sess_neb_2a"]?.status, .working)
    }

    func testUnknownStatusPreservesOriginalOrder() {
        let viewModel = makeViewModel(workspaceId: "ws_neb_2", name: "jack-in-protocol")
        // Nothing loaded: orderedSessions of an empty list is empty, and adding sessions
        // without statuses keeps insertion order.
        viewModel.addCreatedSession(Session(id: "s1", deepLink: "conductor://x", name: "one", model: nil))
        viewModel.addCreatedSession(Session(id: "s2", deepLink: "conductor://x", name: "two", model: nil))
        XCTAssertEqual(viewModel.orderedSessions.map(\.id), ["s1", "s2"])
    }

    /// Pull-to-refresh must not blank the visible list: `sessionsLoadable` should only
    /// ever pass through `.loading` when there was nothing loaded yet. Verified both by
    /// checking mid-flight state (via an artificial delay on the second call) and by
    /// confirming the refreshed data lands correctly.
    func testRefreshDoesNotReenterLoadingWhenAlreadyPopulated() async {
        let client = SessionListStubClient(
            pages: [
                Page(data: [Session(id: "s1", deepLink: "conductor://x", name: "one", model: nil)], offset: 0, hasMore: false),
                Page(data: [Session(id: "s1", deepLink: "conductor://x", name: "one (renamed)", model: nil)], offset: 0, hasMore: false),
            ]
        )
        let viewModel = WorkspaceDetailViewModel(
            workspace: Workspace(id: "ws1", name: "w", createdAt: "2026-07-04 14:27:40.002976+00", deepLink: "conductor://x", creatorId: nil),
            client: client
        )
        await viewModel.loadSessionsInitial()
        XCTAssertEqual(viewModel.sessions.map(\.id), ["s1"])

        client.delayBeforeReturning = .milliseconds(50)
        let refreshTask = Task { await viewModel.refreshSessions() }

        // While the refresh is in flight, the previously loaded row must still be visible
        // — `sessionsLoadable` must not have been reset to `.loading` (which would blank
        // `.value`).
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertNotNil(viewModel.sessionsLoadable.value, "loadable must retain its value instead of re-entering .loading")
        XCTAssertEqual(viewModel.sessions.map(\.id), ["s1"])

        await refreshTask.value

        XCTAssertEqual(viewModel.sessions.map(\.name), ["one (renamed)"])
    }

    /// A load-more failure must set `loadMoreSessionsFailed` (not silently truncate the
    /// list via `hasMoreSessions = false`), and `retryLoadMoreSessions()` must recover.
    func testLoadMoreFailureSetsFlagAndRetrySucceeds() async {
        let client = SessionListStubClient(
            pages: [
                Page(data: [Session(id: "s1", deepLink: "conductor://x", name: "one", model: nil)], offset: 0, hasMore: true),
            ],
            failLoadMore: true
        )
        let viewModel = WorkspaceDetailViewModel(
            workspace: Workspace(id: "ws1", name: "w", createdAt: "2026-07-04 14:27:40.002976+00", deepLink: "conductor://x", creatorId: nil),
            client: client
        )
        await viewModel.loadSessionsInitial()
        XCTAssertTrue(viewModel.hasMoreSessions)

        await viewModel.loadMoreSessionsIfNeeded()
        XCTAssertTrue(viewModel.loadMoreSessionsFailed)
        XCTAssertTrue(viewModel.hasMoreSessions, "hasMoreSessions must not be silently cleared on failure")
        XCTAssertEqual(viewModel.sessions.map(\.id), ["s1"], "the failed page must not be appended")

        // A second loadMoreSessionsIfNeeded should be a no-op while the failure flag is set.
        await viewModel.loadMoreSessionsIfNeeded()
        XCTAssertEqual(client.loadMoreCallCount, 1)

        client.failLoadMore = false
        client.nextPage = Page(data: [Session(id: "s2", deepLink: "conductor://x", name: "two", model: nil)], offset: 1, hasMore: false)
        await viewModel.retryLoadMoreSessions()

        XCTAssertFalse(viewModel.loadMoreSessionsFailed)
        XCTAssertEqual(viewModel.sessions.map(\.id), ["s1", "s2"])
    }
}

/// Stubs `listSessions` from a queue of canned pages (first call = initial load, second
/// call = refresh, ...), optionally failing every load-more (offset > 0) call while
/// `failLoadMore` is set. Lets tests drive the workspace session list's loading-state and
/// retry behavior precisely, which MockConductorClient's fixed seed data can't do.
private final class SessionListStubClient: ConductorClient, @unchecked Sendable {
    private var pages: [Page<Session>]
    var failLoadMore: Bool
    var nextPage: Page<Session>?
    var delayBeforeReturning: Duration?
    private(set) var loadMoreCallCount = 0

    init(pages: [Page<Session>], failLoadMore: Bool = false) {
        self.pages = pages
        self.failLoadMore = failLoadMore
    }

    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> {
        if let delayBeforeReturning {
            try? await Task.sleep(for: delayBeforeReturning)
        }
        if (offset ?? 0) > 0 {
            loadMoreCallCount += 1
            if failLoadMore {
                throw notFound("load more failed")
            }
            return nextPage ?? Page(data: [], offset: Double(offset ?? 0), hasMore: false)
        }
        guard !pages.isEmpty else {
            return Page(data: [], offset: 0, hasMore: false)
        }
        return pages.removeFirst()
    }

    func getSessionStatus(id: String) async throws -> SessionStatus {
        SessionStatus(workspaceId: "ws1", sessionId: id, status: .idle, updatedAt: "2026-07-04 14:28:19.429+00", errorMessage: nil)
    }

    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus {
        WorkspaceStatus(workspaceId: id, status: .ready, lifecycleStep: nil, updatedAt: "2026-07-04 14:28:19.429+00", errorMessage: nil)
    }

    private func notFound(_ message: String) -> ConductorError {
        .server(statusCode: 404, structured: StructuredError(
            code: "not_found", userMessage: message, debugMessage: nil, retryable: false, source: nil, stack: nil, underlying: nil
        ))
    }

    // Unused by these tests.
    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project> { Page(data: [], offset: 0, hasMore: false) }
    func getProject(id: String) async throws -> Project { fatalError("unused") }
    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> { Page(data: [], offset: 0, hasMore: false) }
    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse { fatalError("unused") }
    func getWorkspace(id: String) async throws -> Workspace { fatalError("unused") }
    func renameWorkspace(id: String, name: String) async throws -> Workspace { fatalError("unused") }
    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse { fatalError("unused") }
    func createSession(_ request: CreateSessionRequest) async throws -> Session { fatalError("unused") }
    func getSession(id: String) async throws -> Session { fatalError("unused") }
    func renameSession(id: String, name: String) async throws -> Session { fatalError("unused") }
    func cancelSession(id: String) async throws -> SessionCancelResponse { fatalError("unused") }
    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> { Page(data: [], offset: 0, hasMore: false) }
    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse { fatalError("unused") }
    func getMessage(id: String) async throws -> TranscriptMessage { fatalError("unused") }
}
