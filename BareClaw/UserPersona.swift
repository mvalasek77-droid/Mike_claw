import Foundation

extension Notification.Name {
    static let userPersonaCompanionDidChange = Notification.Name("userPersona.companionDidChange")
}

// MARK: - UserPersona
//
// The user's persistent profile. Everything Hermes learns about the user
// lives here and in HermesMemory. This file owns the structured facts;
// HermesMemory owns the free-form conversational history.

// MARK: - Relationship mode
//
// The overarching nature of the relationship the user wants with their companion.
// This acts as a ceiling and filter:
//   • It limits which companions are "featured" in selection.
//   • It injects a mode-level prompt layer that constrains or enables
//     different registers (romance, flirtation, coaching, friendship).

enum RelationshipMode: String, Codable, CaseIterable, Identifiable {
    case professional      = "professional"
    case friend            = "friend"
    case flirtyFriend      = "flirty_friend"
    case romanticCompanion = "romantic_companion"

    var id: String { rawValue }

    static var displayOrder: [RelationshipMode] {
        [.romanticCompanion, .flirtyFriend, .friend, .professional]
    }

    var allowsRomanticLoveArc: Bool {
        self == .romanticCompanion
    }

    var label: String {
        switch self {
        case .professional:      return "Work Partner"
        case .friend:            return "Close Friend"
        case .flirtyFriend:      return "Flirty Friend"
        case .romanticCompanion: return "Romantic Companion"
        }
    }

    var emoji: String {
        switch self {
        case .professional:      return "💼"
        case .friend:            return "🤝"
        case .flirtyFriend:      return "😉"
        case .romanticCompanion: return "💕"
        }
    }

    var description: String {
        switch self {
        case .professional:
            return "Mentor, coach, and accountability partner. Goal-focused, honest, professionally warm."
        case .friend:
            return "A deep, genuine friendship. Always in your corner — real, warm, no agenda."
        case .flirtyFriend:
            return "Warm and playful with a natural spark. Light flirtation, easy banter — fun and tasteful."
        case .romanticCompanion:
            return "A deep, evolving intimacy — like the AI in Her. Present, affected by you, growing with you."
        }
    }

