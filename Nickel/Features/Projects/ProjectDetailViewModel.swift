import Foundation
import Observation

/// Drives a single project's workspace list: initial load, refresh, pagination, and a
/// per-workspace status cache. Statuses are fetched eagerly (concurrently) for every
/// listed workspace so archived ones can be grouped into their own collapsed section —
/// a hidden row can't lazily fetch the status that decides whether it's hidden.
@MainActor
@Observable
final class ProjectDetailViewModel {
    private(set) var loadable: Loadable<[Workspace]> = .idle
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    private(set) var statusesById: [String: WorkspaceStatus] = [:]

    let project: Project
    private let client: ConductorClient
    private let pageSize = 20

    init(project: Project, client: ConductorClient) {
        self.project = project
        self.client = client
    }

    var workspaces: [Workspace] {
        loadable.value ?? []
    }

    /// Workspaces shown in the main list: everything not known to be archived/deleted.
    /// A workspace with a still-loading status counts as active until proven otherwise.
    var activeWorkspaces: [Workspace] {
        workspaces.filter { !isArchived($0.id) }
    }

    /// Workspaces tucked into the collapsed "Archived" section.
    var archivedWorkspaces: [Workspace] {
        workspaces.filter { isArchived($0.id) }
    }

    private func isArchived(_ workspaceId: String) -> Bool {
        guard let status = statusesById[workspaceId]?.status else {
            return false
        }
        return status == .archived || status == .deleted
    }

    func loadInitial() async {
        guard loadable.value == nil else {
            return
        }
        await refresh()
    }

    func refresh() async {
        loadable = .loading
        do {
            let page = try await client.listWorkspaces(projectId: project.id, limit: pageSize, offset: nil)
            loadable = .loaded(page.data)
            hasMore = page.hasMore
            // Drop cached row statuses so the refreshed list re-fetches live ones.
            statusesById = [:]
            await loadStatuses(for: page.data)
        } catch let error as ConductorError {
            loadable = .failed(error)
        } catch {
            loadable = .failed(.transport(message: error.localizedDescription))
        }
    }

    /// Loads the next page. Triggered by a sentinel at the end of the list (grouping
    /// means the last *visible* row is no longer necessarily the last loaded workspace).
    func loadMoreIfNeeded() async {
        guard hasMore, !isLoadingMore else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.listWorkspaces(projectId: project.id, limit: pageSize, offset: workspaces.count)
            loadable = .loaded(workspaces + page.data)
            hasMore = page.hasMore
            await loadStatuses(for: page.data)
        } catch {
            hasMore = false
        }
    }

    /// Fetches a single workspace's live status, caching the result. Rows keep calling
    /// this from `.task` as a safety net; the eager path is `loadStatuses(for:)`.
    func loadStatusIfNeeded(for workspaceId: String) async {
        guard statusesById[workspaceId] == nil else {
            return
        }
        if let status = try? await client.getWorkspaceStatus(id: workspaceId) {
            statusesById[workspaceId] = status
        }
    }

    /// Concurrently fetches statuses for every workspace that doesn't have one yet.
    private func loadStatuses(for workspaces: [Workspace]) async {
        await withTaskGroup(of: Void.self) { group in
            for workspace in workspaces where statusesById[workspace.id] == nil {
                group.addTask { await self.loadStatusIfNeeded(for: workspace.id) }
            }
        }
    }

    func prependNewWorkspace(_ workspace: Workspace) {
        if case .loaded(let workspaces) = loadable {
            loadable = .loaded([workspace] + workspaces)
        } else {
            loadable = .loaded([workspace])
        }
        Task {
            await loadStatusIfNeeded(for: workspace.id)
        }
    }
}
