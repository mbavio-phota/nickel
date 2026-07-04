import SwiftUI

/// First-run screen: paste a Conductor API key to sign in live, or explore with fully
/// mocked demo data. Keyboard-safe (scrolls the hero out of the way when the field is
/// focused) and renders the API's `userMessage` inline on a failed validation.
struct OnboardingView: View {
    @Environment(AppSession.self) private var session
    @State private var apiKey = ""
    @FocusState private var isKeyFieldFocused: Bool

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("API key")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    apiKeyField

                    if let error = session.signInError {
                        Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.StatusColor.error)
                    }

                    connectButton
                }
                .padding(.horizontal, 24)

                demoButton
                    .padding(.top, 4)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemBackground))
    }

    /// Brand-drenched welcome: the one screen where the cover art IS the surface.
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CoverArtView(seed: "nickel", palette: CoverArt.palettes[0])
            CoverScrim()
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Nickel")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)

                Text("Your Conductor agents, in your pocket. Monitor and manage fleets of coding agents from anywhere.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var apiKeyField: some View {
        HStack(spacing: 8) {
            SecureField("cond_...", text: $apiKey)
                .font(Theme.monospace(14))
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isKeyFieldFocused)

            Button {
                if let clipboardString = UIPasteboard.general.string {
                    apiKey = clipboardString
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Paste API key")
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var connectButton: some View {
        Button {
            isKeyFieldFocused = false
            Task { await session.signInLive(apiKey: trimmedKey) }
        } label: {
            HStack {
                Spacer()
                if session.isValidatingSignIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Connect")
                        .font(.headline)
                }
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(trimmedKey.isEmpty || session.isValidatingSignIn)
    }

    private var demoButton: some View {
        Button {
            isKeyFieldFocused = false
            session.enterDemo()
        } label: {
            Label("Explore with demo data", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Theme.accent.opacity(0.12), in: Capsule())
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview("Empty") {
    OnboardingView()
        .environment(AppSession())
}

#Preview("Error") {
    let session = AppSession(
        liveClientFactory: { _ in FailingPreviewClient() },
        demoClientFactory: { MockConductorClient() }
    )
    return OnboardingView()
        .environment(session)
        .task {
            await session.signInLive(apiKey: "cond_invalid")
        }
}

/// A `ConductorClient` that fails every call, for previewing error states without hitting
/// the network.
private actor FailingPreviewClient: ConductorClient {
    private let error = ConductorError.unauthorized(userMessage: "That API key doesn't look right. Check it and try again.")

    func listProjects(limit: Int?, offset: Int?) async throws -> Page<Project> { throw error }
    func getProject(id: String) async throws -> Project { throw error }
    func listWorkspaces(projectId: String, limit: Int?, offset: Int?) async throws -> Page<Workspace> { throw error }
    func createWorkspace(_ request: CreateWorkspaceRequest) async throws -> WorkspaceCreateResponse { throw error }
    func getWorkspace(id: String) async throws -> Workspace { throw error }
    func renameWorkspace(id: String, name: String) async throws -> Workspace { throw error }
    func archiveWorkspace(id: String) async throws -> WorkspaceArchiveResponse { throw error }
    func getWorkspaceStatus(id: String) async throws -> WorkspaceStatus { throw error }
    func listSessions(workspaceId: String, limit: Int?, offset: Int?) async throws -> Page<Session> { throw error }
    func createSession(_ request: CreateSessionRequest) async throws -> Session { throw error }
    func getSession(id: String) async throws -> Session { throw error }
    func renameSession(id: String, name: String) async throws -> Session { throw error }
    func getSessionStatus(id: String) async throws -> SessionStatus { throw error }
    func cancelSession(id: String) async throws -> SessionCancelResponse { throw error }
    func listMessages(sessionId: String, limit: Int?, offset: Int?) async throws -> Page<TranscriptMessage> { throw error }
    func sendMessage(sessionId: String, message: String, messageId: String?) async throws -> MessageCreateResponse { throw error }
    func getMessage(id: String) async throws -> TranscriptMessage { throw error }
}
