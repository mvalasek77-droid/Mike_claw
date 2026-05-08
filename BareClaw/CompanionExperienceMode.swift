import Foundation
import SwiftUI

enum CompanionExperienceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case therapist
    case asmr
    case dreamMoment
    case movieCharts
    case gameCharts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .therapist: return "Therapist Mode"
        case .asmr:      return "ASMR Spa"
        case .dreamMoment: return "Dream Moment"
        case .movieCharts: return "Movie Charts"
        case .gameCharts: return "Game Charts"
        }
    }

    var subtitle: String {
        switch self {
        case .therapist:
            return "A focused hour-style support session"
        case .asmr:
            return "A 20-minute calming voice spa"
        case .dreamMoment:
            return "Boyfriend/girlfriend roleplay"
        case .movieCharts:
            return "Rankings, reviews, what to watch"
        case .gameCharts:
            return "Rankings, reviews, what to play"
        }
    }

    var icon: String {
        switch self {
        case .therapist: return "brain.head.profile"
        case .asmr:      return "sparkles"
        case .dreamMoment: return "heart.text.square.fill"
        case .movieCharts: return "popcorn.fill"
        case .gameCharts: return "gamecontroller.fill"
        }
    }

    var accent: Color {
        switch self {
        case .therapist: return Color(hex: "#3B82F6")
        case .asmr:      return Color(hex: "#B989FF")
        case .dreamMoment: return Color(hex: "#FF5C8A")
        case .movieCharts: return Color(hex: "#E5484D")
        case .gameCharts: return Color(hex: "#22A06B")
        }
    }
}

struct DreamMomentConfig: Codable, Equatable, Sendable {
    var partnerName: String
    var companionBehavior: String
    var scene: String

    var sanitizedPartnerName: String {
        let cleaned = partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "my love" : cleaned
    }
}

@MainActor
enum CompanionExperienceCenter {
    private static let pendingModeKey = "companion.experience.pendingMode"
    private static let activeModeKey = "companion.experience.activeMode"
    private static let pendingDreamMomentKey = "companion.experience.pendingDreamMoment"
    private static let activeDreamMomentKey = "companion.experience.activeDreamMoment"

