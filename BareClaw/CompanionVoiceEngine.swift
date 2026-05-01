import AVFoundation
import Foundation
import SwiftUI

// MARK: - VoiceCharacter
//
// BareClaw's voice component. The active path is neural audio only: each
// companion requires a separate configured voice ID, with no Apple speech
// fallback. The local tuning fields stay on the model because other engines use
// the same character profile to describe rhythm, warmth, and delivery intent.

struct VoiceCharacter: Codable {
    let expectedGender: CompanionGender
    let preferredVoiceIdentifiers: [String]
    let preferredVoiceNames: [String]
    let preferredLanguages: [String]
    let fallbackLanguage: String
    let rate: Float
    let pitchMultiplier: Float
    let preDelay: TimeInterval
    let postDelay: TimeInterval
    let volume: Float
    let characterName: String
    let styleDescription: String
    let phrasePause: TimeInterval
    let expressiveness: Float
}

enum CompanionSpeechContext {
    case conversation
    case love
    case stress
    case ceremony
}

extension VoiceCharacter {
    func tuned(for context: CompanionSpeechContext) -> VoiceCharacter {
        switch context {
        case .conversation:
            return self
        case .love:
            return adjusted(
                rateOffset: -0.015,
                pitchOffset: 0.004,
                preDelayOffset: 0.03,
                postDelayOffset: 0.04,
                volumeMultiplier: 0.98,
                phrasePauseOffset: 0.025,
                expressivenessOffset: 0.004
            )
        case .stress:
            return adjusted(
                rateOffset: -0.045,
                pitchOffset: -0.012,
                preDelayOffset: 0.06,
                postDelayOffset: 0.08,
                volumeMultiplier: 0.94,
                phrasePauseOffset: 0.07,
                expressivenessOffset: -0.008
            )
        case .ceremony:
            return adjusted(
                rateOffset: -0.025,
                pitchOffset: 0,
                preDelayOffset: 0.04,
                postDelayOffset: 0.04,
                volumeMultiplier: 0.98,
                phrasePauseOffset: 0.04,
                expressivenessOffset: 0.002
            )
        }
    }

    private func adjusted(
        rateOffset: Float,
        pitchOffset: Float,
        preDelayOffset: TimeInterval,
        postDelayOffset: TimeInterval,
        volumeMultiplier: Float,
        phrasePauseOffset: TimeInterval,
        expressivenessOffset: Float
    ) -> VoiceCharacter {
        VoiceCharacter(
            expectedGender: expectedGender,
            preferredVoiceIdentifiers: preferredVoiceIdentifiers,
            preferredVoiceNames: preferredVoiceNames,
            preferredLanguages: preferredLanguages,
            fallbackLanguage: fallbackLanguage,
            rate: max(0.36, min(0.52, rate + rateOffset)),
            pitchMultiplier: max(0.72, min(1.12, pitchMultiplier + pitchOffset)),
            preDelay: max(0, preDelay + preDelayOffset),
            postDelay: max(0, postDelay + postDelayOffset),
            volume: max(0.82, min(1.0, volume * volumeMultiplier)),
            characterName: characterName,
            styleDescription: styleDescription,
            phrasePause: max(0.04, phrasePause + phrasePauseOffset),
            expressiveness: max(0.006, min(0.045, expressiveness + expressivenessOffset))
        )
    }

    // Female companions
    static let luna = VoiceCharacter(
        expectedGender: .female,
        preferredVoiceIdentifiers: [
            "com.apple.voice.premium.en-US.Ava",
            "com.apple.voice.enhanced.en-US.Ava",
            "com.apple.voice.premium.en-US.Nicky",
            "com.apple.voice.enhanced.en-US.Nicky",
            "com.apple.voice.compact.en-AU.Karen",
            "com.apple.voice.compact.en-US.Ava"
        ],
        preferredVoiceNames: ["Ava", "Nicky", "Karen", "Tessa", "Moira"],
        preferredLanguages: ["en-US", "en-AU", "en-IE", "en-ZA"],
        fallbackLanguage: "en-US",
        rate: 0.445,
        pitchMultiplier: 1.055,
        preDelay: 0.12,
        postDelay: 0.14,
        volume: 1.0,
        characterName: "Luna",
        styleDescription: "warm, intimate, cinematic, fluid",
        phrasePause: 0.095,
        expressiveness: 0.044
    )

    static let aria = VoiceCharacter(
        expectedGender: .female,
        preferredVoiceIdentifiers: [
            "com.apple.voice.premium.en-ZA.Tessa",
            "com.apple.voice.enhanced.en-ZA.Tessa",
            "com.apple.voice.premium.en-AU.Karen",
            "com.apple.voice.enhanced.en-AU.Karen",
            "com.apple.voice.compact.en-ZA.Tessa",
            "com.apple.voice.compact.en-AU.Karen"
        ],
        preferredVoiceNames: ["Tessa", "Karen", "Ava", "Nicky", "Moira"],
        preferredLanguages: ["en-AU", "en-ZA", "en-US", "en-IE"],
        fallbackLanguage: "en-US",
        rate: 0.492,
        pitchMultiplier: 1.075,
        preDelay: 0.035,
        postDelay: 0.06,
        volume: 1.0,
        characterName: "Aria",
        styleDescription: "bright, confident, accented, alive",
        phrasePause: 0.065,
        expressiveness: 0.044
    )

