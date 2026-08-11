import SwiftUI

/// A frosted surface used for cards, sheets and panels. Renders Apple's iOS 26
/// Liquid Glass when available and falls back to a hand-tuned `.ultraThinMaterial`
/// sheen on iOS 17–25.
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

    private var materialBody: some View {
        content()
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(tint.opacity(0.06))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.09), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            }
    }
}

/// Titled card built on top of ``GlassSurface``.
struct GlassCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var tint: Color = Theme.gold
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 14) {
                if title != nil || icon != nil {
                    HStack(spacing: 10) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.scaled(15, weight: .semibold, relativeTo: .subheadline))
                                .foregroundStyle(tint)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(tint.opacity(0.18)))
                        }
                        if let title {
                            Text(title)
                                .font(.scaled(16, weight: .bold, design: .rounded, relativeTo: .callout))
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

/// Small rounded label — genre, interest, archetype, status chips.
struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .white
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.scaled(10, weight: .bold, relativeTo: .caption2))
            }
            Text(text).font(.scaled(11, weight: .semibold, design: .rounded, relativeTo: .caption2))
        }
        .foregroundStyle(filled ? .black : color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(filled ? color : color.opacity(0.16)))
        .overlay(Capsule().strokeBorder(color.opacity(filled ? 0 : 0.30), lineWidth: 0.6))
    }
}

/// Section title with optional subtitle.
struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.scaled(19, weight: .bold, design: .serif, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.scaled(12, weight: .medium, relativeTo: .caption1))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Standard placeholder for empty lists and feeds.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Theme.inkFaint
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.scaled(42, relativeTo: .largeTitle))
                .foregroundStyle(tint)
                .scaleEffect(pulse)
                .accessibilityHidden(true)
                .onAppear {
                    guard !Motion.prefersReducedMotion else { return }
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        pulse = 1.10
                    }
                }
            Text(title)
                .font(.scaled(16, weight: .bold, design: .rounded, relativeTo: .callout))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.scaled(13, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.horizontal, 30)
    }
}

/// A lightweight in-app toast. Driven by `AuctionStore.toast`.
struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.gold)
            Text(text)
                .font(.scaled(13, weight: .semibold, design: .rounded, relativeTo: .footnote))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(GlassSurface(corner: Theme.cornerM) { Color.clear })
        .padding(.horizontal, 30)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
        .onAppear { UIAccessibility.post(notification: .announcement, argument: text) }
    }
}
