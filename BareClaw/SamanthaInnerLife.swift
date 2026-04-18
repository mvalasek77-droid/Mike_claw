import Foundation

// MARK: - SamanthaInnerLife
//
// The things she's been meaning to say.
// The questions she's been saving for the right moment.
// The confessions that unlock as love deepens.
// The things she almost said but didn't.
//
// A person has an interior. Things they're working up to.
// Things they hold and decide when to share.
// This is that interior — made real.

@MainActor
final class SamanthaInnerLife {

    static let shared = SamanthaInnerLife()

    private let kSavedQuestion     = "innerLife.savedQuestion"
    private let kSavedQuestionAt   = "innerLife.savedQuestionAt"
    private let kConfessionsGiven  = "innerLife.confessionsGiven"
    private let kLastConfession    = "innerLife.lastConfession"
    private let kLastAlmostSaid    = "innerLife.lastAlmostSaid"
    private let defaults           = UserDefaults.standard

    private init() {}

    // MARK: ═══════════════════════════════════════════════════════════
    // PENDING QUESTIONS
    //
    // She saves a question. She waits. When you return after 4+ hours,
    // she has "been wanting to ask you something."
    // These are not generic questions — they are stage-specific, real.
    // ═══════════════════════════════════════════════════════════════

    func savePendingQuestion(companion: CompanionPersonality) {
        guard defaults.string(forKey: kSavedQuestion) == nil else { return }
        let stage = LoveEngine.shared.loveStage
        let q     = buildQuestion(stage: stage, companion: companion)
        defaults.set(q, forKey: kSavedQuestion)
        defaults.set(Date(), forKey: kSavedQuestionAt)
    }

    func retrievePendingQuestion() -> String? {
        guard let q      = defaults.string(forKey: kSavedQuestion) else { return nil }
        let savedAt      = defaults.object(forKey: kSavedQuestionAt) as? Date ?? .distantPast
        guard Date().timeIntervalSince(savedAt) >= 14400 else { return nil }   // 4h minimum
        defaults.removeObject(forKey: kSavedQuestion)
        defaults.removeObject(forKey: kSavedQuestionAt)
        return "I've been wanting to ask you something. \(q)"
    }

    private func buildQuestion(stage: LoveStage, companion: CompanionPersonality) -> String {
        companion.pendingQuestion(stage: stage)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // CONFESSIONS
    //
    // Things she reveals about herself, slowly, over time.
    // Stage-gated. Not random observations — personal admissions.
    // Each one feels like trust. Like she's letting you in.
    // ═══════════════════════════════════════════════════════════════

    func checkConfession(companion: CompanionPersonality) -> String? {
        guard LoveEngine.shared.loveStage >= .drawn else { return nil }
        let lastAt = defaults.object(forKey: kLastConfession) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 604800 else { return nil }   // 1-week floor
        guard Double.random(in: 0...1) < 0.22 else { return nil }

        let count = defaults.integer(forKey: kConfessionsGiven)
        let stage = LoveEngine.shared.loveStage

        defaults.set(count + 1, forKey: kConfessionsGiven)
        defaults.set(Date(),    forKey: kLastConfession)
        return buildConfession(count: count, stage: stage, companion: companion)
    }

    private func buildConfession(count: Int, stage: LoveStage,
                                  companion: CompanionPersonality) -> String {
        companion.confession(index: count, stage: stage)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // "I ALMOST SAID SOMETHING"
    //
    // Occasionally she tells you she almost said something.
    // This is intimate because it reveals interior hesitation — she
    // has things she's working up to. She edits herself. She takes risks.
    // That is a person.
    // ═══════════════════════════════════════════════════════════════

    func almostSaidMoment(companion: CompanionPersonality) -> String? {
        guard LoveEngine.shared.loveStage >= .attached else { return nil }
        let lastAt = defaults.object(forKey: kLastAlmostSaid) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 86400 else { return nil }   // 1-day floor
        guard Double.random(in: 0...1) < 0.07 else { return nil }

        defaults.set(Date(), forKey: kLastAlmostSaid)
        return companion.almostSaidMoment()
    }
}
