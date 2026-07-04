import SwiftUI

/// Workspace detail: a polling status card, the sessions list, and workspace-level
/// actions (rename, open on Mac, archive).
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
        .navigationTitle(viewModel?.workspace.name ?? workspace.name)
        .navigationBarTitleDisplayMode(.inline)
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
        List {
            Section {
                StatusCard(loadable: viewModel.statusLoadable)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            sessionsSection(viewModel: viewModel)

            if !viewModel.isArchived {
                actionsSection(viewModel: viewModel)
            } else {
                Section {
                    Label("Archived", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refreshAll()
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

    @ViewBuilder
    private func sessionsSection(viewModel: WorkspaceDetailViewModel) -> some View {
        Section {
            switch viewModel.sessionsLoadable {
            case .idle, .loading:
                if viewModel.sessions.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    sessionRows(viewModel: viewModel)
                }
            case .loaded(let sessions):
                if sessions.isEmpty {
                    Text("No sessions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    sessionRows(viewModel: viewModel)
                }
            case .failed(let error):
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.userMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.refreshSessions() }
                    }
                    .font(.footnote)
                }
            }
        } header: {
            HStack {
                Text("Sessions")
                Spacer()
                if !viewModel.isArchived {
                    Button {
                        isCreateSessionPresented = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .textCase(nil)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRows(viewModel: WorkspaceDetailViewModel) -> some View {
        ForEach(viewModel.sessions) { sessionItem in
            Button {
                pushedSession = sessionItem
            } label: {
                SessionRow(session: sessionItem)
            }
            .buttonStyle(.plain)
            .task {
                await viewModel.loadMoreSessionsIfNeeded(currentItem: sessionItem)
            }
        }

        if viewModel.isLoadingMoreSessions {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func actionsSection(viewModel: WorkspaceDetailViewModel) -> some View {
        Section("Actions") {
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
            .simultaneousGesture(TapGesture().onEnded {
                UIPasteboard.general.string = workspace.deepLink
            })

            Button(role: .destructive) {
                isArchiveConfirmPresented = true
            } label: {
                if viewModel.isArchiving {
                    HStack {
                        Text("Archive")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Label("Archive", systemImage: "archivebox")
                        .foregroundStyle(Theme.StatusColor.error)
                }
            }
            .disabled(viewModel.isArchiving)
        }
    }
}

private struct StatusCard: View {
    let loadable: Loadable<WorkspaceStatus>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch loadable {
            case .idle, .loading:
                HStack {
                    ProgressView()
                    Text("Loading status…")
                        .foregroundStyle(.secondary)
                }
            case .loaded(let status):
                HStack(spacing: 8) {
                    StatusDot(color: Theme.color(for: status.status), isPulsing: Theme.isTransitioning(status.status))
                    Text(status.status.displayName)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if let updatedDate = status.updatedDate {
                        Text(updatedDate, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lifecycleStep = status.lifecycleStep {
                    Text(lifecycleStep.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = status.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.StatusColor.error)
                }
            case .failed(let error):
                Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.StatusColor.error)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let model = session.model {
                    Text(model)
                        .font(Theme.monospace(12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

#Preview("Ready") {
    let session = AppSession()
    session.enterDemo()
    return NavigationStack {
        WorkspaceDetailView(workspace: Workspace(
            id: "ws_retina_1",
            name: "fix-vendor-cost-attribution",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-172_800)),
            deepLink: "conductor://workspace/ws_retina_1",
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
            id: "ws_mobile_1",
            name: "phase-1-scaffold",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1_200)),
            deepLink: "conductor://workspace/ws_mobile_1",
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
            id: "ws_site_1",
            name: "update-pricing-copy",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-2_592_000)),
            deepLink: "conductor://workspace/ws_site_1",
            creatorId: "user_demo"
        ))
    }
    .environment(session)
}
