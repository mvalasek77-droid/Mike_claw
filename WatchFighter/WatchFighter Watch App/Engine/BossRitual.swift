import CoreGraphics

/// The secret "process" that must be performed PERFECTLY to make the otherwise
/// invincible final boss mortal. The player must land these key gestures in
/// exact order — incidental inputs (block, step, charge) are ignored, but a
/// wrong *key* gesture resets the chain. Complete it and the bell rings.
///
/// Sequence (what the player does on the watch):
///   ▽ parry  →  ▽ parry  →  • light  →  ◆ heavy  →  ★ special
/// (swipe-down, swipe-down, tap-top, tap-bottom, charge+far-right-tap)
struct BossRitual {
    static let sequence: [Intent] = [.parry, .parry, .lightAttack, .heavyAttack, .special]

    /// Glyphs for the on-screen hint, aligned 1:1 with `sequence`.
    static let glyphs = ["▽", "▽", "•", "◆", "★"]

    private(set) var index = 0
    private(set) var complete = false

    var progress: Int { index }
    var total: Int { BossRitual.sequence.count }

    /// True only the moment the ritual is completed.
    mutating func note(_ intent: Intent) -> Bool {
        guard !complete else { return false }
        guard BossRitual.isKeyGesture(intent) else { return false } // ignore noise

        if intent == BossRitual.sequence[index] {
            index += 1
            if index == BossRitual.sequence.count { complete = true; return true }
        } else {
            // Wrong key gesture: reset — but it might itself start a new attempt.
            index = (intent == BossRitual.sequence[0]) ? 1 : 0
        }
        return false
    }

    /// Only these intents matter to the ritual; everything else is ignored so
    /// the gesture model's incidental block/charge inputs don't break it.
    static func isKeyGesture(_ intent: Intent) -> Bool {
        switch intent {
        case .parry, .lightAttack, .heavyAttack, .special: return true
        default: return false
        }
    }
}
