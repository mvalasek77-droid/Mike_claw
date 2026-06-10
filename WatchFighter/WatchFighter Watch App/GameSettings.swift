#if os(watchOS)
import Foundation

/// Lightweight runtime settings the SpriteKit scene reads directly (it isn't a
/// SwiftUI view, so it can't observe `GameFlow`). Persisted to `UserDefaults`.
enum GameSettings {
    private static let bloodKey = "eternalcombat.blood"

    /// Optional stylised blood FX. OFF by default — keeps the base age rating
    /// low; turning it on is a deliberate, remembered choice (affects the App
    /// Store content rating you'd file under).
    static var blood: Bool = UserDefaults.standard.bool(forKey: bloodKey) {
        didSet { UserDefaults.standard.set(blood, forKey: bloodKey) }
    }

    private static let turboKey = "eternalcombat.turbo"

    /// TURBO: arcade-speed fights. Off by default; the base speed is already a
    /// touch quicker than 1:1 for a snappier feel. Purely a real-time pacing
    /// multiplier on the local sim (engine tick logic is unchanged), so it never
    /// affects determinism or the unit tests.
    static var turbo: Bool = UserDefaults.standard.bool(forKey: turboKey) {
        didSet { UserDefaults.standard.set(turbo, forKey: turboKey) }
    }

    /// Real-time → simulation speed multiplier.
    static var gameSpeed: Double { turbo ? 1.75 : 1.18 }

    private static let padKey = "eternalcombat.virtualpad"

    /// On-screen virtual gamepad for fights (vs. the gesture/tap-zone scheme).
    /// Default ON. The scene reads this directly to disable gesture handling.
    static var virtualPad: Bool = {
        UserDefaults.standard.object(forKey: padKey) as? Bool ?? true
    }() {
        didSet { UserDefaults.standard.set(virtualPad, forKey: padKey) }
    }
}
#endif
