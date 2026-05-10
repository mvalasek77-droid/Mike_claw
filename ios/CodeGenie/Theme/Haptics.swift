import UIKit
import CoreHaptics

/// Adaptive haptics. We use Core Haptics where available (iPhone 8+),
/// and degrade gracefully to UIKit feedback generators otherwise.
enum Haptics {
    private static let engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        return try? CHHapticEngine()
    }()

    /// Light tap, suitable for selection changes and incidental UI taps.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Affirming success "thunk". Used after a build finishes or an action confirms.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Variable-intensity tap. `intensity` and `sharpness` are 0…1.
    static func tap(intensity: Float = 0.6, sharpness: Float = 0.5) {
        guard let engine, (try? engine.start()) != nil else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                .init(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0
        )
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player  = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }

    /// Long building "shimmer" — used while a job runs in the background.
    static func shimmer() {
        guard let engine, (try? engine.start()) != nil else { return }
        var events: [CHHapticEvent] = []
        for i in 0..<6 {
            let t = Double(i) * 0.08
            events.append(.init(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.25 + Float(i) * 0.05),
                    .init(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: t
            ))
        }
        if let pattern = try? CHHapticPattern(events: events, parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }
}
