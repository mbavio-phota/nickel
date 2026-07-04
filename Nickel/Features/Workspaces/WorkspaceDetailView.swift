import SwiftUI

/// Workspace detail: immersive cover header with the live status chip overlaid, session
/// cards, a floating "New Session" pill, and workspace actions in the toolbar menu.
struct WorkspaceDetailView: View {
    @Environment(AppSession.self) private var session
    let workspace: Workspace

    @State private var viewModel: WorkspaceDetailViewModel?
    @State private var isCreateSessionPresented = false
    @State private var isRenamePresented = false
    @State private var renameText = ""
    @State private var isArchiveConfirmPresented = false
    @State private var pushedSession: Session?

    var body: some View {
        Group {
            if let viewModel {
                loadedBody(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The cover header carries the title; the bar keeps only back + actions.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .task {
            if viewModel == nil, let client = session.client {
                viewModel = WorkspaceDetailViewModel(workspace: workspace, client: client)
            }
            await viewModel?.loadSessionsInitial()
        }
        .task(id: viewModel == nil) {
            guard let viewModel else {
                return
            }
            await poll(every: .seconds(5), while: { viewModel.shouldPollStatus }) {
                await viewModel.loadStatus()
            }
        }
        .navigationDestination(item: $pushedSession) { sessionItem in
            SessionDetailView(session: sessionItem)
        }
    }

    @ViewBuilder
    private func loadedBody(viewModel: WorkspaceDetailViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header(viewModel: viewModel)

                if case .loaded(let status) = viewModel.statusLoadable, let errorMessage = status.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.StatusColor.error)
                }
                if case .failed(let error) = viewModel.statusLoadable {
                    Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.StatusColor.error)
                }

                Text("Sessions")
                    .font(.title3.bold())
                    .padding(.top, 8)

                sessionsContent(viewModel: viewModel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .refreshable {
            await viewModel.refreshAll()
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.isArchived {
                FloatingActionPill(title: "New Session", systemImage: "plus") {
                    isCreateSessionPresented = true
                }
                .padding(.bottom, 8)
                .accessibilityLabel("New session")
            }
        }
        .toolbar {
            if !viewModel.isArchived {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            renameText = viewModel.workspace.name
                            isRenamePresented = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .disabled(viewModel.isRenaming)

                        ShareLink(item: workspace.deepLink) {
                            Label("Open on Mac", systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            isArchiveConfirmPresented = true
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .disabled(viewModel.isArchiving)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Workspace actions")
                }
            }
        }
        .sheet(isPresented: $isCreateSessionPresented) {
            CreateSessionView(workspaceId: workspace.id) { created in
                viewModel.addCreatedSession(created)
            }
        }
        .alert("Rename Workspace", isPresented: $isRenamePresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task { _ = await viewModel.rename(to: renameText) }
            }
        }
        .confirmationDialog(
            "Archive this workspace?",
            isPresented: $isArchiveConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                Task { _ = await viewModel.archive() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can still view it, but it can no longer run agent sessions.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearActionError()
                    }
                }
            ),
            presenting: viewModel.actionError
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.userMessage)
        }
    }

    private func header(viewModel: WorkspaceDetailViewModel) -> some View {
        CoverHeader(seed: workspace.id, title: viewModel.workspace.name, height: 240) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    statusChip(viewModel: viewModel)
                    if case .loaded(let status) = viewModel.statusLoadable, let updatedDate = status.updatedDate {
                        Text(updatedDate, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                if case .loaded(let status) = viewModel.statusLoadable, let lifecycleStep = status.lifecycleStep {
                    Text(lifecycleStep.displayName)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    @ViewBuilder
    private func statusChip(viewModel: WorkspaceDetailViewModel) -> some View {
        switch viewModel.statusLoadable {
        case .idle, .loading:
            StatusChip(color: .white.opacity(0.5), label: "Loading…", onCover: true)
        case .loaded(let status):
            StatusChip(
                color: Theme.color(for: status.status),
                label: status.status.displayName,
                isPulsing: Theme.isTransitioning(status.status),
                onCover: true
            )
        case .failed:
            StatusChip(color: Theme.StatusColor.error, label: "Unavailable", onCover: true)
        }
    }

    @ViewBuilder
    private func sessionsContent(viewModel: WorkspaceDetailViewModel) -> some View {
        switch viewModel.sessionsLoadable {
        case .idle, .loading:
            if viewModel.sessions.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                sessionCards(viewModel: viewModel)
            }
        case .loaded(let sessions):
            if sessions.isEmpty {
                VStack(spacing: 6) {
                    Text(viewModel.isArchived ? "All quiet in the archive" : "No one's talking yet")
                        .font(.headline)
                    Text(viewModel.isArchived
                        ? "This workspace is retired — its transcripts stay readable."
                        : "Start a session and give an agent something to chew on.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                sessionCards(viewModel: viewModel)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Text(error.userMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await viewModel.refreshSessions() }
                }
                .font(.footnote.weight(.semibold))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    @ViewBuilder
    private func sessionCards(viewModel: WorkspaceDetailViewModel) -> some View {
        ForEach(viewModel.orderedSessions) { sessionItem in
            Button {
                pushedSession = sessionItem
            } label: {
                SessionCard(session: sessionItem, status: viewModel.sessionStatusesById[sessionItem.id])
            }
            .buttonStyle(PressableStyle())
            .task {
                await viewModel.loadSessionStatusIfNeeded(for: sessionItem.id)
            }
        }

        if viewModel.isLoadingMoreSessions {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }

        // Pagination sentinel: with status ordering, the last visible card is not
        // necessarily the last loaded session.
        if viewModel.hasMoreSessions {
            Color.clear
                .frame(height: 1)
                .task {
                    await viewModel.loadMoreSessionsIfNeeded()
                }
        }
    }
}

private struct SessionCard: View {
    let session: Session
    let status: SessionStatus?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let model = session.model {
                    Text(model)
                        .font(Theme.monospace(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let status {
                StatusChip(
                    color: Theme.color(for: status.status),
                    label: status.status.displayName,
                    isPulsing: status.status == .working
                )
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

#Preview("Ready") {
    let session = AppSession()
    session.enterDemo()
    return NavigationStack {
        WorkspaceDetailView(workspace: Workspace(
            id: "ws_neb_1",
            name: "free-the-mind",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-172_800)),
            deepLink: "conductor://workspace/ws_neb_1",
            creatorId: "user_demo"
        ))
    }
    .environment(session)
}

#Preview("Initializing") {
    let session = AppSession()
    session.enterDemo()
    return NavigationStack {
        WorkspaceDetailView(workspace: Workspace(
            id: "ws_construct_1",
            name: "guns-lots-of-guns",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1_200)),
            deepLink: "conductor://workspace/ws_construct_1",
            creatorId: "user_demo"
        ))
    }
    .environment(session)
}

#Preview("Archived") {
    let session = AppSession()
    session.enterDemo()
    return NavigationStack {
        WorkspaceDetailView(workspace: Workspace(
            id: "ws_zion_1",
            name: "dock-defense-turrets",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2_592_000)),
            deepLink: "conductor://workspace/ws_zion_1",
            creatorId: "user_demo"
        ))
    }
    .environment(session)
}
