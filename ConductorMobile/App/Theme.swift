import SwiftUI

/// Centralized color + typography constants from the design direction: a precise
/// developer-tool feel, SF Mono for identifiers, muted status dots rather than banners.
enum Theme {
    /// Conductor accent orange.
    static let accent = Color(red: 1.0, green: 0.361, blue: 0.039) // #FF5C0A

    /// Monospaced font for identifiers: branch names, git remotes, models, IDs.
    static func monospace(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    enum StatusColor {
        static let ready = Color.green
        static let transitioning = Color.orange // initializing / updating (animated pulse)
        static let sleeping = Color.indigo
        static let working = Color.orange
        static let idle = Color.secondary
        static let error = Color.red
        static let archived = Color.gray
    }

    /// Maps a workspace status to its display color, per the design direction.
    static func color(for status: WorkspaceStatusValue) -> Color {
        switch status {
        case .ready:
            return StatusColor.ready
        case .initializing, .updating:
            return StatusColor.transitioning
        case .sleeping:
            return StatusColor.sleeping
        case .archived:
            return StatusColor.archived
        case .deleted:
            return StatusColor.archived
        }
    }

    /// Maps a session status to its display color, per the design direction.
    static func color(for status: SessionStatusValue) -> Color {
        switch status {
        case .idle:
            return StatusColor.idle
        case .working:
            return StatusColor.working
        case .error:
            return StatusColor.error
        }
    }

    /// Whether this workspace status should render with the animated pulse treatment.
    static func isTransitioning(_ status: WorkspaceStatusValue) -> Bool {
        status == .initializing || status == .updating
    }
}