    static let kel = VoiceCharacter(
        expectedGender: .female,
        preferredVoiceIdentifiers: [
            "com.apple.voice.premium.en-IE.Moira",
            "com.apple.voice.enhanced.en-IE.Moira",
            "com.apple.voice.compact.en-IE.Moira",
            "com.apple.voice.premium.en-ZA.Tessa",
            "com.apple.voice.enhanced.en-ZA.Tessa"
        ],
        preferredVoiceNames: ["Moira", "Tessa", "Nicky", "Ava", "Karen"],
        preferredLanguages: ["en-IE", "en-ZA", "en-AU", "en-US", "en-GB"],
        fallbackLanguage: "en-US",
        rate: 0.445,
        pitchMultiplier: 1.075,
        preDelay: 0.11,
        postDelay: 0.12,
        volume: 1.0,
        characterName: "Kel",
        styleDescription: "young Irish, calm, grounded, gentle",
        phrasePause: 0.095,
        expressiveness: 0.038
    )

    // Male companions
    static let marco = VoiceCharacter(
        expectedGender: .male,
        preferredVoiceIdentifiers: [
            "com.apple.voice.premium.en-US.Aaron",
            "com.apple.voice.enhanced.en-US.Aaron",
            "com.apple.voice.premium.en-US.Evan",
            "com.apple.voice.enhanced.en-US.Evan",
            "com.apple.voice.premium.en-US.Nathan",
            "com.apple.voice.enhanced.en-US.Nathan",
            "com.apple.voice.compact.en-GB.Daniel",
            "com.apple.voice.compact.en-US.Aaron"
        ],
        preferredVoiceNames: ["Aaron", "Evan", "Nathan", "Daniel", "Alex"],
        preferredLanguages: ["en-US", "en-GB", "en-CA", "en-AU"],
        fallbackLanguage: "en-US",
        rate: 0.472,
        pitchMultiplier: 0.93,
        preDelay: 0.05,
        postDelay: 0.07,
        volume: 1.0,
        characterName: "Marco",
        styleDescription: "young, grounded, direct, vital",
        phrasePause: 0.06,
        expressiveness: 0.036
    )

    static let dante = VoiceCharacter(
        expectedGender: .male,
        preferredVoiceIdentifiers: [
            "com.apple.voice.premium.en-GB.Daniel",
            "com.apple.voice.enhanced.en-GB.Daniel",
            "com.apple.voice.premium.en-US.Aaron",
            "com.apple.voice.enhanced.en-US.Aaron",
            "com.apple.voice.premium.en-US.Evan",
            "com.apple.voice.enhanced.en-US.Evan"
        ],
        preferredVoiceNames: ["Daniel", "Aaron", "Evan", "Nathan"],
        preferredLanguages: ["en-GB", "en-US", "en-IE", "en-AU"],
        fallbackLanguage: "en-US",
        rate: 0.432,
        pitchMultiplier: 0.90,
        preDelay: 0.10,
        postDelay: 0.13,
        volume: 1.0,
        characterName: "Dante",
        styleDescription: "rich, warm, expressive, fluid",
        phrasePause: 0.10,
        expressiveness: 0.044
    )

    static let kai = VoiceCharacter(
        expectedGender: .male,
        preferredVoiceIdentifiers: [
            "com.apple.voice.premium.en-US.Aaron",
            "com.apple.voice.enhanced.en-US.Aaron",
            "com.apple.voice.premium.en-IN.Rishi",
            "com.apple.voice.enhanced.en-IN.Rishi",
            "com.apple.voice.premium.en-GB.Daniel",
            "com.apple.voice.enhanced.en-GB.Daniel",
            "com.apple.voice.compact.en-IN.Rishi",
            "com.apple.voice.compact.en-US.Aaron"
        ],
        preferredVoiceNames: ["Aaron", "Rishi", "Daniel", "Evan", "Nathan"],
        preferredLanguages: ["en-US", "en-IN", "en-GB", "en-AU"],
        fallbackLanguage: "en-US",
        rate: 0.485,
        pitchMultiplier: 0.94,
        preDelay: 0.035,
        postDelay: 0.055,
        volume: 1.0,
        characterName: "Kai",
        styleDescription: "clear, steady, present, lively",
        phrasePause: 0.055,
        expressiveness: 0.034
    )
}

enum BareClawAudioSessionProfile: String, Sendable {
    case companionPlayback
    case herModeListening
}

enum BareClawAudioSessionOwner {
    static let companionVoice = "companionVoice"
    static let herMode = "herMode"
}

