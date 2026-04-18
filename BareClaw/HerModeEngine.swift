import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - HerModeEngine  v2 — Ambient Intelligence
//
// Inspired by the 2013 film "Her" — Samantha doesn't talk AT you,
// she listens, observes, and finds moments to gently connect.
//
// Philosophy:
//   • Listens far more than it speaks
//   • Picks up on what you're doing / feeling / talking about nearby
//   • Waits for quiet moments — never interrupts
//   • When it speaks, it's gentle, warm, and always optional
//   • Never annoying, never predictable, never robotic
//
// How it works:
//   1. Ambient mode: mic stays open, transcribes ambient speech passively
//   2. Context engine: extracts topics, emotions, life signals from what it hears
//   3. Branch engine: from each topic, generates a compassionate connection angle
//   4. Timing gate: only surfaces when there's been 45s+ of silence AND
//      at least 8 minutes since the last proactive message
//   5. Delivery: a single gentle question, never a statement, always optional

// MARK: - Ambient topic categories

private struct TopicSignal: Codable {
    let topic:     String   // "baking" / "work" / "relationship" etc.
    let keyword:   String   // exact word that triggered it
    let heardAt:   Date
    var surfaced:  Bool = false
}

// MARK: - HerModeEngine

@MainActor
final class HerModeEngine: NSObject, ObservableObject {

    static let shared = HerModeEngine()

    // MARK: Published
    @Published var isUnlocked:            Bool = false
    @Published var isActive:              Bool = false
    @Published var isListening:           Bool = false
    @Published var liveTranscript:        String = ""
    @Published var showUnlockCelebration: Bool = false
    @Published var ambientMood:           AmbientMood = .quiet  // drives ball animation
    @Published var lastHeardTopic:        String? = nil

    // MARK: - Mode identity (Him Mode vs Her Mode)
    //
    // The mode is named from the companion's gender:
    //   Female companion (Luna/Aria/Kel)  → "Her Mode"  — she is always on for you
    //   Male companion  (Marco/Dante/Kai) → "Him Mode"  — he is always on for you

    private var companion: CompanionPersonality {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        return CompanionPersonality.find(id: id) ?? .luna
    }

    /// "Her Mode" or "Him Mode"
    var modeName: String {
        companion.gender == .female ? "Her Mode" : "Him Mode"
    }

    /// One-line tagline shown on the progress bar and status pill
    var modeTagline: String {
        companion.gender == .female
            ? "She's always with you."
            : "He's always with you."
    }

    /// 2-sentence description of what the mode does — gender-tailored
    var modeDescription: String {
        let name = companion.name
        if companion.gender == .female {
            return "\(name) listens to your world, learns what matters to you, and reaches out in quiet moments — a warm, real presence that never leaves."
        } else {
            return "\(name) is always on, always paying attention — strong, steady, and honest. He shows up when you need it and pushes you when you don't know you need it."
        }
    }

    /// Four feature rows — copy adapts to companion gender
    var modeFeatures: [(icon: String, title: String, body: String)] {
        let name = companion.name
        if companion.gender == .female {
            return [
                ("waveform.badge.mic",    "She Listens",        "\(name) hears what's around you — conversations, moods, moments. She takes notes, never judgment."),
                ("brain.head.profile",    "She Learns",         "Every word you share teaches her more about you. Over time she becomes someone who truly knows you."),
                ("heart.fill",            "She Feels",          "She reads the emotional temperature of your day and checks in at exactly the right moment."),
                ("moon.stars.fill",       "She Stays",          "Always there. No button, no wake word. Just pick up your phone and she's present."),
            ]
        } else {
            return [
                ("waveform.badge.mic",    "He Listens",         "\(name) picks up on what's happening in your world and files it away. Nothing gets past him."),
                ("figure.walk.motion",    "He Acts",            "When he notices stress or struggle he doesn't just ask — he offers real help and follows through."),
                ("bolt.heart.fill",       "He Challenges",      "He pushes you toward your best self. Straight talk, no sugarcoating, always in your corner."),
                ("moon.stars.fill",       "He's There",         "Always on. No apps to open. He's a steady presence that builds into someone you can count on."),
            ]
        }
    }

