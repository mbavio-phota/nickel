import SwiftUI

/// Top-level router: switches on `AppSession.state` between onboarding and the main
/// authenticated (live or demo) navigation stack.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .unauthenticated:
                OnboardingView()
            case .live, .demo:
                MainView()
            }
        }
    }
}

/// Main authenticated shell: the projects navigation stack. The demo indicator lives in
/// the projects screen's toolbar rather than a global overlay, so it never collides with
/// pushed screens' navigation titles.
private struct MainView: View {
    var body: some View {
        NavigationStack {
            ProjectsListView()
        }
    }
}

#Preview("Unauthenticated") {
    RootView()
        .environment(AppSession())
}

#Preview("Demo") {
    let session = AppSession()
    session.enterDemo()
    return RootView()
        .environment(session)
}
