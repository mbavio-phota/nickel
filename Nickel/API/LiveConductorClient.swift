import Foundation

/// URLSession-based `ConductorClient` conformance that talks to the real Conductor API.
final class LiveConductorClient: ConductorClient, @unchecked Sendable {
    let baseURL: URL
    private let session: URLSession
    private let tokenProvider: @Sendable () -> String?

    init(
        baseURL: URL = URL(string: "https://api.conductor.build")!,
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - Projects

    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project> {
        try await get(path: "/v0/projects", query: paginationQuery(limit: limit, offset: offset))
    }

    func getProject(id: String) async throws -> Project {
        try await get(path: "/v0/projects/\(pathSegment(id))")
    }

    // MARK: - Workspaces

    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> {
        try await get(
            path: "/v0/projects/\(pathSegment(projectId))/workspaces",
            query: paginationQuery(limit: limit, offset: offset)
        )
    }

    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse {
        try await post(path: "/v0/workspaces", body: request)
    }

    func getWorkspace(id: String) async throws -> Workspace {
        try await get(path: "/v0/workspaces/\(pathSegment(id))")
    }

    func renameWorkspace(id: String, name: String) async throws -> Workspace {
        try await post(path: "/v0/workspaces/\(pathSegment(id))/rename", body: RenameRequest(name: name))
    }

    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse {
        try await postEmpty(path: "/v0/workspaces/\(pathSegment(id))/archive")
    }

    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus {
        try await get(path: "/v0/workspaces/\(pathSegment(id))/status")
    }

    // MARK: - Sessions

    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> {
        try await get(
            path: "/v0/workspaces/\(pathSegment(workspaceId))/sessions",
            query: paginationQuery(limit: limit, offset: offset)
        )
    }

    func createSession(_ request: CreateSessionRequest) async throws -> Session {
        try await post(path: "/v0/sessions", body: request)
    }

    func getSession(id: String) async throws -> Session {
        try await get(path: "/v0/sessions/\(pathSegment(id))")
    }

    func renameSession(id: String, name: String) async throws -> Session {
        try await post(path: "/v0/sessions/\(pathSegment(id))/rename", body: RenameRequest(name: name))
    }

    func getSessionStatus(id: String) async throws -> SessionStatus {
        try await get(path: "/v0/sessions/\(pathSegment(id))/status")
    }

    func cancelSession(id: String) async throws -> SessionCancelResponse {
        try await postEmpty(path: "/v0/sessions/\(pathSegment(id))/cancel")
    }

    // MARK: - Messages

    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> {
        try await get(
            path: "/v0/sessions/\(pathSegment(sessionId))/messages",
            query: paginationQuery(limit: limit, offset: offset)
        )
    }

    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse {
        try await post(
            path: "/v0/sessions/\(pathSegment(sessionId))/messages",
            body: SendMessageRequest(messageId: messageId, message: message)
        )
    }

    func getMessage(id: String) async throws -> TranscriptMessage {
        try await get(path: "/v0/messages/\(pathSegment(id))")
    }

    // MARK: - Request building

    /// Percent-encodes a dynamic path segment (an id interpolated into a path string) so
    /// that characters like `/` or `?` can't split or extend the intended path.
    private func pathSegment(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    private func paginationQuery(limit: Int?, offset: Int?) -> [String: String] {
        var query: [String: String] = [:]
        if let limit {
            query["limit"] = String(limit)
        }
        if let offset {
            query["offset"] = String(offset)
        }
        return query
    }

    private func makeURL(path: String, query: [String: String]) throws -> URL {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ConductorError.transport(message: "Could not build request URL for \(path).")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw ConductorError.transport(message: "Could not build request URL for \(path).")
        }
        return url
    }

    private func makeRequest(method: String, path: String, query: [String: String] = [:]) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get<Response: Decodable>(path: String, query: [String: String] = [:]) async throws -> Response {
        let request = try makeRequest(method: "GET", path: path, query: query)
        return try await perform(request)
    }

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var request = try makeRequest(method: "POST", path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    /// POSTs with no request body, for endpoints like archive/cancel that take none.
    private func postEmpty<Response: Decodable>(path: String) async throws -> Response {
        let request = try makeRequest(method: "POST", path: path)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ConductorError.transport(message: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConductorError.transport(message: "Received a non-HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConductorError.fromResponse(statusCode: httpResponse.statusCode, data: data)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ConductorError.decoding(message: "Failed to decode response: \(error.localizedDescription)")
        }
    }
}
