import XCTest

@testable import Nickel

/// The "Active now" fleet scan: cross-project discovery of working/error sessions,
/// working-first ordering, and the cheap status-only re-poll dropping finished sessions.
@MainActor
final class FleetViewModelTests: XCTestCase {
    func testRefreshFindsActiveSessionsAcrossProjects() async {
        // The demo seed has exactly two non-idle sessions, in different projects:
        // sess_neb_2a (working, proj_neb) and sess_construct_2 (error, proj_construct).
        let viewModel = FleetViewModel(client: MockConductorClient(replyDelay: .milliseconds(50)))
        await viewModel.refresh()

        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertEqual(viewModel.entries.map(\.session.id), ["sess_neb_2a", "sess_construct_2"])
        XCTAssertEqual(viewModel.entries.first?.status.status, .working)
        XCTAssertEqual(viewModel.entries.last?.status.status, .error)
        // Each entry carries the workspace and project it was found under, for the card.
        XCTAssertEqual(viewModel.entries.first?.workspace.id, "ws_neb_2")
        XCTAssertEqual(viewModel.entries.first?.project.id, "proj_neb")
    }

    func testPollStatusesDropsSessionsThatWentIdle() async {
        let client = MockConductorClient(replyDelay: .milliseconds(50))
        let viewModel = FleetViewModel(client: client)
        await viewModel.refresh()
        XCTAssertEqual(viewModel.entries.count, 2)

        // Cancelling the working session flips it to idle in the mock's status store —
        // the next cheap poll must drop it from the strip without a full rescan.
        _ = try? await client.cancelSession(id: "sess_neb_2a")
        await viewModel.pollStatuses()

        XCTAssertEqual(viewModel.entries.map(\.session.id), ["sess_construct_2"])
    }
}
