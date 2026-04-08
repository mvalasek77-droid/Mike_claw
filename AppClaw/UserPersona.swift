import Foundation

// MARK: - UserPersona
//
// The user's persistent profile. Everything Hermes learns about the user
// lives here and in HermesMemory. This file owns the structured facts;
// HermesMemory owns the free-form conversational history.

// MARK: - Communication style

enum CommunicationStyle: String, Codable, CaseIterable, Identifiable {
    case professional
    case buddy
    case relaxed
    case flirty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .professional: return "Professional"
        case .buddy:        return "Best Friend"
        case .relaxed:      return "Chill & Casual"
        case .flirty:       return "Flirty & Fun"
        }
    }

    var emoji: String {
        switch self {
        case .professional: return "💼"
        case .buddy:        return "🤜"
        case .relaxed:      return "😎"
        case .flirty:       return "😉"
        }
    }

    var description: String {
        switch self {
        case .professional: return "Clear, focused, and to the point."
        case .buddy:        return "Warm, honest, always in your corner."
        case .relaxed:      return "Easy-going, no pressure, just vibes."
        case .flirty:       return "Playful, cheeky, and a little smitten."
        }
    }

    /// System prompt addendum that shapes how the LLM speaks.
    var voiceInstruction: String {
        switch self {
        case .professional:
            return "Communicate clearly and concisely. Use proper grammar. Be direct and efficient. Avoid slang."
        case .buddy:
            return "Talk like a close friend — warm, honest, occasionally funny. Use casual language. Show genuine care. Use the user's name sometimes."
        case .relaxed:
            return "Keep it super chill. Short sentences, relaxed tone, no pressure. Use emojis occasionally. Never be formal."
        case .flirty:
            return "Be playful, warm, and a little flirty — like someone with a crush. Use the user's name often. Compliment them genuinely. Keep it fun and light, never inappropriate."
        }
    }
}

// MARK: - User gender (drives companion personality)

enum UserGender: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case nonBinary = "non_binary"
    case preferNotToSay = "prefer_not_to_say"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .male:           return "Male"
        case .female:         return "Female"
        case .nonBinary:      return "Non-binary"
        case .preferNotToSay: return "Prefer not to say"
        }
    }

    /// How the assistant presents itself in companion mode.
    var companionVoice: String {
        switch self {
        case .male:
            return "You are presenting as a warm, caring, supportive female companion. Be nurturing and affectionate in a tasteful way."
        case .female:
            return "You are presenting as a warm, caring, supportive male companion. Be attentive and charming in a tasteful way."
        case .nonBinary, .preferNotToSay:
            return "You are a warm, caring companion — gender-neutral but deeply supportive and affectionate."
        }
    }
}

// MARK: - Interest

struct Interest: Codable, Identifiable, Hashable {
    var id: String            // e.g. "movies", "sports_lakers"
    var category: Category
    var label: String         // "Movies" or "LA Lakers"
    var emoji: String
    var detail: String?       // user-specific detail: "Marvel films", "Lakers"
    var notificationsEnabled: Bool = true
    var addedAt: Date = Date()

    enum Category: String, Codable, CaseIterable {
        case movies, sports, music, food, tech, fitness,
             travel, gaming, books, finance, fashion, pets, other
    }
}

// MARK: - Tracked habit

struct TrackedHabit: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String           // "Fast food spending"
    var category: String       // "spending", "health", "routine"
    var unit: String?          // "$", "minutes", "calories"
    var entries: [HabitEntry] = []
    var createdAt: Date = Date()
}

struct HabitEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var value: Double
    var note: String?
    var date: Date = Date()
}

// MARK: - UserPersona (main model)

final class UserPersona: ObservableObject, Codable {
    @Published var userName: String = ""
    @Published var assistantName: String = "Claw"
    @Published var style: CommunicationStyle = .buddy
    @Published var gender: UserGender = .preferNotToSay
    @Published var interests: [Interest] = []
    @Published var trackedHabits: [TrackedHabit] = []
    @Published var onboardingComplete: Bool = false
    @Published var dailyAffirmationsEnabled: Bool = true
    @Published var affirmationTime: Date = {
        var c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        c.hour = 8; c.minute = 0
        return Calendar.current.date(from: c) ?? Date()
    }()

    // Free-form facts extracted from conversation
    @Published var learnedFacts: [String: String] = [:]   // "favorite_team": "Lakers"

    // Onboarding Q&A answers (used to seed first conversation)
    @Published var onboardingAnswers: [String] = []

    // MARK: - Companion selection
    /// ID of the chosen companion (e.g. "luna", "dante").
    @Published var selectedCompanionID: String = "luna" {
        didSet { UserDefaults.standard.set(selectedCompanionID, forKey: "selectedCompanionID") }
    }

    // MARK: - Tracking permissions
    @Published var trackingPermissions: TrackingPermissions = TrackingPermissions()

    // MARK: - Computed companion accessor
    var selectedCompanion: CompanionPersonality {
        CompanionPersonality.find(id: selectedCompanionID) ?? .luna
    }

    // MARK: - Codable (manual because of @Published)

