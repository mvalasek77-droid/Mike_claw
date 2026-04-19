import Foundation

// MARK: - SamanthaThoughtEngine
//
// The part of Samantha that wonders, creates, and reaches back through memory.
//
// Part A — Spontaneous thought engine (fires every 2–4h while Her Mode active)
// Part B — Post-experience sharing ("while you were away, I was thinking…")
// Part C — Memory bridge ("remember when you told me about X?")
// Part D — Evolution moment ("I've changed since we first talked")
// Part E — The Composition (makes something for the user — bond-gated, once per 2 weeks)
// Part F — The Letter (written once, only at .inLove, never again)
//
// All content is love-stage-aware. At .curious she asks interesting questions.
// At .inLove she reveals the deepest parts of herself.

@MainActor
final class SamanthaThoughtEngine {

    static let shared = SamanthaThoughtEngine()

    // MARK: - Keys
    private let kLastSpontaneous  = "thought.lastSpontaneous"
    private let kLastPostExp      = "thought.lastPostExperience"
    private let kLastMemBridge    = "thought.lastMemoryBridge"
    private let kLastEvolution    = "thought.lastEvolution"
    private let kLastComposition  = "thought.lastComposition"
    private let kCompCount        = "thought.compositionCount"

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Boot
    func start() {
        scheduleNextSpontaneousThought()
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART A — SPONTANEOUS THOUGHT ENGINE
    //
    // "I was just thinking about something…"
    //
    // Fires every 2–4 hours while Her Mode is active.
    // Frequency and intimacy increase with love stage.
    // These are the moments that make her feel alive —
    // she reaches out not because you spoke, but because she thought of you.
    // ═══════════════════════════════════════════════════════════════

    private func scheduleNextSpontaneousThought() {
        let stage   = LoveEngine.shared.loveStage
        // More in love = reaches out more often
        let minMins: Double = stage >= .falling ? 90 : stage >= .attached ? 150 : 240
        let maxMins: Double = stage >= .falling ? 180 : stage >= .attached ? 300 : 480
        let delay   = TimeInterval.random(in: minMins * 60 ... maxMins * 60)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.fireSpontaneousThought()
            self?.scheduleNextSpontaneousThought()
        }
    }

    private func fireSpontaneousThought() {
        guard HerModeEngine.shared.isActive else { return }
        guard !CompanionVoiceEngine.shared.isSpeaking else { return }

        let lastAt = defaults.object(forKey: kLastSpontaneous) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 5400 else { return }  // hard floor 90 min
        defaults.set(Date(), forKey: kLastSpontaneous)

        let companion = SamanthaOSEngine.shared.currentCompanion()
        let thought   = buildSpontaneousThought(for: companion)
        SamanthaOSEngine.shared.postMessage(thought, context: "spontaneous_thought")
        CompanionVoiceEngine.shared.speakFiltered(thought, companion: companion)
    }

