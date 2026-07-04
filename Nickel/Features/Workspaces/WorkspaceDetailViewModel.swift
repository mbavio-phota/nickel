import Foundation
import Observation

/// Drives a single workspace's detail screen: status (polled while transitioning),
/// sessions list + pagination, rename, and archive.
@MainActor
@Observable
final class WorkspaceDetailViewModel {
    private(set) var workspace: Workspace
    private(set) var statusLoadable: Loadable<WorkspaceStatus> = .idle
    private(set) var sessionsLoadable: Loadable<[Session]> = .idle
    private(set) var hasMoreSessions = false
    private(set) var isLoadingMoreSessions = false
    private(set) var isRenaming = false
    private(set) var isArchiving = false
    private(set) var actionError: ConductorError?

    private let client: ConductorClient
    private let pageSize = 20

    init(workspace: Workspace, client: ConductorClient) {
        self.workspace = workspace
        self.client = client
    }

    var sessions: [Session] {
        sessionsLoadable.value ?? []
    }

    var isArchived: Bool {
        statusLoadable.value?.status == .archived
    }

    /// Whether the status should keep polling: initializing/updating states change on
    /// their own without user action.
    var shouldPollStatus: Bool {
        guard let status = statusLoadable.value?.status else {
            return true // keep trying until we get a first value
        }
        return status == .initializing || status == .updating
    }

    func loadStatus() async {
        do {
            let status = try await client.getWorkspaceStatus(id: workspace.id)
            statusLoadable = .loaded(status)
        } catch let error as ConductorError {
            statusLoadable = .failed(error)
        } catch {
            statusLoadable = .failed(.transport(message: error.localizedDescription))
        }
    }

    func loadSessionsInitial() async {
        guard sessionsLoadable.value == nil else {
            return
        }
        await refreshSessions()
    }

    func refreshSessions() async {
        sessionsLoadable = .loading
        do {
            let page = try await client.listSessions(workspaceId: workspace.id, limit: pageSize, offset: nil)
            sessionsLoadable = .loaded(page.data)
            hasMoreSessions = page.hasMore
        } catch let error as ConductorError {
            sessionsLoadable = .failed(error)
        } catch {
            sessionsLoadable = .failed(.transport(message: error.localizedDescription))
        }
    }

    func loadMoreSessionsIfNeeded(currentItem sessionItem: Session) async {
        guard hasMoreSessions, !isLoadingMoreSessions, sessionItem.id == sessions.last?.id else {
            return
        }
        isLoadingMoreSessions = true
        defer { isLoadingMoreSessions = false }

        do {
            let page = try await client.listSessions(workspaceId: workspace.id, limit: pageSize, offset: sessions.count)
            sessionsLoadable = .loaded(sessions + page.data)
            hasMoreSessions = page.hasMore
        } catch {
            hasMoreSessions = false
        }
    }

    func refreshAll() async {
        await loadStatus()
        await refreshSessions()
    }

    func rename(to newName: String) async -> Bool {
        isRenaming = true
        actionError = nil
        defer { isRenaming = false }

        do {
            workspace = try await client.renameWorkspace(id: workspace.id, name: newName)
            return true
        } catch let error as ConductorError {
            actionError = error
            return false
        } catch {
            actionError = .transport(message: error.localizedDescription)
            return false
        }
    }

    func archive() async -> Bool {
        isArchiving = true
        actionError = nil
        defer { isArchiving = false }

        do {
            _ = try await client.archiveWorkspace(id: workspace.id)
            await loadStatus()
            return true
        } catch let error as ConductorError {
            actionError = error
            return false
        } catch {
            actionError = .transport(message: error.localizedDescription)
            return false
        }
    }

    func clearActionError() {
        actionError = nil
    }

    func addCreatedSession(_ session: Session) {
        if case .loaded(let sessions) = sessionsLoadable {
            sessionsLoadable = .loaded(sessions + [session])
        } else {
            sessionsLoadable = .loaded([session])
        }
    }
}
