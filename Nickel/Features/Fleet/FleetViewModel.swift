import Foundation
import Observation

/// One currently-active agent session resolved across every project the account can see:
/// the session itself, its live status, and the workspace/project it belongs to.
struct FleetEntry: Identifiable, Equatable {
    let session: Session
    let status: SessionStatus
    let workspace: Workspace
    let project: Project

    var id: String { session.id }
}

/// Drives the "Active now" strip on the projects screen: a bounded, concurrent scan of
/// projects → workspaces → sessions → statuses that keeps only sessions currently
/// `working` or `error` — the desktop app's at-a-glance fleet view, on the phone.
///
/// The scan is best-effort chrome: individual request failures drop that branch of the
/// tree rather than surfacing a second error state on a screen that already has one.
@MainActor
@Observable
final class FleetViewModel {
    private(set) var entries: [FleetEntry] = []
    /// True once the first scan completed (successfully or not) — before that the strip
    /// stays hidden instead of flashing an empty header.
    private(set) var hasLoaded = false

    private let client: ConductorClient
    private var isScanning = false

    /// Fan-out caps: one page of projects, the freshest workspaces overall, one page of
    /// sessions each. Keeps a worst-case live scan to a few dozen requests.
    private let projectLimit = 20
    private let workspacesPerProject = 10
    private let maxWorkspacesScanned = 30
    private let sessionsPerWorkspace = 10

    init(client: ConductorClient) {
        self.client = client
    }

    /// Full rescan of the fleet. On failure the previous entries stay put.
    func refresh() async {
        guard !isScanning else {
            return
        }
        isScanning = true
        defer {
            isScanning = false
            hasLoaded = true
        }

        guard let projects = try? await client.listProjects(limit: projectLimit, offset: nil).data else {
            return
        }

        let workspacePairs = await workspaces(for: projects)
        // Scan the freshest workspaces first — active agents live in recent workspaces.
        let scanned = workspacePairs
            .sorted { ($0.workspace.createdDate ?? .distantPast) > ($1.workspace.createdDate ?? .distantPast) }
            .prefix(maxWorkspacesScanned)

        let found = await activeEntries(in: Array(scanned))
        entries = Self.ordered(found)
    }

    /// Cheap between-scan poll: re-fetch only the statuses of sessions already in the
    /// strip, dropping ones that went idle. New activity is picked up by the next full
    /// `refresh()` (pull-to-refresh or reappear).
    func pollStatuses() async {
        guard !isScanning, !entries.isEmpty else {
            return
        }
        var refreshed: [FleetEntry] = []
        for entry in entries {
            guard let status = try? await client.getSessionStatus(id: entry.session.id) else {
                refreshed.append(entry)
                continue
            }
            if status.status != .idle {
                refreshed.append(FleetEntry(
                    session: entry.session,
                    status: status,
                    workspace: entry.workspace,
                    project: entry.project
                ))
            }
        }
        entries = Self.ordered(refreshed)
    }

    private struct WorkspacePair {
        let project: Project
        let workspace: Workspace
    }

    private func workspaces(for projects: [Project]) async -> [WorkspacePair] {
        await withTaskGroup(of: [WorkspacePair].self) { group in
            for project in projects {
                group.addTask { [client, workspacesPerProject] in
                    guard let page = try? await client.listWorkspaces(
                        projectId: project.id, limit: workspacesPerProject, offset: nil
                    ) else {
                        return []
                    }
                    return page.data.map { WorkspacePair(project: project, workspace: $0) }
                }
            }
            var pairs: [WorkspacePair] = []
            for await batch in group {
                pairs.append(contentsOf: batch)
            }
            return pairs
        }
    }

    private func activeEntries(in pairs: [WorkspacePair]) async -> [FleetEntry] {
        await withTaskGroup(of: [FleetEntry].self) { group in
            for pair in pairs {
                group.addTask { [client, sessionsPerWorkspace] in
                    guard let sessions = try? await client.listSessions(
                        workspaceId: pair.workspace.id, limit: sessionsPerWorkspace, offset: nil
                    ).data else {
                        return []
                    }
                    var found: [FleetEntry] = []
                    for session in sessions {
                        guard let status = try? await client.getSessionStatus(id: session.id),
                              status.status != .idle else {
                            continue
                        }
                        found.append(FleetEntry(
                            session: session,
                            status: status,
                            workspace: pair.workspace,
                            project: pair.project
                        ))
                    }
                    return found
                }
            }
            var entries: [FleetEntry] = []
            for await batch in group {
                entries.append(contentsOf: batch)
            }
            return entries
        }
    }

    /// Working sessions lead (they're the ones to watch), then errors to unblock; newest
    /// activity first within each group.
    private static func ordered(_ entries: [FleetEntry]) -> [FleetEntry] {
        entries.sorted { lhs, rhs in
            if lhs.status.status != rhs.status.status {
                return lhs.status.status == .working
            }
            return (lhs.status.updatedDate ?? .distantPast) > (rhs.status.updatedDate ?? .distantPast)
        }
    }
}
