import SwiftUI

/// The chat centerpiece: message transcript, status pill, cancel button while working,
/// and a pinned composer. Auto-scrolls to the newest message and polls status/messages
/// at a cadence that speeds up while the agent is working.
struct SessionDetailView: View {
    @Environment(AppSession.self) private var appSession
    let session: Session

    @State private var viewModel: SessionDetailViewModel?
    @State private var draft = ""
    @State private var isRenamePresented = false
    @State private var renameText = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        Group {
            if let viewModel {
                loadedBody(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle((viewModel?.session ?? session).displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        renameText = viewModel?.session.name ?? ""
                        isRenamePresented = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Session", isPresented: $isRenamePresented) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task { _ = await viewModel?.rename(to: renameText) }
            }
        }
        .task {
            if viewModel == nil, let client = appSession.client {
                viewModel = SessionDetailViewModel(session: session, client: client)
            }
            await viewModel?.loadInitial()
        }
        .task(id: viewModel?.isWorking) {
            guard let viewModel else {
                return
            }
            await poll(every: viewModel.pollInterval, while: { true }) {
                await viewModel.pollStatusAndMessages()
            }
        }
    }

    @ViewBuilder
    private func loadedBody(viewModel: SessionDetailViewModel) -> some View {
        VStack(spacing: 0) {
            StatusPill(loadable: viewModel.statusLoadable, isCanceling: viewModel.isCanceling) {
                Task { await viewModel.cancel() }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            transcript(viewModel: viewModel)

            if let sendError = viewModel.sendError {
                Label(sendError.userMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.StatusColor.error)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
            }

            Composer(
                text: $draft,
                isSending: viewModel.isSending,
                isFocused: $isComposerFocused
            ) {
                let toSend = draft
                draft = ""
                Task { await viewModel.send(toSend) }
            }
        }
    }

    private func transcript(viewModel: SessionDetailViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    switch viewModel.messagesLoadable {
                    case .idle, .loading:
                        if viewModel.messages.isEmpty {
                            ProgressView()
                                .padding(.top, 40)
                        }
                    case .failed(let error):
                        ContentUnavailableView {
                            Label("Couldn't load messages", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error.userMessage)
                        } actions: {
                            Button("Retry") {
                                Task { await viewModel.refreshMessages() }
                            }
                        }
                        .padding(.top, 40)
                    case .loaded(let messages):
                        if messages.isEmpty {
                            ContentUnavailableView(
                                "The agent is listening",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("Send a message to put it to work.")
                            )
                            .padding(.top, 40)
                        }
                    }

                    ForEach(viewModel.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }

                    if viewModel.isWorking {
                        WorkingIndicator()
                            .id("working-indicator")
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy: proxy, viewModel: viewModel)
            }
            .onChange(of: viewModel.isWorking) {
                scrollToBottom(proxy: proxy, viewModel: viewModel)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, viewModel: viewModel, animated: false)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, viewModel: SessionDetailViewModel, animated: Bool = true) {
        let anchorId: String? = viewModel.isWorking ? "working-indicator" : viewModel.messages.last?.id
        guard let anchorId else {
            return
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(anchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(anchorId, anchor: .bottom)
        }
    }
}

private struct StatusPill: View {
    let loadable: Loadable<SessionStatus>
    let isCanceling: Bool
    var onCancel: () -> Void

    var body: some View {
        HStack {
            switch loadable {
            case .idle, .loading:
                StatusChip(color: .secondary.opacity(0.4), label: "Loading…")
            case .loaded(let status):
                StatusChip(
                    color: Theme.color(for: status.status),
                    label: status.status.displayName,
                    isPulsing: status.status == .working
                )
                if status.status == .working {
                    WorkingDotsText()
                }
                if let errorMessage = status.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.StatusColor.error)
                        .lineLimit(1)
                }
            case .failed(let error):
                StatusChip(color: Theme.StatusColor.error, label: "Unavailable")
                Text(error.userMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.StatusColor.error)
                    .lineLimit(1)
            }

            Spacer()

            if case .loaded(let status) = loadable, status.status == .working {
                Button {
                    onCancel()
                } label: {
                    if isCanceling {
                        ProgressView()
                    } else {
                        Text("Cancel")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .disabled(isCanceling)
            }
        }
    }
}

/// Simple animated "…" suffix while the agent is working. Uses a `.task`-scoped loop so
/// the animation stops automatically when the view disappears.
private struct WorkingDotsText: View {
    @State private var dotCount = 1

    var body: some View {
        Text(String(repeating: ".", count: dotCount))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else {
                        return
                    }
                    dotCount = dotCount % 3 + 1
                }
            }
    }
}

private struct WorkingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Agent is working…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

private struct Composer: View {
    @Binding var text: String
    let isSending: Bool
    var isFocused: FocusState<Bool>.Binding
    var onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .focused(isFocused)

            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Theme.accent : Color.secondary.opacity(0.4))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview("Active transcript") {
    let appSession = AppSession()
    appSession.enterDemo()
    return NavigationStack {
        SessionDetailView(session: Session(
            id: "sess_neb_1",
            deepLink: "conductor://session/sess_neb_1",
            name: "Follow the white rabbit",
            model: "claude-opus-4.6"
        ))
    }
    .environment(appSession)
}

#Preview("Working") {
    let appSession = AppSession()
    appSession.enterDemo()
    return NavigationStack {
        SessionDetailView(session: Session(
            id: "sess_neb_2a",
            deepLink: "conductor://session/sess_neb_2a",
            name: "Operator uplink",
            model: "claude-sonnet-5"
        ))
    }
    .environment(appSession)
}

#Preview("Error status") {
    let appSession = AppSession()
    appSession.enterDemo()
    return NavigationStack {
        SessionDetailView(session: Session(
            id: "sess_construct_2",
            deepLink: "conductor://session/sess_construct_2",
            name: "Trace the black cat glitch",
            model: "codex-5"
        ))
    }
    .environment(appSession)
}
