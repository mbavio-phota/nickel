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
    /// Set when a load-more request fails: pagination pauses behind an explicit Retry
    /// affordance instead of silently truncating the list.
    private(set) var loadMoreFailed = false

    private let client: ConductorClient
    private let pageSize = 20
    /// Bumped on every refresh; in-flight requests from an older generation discard
    /// their results instead of clobbering (or appending to) the fresher list.
    private var generation = 0

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
        generation += 1
        let requestGeneration = generation
        // Keep already-loaded rows on screen during pull-to-refresh — only show the
        // full-screen spinner when there is nothing to show yet.
        if loadable.value == nil {
            loadable = .loading
        }
        do {
            let page = try await client.listProjects(limit: pageSize, offset: nil)
            guard requestGeneration == generation else {
                return
            }
            loadable = .loaded(page.data)
            hasMore = page.hasMore
            loadMoreFailed = false
        } catch let error as ConductorError {
            guard requestGeneration == generation else {
                return
            }
            loadable = .failed(error)
        } catch {
            guard requestGeneration == generation else {
                return
            }
            loadable = .failed(.transport(message: error.localizedDescription))
        }
    }

    func loadMoreIfNeeded(currentItem project: Project) async {
        guard hasMore, !isLoadingMore, !loadMoreFailed, project.id == projects.last?.id else {
            return
        }
        await loadMore()
    }

    func retryLoadMore() async {
        guard hasMore, !isLoadingMore else {
            return
        }
        loadMoreFailed = false
        await loadMore()
    }

    private func loadMore() async {
        let requestGeneration = generation
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.listProjects(limit: pageSize, offset: projects.count)
            guard requestGeneration == generation else {
                return
            }
            loadable = .loaded(projects + page.data)
            hasMore = page.hasMore
        } catch {
            guard requestGeneration == generation else {
                return
            }
            loadMoreFailed = true
        }
    }
}
