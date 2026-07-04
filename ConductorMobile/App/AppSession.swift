import Foundation
import Observation

/// App-wide authentication state: unauthenticated, signed in with a live API key, or
/// exploring in fully-mocked demo mode. Injected into the environment at the app root.
@MainActor
@Observable
final class AppSession {
    enum State {
        case unauthenticated
        case live(ConductorClient)
        case demo(ConductorClient)
    }

    private(set) var state: State = .unauthenticated
    private(set) var isValidatingSignIn = false
    private(set) var signInError: ConductorError?

    private let keychain: KeychainStore
    /// Factory so tests can inject a stub client instead of hitting the network.
    private let liveClientFactory: @Sendable (@escaping @Sendable () -> String?) -> ConductorClient
    private let demoClientFactory: @Sendable () -> ConductorClient

    /// The signed-in API key, if any client is active and it was constructed from one.
    private var apiKey: String?

    init(
        keychain: KeychainStore = KeychainStore(),
        liveClientFactory: @escaping @Sendable (@escaping @Sendable () -> String?) -> ConductorClient = { tokenProvider in
            LiveConductorClient(tokenProvider: tokenProvider)
        },
        demoClientFactory: @escaping @Sendable () -> ConductorClient = { MockConductorClient() }
    ) {
        self.keychain = keychain
        self.liveClientFactory = liveClientFactory
        self.demoClientFactory = demoClientFactory

        if let storedKey = (try? keychain.read()) ?? nil {
            apiKey = storedKey
            state = .live(liveClientFactory { storedKey })
        }
    }

    /// Validates the API key with a live call (projects list, limit 1) before persisting
    /// it to Keychain. Leaves state unchanged and surfaces `signInError` on failure.
    func signInLive(apiKey: String) async {
        isValidatingSignIn = true
        signInError = nil
        defer { isValidatingSignIn = false }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateClient = liveClientFactory { trimmedKey }

        do {
            _ = try await candidateClient.listProjects(limit: 1, offset: nil)
        } catch let error as ConductorError {
            signInError = error
            return
        } catch {
            signInError = .transport(message: error.localizedDescription)
            return
        }

        do {
            try keychain.save(trimmedKey)
        } catch {
            signInError = .transport(message: "Signed in, but couldn't save the key to Keychain: \(error.localizedDescription)")
            return
        }

        self.apiKey = trimmedKey
        state = .live(candidateClient)
    }

    /// Enters fully-mocked demo mode. No network calls, no Keychain writes.
    func enterDemo() {
        state = .demo(demoClientFactory())
    }

    /// Wipes the Keychain and returns to the unauthenticated state.
    func signOut() {
        try? keychain.delete()
        apiKey = nil
        signInError = nil
        state = .unauthenticated
    }

    /// The active client for API calls, or `nil` when unauthenticated.
    var client: ConductorClient? {
        switch state {
        case .unauthenticated:
            return nil
        case .live(let client), .demo(let client):
            return client
        }
    }

    /// Whether the current session is the fully-mocked demo mode.
    var isDemo: Bool {
        if case .demo = state {
            return true
        }
        return false
    }

    /// A masked representation of the stored API key, for Settings display.
    var maskedApiKey: String? {
        guard let apiKey, apiKey.count > 4 else {
            return apiKey.map { _ in "••••" }
        }
        let suffix = apiKey.suffix(4)
        return "••••\(suffix)"
    }
}
