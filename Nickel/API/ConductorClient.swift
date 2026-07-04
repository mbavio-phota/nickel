import Foundation

/// Every Conductor API operation the app needs, implemented by both a live network client
/// and an in-memory demo client.
protocol ConductorClient: Sendable {
    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project>
    func getProject(id: String) async throws -> Project

    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace>
    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse
    func getWorkspace(id: String) async throws -> Workspace
    func renameWorkspace(id: String, name: String) async throws -> Workspace
    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse
    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus

    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session>
    func createSession(_ request: CreateSessionRequest) async throws -> Session
    func getSession(id: String) async throws -> Session
    func renameSession(id: String, name: String) async throws -> Session
    func getSessionStatus(id: String) async throws -> SessionStatus
    func cancelSession(id: String) async throws -> SessionCancelResponse

    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage>
    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse
    func getMessage(id: String) async throws -> TranscriptMessage
}