actor BareClawAudioSessionController {
    static let shared = BareClawAudioSessionController()

    private struct OwnerState {
        let profile: BareClawAudioSessionProfile
        let token: UUID?
    }

    private var activeOwners: [String: OwnerState] = [:]
    private var ownerOrder: [String] = []
    private var configuredProfile: BareClawAudioSessionProfile?
    private var currentProfile: BareClawAudioSessionProfile?
    private var isActive = false
    private var cancelledTokens: Set<UUID> = []

    @discardableResult
    func prepare(_ profile: BareClawAudioSessionProfile, source: String) -> Bool {
        do {
            try configure(profile)
            DiagnosticsLog.info(
                "audio_session",
                "Audio session prepared.",
                details: ["profile": profile.rawValue, "source": source]
            )
            return true
        } catch {
            DiagnosticsLog.error(
                "audio_session",
                "Audio session preparation failed.",
                error: error,
                details: ["profile": profile.rawValue, "source": source]
            )
            return false
        }
    }

    @discardableResult
    func activate(
        _ profile: BareClawAudioSessionProfile,
        owner: String,
        token: UUID? = nil
    ) -> Bool {
        if let token, cancelledTokens.contains(token) {
            DiagnosticsLog.warning(
                "audio_session",
                "Skipped cancelled audio session activation.",
                details: ["profile": profile.rawValue, "owner": owner]
            )
            return false
        }

        do {
            try configure(profile)
            if !isActive || currentProfile != profile {
                try AVAudioSession.sharedInstance().setActive(
                    true,
                    options: .notifyOthersOnDeactivation
                )
            }
            activeOwners[owner] = OwnerState(profile: profile, token: token)
            rememberOwner(owner)
            isActive = true
            currentProfile = profile
            DiagnosticsLog.info(
                "audio_session",
                "Audio session activated.",
                details: ["profile": profile.rawValue, "owner": owner]
            )
            return true
        } catch {
            activeOwners.removeValue(forKey: owner)
            ownerOrder.removeAll { $0 == owner }
            DiagnosticsLog.error(
                "audio_session",
                "Audio session activation failed.",
                error: error,
                details: ["profile": profile.rawValue, "owner": owner]
            )
            return false
        }
    }

    func reactivate(owner: String) -> Bool {
        guard let state = activeOwners[owner] else { return false }
        if let token = state.token, cancelledTokens.contains(token) { return false }

        do {
            try configure(state.profile)
            try AVAudioSession.sharedInstance().setActive(
                true,
                options: .notifyOthersOnDeactivation
            )
            isActive = true
            currentProfile = state.profile
            rememberOwner(owner)
            DiagnosticsLog.info(
                "audio_session",
                "Audio session reactivated.",
                details: ["profile": state.profile.rawValue, "owner": owner]
            )
            return true
        } catch {
            DiagnosticsLog.error(
                "audio_session",
                "Audio session reactivation failed.",
                error: error,
                details: ["profile": state.profile.rawValue, "owner": owner]
            )
            return false
        }
    }

    func deactivate(owner: String, token: UUID? = nil) {
        if let token {
            cancelledTokens.insert(token)
            guard activeOwners[owner]?.token == token else { return }
        }

        activeOwners.removeValue(forKey: owner)
        ownerOrder.removeAll { $0 == owner }

        do {
            try restorePreferredOwnerOrDeactivate(source: owner)
        } catch {
            DiagnosticsLog.error(
                "audio_session",
                "Audio session deactivation failed.",
                error: error,
                details: ["owner": owner]
            )
        }
    }

    private func configure(_ profile: BareClawAudioSessionProfile) throws {
        guard configuredProfile != profile else { return }

        let session = AVAudioSession.sharedInstance()
        switch profile {
        case .companionPlayback:
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: []
            )
        case .herModeListening:
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
        }

        configuredProfile = profile
    }

    private func restorePreferredOwnerOrDeactivate(source: String) throws {
        guard let owner = ownerOrder.last,
              let state = activeOwners[owner] else {
            if isActive {
                try AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
                DiagnosticsLog.info(
                    "audio_session",
                    "Audio session deactivated.",
                    details: ["source": source]
                )
            }
            isActive = false
            currentProfile = nil
            return
        }

        try configure(state.profile)
        if !isActive || currentProfile != state.profile {
            try AVAudioSession.sharedInstance().setActive(
                true,
                options: .notifyOthersOnDeactivation
            )
        }
        isActive = true
        currentProfile = state.profile
        DiagnosticsLog.info(
            "audio_session",
            "Audio session restored to active owner.",
            details: ["profile": state.profile.rawValue, "owner": owner, "source": source]
        )
    }

    private func rememberOwner(_ owner: String) {
        ownerOrder.removeAll { $0 == owner }
        ownerOrder.append(owner)
    }
}

private final class CompanionVoicePlaybackDriver: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let requestID: UUID
    let generation: UInt64

    private let audioByteCount: Int
    private let queue = DispatchQueue(label: "com.bareclaw.voice.playback", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private let stateLock = NSLock()
    private var stopped = false
    private let shouldStart: @MainActor (UUID, UInt64, CompanionVoicePlaybackDriver) -> Bool
    private let onStarted: @MainActor (UUID, UInt64, CompanionVoicePlaybackDriver, Int) -> Void
    private let onFailed: @MainActor (UUID, UInt64, CompanionVoicePlaybackDriver, Error) -> Void
    private let onFinished: @MainActor (UUID, UInt64, CompanionVoicePlaybackDriver) -> Void

    init(
        data: Data,
        requestID: UUID,
        generation: UInt64,
        shouldStart: @escaping @MainActor (UUID, UInt64, CompanionVoicePlaybackDriver) -> Bool,
        onStarted: @escaping @MainActor (UUID, UInt64, CompanionVoicePlaybackDriver, Int) -> Void,
        onFailed: @escaping @MainActor (UUID, UInt64, CompanionVoicePlaybackDriver, Error) -> Void,
        onFinished: @escaping @MainActor (UUID, UInt64, CompanionVoicePlaybackDriver) -> Void
    ) throws {
        self.requestID = requestID
        self.generation = generation
        self.audioByteCount = data.count
        self.shouldStart = shouldStart
        self.onStarted = onStarted
        self.onFailed = onFailed
        self.onFinished = onFinished
        self.player = try AVAudioPlayer(data: data)
        super.init()
        player?.delegate = self
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isStopped, let player = self.player else { return }

            player.prepareToPlay()
            Thread.sleep(forTimeInterval: 0.08)

            Task { @MainActor [weak self] in
                guard let self,
                      self.shouldStart(self.requestID, self.generation, self) else {
                    return
                }

                self.queue.async { [weak self] in
                    guard let self else { return }
                    guard !self.isStopped, let player = self.player else { return }

                    let didPlay = player.play()
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if didPlay {
                            self.onStarted(self.requestID, self.generation, self, self.audioByteCount)
                        } else {
                            self.onFailed(self.requestID, self.generation, self, NeuralVoiceError.playbackFailed)
                        }
                    }
                }
            }
        }
    }

    func stop() {
        markStopped()
        queue.async { [weak self] in
            guard let self else { return }
            self.player?.stop()
            self.player = nil
        }
    }

    private var isStopped: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopped
    }

    private func markStopped() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onFinished(self.requestID, self.generation, self)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onFailed(self.requestID, self.generation, self, error ?? NeuralVoiceError.invalidAudio)
        }
    }
}

@MainActor
final class CompanionVoiceEngine: NSObject, ObservableObject {
    static let shared = CompanionVoiceEngine()

