import Foundation
#if canImport(UIKit)
import UIKit
import CoreHaptics
#endif

/// Adaptive haptic feedback — light for interactions, notification
/// haptics for outcomes, custom Core Haptics patterns for the
/// signature "settlement win" celebration.
///
/// Every trigger is a one-line call site: `Haptics.tap()`,
/// `Haptics.won(large: true)`, etc. Off-thread work is cheap so we
/// don't gate any of these; they're safe to call from view code.
enum Haptics {
    #if canImport(UIKit)
    private static let engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        return try? CHHapticEngine()
    }()

    static func warmUp() {
        try? engine?.start()
    }

    // MARK: - Simple

    /// Selection tick — segmented picker changes, tab swaps.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Light impact — button taps, list-row taps.
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare(); g.impactOccurred()
    }

    /// Notification haptic — .success / .warning / .error.
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let g = UINotificationFeedbackGenerator()
        g.prepare(); g.notificationOccurred(type)
    }

    // MARK: - Semantic

    static func trade()      { tap(.medium) }
    static func closeTrade() { tap(.rigid) }
    static func lost()       { notify(.error) }
    static func won(large: Bool = false) {
        if large { winCelebration() } else { notify(.success) }
    }
    static func tierUp()     { winCelebration() }
    static func badge()      { doubleTap() }
    static func warning()    { notify(.warning) }

    // MARK: - Custom patterns

    /// A short two-thump tap, used for badge unlocks.
    private static func doubleTap() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare(); g.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            g.impactOccurred(intensity: 0.7)
        }
    }

    /// Signature celebration — rising intensity into a firm thump.
    /// Falls back to a plain success haptic on devices without
    /// Core Haptics.
    private static func winCelebration() {
        guard let engine else { notify(.success); return }
        let events: [CHHapticEvent] = [
            .init(eventType: .hapticTransient,
                  parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.35),
                    .init(parameterID: .hapticSharpness, value: 0.5),
                  ], relativeTime: 0),
            .init(eventType: .hapticContinuous,
                  parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.55),
                    .init(parameterID: .hapticSharpness, value: 0.4),
                  ], relativeTime: 0.10, duration: 0.20),
            .init(eventType: .hapticTransient,
                  parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0),
                    .init(parameterID: .hapticSharpness, value: 0.9),
                  ], relativeTime: 0.34),
        ]
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player  = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: 0)
        } catch {
            notify(.success)
        }
    }
    #else
    static func warmUp() {}
    static func selection() {}
    static func tap(_ style: Int = 0) {}
    static func trade() {}
    static func closeTrade() {}
    static func lost() {}
    static func won(large: Bool = false) {}
    static func tierUp() {}
    static func badge() {}
    static func warning() {}
    #endif
}
