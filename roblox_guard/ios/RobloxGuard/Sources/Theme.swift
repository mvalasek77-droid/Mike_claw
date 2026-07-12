import SwiftUI
import UIKit

/// Design system: severity color ramp, glass surfaces, and haptics.
///
/// The glass treatment uses system materials (`.ultraThinMaterial`) so it
/// tracks light/dark mode and accessibility settings (Reduce Transparency
/// falls back automatically). When the iOS 26 Liquid Glass APIs are adopted
/// (see docs/ROADMAP.md) this is the single file that changes.
enum Theme {
    static func severityColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .watch: return .orange
        case .elevated: return .red
        }
    }

    static func severityIcon(_ severity: AlertSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .watch: return "eye.fill"
        case .elevated: return "exclamationmark.shield.fill"
        }
    }
}

/// Adaptive haptics: intensity follows what the event means, so the phone
/// "feels" different for an informational ping vs. an elevated alert.
enum Haptics {
    static func alert(_ severity: AlertSeverity) {
        switch severity {
        case .info:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .watch:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .elevated:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tap() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// Glass card surface with subtle depth. Respects Reduce Transparency and
/// both color schemes via system materials.
struct GlassCard: ViewModifier {
    var tint: Color = .clear

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tint.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            )
    }
}

extension View {
    func glassCard(tint: Color = .clear) -> some View {
        modifier(GlassCard(tint: tint))
    }
}
