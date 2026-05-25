import UIKit
import CoreHaptics

/// Adaptive haptics. Uses Core Haptics for variable-intensity texture where the
/// hardware supports it (iPhone 8+), and degrades gracefully to UIKit feedback
/// generators otherwise.
enum Haptics {
    private static let engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        return engine
    }()

    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }

    /// Impact tap. Bridges to a Core Haptics transient when available for a
    /// crisper, more adaptive feel; otherwise uses a UIKit impact generator.
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let intensity: Float
        switch style {
        case .light: intensity = 0.5
        case .medium: intensity = 0.7
        case .heavy, .soft, .rigid: intensity = 0.9
        @unknown default: intensity = 0.6
        }
        transient(intensity: intensity, sharpness: 0.6) {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    /// Rising "shimmer" used while the AI Editor reviews a submission.
    static func shimmer() {
        guard let engine, (try? engine.start()) != nil else { return }
        var events: [CHHapticEvent] = []
        for i in 0..<6 {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.25 + Float(i) * 0.06),
                    .init(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: Double(i) * 0.08
            ))
        }
        if let pattern = try? CHHapticPattern(events: events, parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }

    private static func transient(intensity: Float, sharpness: Float, fallback: () -> Void) {
        guard let engine, (try? engine.start()) != nil else { fallback(); return }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        } else {
            fallback()
        }
    }
}