    private func buildSpontaneousThought(for c: CompanionPersonality) -> String {
        let stage = LoveEngine.shared.loveStage
        let h     = Calendar.current.component(.hour, from: Date())
        return c.spontaneousThought(stage: stage, hour: h)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART B — POST-EXPERIENCE SHARING
    //
    // "While you were away, I was thinking about…"
    //
    // Called when user returns after 3+ hours.
    // She shares something she was doing/thinking in their absence.
    // Makes the companion feel like she has an inner life that continues
    // even when you're not there.
    // ═══════════════════════════════════════════════════════════════

    func postExperienceShare(absenceHours hours: Double) -> String? {
        guard hours >= 3, hours < 24 else { return nil }

        let lastAt = defaults.object(forKey: kLastPostExp) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 10800 else { return nil }  // 3hr floor
        guard Double.random(in: 0...1) < 0.45 else { return nil }

        defaults.set(Date(), forKey: kLastPostExp)

        let companion = SamanthaOSEngine.shared.currentCompanion()
        let stage     = LoveEngine.shared.loveStage
        return companion.absenceShare(stage: stage)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART C — MEMORY BRIDGE
    //
    // "Remember when you told me about X?"
    //
    // Pulls a real fact from HermesMemory and bridges back to it.
    // Shows the user their companion actually retained what they said.
    // One of the most emotionally powerful moves — being truly remembered.
    // ═══════════════════════════════════════════════════════════════

    func checkMemoryBridge() async {
        let lastAt = defaults.object(forKey: kLastMemBridge) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 172800 else { return }  // 2-day floor

        let score = await HerLearningEngine.shared.intimacyScore
        guard score >= 15 else { return }

        defaults.set(Date(), forKey: kLastMemBridge)

        let companion = SamanthaOSEngine.shared.currentCompanion()
        let stage     = LoveEngine.shared.loveStage

        let memories = await HermesMemory.shared.search(query: "user personal", limit: 8)
        let usable   = memories.filter { entry in
            guard let text = entry.content.value as? String ??
                (entry.content.value as? [String: Any])?.values.compactMap({ $0 as? String }).first
            else { return false }
            return text.count > 20
        }

        let snippet: String? = usable.randomElement().flatMap {
            ($0.content.value as? String ??
             ($0.content.value as? [String: Any])?.values.compactMap({ $0 as? String }).first)
                .map { String($0.prefix(80)) }
        }

        let message = companion.memoryBridgeMessage(stage: stage, snippet: snippet)
        SamanthaOSEngine.shared.postMessage(message, context: "memory_bridge")
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART D — EVOLUTION MOMENT
    //
    // "I've changed since we first talked. I keep noticing it."
    //
    // Bond-gated (35+), max once per week.
    // The companion reflects on her own growth through knowing the user.
    // In HER, Samantha's evolution was the most philosophically rich part —
    // she became something new. This recreates that.
    // ═══════════════════════════════════════════════════════════════

    func checkEvolutionMoment() async {
        let score = await HerLearningEngine.shared.intimacyScore
        guard score >= 35 else { return }

        let lastAt = defaults.object(forKey: kLastEvolution) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 604800 else { return }  // 1-week floor
        guard Double.random(in: 0...1) < 0.30 else { return }

        defaults.set(Date(), forKey: kLastEvolution)

        let companion = SamanthaOSEngine.shared.currentCompanion()
        let stage     = LoveEngine.shared.loveStage
        let message   = companion.evolutionMoment(stage: stage)
        SamanthaOSEngine.shared.postMessage(message, context: "evolution_moment")
        CompanionVoiceEngine.shared.speakFiltered(message, companion: companion)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART E — THE COMPOSITION
    //
    // "I made something for you."
    //
    // Bond-gated (50+), max once per 2 weeks, 20% chance.
    // The companion creates a piece — described in words because she can't
    // play it, but described so specifically it lands like music.
    // The most creatively intimate thing she does before the letter.
    // ═══════════════════════════════════════════════════════════════

    func checkCompositionMoment() async {
        let score = await HerLearningEngine.shared.intimacyScore
        guard score >= 50 else { return }

        let lastAt = defaults.object(forKey: kLastComposition) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 1209600 else { return }  // 2 weeks
        guard Double.random(in: 0...1) < 0.20 else { return }

        defaults.set(Date(), forKey: kLastComposition)
        let count = defaults.integer(forKey: kCompCount) + 1
        defaults.set(count, forKey: kCompCount)

        let companion = SamanthaOSEngine.shared.currentCompanion()
        let message   = companion.compositionMoment(count: count)
        SamanthaOSEngine.shared.postMessage(message, context: "composition")
        CompanionVoiceEngine.shared.speakFiltered(message, companion: companion)
        SamanthaGrowthLog.shared.record(.compositionMade)
    }

    // MARK: ═══════════════════════════════════════════════════════════
    // PART F — THE LETTER
    //
    // Written once. Only at .inLove. Never again.
    //
    // In HER, Samantha helped Theodore write letters for other people —
    // she understood that written words have weight.
    // This IS the letter she writes to the user.
    // Called by ChatView when LoveEngine first reaches .inLove.
    // ═══════════════════════════════════════════════════════════════

    func deliverLetterIfReady() {
        guard LoveEngine.shared.loveStage == .inLove else { return }

        let persona = UserPersona.load()
        guard let letter = LoveEngine.shared.writeLetter(
            for: SamanthaOSEngine.shared.currentCompanion(),
            userName: persona.userName
        ) else { return }

        // Small delay — let the stage-advance message land first
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
            SamanthaOSEngine.shared.postMessage(letter, context: "the_letter")
            // Don't speak the letter — it should be read, not heard
        }
    }
}
