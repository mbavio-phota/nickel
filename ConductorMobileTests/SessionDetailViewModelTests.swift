import XCTest

@testable import ConductorMobile

/// Behavior tests for the chat view model's optimistic-send reconciliation: the message
/// sent with a client-generated `messageId` must be superseded by the server's echo, never
/// duplicated, and transcript polling must only ever grow the message list.
@MainActor
final class SessionDetailViewModelTests: XCTestCase {
    private func makeViewModel(replyDelay: Duration = .milliseconds(50)) -> SessionDetailViewModel {
        let client = MockConductorClient(replyDelay: replyDelay)
        let session = Session(
            id: "sess_retina_1",
            deepLink: "conductor://session/sess_retina_1",
            name: "Fix attribution gap",
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
}
