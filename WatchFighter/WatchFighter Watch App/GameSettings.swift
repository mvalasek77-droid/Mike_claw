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

    private static let padKey = "eternalcombat.controls"

    /// Control scheme. `crown` = rotate the Digital Crown to WALK + tap to fight
    /// (the only physical control watchOS exposes is the Crown's rotation; the
    /// side/Action buttons are not available to apps). `buttons` = on-screen pad.
    /// `gestures` = swipe/tap zones.
    enum ControlScheme: String, CaseIterable {
        case crown, buttons, gestures
        var label: String {
            switch self { case .crown: return "CROWN+TAP"
                          case .buttons: return "BUTTONS"; case .gestures: return "GESTURES" }
        }
        var next: ControlScheme {
            let all = ControlScheme.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    static var controls: ControlScheme = {
        if let s = UserDefaults.standard.string(forKey: padKey),
           let c = ControlScheme(rawValue: s) { return c }
        return .crown
    }() {
        didSet { UserDefaults.standard.set(controls.rawValue, forKey: padKey) }
    }
}

/// Saves an in-progress STORY run so a watch lock-out / suspend can resume it
/// instead of losing your place. (Progression/unlocks persist separately.)
enum ResumeStore {
    private static let idKey = "eternalcombat.resume.id"
    private static let idxKey = "eternalcombat.resume.idx"

    static func save(playerID: String, ladderIndex: Int) {
        UserDefaults.standard.set(playerID, forKey: idKey)
        UserDefaults.standard.set(ladderIndex, forKey: idxKey)
    }
    static func load() -> (id: String, index: Int)? {
        guard let id = UserDefaults.standard.string(forKey: idKey) else { return nil }
        return (id, UserDefaults.standard.integer(forKey: idxKey))
    }
    static func clear() {
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: idxKey)
    }
}
#endif
