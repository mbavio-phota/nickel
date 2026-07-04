import XCTest
@testable import Nickel

final class MockConductorClientTests: XCTestCase {
    func testListProjectsReturnsSeededProjects() async throws {
        let client = MockConductorClient()
        let page = try await client.listProjects(limit: nil, offset: nil)
        XCTAssertEqual(page.data.count, 3)
        XCTAssertFalse(page.hasMore)
    }

    func testListProjectsPagination() async throws {
        let client = MockConductorClient()
        let firstPage = try await client.listProjects(limit: 1, offset: 0)
        XCTAssertEqual(firstPage.data.count, 1)
        XCTAssertTrue(firstPage.hasMore)

        let secondPage = try await client.listProjects(limit: 1, offset: 1)
        XCTAssertEqual(secondPage.data.count, 1)
        XCTAssertNotEqual(firstPage.data[0].id, secondPage.data[0].id)
    }

    func testGetProjectNotFoundThrows() async throws {
        let client = MockConductorClient()
        do {
            _ = try await client.getProject(id: "does-not-exist")
            XCTFail("Expected notFound error")
        } catch let error as ConductorError {
            XCTAssertEqual(error.statusCode, 404)
        }
    }

    func testListWorkspacesAcrossVariedStatuses() async throws {
        let client = MockConductorClient()
        let projectsPage = try await client.listProjects(limit: nil, offset: nil)
        var allStatuses = Set<WorkspaceStatusValue>()
        for project in projectsPage.data {
            let workspaces = try await client.listWorkspaces(projectId: project.id, limit: nil, offset: nil)
            for workspace in workspaces.data {
                let status = try await client.getWorkspaceStatus(id: workspace.id)
                allStatuses.insert(status.status)
            }
        }
        // Seeded demo world spans a variety of workspace statuses per PLAN.md.
        XCTAssertTrue(allStatuses.count >= 4, "Expected varied statuses, got \(allStatuses)")
    }

    func testCreateWorkspaceAppearsInList() async throws {
        let client = MockConductorClient()
        let projectsPage = try await client.listProjects(limit: nil, offset: nil)
        let project = try XCTUnwrap(projectsPage.data.first)

        let before = try await client.listWorkspaces(projectId: project.id, limit: nil, offset: nil)

        let created = try await client.createWorkspace(.forProject(project.id, name: "brand-new-workspace", agent: .claude))

        let after = try await client.listWorkspaces(projectId: project.id, limit: nil, offset: nil)
        XCTAssertEqual(after.data.count, before.data.count + 1)
        XCTAssertTrue(after.data.contains { $0.id == created.workspaceId })
        XCTAssertTrue(after.data.contains { $0.name == "brand-new-workspace" })

        let status = try await client.getWorkspaceStatus(id: created.workspaceId)
        XCTAssertEqual(status.status, .initializing)
    }

    func testCreateWorkspaceRequiresProjectIdInDemoMode() async throws {
        let client = MockConductorClient()
        do {
            _ = try await client.createWorkspace(.forRepository("https://github.com/x/y.git"))
            XCTFail("Expected an error")
        } catch let error as ConductorError {
            XCTAssertEqual(error.statusCode, 400)
        }
    }

    func testRenameWorkspaceUpdatesName() async throws {
        let client = MockConductorClient()
        let projectsPage = try await client.listProjects(limit: nil, offset: nil)
        let project = try XCTUnwrap(projectsPage.data.first)
        let workspacesPage = try await client.listWorkspaces(projectId: project.id, limit: nil, offset: nil)
        let workspace = try XCTUnwrap(workspacesPage.data.first)

        let renamed = try await client.renameWorkspace(id: workspace.id, name: "totally-renamed")
        XCTAssertEqual(renamed.name, "totally-renamed")

        let fetched = try await client.getWorkspace(id: workspace.id)
        XCTAssertEqual(fetched.name, "totally-renamed")
    }

    func testArchiveWorkspaceChangesStatus() async throws {
        let client = MockConductorClient()
        let projectsPage = try await client.listProjects(limit: nil, offset: nil)
        let project = try XCTUnwrap(projectsPage.data.first)
        let workspacesPage = try await client.listWorkspaces(projectId: project.id, limit: nil, offset: nil)
        let workspace = try XCTUnwrap(workspacesPage.data.first)

        let before = try await client.getWorkspaceStatus(id: workspace.id)
        XCTAssertNotEqual(before.status, .archived)

        let response = try await client.archiveWorkspace(id: workspace.id)
        XCTAssertEqual(response.status, "archived")

        let after = try await client.getWorkspaceStatus(id: workspace.id)
        XCTAssertEqual(after.status, .archived)
    }

