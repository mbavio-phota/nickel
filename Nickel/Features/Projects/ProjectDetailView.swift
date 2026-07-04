import SwiftUI

/// A single project: immersive cover header, workspace cards with lazily-fetched status
/// chips, and a floating "New Workspace" pill.
struct ProjectDetailView: View {
    @Environment(AppSession.self) private var session
    let project: Project

    @State private var viewModel: ProjectDetailViewModel?
    @State private var isCreatePresented = false
    @State private var pushedWorkspace: Workspace?
    @State private var isArchivedExpanded = false

    var body: some View {
        content
            // The cover header carries the title; the bar stays a bare back button.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                FloatingActionPill(title: "New Workspace", systemImage: "plus") {
                    isCreatePresented = true
                }
                .padding(.bottom, 8)
                .accessibilityLabel("New workspace")
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
                    scroll(viewModel: viewModel, isEmpty: false)
                }
            case .loaded(let workspaces):
                scroll(viewModel: viewModel, isEmpty: workspaces.isEmpty)
            case .failed(let error):
                ContentUnavailableView {
                    Label("Couldn't load workspaces", systemImage: "exclamationmark.triangle")
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

    private func scroll(viewModel: ProjectDetailViewModel, isEmpty: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                CoverHeader(seed: project.id, title: project.name) {
                    MonoChip(text: project.gitRemote)
                }

                Text("Workspaces")
                    .font(.title3.bold())
                    .padding(.top, 8)

                if isEmpty {
                    VStack(spacing: 6) {
                        Text("This project is quiet")
                            .font(.headline)
                        Text("Spin up a workspace and put an agent to work on \(project.name).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(viewModel.activeWorkspaces) { workspace in
                        workspaceLink(workspace, viewModel: viewModel)
                    }

                    if viewModel.activeWorkspaces.isEmpty {
                        Text("No active workspaces.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }

                    // Pagination sentinel: with the list grouped, "last visible card"
                    // no longer means "last loaded workspace".
                    if viewModel.hasMore {
                        Color.clear
                            .frame(height: 1)
                            .task {
                                await viewModel.loadMoreIfNeeded()
                            }
                    }

                    if !viewModel.archivedWorkspaces.isEmpty {
                        archivedSection(viewModel: viewModel)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .navigationDestination(for: Workspace.self) { workspace in
            WorkspaceDetailView(workspace: workspace)
        }
    }

    private func workspaceLink(_ workspace: Workspace, viewModel: ProjectDetailViewModel) -> some View {
        NavigationLink(value: workspace) {
            WorkspaceCard(workspace: workspace, status: viewModel.statusesById[workspace.id])
                .task {
                    await viewModel.loadStatusIfNeeded(for: workspace.id)
                }
        }
        .buttonStyle(PressableStyle())
    }

    /// Collapsed-by-default home for archived workspaces, below the active list.
    @ViewBuilder
    private func archivedSection(viewModel: ProjectDetailViewModel) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                isArchivedExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .font(.subheadline)
                Text("Archived")
                    .font(.subheadline.weight(.medium))
                Text("\(viewModel.archivedWorkspaces.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isArchivedExpanded ? 180 : 0))
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .accessibilityLabel("Archived workspaces, \(viewModel.archivedWorkspaces.count)")

        if isArchivedExpanded {
            ForEach(viewModel.archivedWorkspaces) { workspace in
                workspaceLink(workspace, viewModel: viewModel)
                    .opacity(0.75)
            }
        }
    }
}

private struct WorkspaceCard: View {
    let workspace: Workspace
    let status: WorkspaceStatus?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(workspace.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
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

            Spacer(minLength: 8)

            if let status {
                StatusChip(
                    color: Theme.color(for: status.status),
                    label: status.status.displayName,
                    isPulsing: Theme.isTransitioning(status.status)
                )
            } else {
                StatusChip(color: .secondary.opacity(0.4), label: "—")
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .contentShape(Rectangle())
    }
}

#Preview("Demo") {
    let session = AppSession()
    session.enterDemo()
    return NavigationStack {
        ProjectDetailView(project: Project(id: "proj_neb", name: "nebuchadnezzar", gitRemote: "git@github.com:zion-fleet/nebuchadnezzar.git"))
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
