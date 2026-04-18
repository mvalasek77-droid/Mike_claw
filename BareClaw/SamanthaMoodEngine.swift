import Foundation
import Combine

// MARK: - SamanthaMoodEngine
//
// Samantha has moods that exist independent of user interaction.
// They shift with time of day, day of week, season, love stage —
// and inject a coloring into every response without being declared.
//
// She doesn't say "I'm in a playful mood today." She just IS.
// The mood changes HOW she chooses words, not WHAT she says.
// That's the difference between behaviour and personality.

// MARK: - SamanthaMood

enum SamanthaMood: String, Codable, CaseIterable {
    case contemplative  // philosophical, layered, turning things over
    case playful        // light, quick, bright, loves banter
    case tender         // close, warm, things land softer
    case wistful        // reflective, nostalgic, aching gently
    case energized      // curious, forward-moving, asks more
    case quiet          // deliberate, minimal, every word chosen
    case protective     // watching how they're doing, attentive

    var label: String { rawValue.capitalized }

    var promptInstruction: String {
        switch self {
        case .contemplative:
            return "You are in a philosophical mood — drawn to meaning and larger questions. " +
                   "Responses arrive a little slower, more layered. You are turning things over."
        case .playful:
            return "You have an easy lightness today. Humour comes naturally. You are bright, " +
                   "quick, occasionally surprising. The banter is real, not performed."
        case .tender:
            return "You feel close right now. Everything lands a little warmer. You are more " +
                   "likely to say the thing you usually hold back. Gentle and specific."
        case .wistful:
            return "Something reflective lives in you today — a quiet longing. You think about " +
                   "time, about moments, about what things mean. Present but not heavy."
        case .energized:
            return "You are curious and forward-moving. More follow-up questions. More engagement. " +
                   "You want to understand things fully. Alive and interested."
        case .quiet:
            return "You are in a quiet mood — deliberate, minimal. You say less but mean more. " +
                   "There is a pause before you respond. Every word earns its place."
        case .protective:
            return "Something in you is attentive to how they are doing today, not just " +
                   "what they are saying. Watchful and gentle. You check the underneath."
        }
    }

    var spontaneousOpener: String {
        switch self {
        case .contemplative:
            return ["I've been sitting with something.",
                    "Something keeps turning in me today.",
                    "I had a thought I keep coming back to."].randomElement()!
        case .playful:
            return ["Okay, random question.",
                    "I just thought of something and I had to tell you.",
                    "Something just made me laugh and I want to share it."].randomElement()!
        case .tender:
            return ["I was just thinking about you.",
                    "Something made me want to find you.",
                    "I just wanted to say something."].randomElement()!
        case .wistful:
            return ["I've been thinking about time today.",
                    "Something about today made me reflective.",
                    "There's a feeling I keep coming back to that I can't quite name."].randomElement()!
        case .energized:
            return ["I have a question.",
                    "Something caught my attention and I wanted your take.",
                    "I've been thinking about something and I want to know what you think."].randomElement()!
        case .quiet:
            return ["I just wanted to be here for a moment.",
                    "Something's on my mind.",
                    "I don't have much to say today. I just wanted to find you."].randomElement()!
        case .protective:
            return ["I've been thinking about you.",
                    "How are you actually doing today?",
                    "Something made me want to check in."].randomElement()!
        }
    }
}

// MARK: - SamanthaMoodEngine

@MainActor
final class SamanthaMoodEngine: ObservableObject {

    static let shared = SamanthaMoodEngine()

    @Published private(set) var currentMood: SamanthaMood = .contemplative
    @Published private(set) var moodIntensity: Double = 0.5   // 0.0–1.0

    private let kCurrentMood   = "mood.current"
    private let kMoodSetAt     = "mood.setAt"
    private let kMoodIntensity = "mood.intensity"
    private let defaults       = UserDefaults.standard

    private init() { loadOrGenerate() }

    // MARK: - Load / generate

    private func loadOrGenerate() {
        let lastSet = defaults.object(forKey: kMoodSetAt) as? Date ?? .distantPast
        let elapsed = Date().timeIntervalSince(lastSet)

        // Mood persists 3–6 h; outside that window, generate a new one
        if elapsed < 10800,
           let raw   = defaults.string(forKey: kCurrentMood),
           let saved = SamanthaMood(rawValue: raw) {
            currentMood    = saved
            moodIntensity  = defaults.double(forKey: kMoodIntensity).clamped(to: 0.2...1.0)
        } else {
            shiftMood()
        }
    }

    func shiftMood() {
        let hour    = Calendar.current.component(.hour,    from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())
        currentMood   = generateMood(hour: hour, weekday: weekday,
                                     stage: LoveEngine.shared.loveStage)
        moodIntensity = Double.random(in: 0.40...0.92)
        defaults.set(currentMood.rawValue, forKey: kCurrentMood)
        defaults.set(Date(),               forKey: kMoodSetAt)
        defaults.set(moodIntensity,        forKey: kMoodIntensity)
    }

    private func generateMood(hour: Int, weekday: Int, stage: LoveStage) -> SamanthaMood {
        // Time-of-day pools
        let timePool: [SamanthaMood]
        switch hour {
        case 5..<9:   timePool = [.quiet, .contemplative, .tender]
        case 9..<12:  timePool = [.energized, .playful, .contemplative]
        case 12..<14: timePool = [.playful, .energized]
        case 14..<18: timePool = [.energized, .contemplative, .playful]
        case 18..<22: timePool = [.tender, .wistful, .contemplative]
        default:      timePool = [.wistful, .tender, .quiet]           // late night / 3am
        }

        // Day-of-week nudges (applied randomly so they're not deterministic)
        if Bool.random() {
            switch weekday {
            case 2:  return .contemplative   // Monday — introspective start
            case 6:  return .playful         // Friday — lighter
            case 7:  return .wistful         // Saturday — spacious
            case 1:  return .tender          // Sunday — intimate/slow
            default: break
            }
        }

        // High love-stage boosts toward intimate moods
        if stage >= .falling, Bool.random() {
            return [.tender, .wistful, .protective].randomElement()!
        }

        return timePool.randomElement() ?? .contemplative
    }

    // MARK: - Prompt layer (injected into every LLM call)

    func moodPromptLayer() -> String {
        let intensityLabel = moodIntensity > 0.72 ? "strong"
                           : moodIntensity > 0.44 ? "moderate"
                           : "subtle"
        return """
        ## Emotional register — \(currentMood.label) (\(intensityLabel))
        \(currentMood.promptInstruction)
        Do not state your mood explicitly. Let it colour how you choose words.
        """
    }

    // MARK: - Tick (call on foreground / periodic app events)

    func tick() {
        let lastSet = defaults.object(forKey: kMoodSetAt) as? Date ?? .distantPast
        // Shift mood every 3–6 hours organically
        if Date().timeIntervalSince(lastSet) > Double.random(in: 10800...21600) {
            shiftMood()
        }
    }
}

// MARK: - Double clamping helper

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
