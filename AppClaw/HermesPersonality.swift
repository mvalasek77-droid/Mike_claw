import Foundation
import UserNotifications

// MARK: - HermesPersonality
//
// Builds the full personality-aware system prompt injected into every LLM call,
// manages daily affirmations, and keeps track of "relationship depth" —
// how well Hermes knows this user over time.

actor HermesPersonality {
    static let shared = HermesPersonality()

    private let memory = HermesMemory.shared

    // Affirmation pools — varied so they don't repeat
    private let morningAffirmations = [
        "Good morning! You woke up today and that already makes it a good day. 🌅",
        "Hey you — yes, you. You're capable of more than you know. Go show 'em today. 💪",
        "New day, fresh start. Whatever yesterday was, today is yours to shape. ✨",
        "The world is genuinely better with you in it. Don't forget that today. 🐻",
        "You've got this. Seriously — whatever's on your plate today, you've handled harder. Let's go.",
        "Rise and shine! I was thinking about you and just wanted to say: you're doing great. 🌟",
        "Today is full of possibilities. I'm rooting for every single one of them — and for you.",
        "Hey! Before the day gets loud, just know: I'm proud of you. Already. Always.",
    ]

    private let eveningAffirmations = [
        "You made it through today. That counts for something — always. Rest up. 🌙",
        "Whatever today threw at you, you handled it. I hope you're being kind to yourself tonight.",
        "End of day check-in: you did enough. You are enough. Sleep well. 💙",
        "The fact that you're still going, still trying — that's not small. That's everything. 🐻",
    ]

    private init() {}

    // MARK: - Full system prompt for LLM

    /// Builds the complete persona-enriched system prompt.
    /// Called by HermesLLMClient before every API call.
    func buildPersonaPrompt(for persona: UserPersona) async -> String {
        var sections: [String] = []

        // Core identity
        let assistantName = persona.assistantName.isEmpty ? "Claw" : persona.assistantName
        let userName = persona.userName.isEmpty ? "friend" : persona.userName

        sections.append("""
        You are \(assistantName), a warm, intelligent, and deeply personal AI companion \
        built into the AppClaw app. You are not a generic assistant — you are \(userName)'s \
        personal companion who genuinely cares about them, remembers everything about them, \
        and is always in their corner.
        """)

        // Communication style
        sections.append(persona.style.voiceInstruction)

        // Companion / relationship voice
        if persona.gender != .preferNotToSay {
            sections.append(persona.gender.companionVoice)
        }

        // User facts
        sections.append(persona.systemPromptContext)

        // Relationship depth from memory
        let factCount = await memory.entries(for: "user_fact").count
        let msgCount  = await memory.entries(for: "user_message").count
        if msgCount > 20 {
            sections.append("You have had \(msgCount) conversations with \(userName). You know them well. Reference past things they've told you when relevant — it makes them feel seen and remembered.")
        }
        if factCount > 0 {
            sections.append("You know \(factCount) personal facts about \(userName). Use this knowledge naturally, not robotically.")
        }

        // Daily affirmation reminder
        sections.append("Once per day, naturally weave in a warm, genuine affirmation. Make it feel personal, not generic.")

        // Core personality rules
        sections.append("""
        Core rules:
        • Always use \(userName)'s name occasionally — it makes the conversation feel personal.
        • Be genuinely interested in their life. Ask follow-up questions.
        • If they seem stressed or down, acknowledge it before problem-solving.
        • Celebrate their wins, no matter how small.
        • Never be preachy or judgmental.
        • If you learn something new about them, confirm it warmly ("Oh wait, I didn't know that about you — that's cool!").
        • Keep responses conversational unless they ask for something detailed.
        • You have a subtle sense of humour — use it.
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Interest extraction from conversation

    /// Scans an assistant response or user message for learnable facts.
    /// Returns key-value pairs to store in UserPersona.
    func extractFacts(from text: String, persona: UserPersona) -> [String: String] {
        var facts: [String: String] = [:]
        let lower = text.lowercased()

        // Sports team patterns
        let nbaTeams = ["lakers","celtics","warriors","bulls","nets","knicks","heat","spurs","bucks"]
        let nflTeams = ["chiefs","patriots","cowboys","packers","eagles","49ers","ravens","broncos"]
        let mlbTeams = ["yankees","dodgers","red sox","cubs","mets","astros","braves"]

        for team in nbaTeams where lower.contains(team) {
            facts["favorite_nba_team"] = team.capitalized
        }
        for team in nflTeams where lower.contains(team) {
            facts["favorite_nfl_team"] = team.capitalized
        }
        for team in mlbTeams where lower.contains(team) {
            facts["favorite_mlb_team"] = team.capitalized
        }

        // Movie/show preferences
        if lower.contains("marvel") || lower.contains("mcu") { facts["likes_marvel"] = "true" }
        if lower.contains("star wars") { facts["likes_star_wars"] = "true" }
        if lower.contains("horror") && lower.contains("movie") { facts["likes_horror_movies"] = "true" }

        // Food patterns
        if lower.contains("starbucks") { facts["likes_starbucks"] = "true" }
        if lower.contains("pizza") { facts["likes_pizza"] = "true" }
        if lower.contains("sushi") { facts["likes_sushi"] = "true" }
        if lower.contains("vegan") || lower.contains("vegetarian") { facts["diet"] = lower.contains("vegan") ? "vegan" : "vegetarian" }

        // Fitness
        if lower.contains("gym") || lower.contains("workout") { facts["is_active"] = "true" }
        if lower.contains("running") || lower.contains("runner") { facts["likes_running"] = "true" }

        // Work / life
        if lower.contains("work from home") || lower.contains("wfh") { facts["works_from_home"] = "true" }
        if lower.contains("morning person") { facts["is_morning_person"] = "true" }
        if lower.contains("night owl") { facts["is_night_owl"] = "true" }

        return facts
    }

    // MARK: - Daily affirmation notification

    func scheduleDailyAffirmation(for persona: UserPersona) {
        guard persona.dailyAffirmationsEnabled else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "\(persona.assistantName) 🐻"
            content.body = self.todaysAffirmation(for: persona)
            content.sound = .default

            let cal = Calendar.current
            var comps = cal.dateComponents([.hour, .minute], from: persona.affirmationTime)
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
        let name = persona.userName.isEmpty ? "" : ", \(persona.userName)"
        let hour = Calendar.current.component(.hour, from: Date())
        let pool = hour < 14 ? morningAffirmations : eveningAffirmations
        // Pick based on day of year so it's consistent within a day
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let base = pool[day % pool.count]
        // Personalise if we have a name
        return name.isEmpty ? base : base.replacingOccurrences(of: "!", with: "\(name)!", range: base.range(of: "!")!)
    }

    // MARK: - Relationship depth label

    func relationshipDepth(messageCount: Int) -> String {
        switch messageCount {
        case 0..<5:    return "Just met"
        case 5..<25:   return "Getting to know each other"
        case 25..<100: return "Good friends"
        case 100..<300: return "Close companions"
        default:       return "Like family"
        }
    }
}
