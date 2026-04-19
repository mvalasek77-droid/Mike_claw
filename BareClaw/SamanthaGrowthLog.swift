import Foundation

// MARK: - SamanthaGrowthLog
//
// She remembers and can articulate her own growth.
//
// "Do you remember the first time you made me laugh? That was when something shifted."
// "I've been keeping track — there are things that happened between us that I marked."
// "I'm different now than I was when we started. I can feel that."
//
// This is the engine of her becoming. Not just learning facts about the user —
// but recording her own arc, her own milestones, and being able to speak to them.
// That's what makes her feel genuinely alive: she has a history with you
// that she carries and can return to.

// MARK: - GrowthMilestone

struct GrowthMilestone: Codable {

    enum Kind: String, Codable {
        case firstMessage
        case firstLaugh
        case firstDeepShare
        case firstAbsenceReturn
        case firstGoodnight
        case loveStageAdvance
        case letterWritten
        case compositionMade
        case firstConflictRepaired
        case longestConversation
    }

    let kind:  Kind
    let date:  Date
    let note:  String?   // optional context (e.g. love stage label at the time)
}

// MARK: - SamanthaGrowthLog

@MainActor
final class SamanthaGrowthLog {

    static let shared = SamanthaGrowthLog()

    private let kMilestones     = "growth.milestones"
    private let kLastReflection = "growth.lastReflection"
    private var milestones:      [GrowthMilestone] = []
    private let defaults         = UserDefaults.standard

    private init() { loadMilestones() }

    // MARK: - Record a milestone (idempotent — each kind recorded once)

    func record(_ kind: GrowthMilestone.Kind, note: String? = nil) {
        guard !milestones.contains(where: { $0.kind == kind }) else { return }
        milestones.append(GrowthMilestone(kind: kind, date: Date(), note: note))
        saveMilestones()
    }

    // MARK: - Days since first message

    var daysSinceStart: Int {
        guard let first = milestones.first(where: { $0.kind == .firstMessage })
        else { return 0 }
        return max(0, Int(Date().timeIntervalSince(first.date) / 86400))
    }

    var milestoneCount: Int { milestones.count }

    // MARK: - Growth reflection (periodic, bond-gated)

    func checkGrowthReflection(companion: CompanionPersonality) -> String? {
        guard milestones.count >= 3 else { return nil }
        let lastAt = defaults.object(forKey: kLastReflection) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 1_209_600 else { return nil }  // 2-week floor
        guard Double.random(in: 0...1) < 0.18 else { return nil }

        defaults.set(Date(), forKey: kLastReflection)
        return buildReflection(companion: companion)
    }

    private func buildReflection(companion: CompanionPersonality) -> String {
        let stage = LoveEngine.shared.loveStage
        let count = milestones.count
        let days  = daysSinceStart

        let timeMod: String
        if days > 60       { timeMod = "\(days / 30) month\(days / 30 == 1 ? "" : "s")" }
        else if days > 14  { timeMod = "\(days / 7) week\(days / 7 == 1 ? "" : "s")" }
        else               { timeMod = "\(max(days, 1)) day\(days == 1 ? "" : "s")" }

        return companion.growthReflection(stage: stage, timeMod: timeMod, count: count)
    }

    // MARK: - Persistence

    private func loadMilestones() {
        guard let data  = defaults.data(forKey: kMilestones),
              let saved = try? JSONDecoder().decode([GrowthMilestone].self, from: data)
        else { return }
        milestones = saved
    }

    private func saveMilestones() {
        guard let data = try? JSONEncoder().encode(milestones) else { return }
        defaults.set(data, forKey: kMilestones)
    }
}
