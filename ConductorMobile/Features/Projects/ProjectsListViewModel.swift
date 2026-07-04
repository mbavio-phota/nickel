import Foundation
import Observation

/// Drives the projects list: initial load, pull-to-refresh, and offset-based infinite
/// scroll pagination.
@MainActor
@Observable
final class ProjectsListViewModel {
    private(set) var loadable: Loadable<[Project]> = .idle
    private(set) var hasMore = false
    private(set) var isLoadingMore = false

    private let client: ConductorClient
    private let pageSize = 20

    init(client: ConductorClient) {
        self.client = client
    }

    var projects: [Project] {
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
            let page = try await client.listProjects(limit: pageSize, offset: nil)
            loadable = .loaded(page.data)
            hasMore = page.hasMore
        } catch let error as ConductorError {
            loadable = .failed(error)
        } catch {
            loadable = .failed(.transport(message: error.localizedDescription))
        }
    }

    func loadMoreIfNeeded(currentItem project: Project) async {
        guard hasMore, !isLoadingMore, project.id == projects.last?.id else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.listProjects(limit: pageSize, offset: projects.count)
            loadable = .loaded(projects + page.data)
            hasMore = page.hasMore
        } catch {
            // Pagination failures are non-fatal — the list already visible stays put;
            // the user can retry by scrolling again.
            hasMore = false
        }
    }
}
