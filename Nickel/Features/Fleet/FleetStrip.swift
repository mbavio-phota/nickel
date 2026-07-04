import SwiftUI

/// "Active now" — a horizontally scrolling strip of the sessions currently working or
/// erroring anywhere in the account, one tap from their chat. The phone-sized version of
/// the desktop app's at-a-glance fleet view. Hidden entirely while the fleet is quiet.
struct FleetStrip: View {
    let entries: [FleetEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Active now")
                    .font(.headline)
                Text("\(entries.count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(entries) { entry in
                        NavigationLink(value: entry.session) {
                            FleetSessionCard(entry: entry)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active now: \(entries.count) session\(entries.count == 1 ? "" : "s")")
    }
}

/// Compact cover card for one active session: the workspace's cover art (matching its
/// detail header), the live status chip, and where the session lives.
private struct FleetSessionCard: View {
    let entry: FleetEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverArtView(seed: entry.workspace.id)
            CoverScrim()
            VStack(alignment: .leading, spacing: 4) {
                StatusChip(
                    color: chipColor,
                    label: chipLabel,
                    isPulsing: entry.status.status == .working,
                    onCover: true
                )
                Spacer(minLength: 0)
                Text(entry.session.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(entry.project.name) / \(entry.workspace.name)")
                    .font(Theme.monospace(11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 216, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(chipLabel): \(entry.session.displayName), workspace \(entry.workspace.name), project \(entry.project.name)"
        )
    }

    private var chipColor: Color {
        entry.status.status == .working ? Theme.StatusColor.working : Theme.StatusColor.error
    }

    private var chipLabel: String {
        entry.status.status == .working ? "Working" : "Error"
    }
}

#Preview("Strip") {
    let workspace = Workspace(
        id: "ws_neb_2", name: "free-the-mind", createdAt: "2026-07-01T10:00:00Z",
        deepLink: "conductor://workspace/ws_neb_2", creatorId: nil
    )
    let project = Project(
        id: "proj_neb", name: "nebuchadnezzar",
        gitRemote: "git@github.com:zion-fleet/nebuchadnezzar.git"
    )
    return NavigationStack {
        ScrollView {
            FleetStrip(entries: [
                FleetEntry(
                    session: Session(id: "sess_1", deepLink: "", name: "Follow the white rabbit", model: nil),
                    status: SessionStatus(
                        workspaceId: "ws_neb_2", sessionId: "sess_1", status: .working,
                        updatedAt: "2026-07-01T10:05:00Z", errorMessage: nil
                    ),
                    workspace: workspace,
                    project: project
                ),
                FleetEntry(
                    session: Session(id: "sess_2", deepLink: "", name: "Debug the Sentinel swarm", model: nil),
                    status: SessionStatus(
                        workspaceId: "ws_neb_2", sessionId: "sess_2", status: .error,
                        updatedAt: "2026-07-01T09:00:00Z", errorMessage: "Connection severed."
                    ),
                    workspace: workspace,
                    project: project
                ),
            ])
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