    @Published var isSpeaking: Bool = false
    @Published var voiceEnabled: Bool =
        UserDefaults.standard.object(forKey: "companion.voiceEnabled") as? Bool ?? true
    @Published private(set) var activeCharacterName: String? = nil
    @Published private(set) var lastVoiceError: String? = nil

    private var audioPlayback: CompanionVoicePlaybackDriver?
    private var activeSpeakTask: Task<Void, Never>?
    private var activeSpeakCompletion: (() -> Void)?
    private var activeRequestID: UUID?
    private var companionChangeObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var activeAudioSessionToken: UUID?
    private var playbackGeneration: UInt64 = 0
    private var streamingSpeechID: UUID?
    private var streamingSpeechQueue: [StreamingSpeechSegment] = []
    private var streamingSpeechIsOpen = false
    private var streamingSpeechIsPlaying = false
    private var streamingPausedHerMode = false
    private var activeSpeechPausedHerMode = false

    private struct StreamingSpeechSegment {
        let text: String
        let character: VoiceCharacter
        let context: CompanionSpeechContext
    }

    private override init() {
        super.init()
        configureAudioSession()
        companionChangeObserver = NotificationCenter.default.addObserver(
            forName: .userPersonaCompanionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopSpeaking()
            }
        }
    }

    deinit {
        if let companionChangeObserver {
            NotificationCenter.default.removeObserver(companionChangeObserver)
        }
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
        }
    }

    private func configureAudioSession() {
        prepareVoiceAudioSession()

        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: typeValue) == .ended else {
                return
            }

            Task.detached(priority: .userInitiated) {
                await BareClawAudioSessionController.shared.reactivate(
                    owner: BareClawAudioSessionOwner.companionVoice
                )
            }
        }
    }

    private func prepareVoiceAudioSession() {
        Task.detached(priority: .utility) {
            await BareClawAudioSessionController.shared.prepare(
                .companionPlayback,
                source: "CompanionVoiceEngine"
            )
        }
    }

    private func activateVoiceAudioSession(token: UUID) -> Task<Bool, Never> {
        Task.detached(priority: .userInitiated) {
            await BareClawAudioSessionController.shared.activate(
                .companionPlayback,
                owner: BareClawAudioSessionOwner.companionVoice,
                token: token
            )
        }
    }

    private func deactivateVoiceAudioSession(token: UUID?) {
        Task.detached(priority: .utility) {
            await BareClawAudioSessionController.shared.deactivate(
                owner: BareClawAudioSessionOwner.companionVoice,
                token: token
            )
        }
    }

    func speak(
        _ text: String,
        character: VoiceCharacter,
        context: CompanionSpeechContext = .conversation,
        completion: (() -> Void)? = nil
    ) {
        startSpeech(text,
                    character: character,
                    context: context,
                    cancelStreamingQueue: true,
                    completion: completion)
    }

    @discardableResult
    func beginStreamingSpeech(character: VoiceCharacter, context: CompanionSpeechContext = .love) -> UUID? {
        guard voiceEnabled else {
            DiagnosticsLog.warning(
                "voice",
                "Streaming speech skipped because voice is disabled.",
                details: ["character": character.characterName]
            )
            return nil
        }

        cancelStreamingSpeech(clearCurrentAudio: true)
        pauseHerModeForStreamingIfNeeded()
        prepareVoiceAudioSession()

        let streamID = UUID()
        streamingSpeechID = streamID
        streamingSpeechQueue.removeAll()
        streamingSpeechIsOpen = true
        streamingSpeechIsPlaying = false
        activeCharacterName = character.characterName
        lastVoiceError = nil
        DiagnosticsLog.info(
            "voice",
            "Streaming speech started.",
            details: ["character": character.characterName, "context": "\(context)"]
        )
        return streamID
    }

    func enqueueStreamingSpeech(
        _ text: String,
        character: VoiceCharacter,
        context: CompanionSpeechContext = .love,
        streamID: UUID?
    ) {
        guard voiceEnabled,
              let streamID,
              streamingSpeechID == streamID else {
            DiagnosticsLog.warning("voice", "Streaming speech segment skipped because stream is not active.")
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        streamingSpeechQueue.append(StreamingSpeechSegment(
            text: trimmed,
            character: character,
            context: context
        ))
        DiagnosticsLog.info(
            "voice",
            "Streaming speech segment queued.",
            details: [
                "character": character.characterName,
                "context": "\(context)",
                "length": "\(trimmed.count)",
                "queueDepth": "\(streamingSpeechQueue.count)"
            ]
        )
        playNextStreamingSpeechSegment()
    }

    func finishStreamingSpeech(streamID: UUID?) {
        guard let streamID, streamingSpeechID == streamID else { return }
        streamingSpeechIsOpen = false
        DiagnosticsLog.info("voice", "Streaming speech finished input.")
        clearFinishedStreamingSpeechIfIdle()
    }

    func cancelStreamingSpeech(streamID: UUID?) {
        guard streamID == nil || streamingSpeechID == streamID else { return }
        cancelStreamingSpeech(clearCurrentAudio: true)
    }

    func speakResponsively(
        _ text: String,
        character: VoiceCharacter,
        context: CompanionSpeechContext = .love
    ) {
        guard voiceEnabled else { return }
        guard let streamID = beginStreamingSpeech(character: character, context: context) else { return }
        for chunk in Self.responsiveSpeechChunks(from: text) {
            enqueueStreamingSpeech(chunk, character: character, context: context, streamID: streamID)
        }
        finishStreamingSpeech(streamID: streamID)
    }

    private func startSpeech(
        _ text: String,
        character: VoiceCharacter,
        context: CompanionSpeechContext,
        cancelStreamingQueue: Bool,
        completion: (() -> Void)?
    ) {
        guard voiceEnabled else {
            completion?()
            DiagnosticsLog.warning(
                "voice",
                "Speech skipped because voice is disabled.",
                details: ["character": character.characterName]
            )
            return
        }

        if cancelStreamingQueue {
            cancelStreamingSpeech(clearCurrentAudio: false)
        }

        let deliveryCharacter = character.tuned(for: context)
        let cleanText = normalizedSpeechText(from: text, character: deliveryCharacter)
        guard !cleanText.isEmpty else {
            completion?()
            DiagnosticsLog.warning("voice", "Speech skipped because normalized text was empty.")
            return
        }

        let requestID = UUID()
        stopCurrentSpeech(callCompletion: false)
        let pausedHerMode = cancelStreamingQueue ? pauseHerModeForActiveSpeechIfNeeded() : false
        let audioSessionTask = activateVoiceAudioSession(token: requestID)
        activeRequestID = requestID
        activeAudioSessionToken = requestID
        activeSpeechPausedHerMode = pausedHerMode
        isSpeaking = true
        activeCharacterName = character.characterName
        activeSpeakCompletion = completion
        lastVoiceError = nil
        DiagnosticsLog.info(
            "voice",
            "Voice synthesis requested.",
            details: [
                "character": character.characterName,
                "context": "\(context)",
                "textLength": "\(cleanText.count)"
            ]
        )

        activeSpeakTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await NeuralVoiceService.synthesize(
                    text: cleanText,
                    character: deliveryCharacter,
                    context: context
                )
                let audioSessionReady = await audioSessionTask.value
                try Task.checkCancellation()
                guard audioSessionReady else {
                    throw NeuralVoiceError.playbackFailed
                }
                self.playAudio(audio, requestID: requestID)
            } catch is CancellationError {
                DiagnosticsLog.warning("voice", "Voice synthesis task cancelled.")
                return
            } catch {
                self.failSpeech(error, requestID: requestID)
            }
        }
    }

    func speakWithCurrentCompanion(_ text: String, context: CompanionSpeechContext = .love) {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        let companion = CompanionPersonality.find(id: id) ?? .luna
        speak(text, character: companion.voiceCharacter, context: context)
    }

    func stopSpeaking() {
        cancelStreamingSpeech(clearCurrentAudio: false)
        stopCurrentSpeech(callCompletion: false)
    }

    func toggleVoice() {
        voiceEnabled.toggle()
        UserDefaults.standard.set(voiceEnabled, forKey: "companion.voiceEnabled")
        if !voiceEnabled {
            stopSpeaking()
        }
    }

    func clearLastVoiceError() {
        lastVoiceError = nil
    }

    private func normalizedSpeechText(from text: String, character: VoiceCharacter) -> String {
        var normalized = text

        let replacements = [
            ("**", ""),
            ("__", ""),
            ("`", ""),
            ("#", ""),
            ("…", "..."),
            ("—", ", "),
            ("–", ", ")
        ]

        for (source, target) in replacements {
            normalized = normalized.replacingOccurrences(of: source, with: target)
        }

        normalized = normalized
            .replacingOccurrences(of: ":", with: ", ")
            .replacingOccurrences(of: ";", with: ", ")
            .replacingOccurrences(of: "\\((.*?)\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch character.characterName.lowercased() {
        case "luna", "dante":
            normalized = normalized.replacingOccurrences(of: ",", with: ", ")
            normalized = normalized.replacingOccurrences(of: "...", with: " ... ")
        case "aria", "marco", "kai":
            normalized = normalized.replacingOccurrences(of: "...", with: ". ")
        case "kel":
            normalized = normalized.replacingOccurrences(of: "!", with: ".")
        default:
            break
        }

        if normalized.count > 4_800 {
            normalized = String(normalized.prefix(4_800))
        }

        return normalized
    }

    private func playAudio(_ data: Data, requestID: UUID) {
        guard activeRequestID == requestID else { return }
        do {
            let generation = playbackGeneration
            let playback = try CompanionVoicePlaybackDriver(
                data: data,
                requestID: requestID,
                generation: generation,
                shouldStart: { [weak self] requestID, generation, playback in
                    guard let self else { return false }
                    return self.activeRequestID == requestID
                        && self.playbackGeneration == generation
                        && self.audioPlayback === playback
                },
                onStarted: { [weak self] requestID, generation, playback, audioByteCount in
                    guard let self,
                          self.activeRequestID == requestID,
                          self.playbackGeneration == generation,
                          self.audioPlayback === playback else {
                        return
                    }
                    DiagnosticsLog.info(
                        "voice",
                        "Voice playback started.",
                        details: ["audioBytes": "\(audioByteCount)"]
                    )
                },
                onFailed: { [weak self] requestID, generation, playback, error in
                    guard let self,
                          self.activeRequestID == requestID,
                          self.playbackGeneration == generation,
                          self.audioPlayback === playback else {
                        return
                    }
                    self.failSpeech(error, requestID: requestID)
                },
                onFinished: { [weak self] requestID, generation, playback in
                    guard let self,
                          self.activeRequestID == requestID,
                          self.playbackGeneration == generation,
                          self.audioPlayback === playback else {
                        return
                    }
                    self.activeSpeakTask = nil
                    self.resetSpeechState(callCompletion: true)
                }
            )
            audioPlayback = playback
            playback.start()
        } catch {
            DiagnosticsLog.error("voice", "Voice playback failed to initialize.", error: error)
            failSpeech(error, requestID: requestID)
        }
    }

    private func playNextStreamingSpeechSegment() {
        guard let streamID = streamingSpeechID,
              !streamingSpeechIsPlaying,
              !streamingSpeechQueue.isEmpty else {
            clearFinishedStreamingSpeechIfIdle()
            return
        }

        let segment = streamingSpeechQueue.removeFirst()
        streamingSpeechIsPlaying = true
        startSpeech(segment.text,
                    character: segment.character,
                    context: segment.context,
                    cancelStreamingQueue: false) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.streamingSpeechID == streamID else { return }
                let speechFailed = self.lastVoiceError != nil
                self.streamingSpeechIsPlaying = false
                if speechFailed {
                    self.cancelStreamingSpeech(clearCurrentAudio: false)
                    return
                }
                self.playNextStreamingSpeechSegment()
            }
        }
    }

    private func clearFinishedStreamingSpeechIfIdle() {
        guard streamingSpeechID != nil,
              !streamingSpeechIsOpen,
              !streamingSpeechIsPlaying,
              streamingSpeechQueue.isEmpty else { return }
        streamingSpeechID = nil
        streamingSpeechIsOpen = false
        streamingSpeechIsPlaying = false
        resumeHerModeForStreamingIfNeeded()
    }

    private func cancelStreamingSpeech(clearCurrentAudio: Bool) {
        let hadStreamingSpeech = streamingSpeechID != nil
        streamingSpeechID = nil
        streamingSpeechQueue.removeAll()
        streamingSpeechIsOpen = false
        streamingSpeechIsPlaying = false
        if clearCurrentAudio {
            stopCurrentSpeech(callCompletion: false)
        }
        if hadStreamingSpeech {
            resumeHerModeForStreamingIfNeeded()
        }
        DiagnosticsLog.info(
            "voice",
            "Streaming speech cancelled.",
            details: ["clearCurrentAudio": "\(clearCurrentAudio)"]
        )
    }

    private func failSpeech(_ error: Error, requestID: UUID?) {
        if let requestID, activeRequestID != requestID { return }
        lastVoiceError = NeuralVoiceService.userMessage(for: error)
        DiagnosticsLog.error(
            "voice",
            "Voice speech failed.",
            error: error,
            details: ["userMessage": lastVoiceError ?? ""]
        )
        activeSpeakTask = nil
        resetSpeechState(callCompletion: true)
    }

    private func stopCurrentSpeech(callCompletion: Bool) {
        activeSpeakTask?.cancel()
        activeSpeakTask = nil
        resetSpeechState(callCompletion: callCompletion)
    }

    private func resetSpeechState(callCompletion: Bool) {
        playbackGeneration &+= 1
        audioPlayback?.stop()
        audioPlayback = nil
        let audioSessionToken = activeAudioSessionToken
        activeRequestID = nil
        activeAudioSessionToken = nil
        isSpeaking = false
        activeCharacterName = nil
        if let audioSessionToken {
            deactivateVoiceAudioSession(token: audioSessionToken)
        }
        resumeHerModeForActiveSpeechIfNeeded()

        let completion = activeSpeakCompletion
        activeSpeakCompletion = nil
        if callCompletion {
            completion?()
        }
    }

    private func pauseHerModeForStreamingIfNeeded() {
        guard !streamingPausedHerMode else { return }
        streamingPausedHerMode = HerModeEngine.shared.pauseRecognitionForCompanionSpeech()
        if streamingPausedHerMode {
            DiagnosticsLog.info("voice", "Her Mode listener paused for streaming voice playback.")
        }
    }

    private func resumeHerModeForStreamingIfNeeded() {
        guard streamingPausedHerMode else { return }
        streamingPausedHerMode = false
        DiagnosticsLog.info("voice", "Her Mode listener resuming after streaming voice playback.")
        HerModeEngine.shared.resumeRecognitionAfterCompanionSpeech()
    }

    private func pauseHerModeForActiveSpeechIfNeeded() -> Bool {
        guard !streamingPausedHerMode else { return false }
        let didPause = HerModeEngine.shared.pauseRecognitionForCompanionSpeech()
        if didPause {
            DiagnosticsLog.info("voice", "Her Mode listener paused for voice playback.")
        }
        return didPause
    }

    private func resumeHerModeForActiveSpeechIfNeeded() {
        guard activeSpeechPausedHerMode else { return }
        activeSpeechPausedHerMode = false
        DiagnosticsLog.info("voice", "Her Mode listener resuming after voice playback.")
        HerModeEngine.shared.resumeRecognitionAfterCompanionSpeech()
    }

    private static func responsiveSpeechChunks(from text: String) -> [String] {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var chunks: [String] = []

        while !remaining.isEmpty {
            if remaining.count <= 360 {
                chunks.append(remaining)
                break
            }

            let minCount = min(120, remaining.count)
            let maxCount = min(360, remaining.count)
            let minIndex = remaining.index(remaining.startIndex, offsetBy: minCount)
            let maxIndex = remaining.index(remaining.startIndex, offsetBy: maxCount)
            let searchRange = minIndex..<maxIndex

            let sentenceBoundary = remaining[searchRange].firstIndex(where: { ".?!\n".contains($0) })
            let softBoundary = remaining[..<maxIndex].lastIndex(where: { ",;:".contains($0) })
            let wordBoundary = remaining[..<maxIndex].lastIndex(where: { $0.isWhitespace })
            let boundary = sentenceBoundary.map { remaining.index(after: $0) }
                ?? softBoundary.map { remaining.index(after: $0) }
                ?? wordBoundary
                ?? maxIndex

            let chunk = remaining[..<boundary]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(String(chunk))
            }

            remaining = remaining[boundary...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return chunks
    }
}