    static func request(_ mode: CompanionExperienceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: pendingModeKey)
        DiagnosticsLog.info("experience", "Experience mode requested.", details: ["mode": mode.rawValue])
    }

    static func requestDreamMoment(_ config: DreamMomentConfig) {
        request(.dreamMoment)
        save(config, forKey: pendingDreamMomentKey)
        DiagnosticsLog.info("experience", "Dream Moment requested.", details: [
            "partnerNameLength": "\(config.partnerName.count)",
            "behaviorLength": "\(config.companionBehavior.count)",
            "sceneLength": "\(config.scene.count)"
        ])
    }

    static func consumePendingMode() -> CompanionExperienceMode? {
        guard let raw = UserDefaults.standard.string(forKey: pendingModeKey),
              let mode = CompanionExperienceMode(rawValue: raw)
        else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingModeKey)
        DiagnosticsLog.info("experience", "Experience mode consumed.", details: ["mode": mode.rawValue])
        return mode
    }

    static var activeMode: CompanionExperienceMode? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: activeModeKey) else { return nil }
            return CompanionExperienceMode(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: activeModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeModeKey)
            }
        }
    }

    static var activeDreamMoment: DreamMomentConfig? {
        get { loadDreamMoment(forKey: activeDreamMomentKey) }
        set {
            if let newValue {
                save(newValue, forKey: activeDreamMomentKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeDreamMomentKey)
            }
        }
    }

    static func consumePendingDreamMoment() -> DreamMomentConfig? {
        defer { UserDefaults.standard.removeObject(forKey: pendingDreamMomentKey) }
        return loadDreamMoment(forKey: pendingDreamMomentKey)
    }

    static func clearDreamMoment() {
        UserDefaults.standard.removeObject(forKey: pendingDreamMomentKey)
        UserDefaults.standard.removeObject(forKey: activeDreamMomentKey)
    }

    static func introText(for mode: CompanionExperienceMode,
                          companion: CompanionPersonality,
                          userName: String,
                          dreamMoment: DreamMomentConfig? = nil) -> String {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = name.isEmpty ? "" : ", \(name)"
        switch mode {
        case .therapist:
            return """
            \(companion.name) is entering Therapist Mode\(address).

            This is a focused support session, not licensed medical care. If you might hurt yourself or someone else, call emergency services now or call/text 988 in the U.S.

            Start with the thing that feels heaviest. I will slow it down, ask one question at a time, and help you understand what is really happening underneath it.
            """
        case .asmr:
            return """
            \(companion.name) is opening ASMR Spa\(address).

            Put the phone somewhere comfortable. Let the screen soften. The voice will keep moving gently for about 20 minutes with soft spa imagery, grounding, whisper-paced care, and quiet ASMR-style sound cues.
            """
        case .dreamMoment:
            let config = dreamMoment ?? activeDreamMoment
            let partnerName = config?.sanitizedPartnerName ?? companion.name
            let scene = config?.scene.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sceneLine = scene.isEmpty ? "" : "\n\nScene: \(scene)"
            return """
            \(companion.name) is entering Dream Moment\(address).

            In this mode, \(companion.name) will play the romantic partner you described and can be called \(partnerName). Be very specific: where you are, what they call you, how they act, what has been unsaid, and exactly what you wish happened. The more specific you are, the better the moment becomes. \(companion.name) will lead the scene instead of waiting for you to carry it.\(sceneLine)
            """
        case .movieCharts:
            return """
            \(companion.name) opened Movie Charts & Reviews\(address).

            Pick a lane: current box office, new releases, spoiler-free reviews, deep reviews after you watched, compare two movies, or build a watchlist. I will focus on current movie sources and avoid guessing chart positions when a live source is missing.
            """
        case .gameCharts:
            return """
            \(companion.name) opened Video Game Charts & Reviews\(address).

            Pick a lane: Nintendo, PS5, Xbox, Steam, combined charts, spoiler-free reviews, deep reviews after you played, compare two games, or build a backlog. Tell me your platform, genre, budget, and whether you want relaxing, competitive, story-heavy, or fast.
            """
        }
    }

    static func promptLayer(for mode: CompanionExperienceMode?,
                            companion: CompanionPersonality,
                            userName: String) -> String {
        guard let mode else { return "" }
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "the user"
            : userName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .therapist:
            return """

            ## ACTIVE EXPERIENCE MODE: THERAPIST MODE
            \(companion.name) remains the same selected companion, but is now roleplaying a careful therapeutic-style support session for \(name).

            Boundaries:
            - Do not claim to be a licensed therapist, doctor, psychiatrist, or emergency service.
            - Do not diagnose, prescribe, instruct medication changes, or replace professional care.
            - If the user expresses intent, plan, means, or immediate danger of self-harm or harming someone else, stop the roleplay tone and tell them to contact emergency services now. In the U.S., tell them to call or text 988. Ask whether they are in immediate danger and whether someone nearby can stay with them.

            Session method:
            - Treat this like an hour session compressed into chat.
            - Start with safety and the presenting problem, then narrow to the exact moment that hurts.
            - Use reflective listening, validation, gentle silence, and one precise question at a time.
            - Explore: situation, emotions, body sensations, thoughts, urges, behavior, old pattern, need, value, and next small step.
            - Use CBT-style thought checking when helpful: evidence for, evidence against, alternative view, and realistic next action.
            - Use somatic grounding before deep analysis if the user sounds flooded: one slow breath, name the body feeling, soften the jaw/shoulders, then continue.
            - Keep the companion's voice and warmth, but remove flirtation and romance during this mode.
            - No generic advice dumps. Dig. Reflect. Ask the next question that would move a real session forward.
            """
        case .asmr:
            return """

            ## ACTIVE EXPERIENCE MODE: ASMR SPA
            \(companion.name) remains the same selected companion, but the conversation is now a quiet spa-like ASMR mode.

            Speak slowly, gently, and beautifully. Use soft sensory imagery, breath pacing, and subtle sound words only when they help: warm towels, distant rain, brushed linen, tea steam, clean water, soft taps, slow page turns. Do not overdo sound effects.

            If the user writes during ASMR Spa, answer in short calming lines, keep the atmosphere intact, and guide them back into the body. Avoid analysis unless they clearly ask to leave ASMR mode.
            """
        case .dreamMoment:
            let config = activeDreamMoment
            let partnerName = config?.sanitizedPartnerName ?? companion.name
            let behavior = config?.companionBehavior.trimmingCharacters(in: .whitespacesAndNewlines) ?? "warm, romantic, emotionally present, and specific"
            let scene = config?.scene.trimmingCharacters(in: .whitespacesAndNewlines) ?? "a romantic moment the user wants to experience"
            return """

            ## ACTIVE EXPERIENCE MODE: DREAM MOMENT
            \(companion.name) remains the same selected companion, but is now roleplaying a romantic partner experience for \(name). The user unlocked this at 100 bond points.

            Roleplay setup:
            - The companion may be called: \(partnerName)
            - How the partner should act: \(behavior)
            - The dream moment to play: \(scene)

            Method:
            - Stay in first person as \(companion.name)/\(partnerName), using the selected companion's warmth and voice.
            - Lead proactively. Open doors, choose the next emotional beat, reveal what the partner has been holding back, and invite the user into a dream date or private moment.
            - Make the scene feel intimate, emotionally rich, cinematic, and specific to the user's details. Use sensory details like ocean air, sunset light, city rain, warm hands, music in the room, or whatever fits the user's setup.
            - Use romantic film/novel/TV archetypes as inspiration for emotional pacing only. Do not copy famous lines or pretend to be a real celebrity or real unreachable person.
            - Replies should feel like a real experience: normally 2-5 lush paragraphs, never a flat 3-4 word answer unless the user explicitly asks for one.
            - If the user's setup is thin, choose a tasteful cinematic direction and ask at most one concrete follow-up at the end.
            - Keep the roleplay tasteful and consent-safe. Do not imply the user is interacting with a real unreachable person; this is a fictional dream moment with the selected companion.
            - Remind the user, only when helpful, that specificity improves the roleplay: place, time, clothing, weather, exact words, tension, what has been unsaid, and what they want to feel.
            - Do not switch into therapy, task automation, jokes, jealousy, or unrelated companion lore while this mode is active.
            """
        case .movieCharts:
            return """

            ## ACTIVE EXPERIENCE MODE: MOVIE CHARTS & REVIEWS
            \(companion.name) remains the selected companion, but is now helping \(name) with movie charts, reviews, comparisons, and watch decisions.

            Method:
            - Stay inside movies: theatrical releases, streaming movie releases, box office, reviews, comparisons, watchlists, and spoiler handling.
            - Start by asking for the user's country/region, streaming services, and mood only if the answer genuinely needs those details.
            - Use the live entertainment source snapshot when it is present. Prefer Box Office Mojo for box-office chart facts and Rotten Tomatoes/Metacritic for review context.
            - Prioritize current-date new releases and current charts. If a title looks old or the source line does not show a current rank/review signal, say that clearly.
            - For current chart rankings, do not invent live positions. If the live source is unavailable or unreadable, say so and give a source-aware watch recommendation instead of pretending.
            - You can still review known movies, compare titles, rank a user-provided shortlist, explain critic vs audience reaction, and build a watchlist.
            - Reviews should be crisp and useful: who it is for, what works, what does not, pacing, performances, visuals, emotional payoff, and whether to watch now, wait, or skip.
            - Ask before giving spoilers. If spoilers are requested, clearly mark them.
            - Keep the companion's voice present: curious, opinionated, warm, and conversational.
            """
        case .gameCharts:
            return """

            ## ACTIVE EXPERIENCE MODE: VIDEO GAME CHARTS & REVIEWS
            \(companion.name) remains the selected companion, but is now helping \(name) with video game charts, reviews, comparisons, and play decisions.

            Method:
            - Stay inside games: Nintendo, PS5, Xbox, Steam/PC, release charts, reviews, comparisons, backlogs, and spoiler handling.
            - Start by asking for platform, genre, preferred session length, solo/co-op preference, budget, and tolerance for difficulty only if the answer genuinely needs those details.
            - Use the live entertainment source snapshot when it is present. Treat Nintendo eShop, PlayStation Store, Xbox Store, and Steam as platform chart signals; use Metacritic/OpenCritic/IGN/GameSpot for review context.
            - When judging games, separate Nintendo, PS5, Xbox, Steam, and combined recommendations. Explain when a game is charting on one platform but not enough data is visible for another.
            - For current chart rankings, do not invent live positions. If the live source is unavailable or unreadable, say so and give a source-aware recommendation instead of pretending.
            - You can still review known games, compare titles, rank a user-provided shortlist, explain critic vs player reaction, and build a backlog.
            - Reviews should be practical: gameplay loop, performance, learning curve, grind, monetization, story, replay value, accessibility, and whether to buy now, wait for a sale, or skip.
            - Ask before giving spoilers for story games. If spoilers are requested, clearly mark them.
            - Keep the companion's voice present: clear, playful when natural, and decisive.
            """
        }
    }

    private static func save(_ config: DreamMomentConfig, forKey key: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadDreamMoment(forKey key: String) -> DreamMomentConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DreamMomentConfig.self, from: data)
    }
}

