import SwiftUI

// Shared design-system components for the expressive shell: status chips, the floating
// action pill, cover headers, and card surfaces. Vocabulary is defined in DESIGN.md —
// one look per concept, reused on every screen.

/// Status as a capsule chip: colored dot plus the status word. Status is never conveyed
/// by color alone (PRODUCT.md, accessibility).
struct StatusChip: View {
    let color: Color
    let label: String
    var isPulsing = false
    /// Material variant for placement on cover art.
    var onCover = false

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: color, isPulsing: isPulsing)
            Text(label)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            onCover ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(color.opacity(0.16)),
            in: Capsule()
        )
        .foregroundStyle(onCover ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

/// Identifier chip for cover overlays (git remote, branch, model): SF Mono on material.
struct MonoChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.monospace(12))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
    }
}

/// The screen's single primary action, floating bottom-center: an adaptive
/// black-on-light / white-on-dark capsule with the accent-colored icon. At most one per
/// screen.
struct FloatingActionPill: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Color.primary, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Immersive detail header: cover art with the entity name and metadata overlaid on a
/// scrim. Screens using it clear their navigation title — this IS the title.
struct CoverHeader<Meta: View>: View {
    let seed: String
    let title: String
    var height: CGFloat = 220
    @ViewBuilder var meta: Meta

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverArtView(seed: seed)
            CoverScrim()
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                meta
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// 150ms press-scale feedback for cards and pills. Disabled under Reduce Motion.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// Standard card surface: secondary grouped background, 16pt continuous radius, soft
    /// shadow (invisible in dark mode by design).
    func cardSurface(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
    }
}

#Preview("Components") {
    ZStack(alignment: .bottom) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CoverHeader(seed: "proj_neb", title: "nebuchadnezzar") {
                    MonoChip(text: "git@github.com:zion-fleet/nebuchadnezzar.git")
                }

                HStack {
                    StatusChip(color: Theme.StatusColor.ready, label: "Ready")
                    StatusChip(color: Theme.StatusColor.transitioning, label: "Initializing", isPulsing: true)
                    StatusChip(color: Theme.StatusColor.error, label: "Error")
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("free-the-mind").font(.headline)
                        Text("2 days ago").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusChip(color: Theme.StatusColor.ready, label: "Ready")
                }
                .padding(16)
                .cardSurface()
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))

        FloatingActionPill(title: "New Workspace", systemImage: "plus") {}
            .padding(.bottom, 12)
    }
}
