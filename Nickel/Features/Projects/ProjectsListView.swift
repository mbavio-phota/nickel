import SwiftUI

/// Root authenticated screen: the "Active now" fleet strip (every session currently
/// working or erroring, across all projects) above every project as a full-width
/// generated cover card — the content wears the color, the chrome stays quiet.
struct ProjectsListView: View {
    @Environment(AppSession.self) private var session
    @State private var viewModel: ProjectsListViewModel?
    @State private var fleetViewModel: FleetViewModel?
    @State private var isSettingsPresented = false
    @State private var isCreateFromURLPresented = false
    @State private var pushedWorkspace: Workspace?
    @State private var searchText = ""

    var body: some View {
        content
            .navigationTitle("Projects")
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                if session.isDemo {
                    ToolbarItem(placement: .topBarLeading) {
                        DemoBadge()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isCreateFromURLPresented = true
                        } label: {
                            Label("Workspace from repo URL", systemImage: "link.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
            }
            .sheet(isPresented: $isCreateFromURLPresented) {
                CreateWorkspaceView(project: nil) { workspace in
                    pushedWorkspace = workspace
                }
            }
            .navigationDestination(item: $pushedWorkspace) { workspace in
                WorkspaceDetailView(workspace: workspace)
            }
            .task {
                if viewModel == nil, let client = session.client {
                    viewModel = ProjectsListViewModel(client: client)
                    fleetViewModel = FleetViewModel(client: client)
                }
                async let projects: Void? = viewModel?.loadInitial()
                async let fleet: Void? = fleetViewModel?.refresh()
                _ = await (projects, fleet)
            }
            .task(id: fleetViewModel == nil) {
                guard let fleetViewModel else {
                    return
                }
                // Between full scans, keep the strip honest: re-check just the statuses
                // of the sessions already on it, so finished work drops off promptly.
                await poll(every: { .seconds(12) }, while: { true }) {
                    await fleetViewModel.pollStatuses()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            switch viewModel.loadable {
            case .idle, .loading:
                if viewModel.projects.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(viewModel: viewModel)
                }
            case .loaded(let projects):
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to conduct yet", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("Projects you create in Conductor on your Mac show up here — gradient covers included.")
                    }
                } else {
                    list(viewModel: viewModel)
                }
            case .failed(let error):
                ContentUnavailableView {
                    Label("Couldn't load projects", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.userMessage)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func filteredProjects(_ viewModel: ProjectsListViewModel) -> [Project] {
        guard isSearching else {
            return viewModel.projects
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return viewModel.projects.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.gitRemote.localizedCaseInsensitiveContains(query)
        }
    }

    private func list(viewModel: ProjectsListViewModel) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                // The fleet strip steps aside while searching — search is about finding
                // a project, not monitoring.
                if !isSearching, let fleetViewModel, !fleetViewModel.entries.isEmpty {
                    FleetStrip(entries: fleetViewModel.entries)
                        .padding(.bottom, 4)
                }

                let filtered = filteredProjects(viewModel)
                if isSearching && filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 40)
                }

                ForEach(filtered) { project in
                    NavigationLink(value: project) {
                        ProjectCoverCard(project: project)
                    }
                    .buttonStyle(PressableStyle())
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: project)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, 12)
                }

                if viewModel.loadMoreFailed {
                    Button {
                        Task { await viewModel.retryLoadMore() }
                    } label: {
                        Label("Couldn't load more — retry", systemImage: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .searchable(text: $searchText, prompt: "Search projects")
        .refreshable {
            async let projects: Void = viewModel.refresh()
            async let fleet: Void? = fleetViewModel?.refresh()
            _ = await (projects, fleet)
        }
        .navigationDestination(for: Project.self) { project in
            ProjectDetailView(project: project)
        }
        .navigationDestination(for: Session.self) { session in
            SessionDetailView(session: session)
        }
    }
}

/// Subtle indicator that the app is showing mocked demo data rather than a live account.
private struct DemoBadge: View {
    var body: some View {
        Text("Demo")
            .font(.caption2.weight(.semibold))
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
            .foregroundStyle(Theme.accent)
            .allowsHitTesting(false)
    }
}

/// Hypelist-style cover card: generated gradient art, project name and mono git remote
/// overlaid on a scrim.
private struct ProjectCoverCard: View {
    let project: Project

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverArtView(seed: project.id)
            CoverScrim()
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(project.gitRemote)
                    .font(Theme.monospace(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview("Demo") {
    let session = AppSession()
    session.enterDemo()
    return NavigationStack {
        ProjectsListView()
    }
    .environment(session)
}

#Preview("Empty") {
    let session = AppSession(
        liveClientFactory: { _ in MockConductorClient() },
        demoClientFactory: { EmptyPreviewClient() }
    )
    session.enterDemo()
    return NavigationStack {
        ProjectsListView()
    }
    .environment(session)
}