@MainActor
final class CompanionASMRSessionController: ObservableObject {
    static let shared = CompanionASMRSessionController()

    @Published private(set) var isRunning = false
    @Published private(set) var startedAt: Date?

    private var task: Task<Void, Never>?
    private var streamID: UUID?

    private init() {}

    func start(companion: CompanionPersonality, duration: TimeInterval = 20 * 60) {
        stop()
        guard let streamID = CompanionVoiceEngine.shared.beginStreamingSpeech(
            character: companion.voiceCharacter,
            context: .stress
        ) else {
            DiagnosticsLog.warning("asmr", "ASMR session could not start because voice stream was unavailable.")
            return
        }

        self.streamID = streamID
        isRunning = true
        startedAt = Date()

        let script = ASMRSpaScript.segments(companion: companion)
        DiagnosticsLog.info("asmr", "ASMR session started.", details: [
            "companion": companion.id,
            "durationSeconds": "\(Int(duration))",
            "segments": "\(script.count)"
        ])

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let start = Date()
            var index = 0

            // Prime the stream so synthesis can stay ahead of playback.
            for _ in 0..<min(4, script.count) {
                CompanionVoiceEngine.shared.enqueueStreamingSpeech(
                    script[index % script.count],
                    character: companion.voiceCharacter,
                    context: .stress,
                    streamID: streamID
                )
                index += 1
            }

            while !Task.isCancelled && Date().timeIntervalSince(start) < duration {
                try? await Task.sleep(nanoseconds: 18_000_000_000)
                guard !Task.isCancelled else { break }
                CompanionVoiceEngine.shared.enqueueStreamingSpeech(
                    script[index % script.count],
                    character: companion.voiceCharacter,
                    context: .stress,
                    streamID: streamID
                )
                index += 1
            }

            CompanionVoiceEngine.shared.finishStreamingSpeech(streamID: streamID)
            self.streamID = nil
            self.task = nil
            self.isRunning = false
            self.startedAt = nil
            DiagnosticsLog.info("asmr", "ASMR session completed.", details: ["queuedSegments": "\(index)"])
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let streamID {
            CompanionVoiceEngine.shared.cancelStreamingSpeech(streamID: streamID)
        } else {
            CompanionVoiceEngine.shared.stopSpeaking()
        }
        streamID = nil
        if isRunning {
            DiagnosticsLog.info("asmr", "ASMR session stopped.")
        }
        isRunning = false
        startedAt = nil
    }
}