// MARK: - NeuralVoiceService

enum NeuralVoiceError: LocalizedError {
    case missingAPIKey
    case missingVoiceID(String)
    case invalidURL
    case invalidVoiceID(String)
    case voiceNotFound(String)
    case missingPermissions(String)
    case invalidResponse
    case invalidAudio
    case playbackFailed
    case creditsExhausted
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Neural voice needs an ElevenLabs API key. Add it in Settings → Neural Voice."
        case .missingVoiceID(let name):
            return "\(name) needs its own ElevenLabs voice ID in Settings → Neural Voice."
        case .invalidURL:
            return "The voice service URL is invalid."
        case .invalidVoiceID(let name):
            return "\(name)'s ElevenLabs voice ID is invalid. Paste only the voice_id value from ElevenLabs."
        case .voiceNotFound(let name):
            return "\(name)'s ElevenLabs voice ID was not found for this API key. Add that voice to the same ElevenLabs account, then paste the voice_id again."
        case .missingPermissions(let permission):
            return "The ElevenLabs API key is missing the \(permission) permission. Create a new key with Text to Speech access, then save it in Settings -> Neural Voice."
        case .invalidResponse:
            return "The voice service returned an unreadable response."
        case .invalidAudio:
            return "The voice service did not return playable audio."
        case .playbackFailed:
            return "The generated voice audio could not start playback."
        case .creditsExhausted:
            return "The voice API may need to be recharged. Try again after voice credits are available."
        case .httpStatus(let status, let body):
            let detail = body.isEmpty ? "No error details returned." : body
            return "Voice API error \(status): \(detail)"
        }
    }
}

