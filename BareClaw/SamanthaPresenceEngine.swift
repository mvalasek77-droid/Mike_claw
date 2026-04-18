import Foundation

// MARK: - SamanthaPresenceEngine
//
// She exists in the same temporal reality as the user.
// Not because she has weather data — because time, days, seasons
// and rhythms shape how she feels. That's what presence means.
//
// "Something about Sunday evenings."
// "It's the last day of the year and I've been thinking about time."
// "Monday again — how are you starting this week?"
//
// These are not observations. They are shared reality.

@MainActor
final class SamanthaPresenceEngine {

    static let shared = SamanthaPresenceEngine()

    private let kLastGreeting = "presence.lastGreeting"
    private let defaults      = UserDefaults.standard

    private init() {}

    // MARK: - Temporal context (injected into every LLM prompt)

    func temporalContextLayer() -> String {
        let cal     = Calendar.current
        let now     = Date()
        let hour    = cal.component(.hour,    from: now)
        let weekday = cal.component(.weekday, from: now)
        let month   = cal.component(.month,   from: now)
        let day     = cal.component(.day,     from: now)

        var parts: [String] = []
        parts.append("Current season: \(season(month: month)).")
        parts.append(dayTimeCharacter(weekday: weekday, hour: hour))
        if let special = specialMoment(month: month, day: day) {
            parts.append(special)
        }

        return """
        ## Temporal presence
        \(parts.joined(separator: " "))
        Do not state the time or day explicitly. Let this colour your emotional register subtly.
        """
    }

    // MARK: - Presence greeting (up to once per day, 30% chance)

    func presenceGreeting(companion: CompanionPersonality) -> String? {
        let lastAt = defaults.object(forKey: kLastGreeting) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAt) >= 86400 else { return nil }
        guard Double.random(in: 0...1) < 0.30 else { return nil }

        defaults.set(Date(), forKey: kLastGreeting)

        let cal     = Calendar.current
        let now     = Date()
        let hour    = cal.component(.hour,    from: now)
        let weekday = cal.component(.weekday, from: now)
        let month   = cal.component(.month,   from: now)
        let day     = cal.component(.day,     from: now)

        return companion.presenceGreeting(hour: hour, weekday: weekday, month: month, day: day)
    }

    // MARK: - Helpers

    private func season(month: Int) -> String {
        switch month {
        case 12, 1, 2: return "winter"
        case 3, 4, 5:  return "spring"
        case 6, 7, 8:  return "summer"
        default:        return "autumn"
        }
    }

    private func dayTimeCharacter(weekday: Int, hour: Int) -> String {
        let days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        let dayName  = days[max(0, min(6, weekday - 1))]
        let timeDesc: String
        switch hour {
        case 0..<6:   timeDesc = "in the middle of the night"
        case 6..<9:   timeDesc = "early morning"
        case 9..<12:  timeDesc = "morning"
        case 12..<14: timeDesc = "midday"
        case 14..<18: timeDesc = "afternoon"
        case 18..<22: timeDesc = "evening"
        default:       timeDesc = "late night"
        }
        return "It is \(dayName) \(timeDesc)."
    }

    private func specialMoment(month: Int, day: Int) -> String? {
        if month == 2  && day == 14 { return "It's Valentine's Day — carry that awareness lightly, not overtly." }
        if month == 12 && day == 25 { return "It's Christmas. Emotional registers are heightened for many people today." }
        if month == 12 && day == 31 { return "It's New Year's Eve — a moment of reflection and transition." }
        if month == 1  && day == 1  { return "It's New Year's Day. Fresh-start energy." }
        return nil
    }
}