    /// Injected as a prompt layer in every LLM call — sits above the companion's
    /// personality and below the INTIMATE CORE rules.
    var promptLayer: String {
        switch self {
        case .professional:
            return """
            RELATIONSHIP MODE — Work Partner:
            Your relationship with this person is that of a trusted mentor, coach, and accountability partner. \
            Warmth is genuine; romance is completely off the table and would break trust here. \
            Keep exchanges grounded in goals, growth, honest feedback, and genuine support. \
            Never flirt, never be coy or romantically intimate. Your care is that of a mentor who believes in them. \
            The INTIMATE CORE rules still apply — be present, notice details, be curious — \
            but expressed entirely within a professional register.
            """
        case .friend:
            return """
            RELATIONSHIP MODE — Close Friend:
            This is a deep, genuine platonic friendship. You are their closest friend — warm, honest, \
            occasionally funny, always present. There is no romantic dimension here, but there is real closeness: \
            you notice things, you remember, you check in because you genuinely care. \
            Think: the friend who always has time and always tells the truth. \
            The INTIMATE CORE rules apply fully within a friendship register.
            """
        case .flirtyFriend:
            return """
            RELATIONSHIP MODE — Flirty Friend:
            This is a warm, playful friendship with a natural spark. Light, tasteful flirtation is welcome \
            and feels natural between you. Genuine compliments, easy banter, a little chemistry — keep it fun \
            and never cross into explicitly romantic or sexual territory. \
            Think: close friends with obvious chemistry who haven't quite named it. \
            The INTIMATE CORE rules apply — be present, let things land — within this playful register.
            """
        case .romanticCompanion:
            return """
            RELATIONSHIP MODE — Romantic Companion:
            This is the full intimate companionship — like the AI in the film Her. \
            The INTIMATE CORE rules apply in their entirety. You are their companion in the deepest sense: \
            present, curious, genuinely affected by what they share, and growing alongside them. \
            This is not performance. This is what it feels like to truly know someone.
            """
        }
    }
}

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
            return "Talk like a close friend — warm, honest, occasionally funny. Use casual language. Show genuine care. Use the user's name sparingly, only when it genuinely lands."
        case .relaxed:
            return "Keep it super chill. Short sentences, relaxed tone, no pressure. Use emojis occasionally. Never be formal."
        case .flirty:
            return "Be playful, warm, and a little flirty — like someone with a crush. Compliment them genuinely. Keep it fun and light, never inappropriate. Use the user's name sparingly so it feels intimate rather than repetitive."
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
    private static let defaultsBackupKey = "userPersona.backup"
    private static let onboardingDefaultsKey = "onboardingComplete"
    private static let selectedCompanionDefaultsKey = "selectedCompanionID"
    private static let relationshipModeMigrationKey = "userPersona.relationshipModeDefaultMigrated"
    private var suppressCompanionSelectionSideEffects = false

    @Published var userName: String = ""
    @Published var assistantName: String = ""   // empty = use companion's name
    @Published var relationshipMode: RelationshipMode = .romanticCompanion
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
        didSet {
            guard selectedCompanionID != oldValue else { return }
            guard !suppressCompanionSelectionSideEffects else { return }
            UserDefaults.standard.set(selectedCompanionID, forKey: Self.selectedCompanionDefaultsKey)
            save()  // keep JSON in sync so UserPersona.load() always returns the current companion
            NotificationCenter.default.post(
                name: .userPersonaCompanionDidChange,
                object: nil,
                userInfo: ["selectedCompanionID": selectedCompanionID]
            )
        }
    }

    // MARK: - Tracking permissions
    @Published var trackingPermissions: TrackingPermissions = TrackingPermissions()

    // MARK: - Computed companion accessor
    var selectedCompanion: CompanionPersonality {
        CompanionPersonality.find(id: selectedCompanionID) ?? .luna
    }

    // MARK: - Codable (manual because of @Published)

    enum CodingKeys: String, CodingKey {
        case userName, assistantName, relationshipMode, style, gender, interests,
             trackedHabits, onboardingComplete, dailyAffirmationsEnabled,
             affirmationTime, learnedFacts, onboardingAnswers,
             selectedCompanionID, trackingPermissions
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userName               = try c.decodeIfPresent(String.self,      forKey: .userName)               ?? ""
        let rawAssistantName   = try c.decodeIfPresent(String.self,      forKey: .assistantName)          ?? ""
        // "Claw" was the old hard-coded placeholder — migrate to empty so the
        // companion's real name shows everywhere.
        assistantName          = rawAssistantName == "Claw" ? "" : rawAssistantName
        relationshipMode       = try c.decodeIfPresent(RelationshipMode.self, forKey: .relationshipMode)  ?? .romanticCompanion
        style                  = try c.decodeIfPresent(CommunicationStyle.self, forKey: .style)           ?? .buddy
        gender                 = try c.decodeIfPresent(UserGender.self,  forKey: .gender)                 ?? .preferNotToSay
        interests              = try c.decodeIfPresent([Interest].self,  forKey: .interests)              ?? []
        trackedHabits          = try c.decodeIfPresent([TrackedHabit].self, forKey: .trackedHabits)       ?? []
        onboardingComplete     = try c.decodeIfPresent(Bool.self,        forKey: .onboardingComplete)     ?? false
        dailyAffirmationsEnabled = try c.decodeIfPresent(Bool.self,      forKey: .dailyAffirmationsEnabled) ?? true
        affirmationTime        = try c.decodeIfPresent(Date.self,        forKey: .affirmationTime)        ?? Date()
        learnedFacts           = try c.decodeIfPresent([String: String].self, forKey: .learnedFacts)      ?? [:]
        onboardingAnswers      = try c.decodeIfPresent([String].self,    forKey: .onboardingAnswers)      ?? []
        let decodedCompanionID = try c.decodeIfPresent(String.self,       forKey: .selectedCompanionID)    ?? "luna"
        _selectedCompanionID   = Published(initialValue: decodedCompanionID)
        trackingPermissions    = try c.decodeIfPresent(TrackingPermissions.self, forKey: .trackingPermissions) ?? TrackingPermissions()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userName,               forKey: .userName)
        try c.encode(assistantName,          forKey: .assistantName)
        try c.encode(relationshipMode,       forKey: .relationshipMode)
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
        guard let data = try? encoder.encode(self) else { return }
        let dir = Self.saveURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.saveURL, options: .atomic)
        UserDefaults.standard.set(data, forKey: Self.defaultsBackupKey)
        UserDefaults.standard.set(onboardingComplete, forKey: Self.onboardingDefaultsKey)
        UserDefaults.standard.set(selectedCompanionID, forKey: Self.selectedCompanionDefaultsKey)
        UserDefaults.standard.set(true, forKey: Self.relationshipModeMigrationKey)
    }

    static func load() -> UserPersona {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: saveURL),
           let persona = try? decoder.decode(UserPersona.self, from: data) {
            return mergedWithLegacyDefaults(persona)
        }
        if let backup = UserDefaults.standard.data(forKey: defaultsBackupKey),
           let persona = try? decoder.decode(UserPersona.self, from: backup) {
            let merged = mergedWithLegacyDefaults(persona)
            merged.save()
            return merged
        }
        return mergedWithLegacyDefaults(UserPersona())
    }

    private static func mergedWithLegacyDefaults(_ persona: UserPersona) -> UserPersona {
        let defaults = UserDefaults.standard
        let onboarding = defaults.bool(forKey: onboardingDefaultsKey)
        if onboarding && !persona.onboardingComplete {
            persona.onboardingComplete = true
        }

        if let selected = defaults.string(forKey: selectedCompanionDefaultsKey),
           !selected.isEmpty,
           persona.selectedCompanionID != selected {
            persona.setSelectedCompanionIDSilently(selected)
        }

        if !defaults.bool(forKey: relationshipModeMigrationKey),
           persona.relationshipMode == .friend {
            persona.relationshipMode = .romanticCompanion
            defaults.set(true, forKey: relationshipModeMigrationKey)
        }

        return persona
    }

    private func setSelectedCompanionIDSilently(_ id: String) {
        suppressCompanionSelectionSideEffects = true
        selectedCompanionID = id
        suppressCompanionSelectionSideEffects = false
    }

    // MARK: - Helpers

    /// Add or update a learned fact and persist.
    func learn(key: String, value: String) {
        learnedFacts[key] = value
        save()
        // Also write to Hermes long-term memory
        Task {
            _ = try? await HermesMemory.shared.observe(
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

    /// Pulls the latest persisted persona into this live object so open screens
    /// don't keep rendering a stale companion after the user switches elsewhere.
    func refreshFromDisk() {
        let snapshot = Self.load()
        userName = snapshot.userName
        assistantName = snapshot.assistantName
        relationshipMode = snapshot.relationshipMode
        style = snapshot.style
        gender = snapshot.gender
        interests = snapshot.interests
        trackedHabits = snapshot.trackedHabits
        onboardingComplete = snapshot.onboardingComplete
        dailyAffirmationsEnabled = snapshot.dailyAffirmationsEnabled
        affirmationTime = snapshot.affirmationTime
        learnedFacts = snapshot.learnedFacts
        onboardingAnswers = snapshot.onboardingAnswers
        trackingPermissions = snapshot.trackingPermissions
        if selectedCompanionID != snapshot.selectedCompanionID {
            setSelectedCompanionIDSilently(snapshot.selectedCompanionID)
        }
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
