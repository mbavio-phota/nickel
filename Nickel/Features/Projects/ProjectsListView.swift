import SwiftUI

/// Root authenticated screen: all projects, each showing its name and git remote.
struct ProjectsListView: View {
    @Environment(AppSession.self) private var session
    @State private var viewModel: ProjectsListViewModel?
    @State private var isSettingsPresented = false

    var body: some View {
        content
            .navigationTitle("Projects")
            .toolbar {
                if session.isDemo {
                    ToolbarItem(placement: .topBarLeading) {
                        DemoBadge()
                    }
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
            .task {
                if viewModel == nil, let client = session.client {
                    viewModel = ProjectsListViewModel(client: client)
                }
                await viewModel?.loadInitial()
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
                    ContentUnavailableView(
                        "No projects yet",
                        systemImage: "folder",
                        description: Text("Projects you create on the Conductor Mac app will show up here.")
                    )
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
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func list(viewModel: ProjectsListViewModel) -> some View {
        List {
            ForEach(viewModel.projects) { project in
                NavigationLink(value: project) {
                    ProjectRow(project: project)
                }
                .task {
                    await viewModel.loadMoreIfNeeded(currentItem: project)
                }
            }

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refresh()
        }
        .navigationDestination(for: Project.self) { project in
            ProjectDetailView(project: project)
        }
    }
}

/// Subtle indicator that the app is showing mocked demo data rather than a live account.
private struct DemoBadge: View {
    var body: some View {
        Text("Demo")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1))
            .foregroundStyle(Theme.accent)
            .allowsHitTesting(false)
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .font(.body.weight(.medium))
            Text(project.gitRemote)
                .font(Theme.monospace(12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
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
