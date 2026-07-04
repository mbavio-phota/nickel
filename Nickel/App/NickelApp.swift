import SwiftUI

@main
struct NickelApp: App {
    @State private var session: AppSession

    init() {
        // UI tests need a deterministic first-run state regardless of any API key the
        // simulator's Keychain already holds. Must run before AppSession's init, which
        // restores the stored key.
        if CommandLine.arguments.contains("--uitest-reset-state") {
            try? KeychainStore().delete()
        }
        _session = State(initialValue: AppSession())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.accent)
        }
    }
}