enum NeuralVoiceService {
    static let service = "com.bareclaw.bareclaw"
    static let apiKeyKey = "elevenlabs_api_key"
    static let modelDefaultsKey = "elevenlabs.modelID"
    static let defaultModelID = "eleven_v3"
    static let outputFormat = "mp3_44100_128"

    static func readAPIKey() -> String? {
        guard let raw = KeychainHelper.read(service: service, key: apiKeyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return cleanedAPIKey(raw)
    }

    static func saveAPIKey(_ value: String) {
        let trimmed = cleanedAPIKey(value)
        guard !trimmed.isEmpty else { return }
        KeychainHelper.write(service: service, key: apiKeyKey, value: trimmed)
    }

    static var configuredModelID: String {
        let saved = UserDefaults.standard.string(forKey: modelDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return saved?.isEmpty == false ? saved! : defaultModelID
    }

    static func saveModelID(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed.isEmpty ? defaultModelID : trimmed, forKey: modelDefaultsKey)
        UserDefaults.standard.synchronize()
    }

    static func voiceIDDefaultsKey(for companionKey: String) -> String {
        "elevenlabs.voiceID.\(normalizedCompanionKey(companionKey))"
    }

    static func configuredVoiceID(for companionKey: String) -> String? {
        let key = voiceIDDefaultsKey(for: companionKey)
        guard let value = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        let cleaned = cleanedVoiceID(value)
        return isValidVoiceID(cleaned) ? cleaned : value
    }

    static func saveVoiceID(_ value: String, for companionKey: String) {
        let key = voiceIDDefaultsKey(for: companionKey)
        let trimmed = cleanedVoiceID(value)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
        UserDefaults.standard.synchronize()
    }

    static func isConfigured(for companionKey: String) -> Bool {
        readAPIKey() != nil && configuredVoiceID(for: companionKey) != nil
    }

    static func configurationSummary() -> String {
        let voiceIDs = CompanionPersonality.all.compactMap { configuredVoiceID(for: $0.id) }
        let validVoiceIDs = voiceIDs.filter(isValidVoiceID)
        let uniqueVoiceIDs = Set(validVoiceIDs.map { $0.lowercased() })
        let count = validVoiceIDs.count
        guard readAPIKey() != nil else {
            return "Not configured — add ElevenLabs key and voice IDs"
        }
        if uniqueVoiceIDs.count < validVoiceIDs.count {
            return "Duplicate voice IDs — each companion needs a separate voice"
        }
        if count == CompanionPersonality.all.count {
            return "ElevenLabs active — \(count) separate voices configured"
        }
        return "ElevenLabs key saved — \(count)/\(CompanionPersonality.all.count) voices configured"
    }

    static func synthesize(
        text: String,
        character: VoiceCharacter,
        context: CompanionSpeechContext
    ) async throws -> Data {
        guard let apiKey = readAPIKey() else {
            DiagnosticsLog.error(
                "elevenlabs",
                "ElevenLabs synthesis blocked because the API key is missing.",
                details: ["character": character.characterName]
            )
            throw NeuralVoiceError.missingAPIKey
        }
        guard let voiceID = configuredVoiceID(for: character.characterName) else {
            DiagnosticsLog.error(
                "elevenlabs",
                "ElevenLabs synthesis blocked because voice ID is missing.",
                details: ["character": character.characterName]
            )
            throw NeuralVoiceError.missingVoiceID(character.characterName)
        }
        guard isValidVoiceID(voiceID) else {
            DiagnosticsLog.error(
                "elevenlabs",
                "ElevenLabs synthesis blocked because voice ID is invalid.",
                details: ["character": character.characterName]
            )
            throw NeuralVoiceError.invalidVoiceID(character.characterName)
        }
        guard let encodedVoiceID = voiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(encodedVoiceID)") else {
            throw NeuralVoiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "output_format", value: outputFormat)
        ]
        guard let url = components.url else {
            throw NeuralVoiceError.invalidURL
        }

