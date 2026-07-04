import Foundation

#if DEBUG

/// A `ConductorClient` that returns empty, successful results for every list call — used
/// to preview empty states without needing bespoke seed data.
actor EmptyPreviewClient: ConductorClient {
    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project> {
        Page(data: [], offset: 0, hasMore: false)
    }

    func getProject(id: String) async throws -> Project {
        throw notFound()
    }

    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> {
        Page(data: [], offset: 0, hasMore: false)
    }

    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse {
        throw notFound()
    }

    func getWorkspace(id: String) async throws -> Workspace {
        throw notFound()
    }

    func renameWorkspace(id: String, name: String) async throws -> Workspace {
        throw notFound()
    }

    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse {
        throw notFound()
    }

    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus {
        throw notFound()
    }

    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> {
        Page(data: [], offset: 0, hasMore: false)
    }

    func createSession(_ request: CreateSessionRequest) async throws -> Session {
        throw notFound()
    }

    func getSession(id: String) async throws -> Session {
        throw notFound()
    }

    func renameSession(id: String, name: String) async throws -> Session {
        throw notFound()
    }

    func getSessionStatus(id: String) async throws -> SessionStatus {
        throw notFound()
    }

    func cancelSession(id: String) async throws -> SessionCancelResponse {
        throw notFound()
    }

    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> {
        Page(data: [], offset: 0, hasMore: false)
    }

    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse {
        throw notFound()
    }

    func getMessage(id: String) async throws -> TranscriptMessage {
        throw notFound()
    }

    private func notFound() -> ConductorError {
        .server(statusCode: 404, structured: StructuredError(
            code: "not_found",
            userMessage: "Not found.",
            debugMessage: nil,
            retryable: false,
            source: nil,
            stack: nil,
            underlying: nil
        ))
    }
}

#endif
