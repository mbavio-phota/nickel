import SwiftUI

/// Deterministic generated cover art: every project and workspace gets its own duotone
/// gradient cover, seeded by its id, so the same entity always renders the same cover —
/// no assets, no network. The content wears the color; the chrome stays quiet (DESIGN.md).
enum CoverArt {
    struct Palette {
        let start: Color
        let end: Color
        let glow: Color
    }

    /// Dark-leaning saturated duotones chosen so white, scrim-backed text stays legible.
    static let palettes: [Palette] = [
        // Ember — the brand anchor.
        Palette(start: Color(0xFF5C0A), end: Color(0xB0246E), glow: Color(0xFFB38A)),
        // Magma.
        Palette(start: Color(0xD93A17), end: Color(0xF58A1F), glow: Color(0xFFD9A8)),
        // Indigo to cyan.
        Palette(start: Color(0x3949AB), end: Color(0x00A6C0), glow: Color(0x7FE3F0)),
        // Violet to pink.
        Palette(start: Color(0x5E35B1), end: Color(0xE84A7F), glow: Color(0xFFB3C7)),
        // Teal to green.
        Palette(start: Color(0x00695C), end: Color(0x43A047), glow: Color(0xB9F6CA)),
        // Blue to aqua.
        Palette(start: Color(0x1565C0), end: Color(0x26C6DA), glow: Color(0xB2EBF2)),
        // Graphite to ember — the terminal cover.
        Palette(start: Color(0x263238), end: Color(0xE64A19), glow: Color(0xFF8A65)),
    ]

    /// FNV-1a. Stable across launches, unlike `Hasher`.
    static func hash(_ seed: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func palette(for seed: String) -> Palette {
        palettes[Int(hash(seed) % UInt64(palettes.count))]
    }
}

/// The art itself: duotone linear base plus a radial glow whose center is also derived
/// from the seed, so covers differ in composition as well as hue.
struct CoverArtView: View {
    let seed: String
    /// Explicit palette override for fixed-brand placements (onboarding hero).
    var palette: CoverArt.Palette?

    var body: some View {
        let resolved = palette ?? CoverArt.palette(for: seed)
        let hash = CoverArt.hash(seed)
        let glowX = 0.15 + Double((hash >> 8) % 1000) / 1000 * 0.7
        let glowY = Double((hash >> 24) % 1000) / 1000 * 0.45
        let diagonal = (hash >> 40) % 2 == 0

        ZStack {
            LinearGradient(
                colors: [resolved.start, resolved.end],
                startPoint: diagonal ? .topLeading : .top,
                endPoint: diagonal ? .bottomTrailing : .bottom
            )
            RadialGradient(
                colors: [resolved.glow.opacity(0.55), .clear],
                center: UnitPoint(x: glowX, y: glowY),
                startRadius: 0,
                endRadius: 280
            )
        }
    }
}

/// Bottom-up black scrim guaranteeing contrast for text overlaid on cover art.
struct CoverScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .black.opacity(0.18), location: 0.45),
                .init(color: .clear, location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

private extension Color {
    init(_ hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview("Palette sweep") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(["proj_neb", "proj_zion", "proj_construct", "ws_free_the_mind", "ws_dock", "alpha", "omega"], id: \.self) { seed in
                ZStack(alignment: .bottomLeading) {
                    CoverArtView(seed: seed)
                    CoverScrim()
                    Text(seed)
                        .font(Theme.monospace(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding()
    }
}