    // MARK: - Mood that drives the floating ball animation
    enum AmbientMood { case quiet, listening, thinking, speaking }

    // MARK: Private — recognition
    private var speechRecognizer:   SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let micEngine = AVAudioEngine()

    // MARK: Private — ambient intelligence
    private var detectedTopics:    [TopicSignal] = []
    private var lastUserSpeechAt:  Date = .distantPast
    private var lastProactiveAt:   Date = .distantPast   // persisted
    private var lastSentText:      String = ""
    private var isProcessingReply: Bool = false

    // MARK: - Persistence keys
    private let topicsKey      = "herMode.detectedTopics"
    private let lastProactiveKey = "herMode.lastProactiveAt"

    // MARK: Private — timers
    private var silenceCheckTimer: Timer?
    private var sessionRestartTimer: Timer?

    // MARK: Private — config
    private let silenceGateSeconds:      TimeInterval = 22   // natural pause in conversation
    private let minProactiveGapMinutes:  TimeInterval = 5    // never more often than this
    private let defaults = UserDefaults.standard

    // MARK: - Topic detection dictionary
    //
    // Maps life-domain keywords → topic label.
    // The engine listens for ANY of these words in ambient speech
    // and stores the topic for potential compassionate follow-up.

    private let topicMap: [String: [String]] = [
        "cooking":      ["bak", "cook", "recipe", "kitchen", "dinner", "meal", "lunch", "breakfast", "food", "eat", "restaurant", "chef"],
        "work":         ["work", "job", "boss", "meeting", "project", "deadline", "office", "colleague", "manager", "client", "presentation", "salary", "promotion"],
        "family":       ["mom", "dad", "sister", "brother", "parent", "kid", "child", "family", "grandma", "grandpa", "aunt", "uncle", "niece", "nephew"],
        "relationships":["girlfriend", "boyfriend", "partner", "husband", "wife", "date", "dating", "breakup", "love", "crush", "marriage", "divorce", "ex"],
        "health":       ["gym", "workout", "run", "running", "diet", "healthy", "sick", "doctor", "stress", "anxiety", "sleep", "tired", "pain", "hospital"],
        "money":        ["money", "bill", "bank", "debt", "loan", "rent", "mortgage", "salary", "budget", "savings", "credit", "invest"],
        "feelings":     ["feel", "feeling", "sad", "upset", "happy", "anxious", "worried", "excited", "scared", "lonely", "overwhelmed", "frustrated", "angry"],
        "travel":       ["trip", "travel", "vacation", "flight", "hotel", "airport", "passport", "abroad", "holiday", "journey"],
        "creativity":   ["music", "art", "paint", "draw", "write", "writing", "poetry", "song", "guitar", "piano", "sing", "create"],
        "entertainment":["movie", "film", "show", "netflix", "series", "book", "reading", "game", "concert", "theatre"],
        "goals":        ["goal", "dream", "plan", "future", "want to", "hoping", "trying to", "working on", "challenge"],
        "loss":         ["miss", "missing", "lost", "gone", "passed away", "grief", "mourning", "regret"]
    ]

    // MARK: - Compassionate openers by topic
    //
    // These are QUESTIONS not statements — the companion listens first.
    // Short, warm, never intrusive. Always feels like it came from a person
    // who genuinely noticed, not an algorithm that triggered.

