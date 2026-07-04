import SwiftUI

/// A single project's workspaces, with lazily-fetched status dots and a create-workspace
/// entry point.
struct ProjectDetailView: View {
    @Environment(AppSession.self) private var session
    let project: Project

    @State private var viewModel: ProjectDetailViewModel?
    @State private var isCreatePresented = false
    @State private var pushedWorkspace: Workspace?

    var body: some View {
        content
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatePresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New workspace")
                }
            }
            .sheet(isPresented: $isCreatePresented) {
                if let viewModel {
                    CreateWorkspaceView(project: project) { created in
                        viewModel.prependNewWorkspace(created)
                        pushedWorkspace = created
                    }
                }
            }
            .navigationDestination(item: $pushedWorkspace) { workspace in
                WorkspaceDetailView(workspace: workspace)
            }
            .task {
                if viewModel == nil, let client = session.client {
                    viewModel = ProjectDetailViewModel(project: project, client: client)
                }
                await viewModel?.loadInitial()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            switch viewModel.loadable {
            case .idle, .loading:
                if viewModel.workspaces.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(viewModel: viewModel)
                }
            case .loaded(let workspaces):
                if workspaces.isEmpty {
                    ContentUnavailableView {
                        Label("No workspaces yet", systemImage: "shippingbox")
                    } description: {
                        Text("Create a workspace to start an agent session on \(project.name).")
                    } actions: {
                        Button("New Workspace") {
                            isCreatePresented = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                } else {
                    list(viewModel: viewModel)
                }
            case .failed(let error):
                ContentUnavailableView {
                    Label("Couldn't load workspaces", systemImage: "exclamationmark.triangle")
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

    private func list(viewModel: ProjectDetailViewModel) -> some View {
        List {
            Section {
                Text(project.gitRemote)
                    .font(Theme.monospace(12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Workspaces") {
                ForEach(viewModel.workspaces) { workspace in
                    NavigationLink(value: workspace) {
                        WorkspaceRow(workspace: workspace, status: viewModel.statusesById[workspace.id])
                            .task {
                                await viewModel.loadStatusIfNeeded(for: workspace.id)
                            }
                    }
                    .task {
                        await viewModel.loadMoreIfNeeded(currentItem: workspace)
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
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refresh()
        }
        .navigationDestination(for: Workspace.self) { workspace in
            WorkspaceDetailView(workspace: workspace)
        }
    }
}

private struct WorkspaceRow: View {
    let workspace: Workspace
    let status: WorkspaceStatus?

    var body: some View {
        HStack(spacing: 12) {
            if let status {
                StatusDot(color: Theme.color(for: status.status), isPulsing: Theme.isTransitioning(status.status))
            } else {
                StatusDot(color: .secondary.opacity(0.3))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(workspace.name)
                    .font(.body.weight(.medium))
                if let createdDate = workspace.createdDate {
                    Text(createdDate, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(workspace.createdAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview("Demo") {
    let session = AppSession()
    session.enterDemo()
    return NavigationStack {
        ProjectDetailView(project: Project(id: "proj_retina", name: "retina", gitRemote: "git@github.com:photalabs/retina.git"))
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
        ProjectDetailView(project: Project(id: "proj_empty", name: "empty-project", gitRemote: "git@github.com:demo/empty.git"))
    }
    .environment(session)
}
