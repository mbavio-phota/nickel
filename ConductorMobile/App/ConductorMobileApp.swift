import SwiftUI

@main
struct ConductorMobileApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.accent)
        }
    }
}