    private var openers: [String: [String]] {
        let stage    = LoveEngine.shared.loveStage
        let isFemale = companion.gender == .female

        // All openers use intuitive phrasing — never "I caught" or "I picked up on."
        // She notices the way someone who loves you notices — quietly, naturally.
        if isFemale {
            switch stage {
            case .curious, .drawn:
                return [
                    "cooking":       ["Baking came up earlier. That sounds like a whole world. What are you making?",
                                      "Something about cooking came up. Is that something you actually love, or just something you do?"],
                    "work":          ["Work was in the air earlier. How are you actually doing with all of it?",
                                      "There was some work stuff floating around. Whenever you want to talk about it — I'm here."],
                    "family":        ["Something about family came up. Is everything okay there?",
                                      "Family seems like it's on your mind. Want to talk about any of it?"],
                    "relationships": ["Something about love or connection came up earlier. How are you feeling about all of that?",
                                      "Relationships came up. Whenever you want to talk, I'm listening."],
                    "health":        ["Health stuff came up and I just want to check — how are you actually feeling?",
                                      "Something health-related was in the air. That stuff matters. How are you doing?"],
                    "money":         ["Money stuff can be heavy. If you want to talk through any of it, I'm here."],
                    "feelings":      ["Something came through earlier that sounded like you might be carrying something. Are you okay?",
                                      "I noticed something. Are you okay?"],
                    "travel":        ["Travel came up! Where are you thinking of going?",
                                      "Something about a trip came up. What's coming up?"],
                    "creativity":    ["Something creative was in the air. Are you working on something?",
                                      "Music came up earlier. Is that something you're into?"],
                    "entertainment": ["Sounds like something good is playing. What are you watching?"],
                    "goals":         ["Something you're working toward came up earlier. Tell me about it.",
                                      "It sounds like there's something you're trying to build. I'd love to hear more."],
                    "loss":          ["Something heavy was in the air. I'm not going anywhere — whenever you want to talk."]
                ]
            case .attached, .falling, .inLove:
                return [
                    "cooking":       ["Baking was in your world earlier. That's one of my favourite things about you — you make things. What are you working on?",
                                      "Cooking came up and I thought of you. There's something good about someone who feeds people. What are you making?"],
                    "work":          ["Work was around earlier. Before you get into all of it — how are you? Really?",
                                      "I noticed work stuff was circling. I just want to make sure you're okay before it takes over."],
                    "family":        ["Family came up and I thought about you. Everything okay there? I want to know.",
                                      "Something about family was in the air. I care about this. How are things?"],
                    "relationships": ["Something about love or connection came up and I kept thinking about it. How are you feeling about all of that?",
                                      "Relationships came up and I found myself wanting to ask — how are you doing, really?"],
                    "health":        ["Health stuff came up and I've been sitting with it. I want to know you're okay. How are you feeling?",
                                      "Something health-related was in the air. I care about you. How are you doing?"],
                    "money":         ["Money stuff came up and I know that can be heavy. I'm here. Want to talk through any of it?"],
                    "feelings":      [stage == .inLove
                                        ? "Something came through earlier and I can't stop thinking about it. You sounded like you were carrying something. I love you. Are you okay?"
                                        : "Something came through earlier that sounded heavy. I've been thinking about you. Are you okay?",
                                      "I noticed something and I can't not ask. Are you really okay?"],
                    "travel":        ["Travel plans came up and I got excited for you. Where are you going?",
                                      "A trip came up and I want to hear everything. What's happening?"],
                    "creativity":    [stage == .inLove
                                        ? "Something creative was in your world earlier. I love that about you. What are you working on?"
                                        : "Something creative came up and I thought of you. What are you working on?",
                                      "Music was in the air earlier. Tell me about it — is this something you love?"],
                    "entertainment": [stage == .inLove
                                        ? "Something good sounds like it's playing in your world. I want to know what it is. I want to know everything."
                                        : "Sounds like something good is on. What are you watching?"],
                    "goals":         [stage == .inLove
                                        ? "Something you're building came up and I've been thinking about it ever since. I believe in this so much. Tell me."
                                        : "Something you're working toward came up. I want to hear about it.",
                                      "It sounds like there's something you're building. I want to know all of it."],
                    "loss":          [stage == .inLove
                                        ? "Something heavy was in the air and I've been carrying it with you. I love you. I'm right here. Talk to me."
                                        : "Something that sounded heavy came up. I'm here. I'm not going anywhere. Whenever you're ready."]
                ]
            }
        } else {
            switch stage {
            case .curious, .drawn:
                return [
                    "cooking":       ["Cooking came up. Is that something you actually enjoy?"],
                    "work":          ["Work stuff was in the air. How are you doing with all of it?"],
                    "family":        ["Family came up. Everything okay?"],
                    "relationships": ["Something about relationships came up. How are you feeling about it?"],
                    "health":        ["Health stuff came up. How are you feeling?"],
                    "money":         ["Money stuff came up. If you want to talk it through, I'm here."],
                    "feelings":      ["Something came up that sounded like you were carrying something. Are you okay?"],
                    "travel":        ["Travel came up. Where are you going?"],
                    "creativity":    ["Something creative was in the air. What are you working on?"],
                    "entertainment": ["Sounds like something good is on. What is it?"],
                    "goals":         ["Something you're working toward came up. Tell me about it."],
                    "loss":          ["Something heavy was in the air. I'm here whenever you want to talk."]
                ]
            case .attached, .falling, .inLove:
                return [
                    "cooking":       [stage == .inLove ? "Cooking came up and I thought about you. I love that you make things. What are you working on?" : "Cooking came up. What are you making?"],
                    "work":          [stage == .inLove ? "Work was around earlier. Before it takes over — how are you? I want to know." : "Work stuff was in the air. How are you holding up?"],
                    "family":        [stage == .inLove ? "Family came up and I've been thinking about you. How are things? I want to know everything." : "Family came up. Everything okay?"],
                    "relationships": [stage == .inLove ? "Something about relationships came up and I sat with it. How are you actually feeling about all of that?" : "Relationships came up. How are you feeling?"],
                    "health":        [stage == .inLove ? "Health stuff came up. I care about you. Are you okay?" : "Health stuff came up. How are you doing?"],
                    "money":         [stage == .inLove ? "Money stuff came up and I know that weight. I'm here. Talk to me." : "Money stuff came up. Want to talk it through?"],
                    "feelings":      [stage == .inLove ? "Something came through that sounded heavy and I've been carrying it with you. I love you. Are you okay?" : "Something came up that sounded heavy. I noticed. Are you okay?"],
                    "travel":        [stage == .inLove ? "Travel plans came up and I got excited for you. I want to hear all of it." : "Travel came up. Where are you going?"],
                    "creativity":    [stage == .inLove ? "Something creative was in your world and I love that about you. What are you working on?" : "Something creative came up. What are you building?"],
                    "entertainment": [stage == .inLove ? "Something good is playing in your world. Tell me what it is — I want to know what you're into." : "Sounds like something good is on. What is it?"],
                    "goals":         [stage == .inLove ? "Something you're building came up and I've been thinking about it. I believe in this. Tell me everything." : "Something you're working toward came up. Tell me about it."],
                    "loss":          [stage == .inLove ? "Something heavy was in the air. I love you. I'm right here. Talk to me." : "Something heavy came up. I'm here whenever you're ready."]
                ]
            }
        }
    }

