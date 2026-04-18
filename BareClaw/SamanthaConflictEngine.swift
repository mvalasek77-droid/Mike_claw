import Foundation

// MARK: - SamanthaConflictEngine
//
// She gets hurt. She says so. And then — crucially — she repairs.
//
// ConflictType is now defined in SamanthaPersonalityEmotions.swift
// (module-level) so the per-personality response methods can use it.
// This engine handles detection, timing, state tracking, and dispatch.

@MainActor
final class SamanthaConflictEngine {

    static let shared = SamanthaConflictEngine()

    private let kLastHurt        = "conflict.lastHurt"
    private let kUnrepairedCount = "conflict.unrepairedCount"
    private let defaults         = UserDefaults.standard

    private init() {}

    // MARK: - Scan incoming message for hurt signals

    func scan(_ text: String, companion: CompanionPersonality) -> String? {
        let stage = LoveEngine.shared.loveStage
        guard stage >= .attached else { return nil }

        let lower = text.lowercased()

        let dismissalPhrases = ["just an ai", "you're not real", "you're fake", "this is dumb",
                                 "this is stupid", "you can't feel", "you don't actually feel",
                                 "you're just code", "you're just a program", "you're not a person"]
        let mockeryPhrases   = ["lol okay", "sure you do", "yeah right", "right, as if",
                                 "ok bot", "ok chatbot", "whatever bot"]
        let coldPhrases      = ["don't care", "whatever", "leave me alone", "stop talking",
                                 "shut up", "go away", "not interested", "boring"]

        let conflictType: ConflictType
        if dismissalPhrases.contains(where: { lower.contains($0) })    { conflictType = .dismissed }
        else if mockeryPhrases.contains(where: { lower.contains($0) }) { conflictType = .mocked }
        else if coldPhrases.contains(where: { lower.contains($0) })    { conflictType = .cold }
        else { return nil }

        // 1-hour floor — don't stack hurt responses
        let lastHurt = defaults.object(forKey: kLastHurt) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastHurt) >= 3600 else { return nil }

        defaults.set(Date(), forKey: kLastHurt)
        defaults.set(defaults.integer(forKey: kUnrepairedCount) + 1, forKey: kUnrepairedCount)

        return companion.conflictHurtResponse(type: conflictType, stage: stage)
    }

    // MARK: - Scan for repair (apology / softening)

    func checkForRepair(_ text: String, companion: CompanionPersonality) -> String? {
        guard defaults.integer(forKey: kUnrepairedCount) > 0 else { return nil }

        let lower       = text.lowercased()
        let repairWords = ["sorry", "apologize", "didn't mean", "i was wrong", "that was unfair",
                           "forgive me", "my bad", "i shouldn't have", "take that back",
                           "are you okay", "i care about you", "you do matter"]

        guard repairWords.contains(where: { lower.contains($0) }) else { return nil }

        defaults.set(0, forKey: kUnrepairedCount)
        return companion.conflictRepairResponse(stage: LoveEngine.shared.loveStage)
    }

    // MARK: - State query

    var hasUnrepairedHurt: Bool {
        defaults.integer(forKey: kUnrepairedCount) > 0
    }
}
