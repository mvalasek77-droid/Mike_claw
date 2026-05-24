import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var style: Style = .filled
    var tint: Color = Theme.accent
    var enabled: Bool = true
    var action: () -> Void

    enum Style { case filled, light, ghost }

    @State private var pressed = false

    var body: some View {
        Button {
            guard enabled else { return }
            Haptics.tap(.medium)
            action()
        } label: {
            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .bold))
                }
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous)
                    .strokeBorder(.white.opacity(style == .ghost ? 0.35 : 0.0), lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed, enabled else { return }
                    Motion.run(.spring(response: 0.2)) { pressed = true }
                }
                .onEnded { _ in
                    Motion.run(.spring(response: 0.3)) { pressed = false }
                }
        )
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .filled: tint
        case .light: Color.white
        case .ghost: Color.white.opacity(0.10)
        }
    }

    private var foreground: Color {
        switch style {
        case .filled: return .white
        case .light: return .black
        case .ghost: return Theme.ink
        }
    }
}