    func testArchiveWorkspaceIsIdempotent() async throws {
        let client = MockConductorClient()
        let projectsPage = try await client.listProjects(limit: nil, offset: nil)
        let project = try XCTUnwrap(projectsPage.data.first)
        let workspacesPage = try await client.listWorkspaces(projectId: project.id, limit: nil, offset: nil)
        let workspace = try XCTUnwrap(workspacesPage.data.first)

        _ = try await client.archiveWorkspace(id: workspace.id)
        let secondResponse = try await client.archiveWorkspace(id: workspace.id)
        XCTAssertEqual(secondResponse.status, "archived")
    }

    func testListSessionsReturnsRealisticTranscriptSessions() async throws {
        let client = MockConductorClient()
        let projectsPage = try await client.listProjects(limit: nil, offset: nil)
        let project = try XCTUnwrap(projectsPage.data.first)
        let workspacesPage = try await client.listWorkspaces(projectId: project.id, limit: nil, offset: nil)
        let workspace = try XCTUnwrap(workspacesPage.data.first)

        let sessionsPage = try await client.listSessions(workspaceId: workspace.id, limit: nil, offset: nil)
        XCTAssertFalse(sessionsPage.data.isEmpty)

        let session = try XCTUnwrap(sessionsPage.data.first)
        let messagesPage = try await client.listMessages(sessionId: session.id, limit: nil, offset: nil)
        XCTAssertFalse(messagesPage.data.isEmpty)

        // Transcript mixes user text messages and agent/event messages with JSON content.
        let types = Set(messagesPage.data.map(\.type))
        XCTAssertTrue(types.contains("user"))
    }

    func testCancelSessionFlipsWorkingToIdle() async throws {
        let client = MockConductorClient()
        // sess_neb_2a is seeded as `.working`.
        let before = try await client.getSessionStatus(id: "sess_neb_2a")
        XCTAssertEqual(before.status, .working)

        let response = try await client.cancelSession(id: "sess_neb_2a")
        XCTAssertEqual(response.status, .idle)
        XCTAssertEqual(response.canceledQueuedMessages, 1)

        let after = try await client.getSessionStatus(id: "sess_neb_2a")
        XCTAssertEqual(after.status, .idle)
    }

    func testCancelSessionOnIdleSessionIsNoOp() async throws {
        let client = MockConductorClient()
        // sess_neb_1 is seeded as `.idle`.
        let response = try await client.cancelSession(id: "sess_neb_1")
        XCTAssertEqual(response.status, .idle)
        XCTAssertEqual(response.canceledQueuedMessages, 0)
    }

    func testRenameSessionUpdatesName() async throws {
        let client = MockConductorClient()
        let renamed = try await client.renameSession(id: "sess_neb_1", name: "new-session-name")
        XCTAssertEqual(renamed.name, "new-session-name")

        let fetched = try await client.getSession(id: "sess_neb_1")
        XCTAssertEqual(fetched.name, "new-session-name")
    }

    /// Uses a short injected delay so the test doesn't wait out the real ~6s demo delay.
    func testSendMessageEventuallyAppendsReply() async throws {
        let client = MockConductorClient(replyDelay: .milliseconds(50))

        let before = try await client.listMessages(sessionId: "sess_neb_1", limit: nil, offset: nil)
        let beforeCount = before.data.count

        let response = try await client.sendMessage(sessionId: "sess_neb_1", message: "test message", messageId: nil)
        XCTAssertEqual(response.state, .sent)

        let statusDuringSend = try await client.getSessionStatus(id: "sess_neb_1")
        XCTAssertEqual(statusDuringSend.status, .working)

        let afterSend = try await client.listMessages(sessionId: "sess_neb_1", limit: nil, offset: nil)
        XCTAssertEqual(afterSend.data.count, beforeCount + 1)
        XCTAssertEqual(afterSend.data.last?.content.displayText, "test message")

        // Poll briefly for the canned reply rather than a fixed sleep, keeping this fast
        // and non-flaky.
        var finalMessages = afterSend
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(20))
            finalMessages = try await client.listMessages(sessionId: "sess_neb_1", limit: nil, offset: nil)
            if finalMessages.data.count == beforeCount + 2 {
                break
            }
        }

        XCTAssertEqual(finalMessages.data.count, beforeCount + 2)
        XCTAssertEqual(finalMessages.data.last?.type, "agent_message")
        XCTAssertNotNil(finalMessages.data.last?.content.displayText)

        let finalStatus = try await client.getSessionStatus(id: "sess_neb_1")
        XCTAssertEqual(finalStatus.status, .idle)
    }

    func testSendMessageNotFoundForUnknownSession() async throws {
        let client = MockConductorClient()
        do {
            _ = try await client.sendMessage(sessionId: "no-such-session", message: "hi", messageId: nil)
            XCTFail("Expected an error")
        } catch let error as ConductorError {
            XCTAssertEqual(error.statusCode, 404)
        }
    }

    func testGetMessageReturnsSeededMessage() async throws {
        let client = MockConductorClient()
        let message = try await client.getMessage(id: "msg_r1_1")
        XCTAssertEqual(message.sessionId, "sess_neb_1")
    }
}
