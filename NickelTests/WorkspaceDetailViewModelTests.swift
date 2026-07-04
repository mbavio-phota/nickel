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
}
