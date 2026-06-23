import UIKit
import CoreHaptics

/// Adaptive haptics. We use Core Haptics where available (iPhone 8+), and
/// degrade gracefully to UIKit feedback generators otherwise.
enum Haptics {
    static let reduceHapticsKey = "reduceHaptics"

    private static let engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        return try? CHHapticEngine()
    }()

    /// Honours the in-app "Reduce haptics" preference. Read fresh each call so
    /// toggling the setting takes effect immediately.
    private static var isMuted: Bool {
        UserDefaults.standard.bool(forKey: Haptics.reduceHapticsKey)
    }

    /// Light tap, suitable for selection changes and incidental UI taps.
    static func selection() {
        guard !isMuted else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Affirming success "thunk". Used after an export finishes.
    static func success() {
        guard !isMuted else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard !isMuted else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        guard !isMuted else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Variable-intensity tap. `intensity` and `sharpness` are 0…1.
    static func tap(intensity: Float = 0.6, sharpness: Float = 0.5) {
        guard !isMuted else { return }
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

    /// Rising "ramp" used while an export batch renders — a sequence of taps
    /// that climb in intensity so the device communicates progress.
    static func ramp() {
        guard !isMuted else { return }
        guard let engine, (try? engine.start()) != nil else { return }
        var events: [CHHapticEvent] = []
        for i in 0..<6 {
            let t = Double(i) * 0.07
            events.append(.init(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.25 + Float(i) * 0.06),
                    .init(parameterID: .hapticSharpness, value: 0.45)
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