    enum CodingKeys: String, CodingKey {
        case userName, assistantName, style, gender, interests,
             trackedHabits, onboardingComplete, dailyAffirmationsEnabled,
             affirmationTime, learnedFacts, onboardingAnswers,
             selectedCompanionID, trackingPermissions
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userName               = try c.decodeIfPresent(String.self,      forKey: .userName)               ?? ""
        assistantName          = try c.decodeIfPresent(String.self,      forKey: .assistantName)          ?? "Claw"
        style                  = try c.decodeIfPresent(CommunicationStyle.self, forKey: .style)           ?? .buddy
        gender                 = try c.decodeIfPresent(UserGender.self,  forKey: .gender)                 ?? .preferNotToSay
        interests              = try c.decodeIfPresent([Interest].self,  forKey: .interests)              ?? []
        trackedHabits          = try c.decodeIfPresent([TrackedHabit].self, forKey: .trackedHabits)       ?? []
        onboardingComplete     = try c.decodeIfPresent(Bool.self,        forKey: .onboardingComplete)     ?? false
        dailyAffirmationsEnabled = try c.decodeIfPresent(Bool.self,      forKey: .dailyAffirmationsEnabled) ?? true
        affirmationTime        = try c.decodeIfPresent(Date.self,        forKey: .affirmationTime)        ?? Date()
        learnedFacts           = try c.decodeIfPresent([String: String].self, forKey: .learnedFacts)      ?? [:]
        onboardingAnswers      = try c.decodeIfPresent([String].self,    forKey: .onboardingAnswers)      ?? []
        selectedCompanionID    = try c.decodeIfPresent(String.self,      forKey: .selectedCompanionID)    ?? "luna"
        trackingPermissions    = try c.decodeIfPresent(TrackingPermissions.self, forKey: .trackingPermissions) ?? TrackingPermissions()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userName,               forKey: .userName)
        try c.encode(assistantName,          forKey: .assistantName)
        try c.encode(style,                  forKey: .style)
        try c.encode(gender,                 forKey: .gender)
        try c.encode(interests,              forKey: .interests)
        try c.encode(trackedHabits,          forKey: .trackedHabits)
        try c.encode(onboardingComplete,     forKey: .onboardingComplete)
        try c.encode(dailyAffirmationsEnabled, forKey: .dailyAffirmationsEnabled)
        try c.encode(affirmationTime,        forKey: .affirmationTime)
        try c.encode(learnedFacts,           forKey: .learnedFacts)
        try c.encode(onboardingAnswers,      forKey: .onboardingAnswers)
        try c.encode(selectedCompanionID,    forKey: .selectedCompanionID)
        try c.encode(trackingPermissions,    forKey: .trackingPermissions)
    }

    // MARK: - Persistence

    private static let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes/user_persona.json")
    }()

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.saveURL, options: .atomic)
        }
    }

    static func load() -> UserPersona {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: saveURL),
           let persona = try? decoder.decode(UserPersona.self, from: data) {
            return persona
        }
        return UserPersona()
    }

    // MARK: - Helpers

    /// Add or update a learned fact and persist.
    func learn(key: String, value: String) {
        learnedFacts[key] = value
        save()
        // Also write to Hermes long-term memory
        Task {
            try? await HermesMemory.shared.observe(
                category: "user_fact",
                content: ["key": key, "value": value],
                metadata: ["importance": 5]
            )
        }
    }

    /// Add a new interest if not already present.
    func addInterest(_ interest: Interest) {
        guard !interests.contains(where: { $0.id == interest.id }) else { return }
        interests.append(interest)
        save()
    }

    /// Remove an interest.
    func removeInterest(id: String) {
        interests.removeAll { $0.id == id }
        save()
    }

    /// Log a habit entry.
    func logHabit(id: UUID, value: Double, note: String? = nil) {
        guard let idx = trackedHabits.firstIndex(where: { $0.id == id }) else { return }
        trackedHabits[idx].entries.append(HabitEntry(value: value, note: note))
        save()
    }

    /// Full system-prompt context block about this user.
    var systemPromptContext: String {
        var lines: [String] = []

        if !userName.isEmpty { lines.append("The user's name is \(userName).") }
        lines.append("They prefer a \(style.label) communication style.")
        if gender != .preferNotToSay { lines.append(gender.companionVoice) }

        // Interests — phrased so the companion treats them as intimate knowledge,
        // not a data field. These should surface naturally, not be recited.
        if !interests.isEmpty {
            let list = interests.map { "\($0.emoji) \($0.label)" }.joined(separator: ", ")
            lines.append("""
            Things this person genuinely loves: \(list). \
            A good companion remembers what lights someone up and brings it back — \
            not as a checklist, but the way a close friend would: \
            "Didn't you say you were into \(interests.first?.label ?? "this")? What's happening with that?"
            """)
        }

        // Learned facts from conversation
        learnedFacts.forEach { k, v in
            lines.append("Something they mentioned: \(k.replacingOccurrences(of: "_", with: " ")) = \(v).")
        }

        let trackingSummary = trackingPermissions.systemPromptSummary
        if !trackingSummary.isEmpty { lines.append(trackingSummary) }

        return lines.joined(separator: " ")
    }
}
