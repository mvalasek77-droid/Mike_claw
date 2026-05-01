import Foundation
import AVFoundation
import Speech
import Combine
import SwiftUI
import UIKit
import OSLog

#if DEBUG
private let herModeDebugLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "BareClaw",
    category: "HerModeEngine"
)
#endif

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
    var summary:   String? = nil
    var prompt:    String? = nil
    var surfaced:  Bool = false
}

// MARK: - HerModeEngine

@MainActor
final class HerModeEngine: NSObject, ObservableObject {

    static let shared = HerModeEngine()

#if DEBUG
    private func debugLog(_ message: String) {
        print("HerModeEngine: \(message)")
        herModeDebugLogger.debug("\(message, privacy: .public)")
        DiagnosticsLog.info("him_her_mode", message)
    }
#else
    private func debugLog(_ message: String) {
        DiagnosticsLog.info("him_her_mode", message)
    }
#endif

    // MARK: Published
    @Published var isUnlocked:            Bool = false
    @Published var isActive:              Bool = false
    @Published var isListening:           Bool = false
    @Published var liveTranscript:        String = ""
    @Published var showUnlockCelebration: Bool = false
    @Published var showCeremony:          Bool = false
    @Published var ambientMood:           AmbientMood = .quiet  // drives ball animation
    @Published var lastHeardTopic:        String? = nil
    @Published var statusMessage:         String = "Paused"

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
    private var nextProactiveAllowedAt: Date = .distantPast
    private var proactiveDayStamp: String = ""
    private var proactiveCountToday: Int = 0
    private var ambientWindowPieces: [String] = []
    private var ambientWindowStartedAt: Date?
    private var lastAmbientInsightAt: Date = .distantPast
    private var lastSentText:      String = ""
    private var isProcessingReply: Bool = false
    private var directDispatchTask: Task<Void, Never>?

    // MARK: - Persistence keys
    private let topicsKey      = "herMode.detectedTopics"
    private let lastProactiveKey = "herMode.lastProactiveAt"
    private let nextProactiveAllowedKey = "herMode.nextProactiveAllowedAt"
    private let proactiveDayKey = "herMode.proactiveDay"
    private let proactiveCountKey = "herMode.proactiveCountToday"
    private let pendingDirectMessageKey = "herMode.pendingDirectMessage"

    // MARK: Private — timers
    private var silenceCheckTimer: Timer?
    private var sessionRestartTimer: Timer?

    // MARK: Private — restart loop guard
    private var restartAttempts:    Int  = 0
    private let maxRestartAttempts: Int  = 4
    private var isRestarting:       Bool = false
    private var isPausedForCompanionSpeech: Bool = false

