import SwiftUI

// MARK: - CompanionPortraitView
//
// Clean gradient avatar shown whenever a real companion photo hasn't been
// added to Assets.xcassets yet. Shows a smooth two-tone gradient built
// from the companion's own accent colour with a large initial letter centred.
//
// No drawn faces, no clothing outlines — just colour and type.

struct CompanionPortraitView: View {
    let companion: CompanionPersonality
    let size: AvatarSize

    // ── Sizing ──────────────────────────────────────────────────────────

    private var dimension: CGFloat {
        switch size {
        case .chat:   return 44
        case .card:   return 80
        case .detail: return 160
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .chat:   return 20
        case .card:   return 34
        case .detail: return 68
        }
    }

    private var initial: String { String(companion.name.prefix(1)) }

    // ── Body ────────────────────────────────────────────────────────────

    var body: some View {
        ZStack {
            // Two-layer gradient: accent colour at top, dark base at bottom
            LinearGradient(
                colors: [
                    companion.accentColor.opacity(0.90),
                    companion.accentColor.opacity(0.40),
                    Color.BC.background
                ],
                startPoint: .topLeading,
                endPoint:   .bottomTrailing
            )

            // Soft radial glow behind the letter
            RadialGradient(
                colors: [
                    companion.accentColor.opacity(0.30),
                    Color.clear
                ],
                center:      .center,
                startRadius: 0,
                endRadius:   dimension * 0.55
            )

            // Initial letter
            Text(initial)
                .font(.system(size: fontSize, weight: .ultraLight, design: .rounded))
                .foregroundColor(.white.opacity(0.90))
        }
        .frame(width: dimension, height: dimension)
        .clipShape(Circle())
    }
}