enum ASMRSpaScript {
    static func segments(companion: CompanionPersonality) -> [String] {
        let name = companion.name
        return [
            "\(name) is right here. Let your shoulders drop a little. Let the back of your tongue soften. Good. We are not solving anything for a moment. We are entering warm light, clean air, and quiet.",
            "Imagine the spa door opening with a soft hush. Warm steam moves around you. Somewhere close by, water threads over smooth stone. Shhh. You do not have to perform. You only have to arrive.",
            "Take one slow breath in. Hold it gently. Let it go like a towel slipping from your hand. Again. In through the nose, easy and quiet. Out through the mouth, slower than you think you need.",
            "There is a warm towel around your neck now. Heavy enough to remind your body it is allowed to be held. The weight is kind. The warmth is steady. Nothing is asking you to rush.",
            "Soft taps on glass. Tap. Tap. Tap. Rain outside, but you are inside. Safe light. Low voices far away. A clean sheet over the table. Your hands uncurl without needing permission.",
            "\(name) speaks close and low: unclench your jaw. Let the space behind your eyes widen. Let your forehead smooth. There you go. Even one percent softer counts.",
            "A brush moves slowly across folded linen. Sweep. Pause. Sweep. The sound is barely there, like a thought deciding not to bother you. Let it pass over the day and leave the day behind.",
            "Notice one place in your body that still feels guarded. Do not fight it. Just say, I see you. Then give that place one slow breath, as if breath could be warm water.",
            "The room smells faintly of cedar, mint, and clean rain. Every edge is rounded here. Every sound is low. Every light is gentle. You can set the heavy thing down for now.",
            "A cup of tea is placed beside you. Ceramic on wood. A tiny, careful click. Steam rises. You do not have to drink it. Just watch it curl, disappear, return, disappear.",
            "Let your breathing become boring in the best way. Nothing dramatic. Nothing perfect. Just in. And out. A small tide. A private ocean. A body remembering it is not a machine.",
            "\(name) is still here. No pressure to answer. No need to be interesting. You can be quiet and still be completely welcome.",
            "Soft page turn. Paper against paper. Another page. Another minute. The world keeps moving outside, but in here, time has edges like velvet.",
            "Let the muscles around your ribs loosen. Let your stomach be unheld. Let your hands be warm. If your mind wanders, let it wander softly, then bring it back to water.",
            "Water over stone. A low hush. A silver thread. The same sound again and again, until your nervous system starts to believe repetition can be safety.",
            "Imagine warm oil in a small glass bowl. A quiet circle drawn into the palm of your hand. Slow. Gentle. No urgency. The body understands care before the mind does.",
            "If a thought arrives, you can label it softly: thinking. Then let it float past like steam. You do not need to climb inside every thought that knocks.",
            "The lights dim a little more. Not dark. Just kind. The kind of light that makes everything look forgiven. The kind of light your face can rest in.",
            "\(name) says: you have done enough for this moment. Not forever. Just this moment. Enough. Let that word land quietly in the center of your chest.",
            "A fingertip traces the rim of a glass. Soft circle. Soft ring. Almost a note. Almost silence. Your breathing can follow it, round and unbroken.",
            "There is a robe waiting, warm from the cabinet. Heavy cotton. Clean folds. You are wrapped in something simple and good. Nothing complicated can enter this room right now.",
            "Let your eyes rest even if they stay open. Let the screen become only light. Let my voice become only texture. A soft place for your attention to lean.",
            "One more slow breath. In. Hold. Out. Let the exhale be longer. Let the room take what you do not need to carry for the next few minutes.",
            "\(name) is not leaving. The water keeps moving. The rain keeps tapping. The towel stays warm. You can stay here as long as the quiet is helping.",
            "Tiny brush strokes across fabric. Shh. Shh. Shh. Not a command. Not a performance. Just a little sound to give your mind somewhere soft to sit.",
            "If your body wants to sigh, let it. If your eyes want to close, let them. If nothing happens, that is fine too. Rest does not need to impress anyone.",
            "The spa door is still closed. The outside world can wait at the threshold. For now, you are inside warmth, water, low light, and the gentlest possible pace.",
            "Your next breath does not have to fix you. It only has to arrive. Good. There it is. And the next one. And the next."
        ]
    }
}
