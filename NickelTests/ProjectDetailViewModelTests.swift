import XCTest

@testable import Nickel

/// Grouping behavior for the project workspace list: archived/deleted workspaces move to
/// their own section once their (eagerly fetched) status is known; unknown-status
/// workspaces count as active.
@MainActor
final class ProjectDetailViewModelTests: XCTestCase {
    private func makeViewModel(projectId: String, name: String) -> ProjectDetailViewModel {
        ProjectDetailViewModel(
            project: Project(id: projectId, name: name, gitRemote: "git@github.com:zion-fleet/\(name).git"),
            client: MockConductorClient(replyDelay: .milliseconds(50))
        )
    }

    func testArchivedWorkspacesGroupSeparatelyAfterRefresh() async {
        // proj_zion's only workspace (dock-defense-turrets) is seeded archived.
        let viewModel = makeViewModel(projectId: "proj_zion", name: "zion-mainframe")
        await viewModel.loadInitial()

        XCTAssertEqual(viewModel.workspaces.count, 1)
        XCTAssertTrue(viewModel.activeWorkspaces.isEmpty)
        XCTAssertEqual(viewModel.archivedWorkspaces.map(\.name), ["dock-defense-turrets"])
    }

    func testActiveProjectHasNoArchivedGroup() async {
        // proj_neb's workspaces are ready / updating / sleeping — all active.
        let viewModel = makeViewModel(projectId: "proj_neb", name: "nebuchadnezzar")
        await viewModel.loadInitial()

        XCTAssertEqual(viewModel.workspaces.count, 3)
        XCTAssertEqual(viewModel.activeWorkspaces.count, 3)
        XCTAssertTrue(viewModel.archivedWorkspaces.isEmpty)
    }

    func testUnknownStatusCountsAsActive() async {
        let viewModel = makeViewModel(projectId: "proj_zion", name: "zion-mainframe")
        await viewModel.loadInitial()

        // A freshly created workspace has no cached status yet — it must be visible in
        // the active list, not silently hidden in the archived group.
        let created = Workspace(
            id: "ws_new", name: "brand-new", createdAt: "2026-07-04 14:27:40.002976+00",
            deepLink: "conductor://workspace?id=ws_new", creatorId: nil
        )
        viewModel.prependNewWorkspace(created)
        XCTAssertTrue(viewModel.activeWorkspaces.contains { $0.id == "ws_new" })
    }

    /// Pull-to-refresh must not blank the visible list: `loadable` should only ever pass
    /// through `.loading` when there was nothing loaded yet.
    func testRefreshDoesNotReenterLoadingWhenAlreadyPopulated() async {
        let client = WorkspaceListStubClient(
            pages: [
                Page(data: [Workspace(id: "w1", name: "one", createdAt: "2026-07-04 14:27:40.002976+00", deepLink: "conductor://x", creatorId: nil)], offset: 0, hasMore: false),
                Page(data: [Workspace(id: "w1", name: "one (renamed)", createdAt: "2026-07-04 14:27:40.002976+00", deepLink: "conductor://x", creatorId: nil)], offset: 0, hasMore: false),
            ]
        )
        let viewModel = ProjectDetailViewModel(
            project: Project(id: "proj1", name: "p", gitRemote: "git@github.com:demo/p.git"),
            client: client
        )
        await viewModel.loadInitial()
        XCTAssertEqual(viewModel.workspaces.map(\.id), ["w1"])

        client.delayBeforeReturning = .milliseconds(50)
        let refreshTask = Task { await viewModel.refresh() }

        // While the refresh is in flight, the previously loaded row must still be visible
        // — `loadable` must not have been reset to `.loading` (which would blank `.value`).
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertNotNil(viewModel.loadable.value, "loadable must retain its value instead of re-entering .loading")
        XCTAssertEqual(viewModel.workspaces.map(\.id), ["w1"])

        await refreshTask.value

        XCTAssertEqual(viewModel.workspaces.map(\.name), ["one (renamed)"])
    }

    /// A load-more failure must set `loadMoreFailed` (not silently truncate the list via
    /// `hasMore = false`), and `retryLoadMore()` must recover.
    func testLoadMoreFailureSetsFlagAndRetrySucceeds() async {
        let client = WorkspaceListStubClient(
            pages: [
                Page(data: [Workspace(id: "w1", name: "one", createdAt: "2026-07-04 14:27:40.002976+00", deepLink: "conductor://x", creatorId: nil)], offset: 0, hasMore: true),
            ],
            failLoadMore: true
        )
        let viewModel = ProjectDetailViewModel(
            project: Project(id: "proj1", name: "p", gitRemote: "git@github.com:demo/p.git"),
            client: client
        )
        await viewModel.loadInitial()
        XCTAssertTrue(viewModel.hasMore)

        await viewModel.loadMoreIfNeeded()
        XCTAssertTrue(viewModel.loadMoreFailed)
        XCTAssertTrue(viewModel.hasMore, "hasMore must not be silently cleared on failure")
        XCTAssertEqual(viewModel.workspaces.map(\.id), ["w1"], "the failed page must not be appended")

        // A second loadMoreIfNeeded should be a no-op while the failure flag is set.
        await viewModel.loadMoreIfNeeded()
        XCTAssertEqual(client.loadMoreCallCount, 1)

        client.failLoadMore = false
        client.nextPage = Page(data: [Workspace(id: "w2", name: "two", createdAt: "2026-07-04 14:27:40.002976+00", deepLink: "conductor://x", creatorId: nil)], offset: 1, hasMore: false)
        await viewModel.retryLoadMore()

        XCTAssertFalse(viewModel.loadMoreFailed)
        XCTAssertEqual(viewModel.workspaces.map(\.id), ["w1", "w2"])
    }
}

/// Stubs `listWorkspaces` from a queue of canned pages (first call = initial load, second
/// call = refresh, ...), optionally failing every load-more (offset > 0) call while
/// `failLoadMore` is set. Lets tests drive the project workspace list's loading-state and
/// retry behavior precisely, which MockConductorClient's fixed seed data can't do.
private final class WorkspaceListStubClient: ConductorClient, @unchecked Sendable {
    private var pages: [Page<Workspace>]
    var failLoadMore: Bool
    var nextPage: Page<Workspace>?
    var delayBeforeReturning: Duration?
    private(set) var loadMoreCallCount = 0

    init(pages: [Page<Workspace>], failLoadMore: Bool = false) {
        self.pages = pages
        self.failLoadMore = failLoadMore
    }

    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> {
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
    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse { fatalError("unused") }
    func getWorkspace(id: String) async throws -> Workspace { fatalError("unused") }
    func renameWorkspace(id: String, name: String) async throws -> Workspace { fatalError("unused") }
    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse { fatalError("unused") }
    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> { Page(data: [], offset: 0, hasMore: false) }
    func createSession(_ request: CreateSessionRequest) async throws -> Session { fatalError("unused") }
    func getSession(id: String) async throws -> Session { fatalError("unused") }
    func renameSession(id: String, name: String) async throws -> Session { fatalError("unused") }
    func getSessionStatus(id: String) async throws -> SessionStatus { fatalError("unused") }
    func cancelSession(id: String) async throws -> SessionCancelResponse { fatalError("unused") }
    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> { Page(data: [], offset: 0, hasMore: false) }
    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse { fatalError("unused") }
    func getMessage(id: String) async throws -> TranscriptMessage { fatalError("unused") }
}
