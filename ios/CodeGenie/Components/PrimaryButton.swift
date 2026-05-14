import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var style: Style = .filled
    var action: () -> Void

    enum Style { case filled, glass, ghost }

    @State private var pressed = false

    var body: some View {
        Button {
            Haptics.tap(intensity: 0.7, sharpness: 0.55)
            action()
        } label: {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                }
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(.white.opacity(style == .ghost ? 0.5 : 0.25), lineWidth: 0.8)
            )
            .scaleEffect(pressed ? 0.97 : 1)
            .shadow(color: shadow, radius: pressed ? 4 : 12, x: 0, y: pressed ? 2 : 6)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    Motion.run(.spring(response: 0.2)) { pressed = true }
                }
                .onEnded { _ in
                    Motion.run(.spring(response: 0.3)) { pressed = false }
                }
        )
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .filled: LiquidGlass.auroraGradient
        case .glass:  Color.clear.background(.ultraThinMaterial)
        case .ghost:  Color.white.opacity(0.06)
        }
    }
    private var foreground: Color {
        switch style {
        case .filled: .white
        case .glass, .ghost: LiquidGlass.primaryText.opacity(0.95)
        }
    }
    private var shadow: Color {
        style == .filled ? LiquidGlass.accent.opacity(0.45) : .black.opacity(0.25)
    }
}
