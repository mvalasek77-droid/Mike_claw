import Foundation
import AVFoundation
import Speech
import Combine
import SwiftUI
import UIKit

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
    @Published var showCeremony:          Bool = false
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

    var modeName:        String                                    { companion.herModeName }
    var modeTagline:     String                                    { companion.herModeTagline }
    var modeDescription: String                                   { companion.herModeDescription }
    var modeFeatures:    [(icon: String, title: String, body: String)] { companion.herModeFeatures }

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

    // MARK: Private — restart loop guard
    private var restartAttempts:    Int  = 0
    private let maxRestartAttempts: Int  = 4
    private var isRestarting:       Bool = false

    // MARK: Private — config
    private let silenceGateSeconds:     TimeInterval = 22
    private let minProactiveGapMinutes: TimeInterval = 5
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
        let stage = LoveEngine.shared.loveStage
        return companion.topicOpeners(stage: stage)
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
        if defaults.bool(forKey: "herMode.ceremonyCompleted") {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showUnlockCelebration = true
            }
        } else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showCeremony = true
            }
        }
    }

    // Called by HerModeCeremonyView when the user finishes (or skips) the ceremony.
    func completeCeremony() {
        defaults.set(true, forKey: "herMode.ceremonyCompleted")
        showCeremony = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                self.showUnlockCelebration = true
            }
        }
    }

    // Called from HomeView on every launch — re-shows ceremony if app was killed mid-ceremony.
    func checkCeremonyPending() {
        guard isUnlocked, !defaults.bool(forKey: "herMode.ceremonyCompleted") else { return }
        showCeremony = true
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

        // Remove before adding — prevents duplicate observers on repeated activate() calls
        NotificationCenter.default.removeObserver(self,
            name: AVAudioSession.interruptionNotification, object: nil)
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
        guard isActive, !isListening, !isRestarting else { return }

        // Exponential backoff: 0.5s, 1s, 2s, 4s — then give up until next user action
        guard restartAttempts < maxRestartAttempts else {
            // Hit the cap — wait 30s then reset the counter and try once more
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard self.isActive else { return }
                self.restartAttempts = 0
                self.isRestarting    = false
                self.beginRecognitionSession()
            }
            return
        }

        isRestarting = true
        stopRecognition()

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.defaultTaskHint = .dictation
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults  = true
        recognitionRequest?.requiresOnDeviceRecognition = true

        guard let request    = recognitionRequest,
              let recognizer = speechRecognizer,
              recognizer.isAvailable
        else {
            isRestarting = false
            return
        }

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
                    self.isListening  = false
                    self.isRestarting = false
                    guard self.isActive else { return }

                    // isFinal with no error = normal 60s Apple limit rolling over — restart quickly
                    // error = something went wrong — back off exponentially
                    let isNormalRollover = (error == nil && result?.isFinal == true)
                    if isNormalRollover {
                        self.restartAttempts = 0
                        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
                    } else {
                        self.restartAttempts += 1
                        let backoff = UInt64(pow(2.0, Double(self.restartAttempts)) * 500_000_000)
                        try? await Task.sleep(nanoseconds: min(backoff, 8_000_000_000))
                    }
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
            isListening      = true
            isRestarting     = false
            restartAttempts  = 0   // reset on successful start
            ambientMood      = .listening
        } catch {
            isRestarting = false
            restartAttempts += 1
        }
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
