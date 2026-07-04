import XCTest
@testable import Nickel

/// Decoding fixtures embedded as JSON literals matching `openapi.json` exactly, for every
/// response shape the app decodes.
final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    // MARK: - Projects

    func testDecodeProjectsListPage() throws {
        let json = """
        {
            "data": [
                {"id": "proj_1", "name": "retina", "gitRemote": "git@github.com:photalabs/retina.git"}
            ],
            "offset": 0,
            "hasMore": true
        }
        """
        let page = try decoder.decode(Page<Project>.self, from: Data(json.utf8))
        XCTAssertEqual(page.data.count, 1)
        XCTAssertEqual(page.data[0].id, "proj_1")
        XCTAssertEqual(page.data[0].name, "retina")
        XCTAssertEqual(page.data[0].gitRemote, "git@github.com:photalabs/retina.git")
        XCTAssertEqual(page.offset, 0)
        XCTAssertTrue(page.hasMore)
    }

    func testDecodeProject() throws {
        let json = """
        {"id": "proj_1", "name": "retina", "gitRemote": "git@github.com:photalabs/retina.git"}
        """
        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        XCTAssertEqual(project.id, "proj_1")
    }

    // MARK: - Workspaces

    func testDecodeWorkspace() throws {
        let json = """
        {
            "id": "ws_1",
            "name": "fix-bug",
            "createdAt": "2026-06-24T12:00:00.000Z",
            "deepLink": "conductor://workspace/ws_1",
            "creatorId": "user_1"
        }
        """
        let workspace = try decoder.decode(Workspace.self, from: Data(json.utf8))
        XCTAssertEqual(workspace.id, "ws_1")
        XCTAssertEqual(workspace.name, "fix-bug")
        XCTAssertEqual(workspace.deepLink, "conductor://workspace/ws_1")
        XCTAssertEqual(workspace.creatorId, "user_1")
        XCTAssertNotNil(workspace.createdDate)
    }

    func testDecodeWorkspaceWithoutOptionalCreatorId() throws {
        let json = """
        {
            "id": "ws_1",
            "name": "fix-bug",
            "createdAt": "2026-06-24T12:00:00.000Z",
            "deepLink": "conductor://workspace/ws_1"
        }
        """
        let workspace = try decoder.decode(Workspace.self, from: Data(json.utf8))
        XCTAssertNil(workspace.creatorId)
    }

    func testDecodeWorkspacesListPage() throws {
        let json = """
        {
            "data": [
                {"id": "ws_1", "name": "fix-bug", "createdAt": "2026-06-24T12:00:00.000Z", "deepLink": "conductor://workspace/ws_1"}
            ],
            "offset": 0,
            "hasMore": false
        }
        """
        let page = try decoder.decode(Page<Workspace>.self, from: Data(json.utf8))
        XCTAssertEqual(page.data.count, 1)
        XCTAssertFalse(page.hasMore)
    }

    func testDecodeWorkspaceCreateResponse() throws {
        let json = """
        {"workspaceId": "ws_1", "sessionId": "sess_1", "deepLink": "conductor://workspace/ws_1"}
        """
        let response = try decoder.decode(WorkspaceCreateResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.workspaceId, "ws_1")
        XCTAssertEqual(response.sessionId, "sess_1")
    }

    func testDecodeWorkspaceArchiveResponse() throws {
        let json = """
        {"workspaceId": "ws_1", "status": "archived"}
        """
        let response = try decoder.decode(WorkspaceArchiveResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.status, "archived")
    }

    func testDecodeWorkspaceStatusAllValues() throws {
        for status in WorkspaceStatusValue.allCases {
            let json = """
            {"workspaceId": "ws_1", "status": "\(status.rawValue)", "updatedAt": "2026-06-24T12:00:00.000Z"}
            """
            let decoded = try decoder.decode(WorkspaceStatus.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.status, status)
        }
    }

    func testDecodeWorkspaceStatusWithLifecycleStepAndError() throws {
        let json = """
        {
            "workspaceId": "ws_1",
            "status": "updating",
            "lifecycleStep": "building_snapshot",
            "updatedAt": "2026-06-24T12:00:00.000Z",
            "errorMessage": "boom"
        }
        """
        let status = try decoder.decode(WorkspaceStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.lifecycleStep, .buildingSnapshot)
        XCTAssertEqual(status.errorMessage, "boom")
    }

    func testDecodeAllLifecycleSteps() throws {
        let cases: [(String, WorkspaceLifecycleStep)] = [
            ("building_snapshot", .buildingSnapshot),
            ("preparing", .preparing),
            ("setting_up", .settingUp),
            ("updating", .updating),
        ]
        for (raw, expected) in cases {
            let json = """
            {"workspaceId": "ws_1", "status": "updating", "lifecycleStep": "\(raw)", "updatedAt": "2026-06-24T12:00:00.000Z"}
            """
            let status = try decoder.decode(WorkspaceStatus.self, from: Data(json.utf8))
            XCTAssertEqual(status.lifecycleStep, expected)
        }
    }

    // MARK: - Sessions

    func testDecodeSession() throws {
        let json = """
        {"id": "sess_1", "deepLink": "conductor://session/sess_1", "name": "Fix bug", "model": "claude-opus-4.6"}
        """
        let session = try decoder.decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(session.id, "sess_1")
        XCTAssertEqual(session.name, "Fix bug")
        XCTAssertEqual(session.model, "claude-opus-4.6")
    }

    func testDecodeSessionWithoutOptionalFields() throws {
        let json = """
        {"id": "sess_1", "deepLink": "conductor://session/sess_1"}
        """
        let session = try decoder.decode(Session.self, from: Data(json.utf8))
        XCTAssertNil(session.name)
        XCTAssertNil(session.model)
    }

    func testDecodeSessionsListPage() throws {
        let json = """
        {
            "data": [{"id": "sess_1", "deepLink": "conductor://session/sess_1"}],
            "offset": 0,
            "hasMore": false
        }
        """
        let page = try decoder.decode(Page<Session>.self, from: Data(json.utf8))
        XCTAssertEqual(page.data.count, 1)
    }

    func testDecodeSessionStatusAllValues() throws {
        for status in SessionStatusValue.allCases {
            let json = """
            {"workspaceId": "ws_1", "sessionId": "sess_1", "status": "\(status.rawValue)", "updatedAt": "2026-06-24T12:00:00.000Z"}
            """
            let decoded = try decoder.decode(SessionStatus.self, from: Data(json.utf8))
            XCTAssertEqual(decoded.status, status)
        }
    }

    func testDecodeSessionCancelResponse() throws {
        let json = """
        {"workspaceId": "ws_1", "sessionId": "sess_1", "status": "idle", "canceledQueuedMessages": 2}
        """
        let response = try decoder.decode(SessionCancelResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.status, .idle)
        XCTAssertEqual(response.canceledQueuedMessages, 2)
    }

    // MARK: - Messages

    func testDecodeMessageCreateResponse() throws {
        let json = """
        {"messageId": "msg_1", "state": "queued"}
        """
        let response = try decoder.decode(MessageCreateResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.messageId, "msg_1")
        XCTAssertEqual(response.state, .queued)
    }

    func testDecodeSimpleTextMessage() throws {
        let json = """
        {
            "id": "msg_1",
            "sessionId": "sess_1",
            "sessionIndex": 0,
            "type": "user",
            "content": {"text": "hello there"},
            "receivedAt": "2026-06-24T12:00:00.000Z"
        }
        """
        let message = try decoder.decode(TranscriptMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.type, "user")
        XCTAssertEqual(message.content.displayText, "hello there")
    }

    /// A weird, deeply-nested content payload mixing arrays, numbers, nulls, and bools —
    /// exercises that `JSONValue` never crashes on unknown shapes.
    func testDecodeMessageWithWeirdNestedContent() throws {
        let json = """
        {
            "id": "msg_2",
            "sessionId": "sess_1",
            "sessionIndex": 1,
            "type": "tool_call",
            "content": {
                "tool": "edit_file",
                "args": {
                    "path": "src/main.swift",
                    "replacements": [
                        {"old": "foo", "new": "bar", "count": 3},
                        {"old": null, "new": "baz", "count": 0}
                    ],
                    "dryRun": false,
                    "metadata": null
                },
                "nestedArrayOfArrays": [[1, 2], [3, [4, 5]]]
            },
            "receivedAt": "2026-06-24T12:00:01.000Z"
        }
        """
        let message = try decoder.decode(TranscriptMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.sessionIndex, 1)
        XCTAssertEqual(message.content["tool"]?.stringValue, "edit_file")
        XCTAssertEqual(message.content["args"]?["path"]?.stringValue, "src/main.swift")
        XCTAssertEqual(message.content["args"]?["dryRun"]?.boolValue, false)
        XCTAssertEqual(message.content["args"]?["metadata"], .null)
        let replacements = message.content["args"]?["replacements"]?.arrayValue
        XCTAssertEqual(replacements?.count, 2)
        XCTAssertEqual(replacements?[0]["old"]?.stringValue, "foo")
        XCTAssertNil(replacements?[1]["old"]?.stringValue)
        XCTAssertEqual(message.content["nestedArrayOfArrays"]?[1]?[1]?[1]?.numberValue, 5)
    }

    func testDecodeMessagesListPage() throws {
        let json = """
        {
            "data": [
                {
                    "id": "msg_1",
                    "sessionId": "sess_1",
                    "sessionIndex": 0,
                    "type": "user",
                    "content": "plain string content",
                    "receivedAt": "2026-06-24T12:00:00.000Z"
                }
            ],
            "offset": 0,
            "hasMore": false
        }
        """
        let page = try decoder.decode(Page<TranscriptMessage>.self, from: Data(json.utf8))
        XCTAssertEqual(page.data.count, 1)
        XCTAssertEqual(page.data[0].content, .string("plain string content"))
    }

    // MARK: - Errors

    func testDecodeStructuredErrorMinimal() throws {
        let json = """
        {"userMessage": "Something went wrong."}
        """
        let error = try decoder.decode(StructuredError.self, from: Data(json.utf8))
        XCTAssertEqual(error.userMessage, "Something went wrong.")
        XCTAssertNil(error.retryable)
    }

    func testDecodeStructuredErrorFull() throws {
        let json = """
        {
            "code": "rate_limited",
            "userMessage": "Too many requests.",
            "debugMessage": "429 from upstream",
            "retryable": true,
            "source": "network",
            "stack": "at foo()",
            "underlying": [{"userMessage": "inner"}]
        }
        """
        let error = try decoder.decode(StructuredError.self, from: Data(json.utf8))
        XCTAssertEqual(error.code, "rate_limited")
        XCTAssertEqual(error.retryable, true)
        XCTAssertEqual(error.underlying?.first?.userMessage, "inner")
    }

    // MARK: - Requests (encoding)

    func testEncodeCreateWorkspaceRequestForProjectOmitsRepositoryUrl() throws {
        let request = CreateWorkspaceRequest.forProject("proj_1", agent: .claude)
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["projectId"] as? String, "proj_1")
        XCTAssertNil(object?["repositoryUrl"])
    }

    func testEncodeCreateWorkspaceRequestForRepositoryOmitsProjectId() throws {
        let request = CreateWorkspaceRequest.forRepository("https://github.com/x/y.git")
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["repositoryUrl"] as? String, "https://github.com/x/y.git")
        XCTAssertNil(object?["projectId"])
    }

    func testAgentKindRawValues() {
        XCTAssertEqual(AgentKind.claude.rawValue, "claude")
        XCTAssertEqual(AgentKind.codex.rawValue, "codex")
        XCTAssertEqual(AgentKind.cursor.rawValue, "cursor")
        XCTAssertEqual(AgentKind.acp.rawValue, "acp")
    }
}
