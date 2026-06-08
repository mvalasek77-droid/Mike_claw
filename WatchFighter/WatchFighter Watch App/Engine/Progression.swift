import Foundation

/// Player progression: total wins, story clears, and which fighters are
/// unlocked. Pure + `Codable` so it can be persisted and unit-tested headless.
///
/// Unlock design: six starters are always available; four more unlock at win
/// milestones; clearing the story once unlocks the tower host (Onyx) as a
/// playable bonus. The final boss (Titus) stays boss-only.
struct Progression: Codable, Equatable {
    static let starters: Set<String> = ["tetsu", "volt", "ember", "frost", "mirage", "bastion"]
    /// (winsRequired, characterID), in ascending order.
    static let winUnlocks: [(wins: Int, id: String)] =
        [(2, "corsair"), (4, "nova"), (6, "vesper"), (8, "marina")]
    static let storyClearUnlock = "onyx"

    var totalWins = 0
    var storyCleared = false

    // MARK: Queries

    func isUnlocked(_ id: String) -> Bool {
        if Progression.starters.contains(id) { return true }
        if id == Progression.storyClearUnlock { return storyCleared }
        if let u = Progression.winUnlocks.first(where: { $0.id == id }) { return totalWins >= u.wins }
        return false
    }

    /// Human-readable hint for a still-locked character (nil if unlocked).
    func unlockHint(_ id: String) -> String? {
        guard !isUnlocked(id) else { return nil }
        if id == Progression.storyClearUnlock { return "Clear Story" }
        if let u = Progression.winUnlocks.first(where: { $0.id == id }) {
            return "Win \(u.wins) (\(totalWins)/\(u.wins))"
        }
        return "Locked"
    }

    // MARK: Mutations (return any newly unlocked ids for a celebratory toast)

    mutating func recordWin() -> [String] {
        let before = unlockedSet()
        totalWins += 1
        return Array(unlockedSet().subtracting(before)).sorted()
    }

    mutating func clearStory() -> [String] {
        guard !storyCleared else { return [] }
        let before = unlockedSet()
        storyCleared = true
        return Array(unlockedSet().subtracting(before)).sorted()
    }

    private func unlockedSet() -> Set<String> {
        var s = Progression.starters
        for u in Progression.winUnlocks where totalWins >= u.wins { s.insert(u.id) }
        if storyCleared { s.insert(Progression.storyClearUnlock) }
        return s
    }

    /// All ids selectable given current progress, in a stable display order.
    static func selectableIDs(_ p: Progression) -> [String] {
        (CharacterSpec.selectable.map { $0.id } + [storyClearUnlock])
    }
}
