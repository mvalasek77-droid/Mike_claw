import SwiftUI
import UIKit

/// Dark-first, warm neutral palette with a single accent that pulses on
/// "Skill updated" moments.
enum Theme {
    static let background = Color(red: 0.09, green: 0.08, blue: 0.075)
    static let surface = Color(red: 0.14, green: 0.13, blue: 0.12)
    static let primaryText = Color(red: 0.96, green: 0.94, blue: 0.91)
    static let secondaryText = Color(red: 0.66, green: 0.62, blue: 0.57)
    /// Mirrors the AccentColor asset so shape styles can reference it directly.
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.32)
}

// MARK: - Glass cards

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCardModifier()) }
}

// MARK: - Accent pulse

/// Briefly glows the accent when the observed trigger changes
/// (the "Skill updated" moment).
struct AccentPulseModifier: ViewModifier {
    let trigger: Int
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: Theme.accent.opacity(pulsing ? 0.55 : 0), radius: pulsing ? 14 : 0)
            .scaleEffect(pulsing ? 1.02 : 1.0)
            .onChange(of: trigger) {
                withAnimation(.easeOut(duration: 0.25)) { pulsing = true }
                withAnimation(.easeIn(duration: 0.6).delay(0.35)) { pulsing = false }
            }
    }
}

extension View {
    func accentPulse(on trigger: Int) -> some View { modifier(AccentPulseModifier(trigger: trigger)) }
}

// MARK: - Haptics

enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
