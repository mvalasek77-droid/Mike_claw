import SwiftUI

struct GlassCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var tint: Color = LiquidGlass.accent
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassSurface(tier: .raised) {
            VStack(alignment: .leading, spacing: 14) {
                if title != nil || icon != nil {
                    HStack(spacing: 10) {
                        if let icon {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(tint)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(tint.opacity(0.18)))
                        }
                        if let title {
                            Text(title)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                        }
                        Spacer(minLength: 0)
                    }
                }
                content()
            }
            .padding(20)
        }
    }
}

struct StatPill: View {
    let label: String
    let value: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}
