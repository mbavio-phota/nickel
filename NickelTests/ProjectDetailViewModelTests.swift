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
}