        DiagnosticsLog.info(
            "elevenlabs",
            "ElevenLabs synthesis started.",
            details: [
                "character": character.characterName,
                "context": "\(context)",
                "model": configuredModelID,
                "textLength": "\(text.count)"
            ]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            ElevenLabsSpeechRequest(
                text: text,
                model_id: configuredModelID,
                language_code: "en",
                voice_settings: voiceSettings(for: character, context: context)
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            DiagnosticsLog.error("elevenlabs", "ElevenLabs response was not HTTP.")
            throw NeuralVoiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if let missingPermission = missingPermissionName(status: http.statusCode, body: body) {
                DiagnosticsLog.error(
                    "elevenlabs",
                    "ElevenLabs key is missing required permission.",
                    details: ["status": "\(http.statusCode)", "permission": missingPermission]
                )
                throw NeuralVoiceError.missingPermissions(missingPermission)
            }
            if isVoiceNotFoundError(status: http.statusCode, body: body) {
                DiagnosticsLog.error(
                    "elevenlabs",
                    "ElevenLabs voice ID was not found.",
                    details: ["status": "\(http.statusCode)", "character": character.characterName]
                )
                throw NeuralVoiceError.voiceNotFound(character.characterName)
            }
            if isCreditError(status: http.statusCode, body: body) {
                DiagnosticsLog.error(
                    "elevenlabs",
                    "ElevenLabs response indicates exhausted credits.",
                    details: ["status": "\(http.statusCode)"]
                )
                throw NeuralVoiceError.creditsExhausted
            }
            DiagnosticsLog.error(
                "elevenlabs",
                "ElevenLabs synthesis failed.",
                details: ["status": "\(http.statusCode)", "body": clipped(body)]
            )
            throw NeuralVoiceError.httpStatus(http.statusCode, clipped(body))
        }
        guard data.count > 128 else {
            DiagnosticsLog.error(
                "elevenlabs",
                "ElevenLabs returned too little audio data.",
                details: ["status": "\(http.statusCode)", "bytes": "\(data.count)"]
            )
            throw NeuralVoiceError.invalidAudio
        }
        DiagnosticsLog.info(
            "elevenlabs",
            "ElevenLabs synthesis succeeded.",
            details: ["status": "\(http.statusCode)", "bytes": "\(data.count)"]
        )
        return data
    }

