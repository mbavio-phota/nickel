import Foundation
import Observation

/// Drives a single project's workspace list: initial load, refresh, pagination, and a
/// per-workspace status cache so each row can fetch its own live status lazily without
/// refetching every time the list re-renders.
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
        } catch let error as ConductorError {
            loadable = .failed(error)
        } catch {
            loadable = .failed(.transport(message: error.localizedDescription))
        }
    }

    func loadMoreIfNeeded(currentItem workspace: Workspace) async {
        guard hasMore, !isLoadingMore, workspace.id == workspaces.last?.id else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.listWorkspaces(projectId: project.id, limit: pageSize, offset: workspaces.count)
            loadable = .loaded(workspaces + page.data)
            hasMore = page.hasMore
        } catch {
            hasMore = false
        }
    }

    /// Fetches a single workspace's live status, caching the result so the row doesn't
    /// refetch on every body re-evaluation. Call from the row's `.task`.
    func loadStatusIfNeeded(for workspaceId: String) async {
        guard statusesById[workspaceId] == nil else {
            return
        }
        if let status = try? await client.getWorkspaceStatus(id: workspaceId) {
            statusesById[workspaceId] = status
        }
    }

    func prependNewWorkspace(_ workspace: Workspace) {
        if case .loaded(let workspaces) = loadable {
            loadable = .loaded([workspace] + workspaces)
        } else {
            loadable = .loaded([workspace])
        }
    }
}
