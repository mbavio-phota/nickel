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
    private(set) var sessionStatusesById: [String: SessionStatus] = [:]
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

    /// Sessions for display: working first, then error, then idle/unknown — most
    /// recently active first within each group, original order as the tiebreaker.
    var orderedSessions: [Session] {
        sessions.enumerated().sorted { lhs, rhs in
            let lhsRank = statusRank(lhs.element.id)
            let rhsRank = statusRank(rhs.element.id)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            let lhsUpdated = sessionStatusesById[lhs.element.id]?.updatedDate ?? .distantPast
            let rhsUpdated = sessionStatusesById[rhs.element.id]?.updatedDate ?? .distantPast
            if lhsUpdated != rhsUpdated {
                return lhsUpdated > rhsUpdated
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func statusRank(_ sessionId: String) -> Int {
        switch sessionStatusesById[sessionId]?.status {
        case .working:
            return 0
        case .error:
            return 1
        case .idle, nil:
            return 2
        }
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
            sessionStatusesById = [:]
            await loadSessionStatuses(for: page.data)
        } catch let error as ConductorError {
            sessionsLoadable = .failed(error)
        } catch {
            sessionsLoadable = .failed(.transport(message: error.localizedDescription))
        }
    }

    /// Loads the next page. Triggered by a sentinel at the end of the list (status
    /// ordering means the last visible card is not necessarily the last loaded session).
    func loadMoreSessionsIfNeeded() async {
        guard hasMoreSessions, !isLoadingMoreSessions else {
            return
        }
        isLoadingMoreSessions = true
        defer { isLoadingMoreSessions = false }

        do {
            let page = try await client.listSessions(workspaceId: workspace.id, limit: pageSize, offset: sessions.count)
            sessionsLoadable = .loaded(sessions + page.data)
            hasMoreSessions = page.hasMore
            await loadSessionStatuses(for: page.data)
        } catch {
            hasMoreSessions = false
        }
    }

    /// Fetches a single session's status, caching the result. Rows call this from
    /// `.task` as a safety net; the eager path is `loadSessionStatuses(for:)`.
    func loadSessionStatusIfNeeded(for sessionId: String) async {
        guard sessionStatusesById[sessionId] == nil else {
            return
        }
        if let status = try? await client.getSessionStatus(id: sessionId) {
            sessionStatusesById[sessionId] = status
        }
    }

    /// Concurrently fetches statuses for every session that doesn't have one yet.
    private func loadSessionStatuses(for sessions: [Session]) async {
        await withTaskGroup(of: Void.self) { group in
            for session in sessions where sessionStatusesById[session.id] == nil {
                group.addTask { await self.loadSessionStatusIfNeeded(for: session.id) }
            }
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
        Task {
            await loadSessionStatusIfNeeded(for: session.id)
        }
    }
}
