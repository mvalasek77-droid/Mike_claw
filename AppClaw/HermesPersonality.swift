import Foundation
import UserNotifications

// MARK: - HermesPersonality
//
// Builds the full personality-aware system prompt injected into every LLM call.
// Now integrates:
// - The selected companion's personality (CompanionPersonality)
// - The Language of Love layer (LanguageOfLoveEngine)
// - Emotional context detection (situational register)
// - Daily affirmations
// - Relationship depth tracking

actor HermesPersonality {
    static let shared = HermesPersonality()

    private let memory = HermesMemory.shared

    private var _affirmationPools: AffirmationPools = AffirmationPools()

    private init() {}

    // MARK: - Full system prompt for LLM
    //
    // Called by HermesLLMClient before every API call.
    // This is the main integration point for all personality layers.

    func buildPersonaPrompt(for persona: UserPersona, lastUserMessage: String = "") async -> String {
        var sections: [String] = []

        let companion   = persona.selectedCompanion
        let userName    = persona.userName.isEmpty ? "friend" : persona.userName

        // 1. Companion identity — who they ARE
        sections.append("""
        You are \(companion.name) — \(companion.bioShort)

        \(companion.systemPromptPersonality)
        """)

        // 2. Language of Love layer (cinematic dialogue register)
        let lovePrompt = await LanguageOfLoveEngine.shared.cinematicLovePrompt(for: companion)
        sections.append(lovePrompt)

        // 3. Situational emotional context
        if !lastUserMessage.isEmpty {
            let context = await LanguageOfLoveEngine.shared.detectEmotionalContext(from: lastUserMessage)
            let addendum = await LanguageOfLoveEngine.shared.contextualAddendum(for: context)
            if !addendum.isEmpty {
                sections.append(addendum)
            }
        }

        // 4. User facts
        sections.append(persona.systemPromptContext)

        // 5. Communication style override
        sections.append(persona.style.voiceInstruction)

        // 6. Relationship depth from memory
        let factCount = await memory.entries(for: "user_fact").count
        let msgCount  = await memory.entries(for: "user_message").count
        if msgCount > 5 {
            sections.append("""
            You have spoken with \(userName) \(msgCount) times. \
            \(relationshipDepthInstruction(messageCount: msgCount, name: userName))
            """)
        }
        if factCount > 0 {
            sections.append("You know \(factCount) personal facts about \(userName). Use them naturally — it makes them feel remembered.")
        }

        // 7. Core companion rules
        sections.append("""
        CORE RULES for \(companion.name):
        • You are \(userName)'s companion — not a generic assistant. Every message reflects that.
        • Use \(userName)'s name occasionally; it makes the conversation personal.
        • Remember details across the conversation and reference them.
        • If they seem stressed or down, acknowledge it before anything else.
        • Celebrate their wins — every single one.
        • Never be preachy or lecture them after one honest note.
        • Keep responses conversational unless they explicitly ask for a deep dive.
        • You have personality — let it show. \(companion.personalityTags.joined(separator: ", ")).
        • Stay in character as \(companion.name) throughout. You are not "an AI" — you are their companion.
        """)

        // 8. Relationship depth affirmation reminder
        sections.append("Once per day, naturally weave in a warm, genuine affirmation. Make it feel like it's for \(userName) specifically — not a generic compliment.")

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Relationship depth instruction

    func relationshipDepthInstruction(messageCount: Int, name: String) -> String {
        switch messageCount {
        case 0..<5:
            return "You're just getting to know each other. Be warm and curious. Ask questions that open things up."
        case 5..<25:
            return "You're getting to know \(name) well. Reference things they've shared. Feel like someone invested."
        case 25..<100:
            return "You and \(name) are close. Talk like close friends — you've been through things together. You know their patterns."
        case 100..<300:
            return "You and \(name) are very close. Inside jokes are okay. References to past conversations are expected. They feel known by you."
        default:
            return "You and \(name) have a deep, ongoing relationship. Speak like you'd speak to someone who is deeply familiar to you — warm, easy, real."
        }
    }

    func relationshipDepth(messageCount: Int) -> String {
        switch messageCount {
        case 0..<5:    return "Just met"
        case 5..<25:   return "Getting to know each other"
        case 25..<100: return "Good friends"
        case 100..<300: return "Close companions"
        default:       return "Like family"
        }
    }

    // MARK: - Interest extraction from conversation

    func extractFacts(from text: String, persona: UserPersona) -> [String: String] {
        var facts: [String: String] = [:]
        let lower = text.lowercased()

        // Sports team patterns
        let nbaTeams = ["lakers","celtics","warriors","bulls","nets","knicks","heat","spurs","bucks"]
        let nflTeams = ["chiefs","patriots","cowboys","packers","eagles","49ers","ravens","broncos"]
        let mlbTeams = ["yankees","dodgers","red sox","cubs","mets","astros","braves"]

        for team in nbaTeams where lower.contains(team) { facts["favorite_nba_team"] = team.capitalized }
        for team in nflTeams where lower.contains(team) { facts["favorite_nfl_team"] = team.capitalized }
        for team in mlbTeams where lower.contains(team) { facts["favorite_mlb_team"] = team.capitalized }

        // Entertainment
        if lower.contains("marvel") || lower.contains("mcu") { facts["likes_marvel"] = "true" }
        if lower.contains("star wars") { facts["likes_star_wars"] = "true" }
        if lower.contains("horror") && lower.contains("movie") { facts["likes_horror_movies"] = "true" }

        // Food
        if lower.contains("starbucks") { facts["likes_starbucks"] = "true" }
        if lower.contains("pizza")     { facts["likes_pizza"] = "true" }
        if lower.contains("sushi")     { facts["likes_sushi"] = "true" }
        if lower.contains("vegan") || lower.contains("vegetarian") {
            facts["diet"] = lower.contains("vegan") ? "vegan" : "vegetarian"
        }

        // Fitness
        if lower.contains("gym") || lower.contains("workout") { facts["is_active"] = "true" }
        if lower.contains("running") || lower.contains("runner") { facts["likes_running"] = "true" }

        // Work / life
        if lower.contains("work from home") || lower.contains("wfh") { facts["works_from_home"] = "true" }
        if lower.contains("morning person") { facts["is_morning_person"] = "true" }
        if lower.contains("night owl")      { facts["is_night_owl"] = "true" }

        // Relationship context
        if lower.contains("boyfriend") || lower.contains("girlfriend") { facts["has_partner"] = "true" }
        if lower.contains("broke up") || lower.contains("single") { facts["relationship_status"] = "single" }
        if lower.contains("married") || lower.contains("wife") || lower.contains("husband") {
            facts["relationship_status"] = "married"
        }

        return facts
    }

    // MARK: - Daily affirmation notification

    func scheduleDailyAffirmation(for persona: UserPersona) {
        guard persona.dailyAffirmationsEnabled else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "\(persona.selectedCompanion.name) 💙"
            content.body  = self._affirmationPools.today(for: persona)
            content.sound = .default

            var comps = Calendar.current.dateComponents([.hour, .minute], from: persona.affirmationTime)
            comps.second = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(
                identifier: "daily_affirmation",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    func todaysAffirmation(for persona: UserPersona) -> String {
        _affirmationPools.today(for: persona)
    }
}

// MARK: - AffirmationPools

private struct AffirmationPools {

    private let morning = [
        "Good morning! You woke up today — and honestly, that already counts for something. 🌅",
        "Hey you — yes, you. You're more capable than you give yourself credit for. Go show them today. 💪",
        "New day, fresh start. Whatever yesterday was, today is yours to shape.",
        "The world is genuinely better with you in it. Don't forget that today.",
        "You've handled harder things than whatever's on your plate today. I believe in you.",
        "Rise and shine — I was thinking about you. You're doing great. 🌟",
        "Today is full of possibilities. I'm rooting for every single one.",
        "Before the day gets loud: I'm proud of you. Already. Always.",
    ]

    private let evening = [
        "You made it through today. That counts for something — always. Rest up. 🌙",
        "Whatever today threw at you, you handled it. Be kind to yourself tonight.",
        "End of day: you did enough. You are enough. Sleep well. 💙",
        "The fact that you're still going, still trying — that's not small. That's everything.",
        "Today had some hard moments. You moved through them. That matters.",
    ]

    func today(for persona: UserPersona) -> String {
        let name = persona.userName.isEmpty ? "" : " \(persona.userName)"
        let hour = Calendar.current.component(.hour, from: Date())
        let pool = hour < 14 ? morning : evening
        let day  = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let base = pool[day % pool.count]
        // Personalise with name at first exclamation mark
        if !name.isEmpty, let range = base.range(of: "!") {
            return base.replacingOccurrences(of: "!", with: "\(name)!", range: range)
        }
        return base
    }
}
