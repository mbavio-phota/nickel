import XCTest
@testable import Nickel

final class LiveConductorClientTests: XCTestCase {
    private var client: LiveConductorClient!

    override func setUp() {
        super.setUp()
        client = LiveConductorClient(
            baseURL: URL(string: "https://api.conductor.build")!,
            session: URLProtocolStub.makeSession(),
            tokenProvider: { "test-token-123" }
        )
    }

    override func tearDown() {
        URLProtocolStub.stub = nil
        client = nil
        super.tearDown()
    }

    // MARK: - Request building

    func testListProjectsBuildsGetRequestWithQueryAndAuthHeader() async throws {
        let expectation = expectation(description: "request captured")
        URLProtocolStub.stub = .init(
            statusCode: 200,
            responseBody: Data("""
            {"data": [], "offset": 0, "hasMore": false}
            """.utf8)
        ) { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v0/projects")
            let query = Set(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            XCTAssertTrue(query.contains(URLQueryItem(name: "limit", value: "1")))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-123")
            expectation.fulfill()
        }

        _ = try await client.listProjects(limit: 1, offset: nil)
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testCreateWorkspaceWithProjectIdBuildsPostRequestWithBodyAndOmitsRepositoryUrl() async throws {
        let expectation = expectation(description: "request captured")
        URLProtocolStub.stub = .init(
            statusCode: 201,
            responseBody: Data("""
            {"workspaceId": "ws_1", "sessionId": "sess_1", "deepLink": "conductor://workspace/ws_1"}
            """.utf8)
        ) { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v0/workspaces")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let bodyData = request.httpBody ?? Data()
            let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["projectId"] as? String, "proj_1")
            XCTAssertEqual(body?["agent"] as? String, "claude")
            XCTAssertNil(body?["repositoryUrl"])
            expectation.fulfill()
        }

        let response = try await client.createWorkspace(.forProject("proj_1", agent: .claude))
        XCTAssertEqual(response.workspaceId, "ws_1")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testCreateWorkspaceWithRepositoryUrlOmitsProjectId() async throws {
        let expectation = expectation(description: "request captured")
        URLProtocolStub.stub = .init(
            statusCode: 201,
            responseBody: Data("""
            {"workspaceId": "ws_1", "sessionId": "sess_1", "deepLink": "conductor://workspace/ws_1"}
            """.utf8)
        ) { request in
            let bodyData = request.httpBody ?? Data()
            let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["repositoryUrl"] as? String, "https://github.com/x/y.git")
            XCTAssertNil(body?["projectId"])
            expectation.fulfill()
        }

        _ = try await client.createWorkspace(.forRepository("https://github.com/x/y.git"))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testRenameWorkspaceBuildsCorrectPathAndBody() async throws {
        let expectation = expectation(description: "request captured")
        URLProtocolStub.stub = .init(
            statusCode: 200,
            responseBody: Data("""
            {"id": "ws_1", "name": "renamed", "createdAt": "2026-06-24T12:00:00.000Z", "deepLink": "conductor://workspace/ws_1"}
            """.utf8)
        ) { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v0/workspaces/ws_1/rename")
            let bodyData = request.httpBody ?? Data()
            let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["name"] as? String, "renamed")
            expectation.fulfill()
        }

        let workspace = try await client.renameWorkspace(id: "ws_1", name: "renamed")
        XCTAssertEqual(workspace.name, "renamed")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testArchiveWorkspaceSendsNoBody() async throws {
        let expectation = expectation(description: "request captured")
        URLProtocolStub.stub = .init(
            statusCode: 200,
            responseBody: Data("""
            {"workspaceId": "ws_1", "status": "archived"}
            """.utf8)
        ) { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v0/workspaces/ws_1/archive")
            XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
            expectation.fulfill()
        }

        _ = try await client.archiveWorkspace(id: "ws_1")
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testListWorkspacesBuildsCorrectPathWithPagination() async throws {
        let expectation = expectation(description: "request captured")
        URLProtocolStub.stub = .init(
            statusCode: 200,
            responseBody: Data("""
            {"data": [], "offset": 10, "hasMore": false}
            """.utf8)
        ) { request in
            XCTAssertEqual(request.url?.path, "/v0/projects/proj_1/workspaces")
            let query = Set(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            XCTAssertTrue(query.contains(URLQueryItem(name: "limit", value: "20")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "offset", value: "10")))
            expectation.fulfill()
        }

        _ = try await client.listWorkspaces(projectId: "proj_1", limit: 20, offset: 10)
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testSendMessageBuildsCorrectPathAndBody() async throws {
        let expectation = expectation(description: "request captured")
        URLProtocolStub.stub = .init(
            statusCode: 201,
            responseBody: Data("""
            {"messageId": "msg_1", "state": "sent"}
            """.utf8)
        ) { request in
            XCTAssertEqual(request.url?.path, "/v0/sessions/sess_1/messages")
            let bodyData = request.httpBody ?? Data()
            let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            XCTAssertEqual(body?["message"] as? String, "hello")
            expectation.fulfill()
        }

        let response = try await client.sendMessage(sessionId: "sess_1", message: "hello", messageId: nil)
        XCTAssertEqual(response.state, .sent)
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testCancelSessionSendsNoBody() async throws {
        let expectation = expectation(description: "request captured")
        URLProtocolStub.stub = .init(
            statusCode: 200,
            responseBody: Data("""
            {"workspaceId": "ws_1", "sessionId": "sess_1", "status": "idle", "canceledQueuedMessages": 1}
            """.utf8)
        ) { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v0/sessions/sess_1/cancel")
            expectation.fulfill()
        }

        _ = try await client.cancelSession(id: "sess_1")
        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: - Error mapping

    func test401MapsToUnauthorized() async throws {
        URLProtocolStub.stub = .init(
            statusCode: 401,
            responseBody: Data("""
            {"userMessage": "Invalid API key."}
            """.utf8)
        )

        do {
            _ = try await client.listProjects(limit: nil, offset: nil)
            XCTFail("Expected an error")
        } catch let error as ConductorError {
            guard case .unauthorized(let userMessage) = error else {
                XCTFail("Expected .unauthorized, got \(error)")
                return
            }
            XCTAssertEqual(userMessage, "Invalid API key.")
            XCTAssertFalse(error.retryable)
        }
    }

    func test400MapsToServerErrorWithStructuredBody() async throws {
        URLProtocolStub.stub = .init(
            statusCode: 400,
            responseBody: Data("""
            {"code": "invalid_request", "userMessage": "Missing projectId.", "retryable": false}
            """.utf8)
        )

        do {
            _ = try await client.createWorkspace(.forProject("x"))
            XCTFail("Expected an error")
        } catch let error as ConductorError {
            guard case .server(let statusCode, let structured) = error else {
                XCTFail("Expected .server, got \(error)")
                return
            }
            XCTAssertEqual(statusCode, 400)
            XCTAssertEqual(structured.userMessage, "Missing projectId.")
            XCTAssertFalse(error.retryable)
        }
    }

    func test500RetryableServerError() async throws {
        URLProtocolStub.stub = .init(
            statusCode: 500,
            responseBody: Data("""
            {"userMessage": "Internal error.", "retryable": true}
            """.utf8)
        )

        do {
            _ = try await client.listProjects(limit: nil, offset: nil)
            XCTFail("Expected an error")
        } catch let error as ConductorError {
            XCTAssertTrue(error.retryable)
            XCTAssertEqual(error.statusCode, 500)
        }
    }

    func testMalformedErrorBodyStillProducesUsableError() async throws {
        URLProtocolStub.stub = .init(
            statusCode: 503,
            responseBody: Data("not json at all".utf8)
        )

        do {
            _ = try await client.listProjects(limit: nil, offset: nil)
            XCTFail("Expected an error")
        } catch let error as ConductorError {
            XCTAssertEqual(error.statusCode, 503)
            XCTAssertFalse(error.userMessage.isEmpty)
        }
    }

    func testDecodingErrorOnMalformedSuccessBody() async throws {
        URLProtocolStub.stub = .init(
            statusCode: 200,
            responseBody: Data("""
            {"totally": "unexpected shape"}
            """.utf8)
        )

        do {
            _ = try await client.listProjects(limit: nil, offset: nil)
            XCTFail("Expected an error")
        } catch let error as ConductorError {
            guard case .decoding = error else {
                XCTFail("Expected .decoding, got \(error)")
                return
            }
        }
    }
}
