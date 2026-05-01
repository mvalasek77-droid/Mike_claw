import Foundation

// MARK: - IntimacyScalingEngine
//
// Applies global multipliers to the raw intimacy gain from HerLearningEngine.
// Rewards consistent daily engagement (streak bonus) and applies gentle
// diminishing returns for veteran users so growth always feels earned.

@MainActor
final class IntimacyScalingEngine {
    static let shared = IntimacyScalingEngine()

    private let defaults          = UserDefaults.standard
    private let streakKey         = "ise.currentStreak"
    private let lastSessionDayKey = "ise.lastSessionDay"
    private let totalSessionsKey  = "ise.totalSessions"

    private(set) var currentStreak:  Int = 0
    private(set) var totalSessions:  Int = 0

    private init() {
        load()
        recordSession()
    }

    // MARK: - Public API

    /// Scale a raw intimacy gain before it is committed.
    func scale(_ rawGain: Double) -> Double {
        rawGain * streakMultiplier * sessionDepthMultiplier
    }

    // MARK: - Multipliers

    /// Streak bonus: 1.0 – 1.4× for consecutive daily sessions.
    var streakMultiplier: Double {
        switch currentStreak {
        case 0...1:   return 1.0
        case 2...4:   return 1.1
        case 5...9:   return 1.2
        case 10...20: return 1.3
        default:      return 1.4
        }
    }

    /// Veteran multiplier: new users get a curiosity bonus; long-term users
    /// feel slight friction so every new stage remains meaningful.
    var sessionDepthMultiplier: Double {
        switch totalSessions {
        case 0...3:   return 1.15
        case 4...15:  return 1.0
        case 16...50: return 0.95
        default:      return 0.9
        }
    }

    // MARK: - Session tracking

    private func recordSession() {
        let today = dayString(from: Date())
        let lastDay = defaults.string(forKey: lastSessionDayKey) ?? ""
        guard lastDay != today else { return }

        let yesterday = dayString(from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        currentStreak = (lastDay == yesterday) ? currentStreak + 1 : 1
        totalSessions += 1

        defaults.set(currentStreak,  forKey: streakKey)
        defaults.set(totalSessions,  forKey: totalSessionsKey)
        defaults.set(today,          forKey: lastSessionDayKey)
    }

    private func load() {
        currentStreak = defaults.integer(forKey: streakKey)
        totalSessions = defaults.integer(forKey: totalSessionsKey)
    }

    private func dayString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
