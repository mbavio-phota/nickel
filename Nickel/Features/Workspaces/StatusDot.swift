import SwiftUI

/// Small colored dot conveying workspace/session status, with an animated pulse for
/// in-progress states — per the design direction, status is conveyed with dots + labels,
/// never loud banners.
struct StatusDot: View {
    let color: Color
    var isPulsing: Bool = false

    @State private var isPulseVisible = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? (isPulseVisible ? 1.0 : 0.4) : 1.0)
            .onAppear {
                guard isPulsing else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulseVisible = true
                }
            }
    }
}

extension WorkspaceStatusValue {
    var displayName: String {
        switch self {
        case .initializing: return "Initializing"
        case .ready: return "Ready"
        case .sleeping: return "Sleeping"
        case .archived: return "Archived"
        case .deleted: return "Deleted"
        case .updating: return "Updating"
        }
    }
}

extension SessionStatusValue {
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .error: return "Error"
        }
    }
}

extension WorkspaceLifecycleStep {
    var displayName: String {
        switch self {
        case .buildingSnapshot: return "Building snapshot"
        case .preparing: return "Preparing"
        case .settingUp: return "Setting up"
        case .updating: return "Updating"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(WorkspaceStatusValue.allCases, id: \.self) { status in
            HStack {
                StatusDot(color: Theme.color(for: status), isPulsing: Theme.isTransitioning(status))
                Text(status.displayName)
            }
        }
    }
    .padding()
}