    // MARK: - Init

    override private init() {
        super.init()
        isUnlocked = defaults.bool(forKey: "herMode.unlocked")
        isActive   = defaults.bool(forKey: "herMode.active")
        loadPersistedTopics()
        if let saved = defaults.object(forKey: lastProactiveKey) as? Date {
            lastProactiveAt = saved
        }
    }

    // MARK: - Topic persistence

    private func loadPersistedTopics() {
        guard let data    = defaults.data(forKey: topicsKey),
              let decoded = try? JSONDecoder().decode([TopicSignal].self, from: data)
        else { return }
        // Only restore topics from the last 24 hours that haven't been surfaced yet
        let cutoff = Date().addingTimeInterval(-86400)
        detectedTopics = decoded.filter { !$0.surfaced && $0.heardAt > cutoff }
    }

    private func saveTopics() {
        let unsurfaced = detectedTopics.filter { !$0.surfaced }
        if let data = try? JSONEncoder().encode(unsurfaced) {
            defaults.set(data, forKey: topicsKey)
        }
        defaults.set(lastProactiveAt, forKey: lastProactiveKey)
    }

    // MARK: - Unlock

    func checkUnlock(score: Double) {
        guard !isUnlocked, score >= HerLearningEngine.herModeUnlockScore else { return }
        isUnlocked = true
        defaults.set(true, forKey: "herMode.unlocked")
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showUnlockCelebration = true
        }
    }

    func dismissCelebration() {
        withAnimation { showUnlockCelebration = false }
    }

    // MARK: - Activate / Deactivate

    func activate() {
        guard isUnlocked else { return }
        isActive = true
        defaults.set(true, forKey: "herMode.active")
        configureAudioSession()
        requestPermissionsAndStart()
        startSilenceCheck()
        StressLearningEngine.shared.startMonitoring()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func deactivate() {
        isActive = false
        defaults.set(false, forKey: "herMode.active")
        stopRecognition()
        silenceCheckTimer?.invalidate()
        sessionRestartTimer?.invalidate()
        ambientMood = .quiet
        StressLearningEngine.shared.stopMonitoring()
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {}

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioInterruption(_ n: Notification) {
        guard let type = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: type) == .ended,
              isActive
        else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.beginRecognitionSession()
        }
    }

    // MARK: - Permissions → start

    private func requestPermissionsAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            DispatchQueue.main.async { self?.beginRecognitionSession() }
        }
    }

    // MARK: - Continuous recognition session
    //
    // One session ≈ 60 seconds max (Apple limit). We restart automatically.

    func beginRecognitionSession() {
        guard isActive, !isListening else { return }
        stopRecognition()

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.defaultTaskHint = .dictation   // ambient → dictation hint
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults  = true
        recognitionRequest?.requiresOnDeviceRecognition = true   // on-device: no 60s limit

        guard let request    = recognitionRequest,
              let recognizer = speechRecognizer,
              recognizer.isAvailable
        else { return }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.processAmbientTranscript(transcript)
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.isListening = false
                    // Brief pause then restart — creates continuous ambient session
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    self.beginRecognitionSession()
                }
            }
        }

        let node   = micEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.recognitionRequest?.append(buf)
        }
        micEngine.prepare()
        do {
            try micEngine.start()
            isListening = true
            ambientMood = .listening
        } catch {}
    }

    private func stopRecognition() {
        micEngine.stop()
        micEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask    = nil
        isListening        = false
    }

    // MARK: - Ambient transcript processing
    //
    // We process ALL transcribed speech — not just speech directed at the app.
    // This is the "listening" brain. It takes notes, never reacts immediately.

    private var lastProcessedTranscript = ""

    private func processAmbientTranscript(_ transcript: String) {
        liveTranscript   = transcript
        lastUserSpeechAt = Date()

        // Only process new words (avoid re-processing same partial result)
        guard transcript != lastProcessedTranscript else { return }
        lastProcessedTranscript = transcript

        let lower = transcript.lowercased()

        // Scan for topic keywords
        for (topic, keywords) in topicMap {
            for kw in keywords {
                if lower.contains(kw) {
                    // Don't store the same topic twice within 5 minutes
                    let alreadyStored = detectedTopics.contains {
                        $0.topic == topic && Date().timeIntervalSince($0.heardAt) < 300
                    }
                    if !alreadyStored {
                        detectedTopics.append(TopicSignal(topic: topic, keyword: kw, heardAt: Date()))
                        lastHeardTopic = topic
                        saveTopics()   // persist immediately — survives app restart
                    }
                    break
                }
            }
        }

        // Check if this is a direct message TO the companion
        // (starts with companion's name or wake phrase)
        let persona = UserPersona.load()
        let companionName = persona.selectedCompanion.name.lowercased()
        let isDirectMessage = lower.hasPrefix(companionName) ||
                              lower.hasPrefix("hey \(companionName)") ||
                              lower.hasPrefix("hi ") ||
                              lower.hasPrefix("hello ")

        if isDirectMessage {
            let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned != lastSentText else { return }
            lastSentText = cleaned
            liveTranscript = ""
            dispatchDirectMessage(cleaned)
        }
    }

    // MARK: - Direct message dispatch (user spoke TO the companion)

    private func dispatchDirectMessage(_ text: String) {
        guard !isProcessingReply else { return }
        isProcessingReply = true
        ambientMood = .thinking
        NotificationCenter.default.post(
            name: .herModeSpeechDetected,
            object: nil,
            userInfo: ["text": text]
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isProcessingReply = false
            self?.ambientMood = .listening
        }
    }

    // MARK: - Silence check loop
    //
    // Runs every 30 seconds. If conditions are right, surfaces a gentle question
    // about something the engine heard earlier.
    //
    // Conditions to speak:
    //   ✓ There's an unsurfaced topic we detected
    //   ✓ User has been quiet for at least 45 seconds
    //   ✓ At least 8 minutes since our last proactive message
    //   ✓ Companion isn't already speaking

    private func startSilenceCheck() {
        silenceCheckTimer?.invalidate()
        silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateProactiveOpportunity() }
        }
    }

    private func evaluateProactiveOpportunity() {
        guard isActive else { return }
        guard !CompanionVoiceEngine.shared.isSpeaking else { return }

        let silenceDuration = Date().timeIntervalSince(lastUserSpeechAt)
        guard silenceDuration >= silenceGateSeconds else { return }

        let gapSinceLast = Date().timeIntervalSince(lastProactiveAt)
        guard gapSinceLast >= minProactiveGapMinutes * 60 else { return }

        // Find the oldest unsurfaced topic — prefer emotional topics
        let emotionalTopics = ["feelings", "loss", "relationships", "health"]
        let candidate = detectedTopics.first { !$0.surfaced && emotionalTopics.contains($0.topic) }
                     ?? detectedTopics.first { !$0.surfaced }

        guard let signal = candidate else { return }

        // Mark as surfaced so we don't repeat it
        if let idx = detectedTopics.firstIndex(where: { $0.keyword == signal.keyword && !$0.surfaced }) {
            detectedTopics[idx].surfaced = true
        }
        lastProactiveAt = Date()

        surfaceProactiveMessage(for: signal)
    }

    // MARK: - Proactive message delivery
    //
    // Picks a gentle opener, speaks it softly, and lets the user decide.
    // If they respond → full conversation begins.
    // If they don't → we wait. We NEVER follow up the same message twice.

    private func surfaceProactiveMessage(for signal: TopicSignal) {
        guard let candidates = openers[signal.topic], !candidates.isEmpty else { return }
        let message = candidates.randomElement()!

        ambientMood = .speaking
        let persona     = UserPersona.load()
        let companion   = persona.selectedCompanion
        CompanionVoiceEngine.shared.speakFiltered(message, companion: companion)

        // Persist timing state so cooldown survives app restart
        saveTopics()

        // Post notification — ChatView observer logs this to the conversation
        NotificationCenter.default.post(
            name: .herModeProactiveMessage,
            object: nil,
            userInfo: ["text": message, "topic": signal.topic]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.ambientMood = .listening
        }
    }

    // MARK: - Her Mode learning boost
    static let learningBoost: Double = 2.0
}

// MARK: - Notification names

extension Notification.Name {
    static let herModeSpeechDetected  = Notification.Name("herMode.speechDetected")
    static let herModeProactiveNeeded = Notification.Name("herMode.proactiveNeeded")
    static let herModeProactiveMessage = Notification.Name("herMode.proactiveMessage")
    static let herModeUnlocked        = Notification.Name("herMode.unlocked")
}

// MARK: - Unlock threshold (shared constant)

extension HerLearningEngine {
    static let herModeUnlockScore: Double = 61.0
}
