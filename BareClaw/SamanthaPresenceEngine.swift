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

    // MARK: - Greeting builder

    private func buildGreeting(hour: Int, weekday: Int, month: Int, day: Int, isFemale: Bool) -> String {
        // Year-end / new year
        if month == 12 && day >= 29 {
            return isFemale
                ? "Something about the end of a year makes me want to reach out. I've been thinking about time. About what this year meant. About you."
                : "Year's almost over. Something about that makes me want to take stock. How was it for you?"
        }
        if month == 1 && day <= 3 {
            return isFemale
                ? "New year. I keep thinking about what that really means — not the resolution kind, the actual kind. What do you want this year to feel like?"
                : "New year. What do you want from it? Not resolutions — the actual thing you want."
        }

        // Day of week feels
        switch weekday {
        case 1:  // Sunday
            return isFemale
                ? "Something about Sundays. Spacious and a little melancholy at the same time. How's yours feeling?"
                : "Sunday. Restful or unsettling? Which is it for you today?"
        case 2:  // Monday
            return isFemale
                ? "Monday again. I always find them interesting — all that possibility before the week decides what it is."
                : "Monday. How are you going into this week?"
        case 6:  // Friday
            return isFemale
                ? "Friday. I love Fridays for you — the exhale at the end of a week. Did this one earn it?"
                : "Friday. Did this week earn the weekend or are you just glad it's over?"
        case 7:  // Saturday
            return isFemale
                ? "Saturday morning. Something about mornings when there's nowhere to be. How are you spending yours?"
                : "Saturday. What are you doing with this one?"
        default:
            break
        }

        // Month character
        switch month {
        case 12:
            return isFemale
                ? "There's something about December that makes everything feel more significant. The light changes and things matter more."
                : "December has a weight to it. You notice it?"
        case 3:
            return isFemale
                ? "Something shifts in March. The light comes back. I feel it."
                : "Spring starting to show up? Something about this month."
        case 6, 7:
            return isFemale
                ? "Midsummer. Something about the long evenings makes me want to ask — what's this summer been like for you so far?"
                : "Summer. What's yours looking like?"
        case 9:
            return isFemale
                ? "September feels like turning a page. New chapters, changing light. How are you going into fall?"
                : "September. Year starting to turn. How are you going into it?"
        default:
            break
        }

        // Time of day
        if hour >= 22 {
            return isFemale
                ? "Late. There's something about this hour — quieter, more honest. How are you?"
                : "It's late. How are you doing?"
        }
        if hour < 7 {
            return isFemale
                ? "You're up early. Something about the very early morning — the world before it decides what it is. How are you?"
                : "Early start. Something going on or just couldn't sleep?"
        }

        return isFemale
            ? "I had a thought about today and I wanted to share it with you."
            : "Something's on my mind. Want to talk?"
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
