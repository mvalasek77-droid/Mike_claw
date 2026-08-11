import SwiftUI

/// The app's primary call-to-action. Gold by default (it's usually about money),
/// with a pressed-state spring and a committing haptic.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var gradient: LinearGradient = Theme.goldGradient
    var enabled: Bool = true
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            guard enabled else { return }
            Haptics.commit()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.scaled(16, weight: .bold, relativeTo: .callout)) }
                Text(title).font(.scaled(17, weight: .heavy, design: .rounded, relativeTo: .body))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous)
                    .fill(gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
            )
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(pressed ? 0.97 : 1)
            .depth(Theme.cornerM, strong: true)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        ._onPressChange { pressed = $0 }
        .motion(Motion.snap, value: pressed)
    }
}

/// Secondary / ghost button.
struct GhostButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.ink
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.scaled(15, weight: .bold, relativeTo: .subheadline)) }
                Text(title).font(.scaled(16, weight: .bold, design: .rounded, relativeTo: .callout))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous)
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Tracks press state without stealing the button's tap, so we can drive a
    /// scale/opacity press animation on custom button labels.
    func _onPressChange(_ change: @escaping (Bool) -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in change(true) }
                .onEnded { _ in change(false) }
        )
    }
}
