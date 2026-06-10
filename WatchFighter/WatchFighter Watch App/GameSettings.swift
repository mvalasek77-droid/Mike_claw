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
}
#endif