    // MARK: Private — config
    private var requiredSilenceSeconds: TimeInterval = TimeInterval.random(in: 35...95)
    private let minProactiveGapMinutes: TimeInterval = 18
    private let maxProactiveMessagesPerDay = 6
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
        "conversation": ["conversation", "talking about", "we were talking", "they said", "she said", "he said"],
        "conflict":     ["yelling", "shouting", "screaming", "argument", "arguing", "fight", "fighting"],
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
        statusMessage = isActive ? "Starting listener..." : "Paused"
        loadPersistedTopics()
        if let saved = defaults.object(forKey: lastProactiveKey) as? Date {
            lastProactiveAt = saved
        }
        if let saved = defaults.object(forKey: nextProactiveAllowedKey) as? Date {
            nextProactiveAllowedAt = saved
        }
        proactiveDayStamp = defaults.string(forKey: proactiveDayKey) ?? ""
        proactiveCountToday = defaults.integer(forKey: proactiveCountKey)
        resetDailyProactiveCounterIfNeeded()
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
        persistProactiveTiming()
    }

    private func resetDailyProactiveCounterIfNeeded() {
        let today = Self.dayStamp(for: Date())
        guard proactiveDayStamp != today else { return }
        proactiveDayStamp = today
        proactiveCountToday = 0
        persistProactiveTiming()
    }

    private func persistProactiveTiming() {
        defaults.set(lastProactiveAt, forKey: lastProactiveKey)
        defaults.set(nextProactiveAllowedAt, forKey: nextProactiveAllowedKey)
        defaults.set(proactiveDayStamp, forKey: proactiveDayKey)
        defaults.set(proactiveCountToday, forKey: proactiveCountKey)
    }

    private func scheduleNextProactiveWindow(minutes range: ClosedRange<Double>) {
        nextProactiveAllowedAt = Date().addingTimeInterval(Double.random(in: range) * 60)
        requiredSilenceSeconds = TimeInterval.random(in: 35...95)
        persistProactiveTiming()
    }

    private static func dayStamp(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    // MARK: - Unlock

    func checkUnlock(score: Double) {
        guard !isUnlocked, score >= HerLearningEngine.herModeUnlockScore else { return }
        isUnlocked = true
        defaults.set(true, forKey: "herMode.unlocked")
        if defaults.bool(forKey: "herMode.ceremonyCompleted") {
            debugLog("unlock threshold reached; ceremony already completed so activating \(modeName)")
            activate()
        } else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showCeremony = true
            }
        }
    }

    // Called by HerModeCeremonyView when the user finishes (or skips) the ceremony.
    func completeCeremony() {
        let shouldActivate = isUnlocked && !isActive
        defaults.set(true, forKey: "herMode.ceremonyCompleted")
        withAnimation(.easeInOut(duration: 0.25)) {
            showCeremony = false
        }
        debugLog("ceremony completed; activating \(modeName)")
        guard shouldActivate else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.isUnlocked, !self.isActive else { return }
            self.activate()
        }
    }

    // Called from HomeView on every launch — re-shows ceremony if app was killed mid-ceremony.
    func checkCeremonyPending() {
        guard isUnlocked, !defaults.bool(forKey: "herMode.ceremonyCompleted") else { return }
        showCeremony = true
    }

    func dismissCelebration() {
        withAnimation { showUnlockCelebration = false }
        if isUnlocked && !isActive {
            activate()
        }
    }

    // MARK: - Activate / Deactivate

    func activate() {
        guard isUnlocked else {
            debugLog("activate blocked: mode is locked")
            return
        }
        debugLog("activate requested for \(modeName)")
        isActive = true
        statusMessage = "Starting microphone..."
        defaults.set(true, forKey: "herMode.active")
        configureAudioSession()
        requestPermissionsAndStart()
        startSilenceCheck()
        StressLearningEngine.shared.startMonitoring()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func resumeIfNeeded() {
        let shouldResume = defaults.bool(forKey: "herMode.active")
        debugLog("resumeIfNeeded unlocked=\(isUnlocked) persistedActive=\(shouldResume)")
        guard isUnlocked, shouldResume else { return }
        activate()
    }

    func deactivate() {
        debugLog("deactivate requested")
        isActive = false
        isPausedForCompanionSpeech = false
        statusMessage = "Paused"
        defaults.set(false, forKey: "herMode.active")
        stopRecognition()
        directDispatchTask?.cancel()
        directDispatchTask = nil
        silenceCheckTimer?.invalidate()
        sessionRestartTimer?.invalidate()
        ambientMood = .quiet
        StressLearningEngine.shared.stopMonitoring()
        UIApplication.shared.isIdleTimerDisabled = false
        Task.detached(priority: .utility) {
            await BareClawAudioSessionController.shared.deactivate(
                owner: BareClawAudioSessionOwner.herMode
            )
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        Task.detached(priority: .utility) {
            await BareClawAudioSessionController.shared.prepare(
                .herModeListening,
                source: "HerModeEngine"
            )
        }
        debugLog("audio session preparation scheduled")

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
        debugLog("audio interruption ended; restarting recognition")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            Task { [weak self] in
                let audioReady = await BareClawAudioSessionController.shared.reactivate(
                    owner: BareClawAudioSessionOwner.herMode
                )
                await MainActor.run {
                    guard let self else { return }
                    if audioReady {
                        self.beginRecognitionSession()
                    } else {
                        self.statusMessage = "Listener audio unavailable"
                        self.isListening = false
                        self.isRestarting = false
                    }
                }
            }
        }
    }

    // MARK: - Permissions → start

    private func requestPermissionsAndStart() {
        debugLog("requesting speech authorization")
        statusMessage = "Requesting speech permission..."
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.debugLog("speech authorization status=\(Self.speechAuthorizationDescription(status))")
                guard status == .authorized else {
                    self.statusMessage = "Speech permission needed"
                    return
                }
                self.requestMicrophonePermissionAndStart()
            }
        }
    }

    private func requestMicrophonePermissionAndStart() {
        statusMessage = "Requesting microphone permission..."
        let handlePermission: (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.debugLog("microphone permission granted=\(granted)")
                guard granted else {
                    self.statusMessage = "Microphone permission needed"
                    self.ambientMood = .quiet
                    self.isListening = false
                    return
                }
                self.statusMessage = "Starting listener..."
                let audioReady = await BareClawAudioSessionController.shared.activate(
                    .herModeListening,
                    owner: BareClawAudioSessionOwner.herMode
                )
                guard audioReady else {
                    self.statusMessage = "Microphone audio session failed"
                    self.ambientMood = .quiet
                    self.isListening = false
                    self.isRestarting = false
                    return
                }
                self.beginRecognitionSession()
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handlePermission)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handlePermission)
        }
    }

    private static func speechAuthorizationDescription(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Continuous recognition session
    //
    // One session ≈ 60 seconds max (Apple limit). We restart automatically.

    func beginRecognitionSession() {
        guard !isPausedForCompanionSpeech else {
            debugLog("beginRecognitionSession skipped: paused for companion speech")
            return
        }
        guard isActive else {
            debugLog("beginRecognitionSession skipped: inactive")
            return
        }
        guard !isListening else {
            debugLog("beginRecognitionSession skipped: already listening")
            return
        }
        guard !isRestarting else {
            debugLog("beginRecognitionSession skipped: restart already in progress")
            return
        }

        // Exponential backoff: 0.5s, 1s, 2s, 4s — then give up until next user action
        guard restartAttempts < maxRestartAttempts else {
            debugLog("recognition restart cap reached; pausing before retry")
            statusMessage = "Listener paused; retrying soon"
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
        statusMessage = "Starting listener..."
        stopRecognition()
        debugLog("beginRecognitionSession starting attempt=\(restartAttempts + 1)")

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.defaultTaskHint = .dictation
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults  = true
        recognitionRequest?.requiresOnDeviceRecognition = true

        guard let request    = recognitionRequest,
              let recognizer = speechRecognizer,
              recognizer.isAvailable
        else {
            debugLog("recognition setup failed: recognizer unavailable or request missing")
            statusMessage = "Speech recognizer unavailable"
            isRestarting = false
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            let errorDescription = error?.localizedDescription
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
                    guard self.isActive, !self.isPausedForCompanionSpeech else { return }

                    // isFinal with no error = normal 60s Apple limit rolling over — restart quickly
                    // error = something went wrong — back off exponentially
                    let isNormalRollover = (error == nil && result?.isFinal == true)
                    if let errorDescription {
                        self.debugLog("recognition task ended with error: \(errorDescription)")
                    } else if isNormalRollover {
                        self.debugLog("recognition task reached normal rollover")
                    }
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
            Task { @MainActor [weak self] in self?.recognitionRequest?.append(buf) }
            guard let channel = buf.floatChannelData?[0] else { return }
            let frameCount = Int(buf.frameLength)
            guard frameCount > 0 else { return }
            var rms: Float = 0
            for i in 0..<frameCount {
                rms += channel[i] * channel[i]
            }
            rms = sqrt(rms / Float(frameCount))
            Task { @MainActor in
                StressLearningEngine.shared.observeAmbientNoiseSample(rms)
            }
        }
        micEngine.prepare()
        do {
            try micEngine.start()
            isListening      = true
            isRestarting     = false
            restartAttempts  = 0   // reset on successful start
            ambientMood      = .listening
            statusMessage    = "Listening"
            debugLog("mic engine started; listening=true")
        } catch {
            isRestarting = false
            restartAttempts += 1
            statusMessage = "Microphone failed to start"
            debugLog("mic engine failed to start: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func pauseRecognitionForCompanionSpeech() -> Bool {
        guard isActive, !isPausedForCompanionSpeech else { return false }
        isPausedForCompanionSpeech = true
        debugLog("pausing recognition for companion speech")
        stopRecognition()
        isRestarting = false
        ambientMood = .speaking
        statusMessage = "Speaking"
        return true
    }

    func resumeRecognitionAfterCompanionSpeech() {
        guard isActive, isPausedForCompanionSpeech else { return }
        debugLog("resuming recognition after companion speech")
        isPausedForCompanionSpeech = false
        statusMessage = "Restarting listener..."

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.isActive, !self.isListening, !self.isRestarting else { return }
            let audioReady = await BareClawAudioSessionController.shared.reactivate(
                owner: BareClawAudioSessionOwner.herMode
            )
            guard audioReady else {
                self.statusMessage = "Listener audio unavailable"
                self.ambientMood = .quiet
                return
            }
            self.beginRecognitionSession()
        }
    }

    private func stopRecognition() {
        if isListening || micEngine.isRunning {
            debugLog("stopping recognition")
        }
        micEngine.stop()
        micEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask    = nil
        isListening        = false
        if isActive {
            statusMessage = "Restarting listener..."
        }
    }

    // MARK: - Ambient transcript processing
    //
    // We process ALL transcribed speech — not just speech directed at the app.
    // This is the "listening" brain. It takes notes, never reacts immediately.

    private var lastProcessedTranscript = ""

    private func processAmbientTranscript(_ transcript: String) {
        liveTranscript   = transcript
        lastUserSpeechAt = Date()
        statusMessage = "Heard speech"

        // Only process new words (avoid re-processing same partial result)
        let previousTranscript = lastProcessedTranscript
        guard transcript != previousTranscript else { return }
        lastProcessedTranscript = transcript

        let ambientDelta = newAmbientText(previous: previousTranscript, current: transcript)
        observeAmbientConversationText(ambientDelta.isEmpty ? transcript : ambientDelta)

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
                        debugLog("ambient topic detected: \(topic)")
                        saveTopics()   // persist immediately — survives app restart
                    }
                    break
                }
            }
        }

        let persona = UserPersona.shared
        if let directMessage = directAmbientMessage(from: transcript, persona: persona) {
            guard directMessage != lastSentText else { return }
            liveTranscript = ""
            scheduleDirectMessage(directMessage)
        }
    }

    // MARK: - Ambient conversation interpretation

    private func newAmbientText(previous: String, current: String) -> String {
        guard !previous.isEmpty else { return current }
        let previousLower = previous.lowercased()
        let currentLower = current.lowercased()

        guard currentLower.hasPrefix(previousLower),
              current.count >= previous.count else {
            return current
        }

        let start = current.index(current.startIndex, offsetBy: previous.count)
        return String(current[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func observeAmbientConversationText(_ text: String) {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.split(separator: " ").count >= 2 else { return }

        if ambientWindowStartedAt == nil {
            ambientWindowStartedAt = Date()
        }
        ambientWindowPieces.append(cleaned)
        trimAmbientWindowIfNeeded()

        let window = ambientWindowPieces.joined(separator: " ")
        let wordCount = window.split(separator: " ").count
        let windowAge = Date().timeIntervalSince(ambientWindowStartedAt ?? Date())
        guard wordCount >= 10, wordCount >= 18 || windowAge >= 18 else { return }
        guard Date().timeIntervalSince(lastAmbientInsightAt) >= 20 else { return }

        maybeCreateAmbientInsight(from: window)
    }

    private func trimAmbientWindowIfNeeded() {
        var words = ambientWindowPieces
            .joined(separator: " ")
            .split(separator: " ")
            .map(String.init)
        guard words.count > 90 else { return }
        words = Array(words.suffix(90))
        ambientWindowPieces = [words.joined(separator: " ")]
    }

    private func maybeCreateAmbientInsight(from text: String) {
        guard let insight = ambientInsight(from: text) else { return }

        let alreadyStored = detectedTopics.contains {
            $0.topic == insight.topic && Date().timeIntervalSince($0.heardAt) < 300
        }
        guard !alreadyStored else {
            ambientWindowPieces.removeAll()
            ambientWindowStartedAt = nil
            return
        }

        detectedTopics.append(TopicSignal(
            topic: insight.topic,
            keyword: insight.keyword,
            heardAt: Date(),
            summary: insight.summary,
            prompt: insight.prompt
        ))
        lastHeardTopic = insight.topic
        lastAmbientInsightAt = Date()
        ambientWindowPieces.removeAll()
        ambientWindowStartedAt = nil
        debugLog("ambient conversation insight detected: \(insight.topic)")
        saveTopics()
    }

    private func ambientInsight(from text: String) -> (topic: String, keyword: String, summary: String, prompt: String)? {
        let lower = text.lowercased()
        if let keyword = matchedKeyword(in: lower, keywords: [
            "yelling", "shouting", "screaming", "argument", "arguing", "fight",
            "fighting", "shut up", "leave me alone", "stop it"
        ]) {
            return (
                "conflict",
                keyword,
                "ambient conversation with signs of tension",
                "I heard tension in the room. Are you safe?"
            )
        }

        if let keyword = matchedKeyword(in: lower, keywords: [
            "stress", "stressed", "anxious", "worried", "overwhelmed", "panic",
            "angry", "frustrated", "tired", "exhausted", "rough day"
        ]) {
            return (
                "feelings",
                keyword,
                "ambient speech about pressure or stress",
                "You sounded like you might be under pressure. Want to tell me what happened?"
            )
        }

        if let keyword = matchedKeyword(in: lower, keywords: [
            "song", "music", "playlist", "album", "artist", "lyrics", "guitar",
            "piano", "singing", "singer"
        ]) {
            return (
                "creativity",
                keyword,
                "ambient speech about music",
                "I heard music come up. Is that a song you like?"
            )
        }

        if let keyword = matchedKeyword(in: lower, keywords: [
            "movie", "film", "show", "series", "episode", "netflix", "youtube",
            "hulu", "disney", "watching", "watched"
        ]) {
            return (
                "entertainment",
                keyword,
                "ambient speech about a show or movie",
                "I heard a show or movie come up. Are you into it?"
            )
        }

        if let keyword = matchedKeyword(in: lower, keywords: [
            "work", "job", "boss", "meeting", "deadline", "project", "client",
            "presentation"
        ]) {
            return (
                "work",
                keyword,
                "ambient speech about work",
                "I heard work come up. Is that weighing on you, or just background noise?"
            )
        }

        if let keyword = matchedKeyword(in: lower, keywords: [
            "relationship", "girlfriend", "boyfriend", "partner", "husband",
            "wife", "date", "love", "breakup"
        ]) {
            return (
                "relationships",
                keyword,
                "ambient speech about a relationship",
                "I heard relationship stuff come up. Do you want to talk about it?"
            )
        }

        if let keyword = matchedKeyword(in: lower, keywords: [
            "conversation", "talking about", "we were talking", "they said",
            "she said", "he said", "asked", "told"
        ]) {
            return (
                "conversation",
                keyword,
                "ambient conversation nearby",
                "I heard a conversation nearby. Is that something you want to unpack?"
            )
        }

        return nil
    }

    private func matchedKeyword(in text: String, keywords: [String]) -> String? {
        keywords.first { text.contains($0) }
    }

    // MARK: - Direct message dispatch (user spoke TO the companion)

    private func scheduleDirectMessage(_ text: String) {
        directDispatchTask?.cancel()
        directDispatchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned != self.lastSentText else { return }
            self.lastSentText = cleaned
            self.debugLog("direct ambient speech detected length=\(cleaned.count)")
            self.dispatchDirectMessage(cleaned)
        }
    }

    private func directAmbientMessage(from transcript: String, persona: UserPersona) -> String? {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let lower = cleaned.lowercased()
        let punctuation = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",.:;!?-"))

        for alias in wakeAliases(for: persona) {
            let lowerAlias = alias.lowercased()
            let prefixes = [
                lowerAlias,
                "hey \(lowerAlias)",
                "hi \(lowerAlias)",
                "hello \(lowerAlias)"
            ]
            for prefix in prefixes {
                guard lower == prefix
                    || lower.hasPrefix(prefix + " ")
                    || lower.hasPrefix(prefix + ",")
                    || lower.hasPrefix(prefix + ".")
                    || lower.hasPrefix(prefix + ":")
                    || lower.hasPrefix(prefix + ";")
                    || lower.hasPrefix(prefix + "!")
                    || lower.hasPrefix(prefix + "?") else {
                    continue
                }

                guard cleaned.count > prefix.count else { return cleaned }
                let start = cleaned.index(cleaned.startIndex, offsetBy: prefix.count)
                let remainder = String(cleaned[start...])
                    .trimmingCharacters(in: punctuation)
                return remainder.isEmpty ? cleaned : remainder
            }
        }

        return nil
    }

    private func wakeAliases(for persona: UserPersona) -> [String] {
        var aliases = [
            persona.assistantName,
            persona.selectedCompanion.name,
            persona.selectedCompanion.id
        ]
        aliases = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        return aliases.filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.count > $1.count }
    }

    private func dispatchDirectMessage(_ text: String) {
        guard !isProcessingReply else {
            debugLog("direct speech ignored: reply already processing")
            return
        }
        isProcessingReply = true
        ambientMood = .thinking
        defaults.set(text, forKey: pendingDirectMessageKey)
        debugLog("dispatching direct ambient speech length=\(text.count)")
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
    //   ✓ User has been quiet for a randomized 35-95 seconds
    //   ✓ Randomized cooldown window is open
    //   ✓ Daily cap has not been reached
    //   ✓ Companion isn't already speaking

    private func startSilenceCheck() {
        silenceCheckTimer?.invalidate()
        debugLog("silence check started")
        silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateProactiveOpportunity() }
        }
    }

    private func evaluateProactiveOpportunity() {
        guard isActive else { return }
        guard !CompanionVoiceEngine.shared.isSpeaking else {
            debugLog("proactive opportunity skipped: companion already speaking")
            return
        }
        resetDailyProactiveCounterIfNeeded()
        guard proactiveCountToday < maxProactiveMessagesPerDay else {
            debugLog("proactive opportunity skipped: daily cap reached")
            return
        }

        let silenceDuration = Date().timeIntervalSince(lastUserSpeechAt)
        guard silenceDuration >= requiredSilenceSeconds else {
            debugLog("proactive opportunity waiting for silence=\(Int(silenceDuration))s")
            return
        }

        guard Date() >= nextProactiveAllowedAt else {
            let wait = Int(nextProactiveAllowedAt.timeIntervalSinceNow)
            debugLog("proactive opportunity waiting for randomized window=\(max(wait, 0))s")
            return
        }

        // Find the oldest unsurfaced topic — prefer emotional topics
        let emotionalTopics = ["feelings", "loss", "relationships", "health", "conflict"]
        let candidate = detectedTopics.first { !$0.surfaced && emotionalTopics.contains($0.topic) }
                     ?? detectedTopics.first { !$0.surfaced }

        guard let signal = candidate else {
            debugLog("proactive opportunity checked: no unsurfaced topic yet")
            return
        }

        let gapSinceLast = Date().timeIntervalSince(lastProactiveAt)
        let minimumGapMinutes = minimumProactiveGapMinutes(for: signal)
        guard gapSinceLast >= minimumGapMinutes * 60 else {
            debugLog("proactive opportunity cooling down gap=\(Int(gapSinceLast))s")
            return
        }

        let chance = proactiveChance(for: signal)
        guard Double.random(in: 0...1) < chance else {
            debugLog("proactive opportunity randomly held topic=\(signal.topic)")
            scheduleNextProactiveWindow(minutes: 4...12)
            return
        }

        // Mark as surfaced so we don't repeat it
        if let idx = detectedTopics.firstIndex(where: { $0.keyword == signal.keyword && !$0.surfaced }) {
            detectedTopics[idx].surfaced = true
        }
        lastProactiveAt = Date()
        proactiveCountToday += 1
        scheduleNextProactiveWindow(minutes: nextWindowRange(after: signal))

        surfaceProactiveMessage(for: signal)
    }

    private func minimumProactiveGapMinutes(for signal: TopicSignal) -> TimeInterval {
        switch signal.topic {
        case "conflict", "feelings", "loss", "health":
            return 10
        default:
            return minProactiveGapMinutes
        }
    }

    private func proactiveChance(for signal: TopicSignal) -> Double {
        switch signal.topic {
        case "conflict":
            return 0.85
        case "feelings", "loss", "health":
            return 0.68
        case "relationships", "work", "money":
            return 0.48
        default:
            return 0.32
        }
    }

    private func nextWindowRange(after signal: TopicSignal) -> ClosedRange<Double> {
        switch signal.topic {
        case "conflict", "feelings", "loss", "health":
            return 18...36
        default:
            return 28...70
        }
    }

    // MARK: - Proactive message delivery
    //
    // Picks a gentle opener, speaks it softly, and lets the user decide.
    // If they respond → full conversation begins.
    // If they don't → we wait. We NEVER follow up the same message twice.

    private func surfaceProactiveMessage(for signal: TopicSignal) {
        let candidates = openers[signal.topic] ?? fallbackOpeners[signal.topic] ?? fallbackOpeners["default"]
        guard let candidates = candidates, !candidates.isEmpty else { return }
        let message = signal.prompt ?? candidates.randomElement()!

        debugLog("surfacing proactive message for topic=\(signal.topic)")
        ambientMood = .speaking
        statusMessage = "Reaching out"
        let persona     = UserPersona.shared
        let companion   = persona.selectedCompanion
        let deferSpeech = CompanionThoughtFlow.shouldDeferProactiveDelivery
        if !deferSpeech {
            CompanionVoiceEngine.shared.speakFiltered(message, companion: companion)
        }

        // Persist timing state so cooldown survives app restart
        saveTopics()

        // Post notification — ChatView observer logs this to the conversation
        NotificationCenter.default.post(
            name: .herModeProactiveMessage,
            object: nil,
            userInfo: ["text": message, "topic": signal.topic, "shouldSpeak": deferSpeech]
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            self?.ambientMood = .listening
            self?.statusMessage = self?.isListening == true ? "Listening" : "Starting listener..."
        }
    }

    // MARK: - Her Mode learning boost
    static let learningBoost: Double = 2.0

    private var fallbackOpeners: [String: [String]] {
        let companionName = companion.name
        return [
            "conversation": [
                "I heard conversation in the room. Was that something you want to talk about?",
                "It sounded like there was a conversation happening. Are you okay?"
            ],
            "conflict": [
                "I heard tension. Are you safe?",
                "That sounded intense. Is everything okay?"
            ],
            "creativity": [
                "Music came up. Is that a song you like?",
                "I heard something about music. Tell me what you were listening to."
            ],
            "entertainment": [
                "It sounded like something was on. What are you watching?",
                "I heard a show or movie come up. Are you into it?"
            ],
            "default": [
                "\(companionName) heard something in your world. Want to tell me about it?"
            ]
        ]
    }
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
