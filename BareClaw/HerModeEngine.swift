import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - HerModeEngine
//
// The beating heart of BareClaw — inspired by the 2013 film "Her".
//
// "Her" mode is an always-on, always-learning intimate companion experience.
// It unlocks when the relationship reaches Stage 4 — Deep Connection (61 pts).
//
// What it does:
//   1. Continuous listening — hears you speak and responds naturally
//   2. Silence detection — 2-second pause triggers a response
//   3. Proactive conversation — companion initiates when you've been quiet
//   4. Ambient presence — runs in the foreground, screen stays warm
//   5. Deeper learning — every exchange in Her Mode is weighted 2× for intimacy growth
//
// Within Apple guidelines:
//   - Audio: AVAudioSession .playAndRecord, background audio mode enabled
//   - Speech: SFSpeechRecognizer (device-side when available)
//   - Mic access: only while app is active/foregrounded (standard iOS rule)
//   - Proactive messages: UNUserNotificationCenter when backgrounded

// MARK: - Unlock threshold

extension HerLearningEngine {
    static let herModeUnlockScore: Double = 61.0   // Stage 4 "Deep Connection"
}

// MARK: - HerModeEngine

@MainActor
final class HerModeEngine: NSObject, ObservableObject {

    static let shared = HerModeEngine()

    // MARK: Published state
    @Published var isUnlocked:           Bool = false
    @Published var isActive:             Bool = false
    @Published var isListening:          Bool = false
    @Published var liveTranscript:       String = ""
    @Published var showUnlockCelebration: Bool = false
    @Published var connectionStrength:   Double = 0   // 0–1, visual pulse indicator

    // MARK: Private — speech recognition
    private var speechRecognizer:   SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let micEngine = AVAudioEngine()

    // MARK: Private — timers
    private var silenceTimer:       Timer?
    private var proactiveTimer:     Timer?
    private var lastSentText:       String = ""
    private var lastSpeechAt:       Date   = .distantPast

    // MARK: Private — state
    private let defaults = UserDefaults.standard
    private var isProcessing = false    // guard against double-send

    // MARK: - Init

    override private init() {
        super.init()
        isUnlocked = defaults.bool(forKey: "herMode.unlocked")
        isActive   = defaults.bool(forKey: "herMode.active")
    }

    // MARK: - Unlock check
    //
    // Called by HerLearningEngine after every message.
    // Safe to call repeatedly — only fires the celebration once.

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
        requestPermissionsAndListen()
        scheduleProactiveCheck()
        UIApplication.shared.isIdleTimerDisabled = true   // keep screen on
    }

    func deactivate() {
        isActive   = false
        isListening = false
        defaults.set(false, forKey: "herMode.active")
        stopRecognition()
        proactiveTimer?.invalidate()
        silenceTimer?.invalidate()
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
        } catch {
            // Fallback — still start; audio may not be routed perfectly
        }

        // Observe interruptions (calls, Siri, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioInterruption(_ n: Notification) {
        guard let type = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let iType = AVAudioSession.InterruptionType(rawValue: type)
        else { return }

        if iType == .ended, isActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.beginRecognitionSession()
            }
        }
    }

    // MARK: - Permissions → start listening

    private func requestPermissionsAndListen() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.beginRecognitionSession()
                }
            }
        }
    }

    // MARK: - Recognition session

    func beginRecognitionSession() {
        guard isActive, !isListening else { return }
        stopRecognition()

        speechRecognizer  = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.defaultTaskHint = .confirmation
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults   = true
        recognitionRequest?.requiresOnDeviceRecognition  = false   // server for best accuracy

        guard let request = recognitionRequest,
              let recognizer = speechRecognizer, recognizer.isAvailable
        else { return }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.liveTranscript = transcript
                    self.lastSpeechAt   = Date()
                    self.resetSilenceTimer(transcript: transcript)
                    // Visual pulse
                    self.connectionStrength = min(1, Double(transcript.count) / 60.0)
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.isListening = false
                    // Restart after a short breath
                    try? await Task.sleep(nanoseconds: 500_000_000)
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
        } catch {}
    }

    func stopRecognition() {
        micEngine.stop()
        micEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask    = nil
        isListening        = false
        silenceTimer?.invalidate()
    }

    // MARK: - Silence detection → send

    private func resetSilenceTimer(transcript: String) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != self.lastSentText else { return }
            self.lastSentText   = text
            self.liveTranscript = ""
            self.connectionStrength = 0
            self.dispatchSpeech(text)
        }
    }

    private func dispatchSpeech(_ text: String) {
        guard !isProcessing else { return }
        isProcessing = true
        NotificationCenter.default.post(
            name: .herModeSpeechDetected,
            object: nil,
            userInfo: ["text": text]
        )
        // Reset processing flag after a second — ChatViewModel picks it up and sends
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isProcessing = false
        }
    }

    // MARK: - Proactive conversation
    //
    // If the user has been silent for 4 minutes while in Her Mode,
    // the companion initiates with a gentle thought.

    private func scheduleProactiveCheck() {
        proactiveTimer?.invalidate()
        proactiveTimer = Timer.scheduledTimer(withTimeInterval: 240, repeats: true) { [weak self] _ in
            guard let self else { return }
            let silence = Date().timeIntervalSince(self.lastSpeechAt)
            guard silence > 230 else { return }
            NotificationCenter.default.post(
                name: .herModeProactiveNeeded,
                object: nil
            )
        }
    }

    // MARK: - Her Mode learning boost
    //
    // Messages in Her Mode get a 2× intimacy multiplier — the relationship
    // deepens faster when you're in the always-on intimate mode.

    static let learningBoost: Double = 2.0
}

// MARK: - Notification names

extension Notification.Name {
    static let herModeSpeechDetected  = Notification.Name("herMode.speechDetected")
    static let herModeProactiveNeeded = Notification.Name("herMode.proactiveNeeded")
    static let herModeUnlocked        = Notification.Name("herMode.unlocked")
}
