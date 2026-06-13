import SwiftUI

/// A frosted surface used for cards, sheets and panels.
struct GlassSurface<Content: View>: View {
    var corner: CGFloat = Theme.cornerL
    var tint: Color = .white
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                GlassEffectContainer {
                    content()
                        .background(
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .fill(tint.opacity(0.05))
                        )
                        .glassEffect(.regular, in: .rect(cornerRadius: corner))
                }
            } else {
                materialBody
            }
            #else
            materialBody
            #endif
        }
        .depth(corner)
    }

    /// Frosted-material surface used below iOS 26.
    private var materialBody: some View {
        content()
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(tint.opacity(0.06))
                }
            }
            .overlay {
                // Top-edge sheen — gives the surface a lit, fluid-glass feel.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.08), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
    }
}

/// Titled card built on top of ``GlassSurface``.
struct GlassCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var tint: Color = Theme.accent
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 14) {
                if title != nil || icon != nil {
                    HStack(spacing: 10) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(tint)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(tint.opacity(0.18)))
                        }
                        if let title {
                            Text(title)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                        }
                        Spacer(minLength: 0)
                    }
                }
                content()
            }
            .padding(18)
        }
    }
}

/// Small rounded label — used for genre, maturity, AI-tool chips, etc.
struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .white
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(filled ? .black : color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(filled ? color : color.opacity(0.16))
        )
        .overlay(
            Capsule().strokeBorder(color.opacity(filled ? 0 : 0.30), lineWidth: 0.6)
        )
    }
}

/// The "AI Editor score" badge shown across the consumption UI.
struct ScoreBadge: View {
    let score: Int
    var compact: Bool = false

    private var color: Color {
        switch score {
        case 90...: return Theme.success
        case 85..<90: return Theme.gold
        default: return Theme.warning
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: compact ? 9 : 11, weight: .bold))
            Text(compact ? "\(score)" : "AI Editor \(score)")
                .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 9)
        .padding(.vertical, compact ? 3 : 5)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 0.6))
    }
}

/// Standard placeholder for empty lists and filtered feeds.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Theme.inkFaint

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.horizontal, 30)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