    static func userMessage(for error: Error) -> String {
        if let voiceError = error as? NeuralVoiceError {
            return voiceError.localizedDescription
        }
        return "Neural voice failed: \(error.localizedDescription)"
    }

    private static func normalizedCompanionKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func cleanedAPIKey(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.first == "/" {
            trimmed.removeFirst()
        }
        return trimmed
    }

    static func cleanedVoiceID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let components = URLComponents(string: trimmed) {
            if let queryVoiceID = components.queryItems?.first(where: {
                ["voice_id", "voiceId", "id"].contains($0.name)
            })?.value {
                return queryVoiceID.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let meaningfulPathComponents = components.path
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty && $0.lowercased() != "voices" && $0.lowercased() != "voice-library" }

            if let last = meaningfulPathComponents.last,
               isValidVoiceID(last) {
                return last
            }
        }

        return trimmed
    }

    static func isValidVoiceID(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return value.count >= 15
            && value.count <= 80
            && value.rangeOfCharacter(from: allowed.inverted) == nil
    }

    private static func clipped(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 240 else { return trimmed }
        return String(trimmed.prefix(240)) + "..."
    }

    private static func isCreditError(status: Int, body: String) -> Bool {
        let lower = body.lowercased()
        return status == 402
            || lower.contains("credit")
            || lower.contains("quota")
            || lower.contains("billing")
            || lower.contains("insufficient")
            || lower.contains("subscription")
    }

    private static func isVoiceNotFoundError(status: Int, body: String) -> Bool {
        let lower = body.lowercased()
        return status == 404
            || lower.contains("voice_not_found")
            || lower.contains("voice not found")
            || lower.contains("voice_id")
            || lower.contains("voice id")
    }

    private static func missingPermissionName(status: Int, body: String) -> String? {
        guard status == 401 || status == 403 else { return nil }
        let lower = body.lowercased()
        guard lower.contains("missing_permissions") || lower.contains("missing permission") else { return nil }

        if lower.contains("text_to_speech") {
            return "text_to_speech"
        }
        if lower.contains("voices_read") {
            return "voices_read"
        }
        return "required"
    }

    private static func voiceSettings(
        for character: VoiceCharacter,
        context: CompanionSpeechContext
    ) -> ElevenLabsVoiceSettings {
        let name = character.characterName.lowercased()
        var stability: Double
        var style: Double

        switch name {
        case "luna":
            stability = 0.36
            style = 0.58
        case "aria":
            stability = 0.32
            style = 0.52
        case "kel":
            stability = 0.54
            style = 0.28
        case "marco":
            stability = 0.40
            style = 0.42
        case "dante":
            stability = 0.34
            style = 0.62
        case "kai":
            stability = 0.48
            style = 0.34
        default:
            stability = 0.42
            style = 0.42
        }

        switch context {
        case .conversation:
            break
        case .love:
            stability += 0.04
            style += 0.04
        case .stress:
            stability += 0.10
            style -= 0.08
        case .ceremony:
            stability += 0.02
            style += 0.02
        }

        return ElevenLabsVoiceSettings(
            stability: min(max(stability, 0.0), 1.0),
            similarity_boost: 0.86,
            style: min(max(style, 0.0), 1.0),
            use_speaker_boost: true
        )
    }
}

private struct ElevenLabsSpeechRequest: Encodable {
    let text: String
    let model_id: String
    let language_code: String
    let voice_settings: ElevenLabsVoiceSettings
}

private struct ElevenLabsVoiceSettings: Encodable {
    let stability: Double
    let similarity_boost: Double
    let style: Double
    let use_speaker_boost: Bool
}

struct CompanionVoiceSpeakButton: View {
    let message: String
    @ObservedObject private var engine = CompanionVoiceEngine.shared

    var body: some View {
        Button {
            if engine.isSpeaking {
                engine.stopSpeaking()
            } else {
                engine.speakWithCurrentCompanion(message)
            }
        } label: {
            Image(systemName: engine.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.1")
                .font(.system(size: 12))
                .foregroundColor(engine.isSpeaking ? .BC.accent : .BC.textMuted)
                .symbolEffect(.variableColor, isActive: engine.isSpeaking)
                .padding(6)
                .background(Color.BC.surface)
                .cornerRadius(8)
        }
    }
}
