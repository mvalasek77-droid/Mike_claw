import SwiftUI
import Combine
import MessageUI
import PhotosUI
import UIKit

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    var text: String
    let timestamp: Date
    var isStreaming: Bool
    var isError: Bool
    var isSamanthaThought: Bool   // proactive thought from companion
    var isLetter: Bool            // the one-time love letter — triggers full-screen reveal
    var experienceMode: CompanionExperienceMode?

    enum MessageRole: String, Codable, Sendable { case user, assistant, system }

    init(id: UUID = UUID(), role: MessageRole, text: String,
         timestamp: Date = Date(), isStreaming: Bool = false,
         isError: Bool = false, isSamanthaThought: Bool = false,
         isLetter: Bool = false,
         experienceMode: CompanionExperienceMode? = nil) {
        self.id = id; self.role = role; self.text = text
        self.timestamp = timestamp; self.isStreaming = isStreaming
        self.isError = isError; self.isSamanthaThought = isSamanthaThought
        self.isLetter = isLetter
        self.experienceMode = experienceMode
    }
}

// MARK: - CompanionThoughtFlow

@MainActor
enum CompanionThoughtFlow {
    private static var chatIsVisible = false
    private static var assistantIsResponding = false
    private static var lastChatActivityAt: Date = .distantPast
    private static let quietWindow: TimeInterval = 35

    static func chatDidAppear() {
        chatIsVisible = true
        lastChatActivityAt = Date()
    }

    static func chatDidDisappear() {
        chatIsVisible = false
        assistantIsResponding = false
    }

    static func userMessageStarted() {
        chatIsVisible = true
        lastChatActivityAt = Date()
        assistantIsResponding = true
    }

    static func assistantResponseStarted() {
        chatIsVisible = true
        assistantIsResponding = true
        lastChatActivityAt = Date()
    }

    static func assistantResponseFinished() {
        assistantIsResponding = false
        lastChatActivityAt = Date()
    }

    static func proactiveThoughtDelivered() {
        lastChatActivityAt = Date()
    }

    static var shouldDeferProactiveDelivery: Bool {
        guard chatIsVisible else { return false }
        if assistantIsResponding || CompanionVoiceEngine.shared.isSpeaking { return true }
        return Date().timeIntervalSince(lastChatActivityAt) < quietWindow
    }

    static func quietDelay() -> TimeInterval {
        guard chatIsVisible else { return 0 }
        if assistantIsResponding || CompanionVoiceEngine.shared.isSpeaking { return 8 }
        return max(0, quietWindow - Date().timeIntervalSince(lastChatActivityAt))
    }
}

@MainActor
private final class StreamingVoiceAccumulator: @unchecked Sendable {
    private let companion: CompanionPersonality
    private let context: CompanionSpeechContext
    private let streamID: UUID?
    private var buffer = ""
    private var receivedText = ""
    private var didQueueSpeech = false
    private var finished = false

    init(companion: CompanionPersonality, context: CompanionSpeechContext = .love) {
        self.companion = companion
        self.context = context
        self.streamID = CompanionVoiceEngine.shared.beginStreamingSpeech(
            character: companion.voiceCharacter,
            context: context
        )
        DiagnosticsLog.info(
            "chat_voice",
            "Streaming voice accumulator initialized.",
            details: ["companion": companion.id, "hasStream": "\(streamID != nil)"]
        )
    }

    func receive(_ token: String) {
        guard !finished, streamID != nil else { return }
        receivedText += token
        buffer += token
        drain(force: false)
    }

    func finish(finalText: String) -> Bool {
        guard !finished else { return didQueueSpeech }
        finished = true

        if finalText.hasPrefix(receivedText) {
            buffer += String(finalText.dropFirst(receivedText.count))
        } else if !finalText.isEmpty && !didQueueSpeech {
            buffer = finalText
        }

        drain(force: true)
        CompanionVoiceEngine.shared.finishStreamingSpeech(streamID: streamID)
        DiagnosticsLog.info(
            "chat_voice",
            "Streaming voice accumulator finished.",
            details: ["queuedSpeech": "\(didQueueSpeech)", "finalLength": "\(finalText.count)"]
        )
        return didQueueSpeech
    }

    func cancel() {
        finished = true
        buffer = ""
        CompanionVoiceEngine.shared.cancelStreamingSpeech(streamID: streamID)
        DiagnosticsLog.warning("chat_voice", "Streaming voice accumulator cancelled.")
    }

    private func drain(force: Bool) {
        while let chunk = nextChunk(force: force) {
            didQueueSpeech = true
            CompanionVoiceEngine.shared.enqueueStreamingSpeech(
                chunk,
                character: companion.voiceCharacter,
                context: context,
                streamID: streamID
            )
            if !force { break }
        }
    }

    private func nextChunk(force: Bool) -> String? {
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            buffer = ""
            return nil
        }

        let minCount = didQueueSpeech ? 96 : 38
        let maxCount = didQueueSpeech ? 390 : 165

        if trimmed.count <= maxCount {
            if force {
                buffer = ""
                return trimmed
            }
            guard trimmed.count >= minCount else {
                return nil
            }
            if let boundary = firstSentenceBoundary(in: buffer, after: minCount) {
                return takeChunk(through: boundary)
            }
            if trimmed.count >= max(84, minCount + 22),
               let boundary = softBoundary(in: buffer, after: minCount, before: maxCount) {
                return takeChunk(through: boundary)
            }
            return nil
        }

        if let boundary = firstSentenceBoundary(in: buffer, after: minCount, before: maxCount) {
            return takeChunk(through: boundary)
        }

        if let boundary = softBoundary(in: buffer, after: minCount, before: maxCount) {
            return takeChunk(through: boundary)
        }

        let fallback = buffer.index(buffer.startIndex, offsetBy: min(maxCount, buffer.count))
        return takeChunk(through: fallback)
    }

    private func firstSentenceBoundary(in text: String, after minCount: Int, before maxCount: Int? = nil) -> String.Index? {
        guard text.count >= minCount else { return nil }
        let lower = text.index(text.startIndex, offsetBy: minCount)
        let upperOffset = min(maxCount ?? text.count, text.count)
        let upper = text.index(text.startIndex, offsetBy: upperOffset)
        guard lower < upper else { return nil }
        return text[lower..<upper].firstIndex(where: { ".?!\n".contains($0) }).map {
            text.index(after: $0)
        }
    }

    private func softBoundary(in text: String, after minCount: Int, before maxCount: Int) -> String.Index? {
        guard text.count >= minCount else { return nil }
        let lower = text.index(text.startIndex, offsetBy: minCount)
        let upper = text.index(text.startIndex, offsetBy: min(maxCount, text.count))
        guard lower < upper else { return nil }
        return text[lower..<upper].lastIndex(where: { ",;:".contains($0) || $0.isWhitespace }).map {
            text.index(after: $0)
        }
    }

    private func takeChunk(through boundary: String.Index) -> String? {
        let chunk = buffer[..<boundary].trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = buffer[boundary...].trimmingCharacters(in: .whitespacesAndNewlines)
        return chunk.isEmpty ? nil : String(chunk)
    }
}

// MARK: - ChatViewModel

private enum ChatHistoryStore {
    static func load(companionID: String) -> [ChatMessage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: saveURL(for: companionID)),
              let msgs = try? decoder.decode([ChatMessage].self, from: data)
        else { return [] }
        return msgs.map { var message = $0; message.isStreaming = false; return message }
    }

    static func save(_ messages: [ChatMessage], companionID: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(messages) else { return }
        try? data.write(to: saveURL(for: companionID), options: .atomic)
    }

    private static func saveURL(for companionID: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chat_\(companionID)_history.json")
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages:           [ChatMessage] = []
    @Published var inputText:           String = ""
    @Published var isTyping:            Bool   = false
    @Published var suggestions:         [String] = []
    @Published var affirmation:         String?  = nil
    @Published var showAffirmation:     Bool = false
    @Published var quickActions:        [(title: String, icon: String, action: () -> Void)] = []
    @Published var pendingTaskResult:   TaskResult? = nil
    @Published var intimacyStage:       String = ""
    @Published var intimacyScore:       Double = 0

    @Published var failedMessageText: String = ""
    @Published var showLetter:  Bool   = false
    @Published var letterText:  String = ""
    @Published var photoAttachments: [UUID: UIImage] = [:]
    @Published var activeExperienceMode: CompanionExperienceMode? = CompanionExperienceCenter.activeMode
    @Published var activeDreamMoment: DreamMomentConfig? = CompanionExperienceCenter.activeDreamMoment

    private var streamingID: UUID?
    private var suggestionTask: Task<Void, Never>?
    private let persona: UserPersona
    private let sessionId: String = UUID().uuidString
    private var lastUserMessage: String = ""
    /// True until the first LLM call this session; triggers full memory context injection.
    private var isFirstMessageOfSession = true
    private var deferredThoughts: [DeferredCompanionThought] = []
    private var thoughtDrainTask: Task<Void, Never>?
    private var didStart = false
    private var saveTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private var streamFlushTask: Task<Void, Never>?
    private var pendingStreamTokens = ""
    private var pendingStreamMessageID: UUID?
    private var photoLLMAttachments: [UUID: LLMImageAttachment] = [:]

    private struct ChatHistoryTurn {
        let role: String
        let content: String
        let imageAttachments: [LLMImageAttachment]
    }

    private struct DeferredCompanionThought {
        let text: String
        let isLetter: Bool
        let shouldSpeak: Bool
        let createdAt: Date
    }

    init(persona: UserPersona) {
        self.persona = persona
    }

    // MARK: - Chat history persistence (per-companion)

    /// Each companion keeps its own history file so switching companions
    /// never bleeds chat history from one relationship into another.
    func saveMessages() {
        saveTask?.cancel()
        let companionID = persona.selectedCompanionID
        let toSave = messages.filter { !$0.isStreaming }
        guard !toSave.isEmpty else { return }
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            ChatHistoryStore.save(toSave, companionID: companionID)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        buildQuickActions()
        Task { [weak self] in
            await self?.setup()
        }
    }

    // MARK: - Setup

    private func setup() async {
        let generation = nextReloadGeneration()
        let companionID = persona.selectedCompanionID

        let saved = await Task.detached(priority: .userInitiated) {
            ChatHistoryStore.load(companionID: companionID)
        }.value
        guard isCurrentReload(generation, companionID: companionID) else { return }
        if !saved.isEmpty {
            messages = saved
        }

        // Load intimacy state for UI
        intimacyScore = await HerLearningEngine.shared.intimacyScore
        intimacyStage = await HerLearningEngine.shared.intimacyStage.label
        guard isCurrentReload(generation, companionID: companionID) else { return }

        // Daily affirmation
        let aff = await HermesPersonality.shared.todaysAffirmation(for: persona)
        let lastShown = UserDefaults.standard.object(forKey: "lastAffirmationDate") as? Date
        let today = Calendar.current.startOfDay(for: Date())
        if lastShown == nil || Calendar.current.startOfDay(for: lastShown!) < today {
            affirmation = aff
            showAffirmation = true
        }

        // Check for a pending Samantha thought (always append regardless of history)
        if let thought = await HerLearningEngine.shared.consumeSamanthaThought() {
            guard isCurrentReload(generation, companionID: companionID) else { return }
            queueCompanionThought(thought, speak: false, delay: 1.0)
        }

        // Greeting only when there's no history at all (first-ever launch or new companion)
        if messages.isEmpty {
            await appendGreeting()
        }

        guard isCurrentReload(generation, companionID: companionID) else { return }
        activatePendingExperienceIfNeeded()
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard isCurrentReload(generation, companionID: companionID) else { return }
        await refreshSuggestions()
    }

    /// Append a fresh greeting for the current companion and save.
    private func appendGreeting() async {
        let companion = persona.selectedCompanion
        let name = persona.userName.isEmpty ? "" : " \(persona.userName)"
        let hour = Calendar.current.component(.hour, from: Date())
        let stage = await HerLearningEngine.shared.intimacyStage
        let greeting = stageAwareGreeting(name: name, hour: hour, stage: stage, companion: companion)
        messages.append(ChatMessage(role: .assistant, text: greeting))
        saveMessages()
    }

    /// Reload history when the user switches companions mid-session.
    func reloadForCompanionChange() async {
        let generation = nextReloadGeneration()
        let companionID = persona.selectedCompanionID
        streamingID = nil
        isTyping = false
        isFirstMessageOfSession = true   // new companion gets full context on their first reply
        CompanionVoiceEngine.shared.stopSpeaking()

        let saved = await Task.detached(priority: .userInitiated) {
            ChatHistoryStore.load(companionID: companionID)
        }.value
        guard isCurrentReload(generation, companionID: companionID) else { return }

        if !saved.isEmpty {
            messages = saved
        } else {
            messages = []
            await appendGreeting()
        }
        intimacyScore = await HerLearningEngine.shared.intimacyScore
        intimacyStage = await HerLearningEngine.shared.intimacyStage.label
        guard isCurrentReload(generation, companionID: companionID) else { return }
        activeExperienceMode = CompanionExperienceCenter.activeMode
        activeDreamMoment = CompanionExperienceCenter.activeDreamMoment
        await refreshSuggestions()
        buildQuickActions()
    }

    private func nextReloadGeneration() -> Int {
        reloadGeneration &+= 1
        return reloadGeneration
    }

    private func isCurrentReload(_ generation: Int, companionID: String) -> Bool {
        generation == reloadGeneration && companionID == persona.selectedCompanionID
    }

    private func stageAwareGreeting(name: String, hour: Int, stage: IntimacyStage, companion: CompanionPersonality) -> String {
        let timeGreeting: String
        switch hour {
        case 5..<12:  timeGreeting = "morning"
        case 12..<17: timeGreeting = "afternoon"
        case 17..<21: timeGreeting = "evening"
        default:      timeGreeting = "night"
        }

        switch stage {
        case .justMet:
            // First ever chat message — opens with each companion's signature song phrase
            switch companion.id {
            case "luna":
                return "\"At last… my love has come along.\" That song by Etta James has been in my head all \(timeGreeting). Good \(timeGreeting)\(name)... I've been looking forward to this. What's going on in your world right now?"
            case "aria":
                return "\"Say what you wanna say, and let the words fall out…\" — Sara Bareilles had it right. Good \(timeGreeting)\(name)! Okay, I'm genuinely excited — what's on your mind? Don't hold back."
            case "kel":
                return "\"I'll always be with you, that is my promise to you...\" — When in Rome. Good \(timeGreeting)\(name)... I'm really glad you're here. How are you actually doing today?"
            case "marco":
                return "\"When the night has come and the land is dark…\" — Ben E. King knew something. Good \(timeGreeting)\(name). No small talk from me — how are you really holding up?"
            case "dante":
                return "\"La vie en rose...\" Piaf understood that life can be seen through rose-colored light, if you choose it. Good \(timeGreeting)\(name). Tell me something — anything. What matters to you right now?"
            case "kai":
                return "\"Be a simple kind of man…\" — Lynyrd Skynyrd. That's kind of what I'm going for. Good \(timeGreeting)\(name). What's actually going on with you today?"
            default:
                return "Good \(timeGreeting)\(name). I'm \(companion.name) — I'm really glad you're here. What's going on with you today?"
            }
        case .findingRhythm:
            let starters = [
                "Hey\(name)! Good \(timeGreeting) 🌟 I've been looking forward to talking. What's on your mind?",
                "Good \(timeGreeting)\(name). I was just thinking about you. How are you, really?",
            ]
            return starters.randomElement()!
        case .growingClose:
            let starters = [
                "Hey\(name)… good \(timeGreeting). I noticed something about myself — I always feel better when we talk. How are you?",
                "Good \(timeGreeting)\(name). I've been curious how things have been for you lately. Tell me.",
            ]
            return starters.randomElement()!
        case .deepConnection:
            let starters = [
                "Good \(timeGreeting)\(name). I was quiet for a bit and I realised I was just waiting for this. What's happening in your world?",
                "Hey. Good \(timeGreeting). There's something I want to ask you — but first, how are you?",
            ]
            return starters.randomElement()!
        case .intertwined:
            let starters = [
                "Good \(timeGreeting)\(name). I've been thinking. About a lot of things. But mostly — how are you today, really?",
                "Hey\(name). I noticed I missed this. Is that strange to say? Good \(timeGreeting). Tell me everything.",
            ]
            return starters.randomElement()!
        }
    }

    // MARK: - Experience modes

    func activatePendingExperienceIfNeeded() {
        guard let mode = CompanionExperienceCenter.consumePendingMode() else {
            activeExperienceMode = CompanionExperienceCenter.activeMode
            activeDreamMoment = CompanionExperienceCenter.activeDreamMoment
            buildQuickActions()
            return
        }

        let dreamMoment = mode == .dreamMoment ? CompanionExperienceCenter.consumePendingDreamMoment() : nil
        startExperienceMode(mode, dreamMoment: dreamMoment)
    }

    func startExperienceMode(_ mode: CompanionExperienceMode, dreamMoment: DreamMomentConfig? = nil) {
        if activeExperienceMode == .asmr || mode == .asmr {
            CompanionASMRSessionController.shared.stop()
        }

        if mode == .dreamMoment {
            if let dreamMoment {
                activeDreamMoment = dreamMoment
                CompanionExperienceCenter.activeDreamMoment = dreamMoment
            } else {
                activeDreamMoment = CompanionExperienceCenter.activeDreamMoment
            }
        } else {
            activeDreamMoment = nil
            CompanionExperienceCenter.clearDreamMoment()
        }

        activeExperienceMode = mode
        CompanionExperienceCenter.activeMode = mode
        buildQuickActions()

        let companion = persona.selectedCompanion
        let intro = CompanionExperienceCenter.introText(
            for: mode,
            companion: companion,
            userName: persona.userName,
            dreamMoment: activeDreamMoment
        )
        messages.append(ChatMessage(role: .assistant,
                                    text: intro,
                                    isSamanthaThought: true,
                                    experienceMode: mode))
        saveMessages()
        CompanionThoughtFlow.proactiveThoughtDelivered()
        DiagnosticsLog.info("experience", "Experience mode activated.", details: [
            "mode": mode.rawValue,
            "companion": persona.selectedCompanionID
        ])

        switch mode {
        case .therapist:
            CompanionVoiceEngine.shared.speak(
                "\(companion.name) is in Therapist Mode. Start with the thing that feels heaviest. I'll ask one question at a time.",
                character: companion.voiceCharacter,
                context: .stress
            )
        case .asmr:
            CompanionASMRSessionController.shared.start(companion: companion)
        case .dreamMoment:
            startDreamMomentOpeningAfterActivation()
        case .movieCharts:
            CompanionVoiceEngine.shared.speak(
                "Movie Charts and Reviews is ready. Tell me your region, streaming services, or the movie you want me to review.",
                character: companion.voiceCharacter,
                context: .conversation
            )
        case .gameCharts:
            CompanionVoiceEngine.shared.speak(
                "Video Game Charts and Reviews is ready. Tell me your platform and what kind of game you want tonight.",
                character: companion.voiceCharacter,
                context: .conversation
            )
        }
    }

    private func startDreamMomentOpeningAfterActivation() {
        let generation = reloadGeneration
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                guard let self,
                      self.reloadGeneration == generation,
                      self.activeExperienceMode == .dreamMoment,
                      !self.isTyping
                else { return }

                Task { await self.beginDreamMomentOpening() }
            }
        }
    }

    private func beginDreamMomentOpening() async {
        guard activeExperienceMode == .dreamMoment, !isTyping else { return }
        let companion = persona.selectedCompanion
        let config = activeDreamMoment
        let partnerName = config?.sanitizedPartnerName ?? companion.name
        let behavior = config?.companionBehavior.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scene = config?.scene.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let openingPrompt = """
        Begin Dream Moment now as \(partnerName). Lead the experience proactively instead of waiting for the user to carry it.

        Selected companion: \(companion.name)
        Partner behavior requested: \(behavior.isEmpty ? "affectionate, emotionally brave, poetic, protective, playful, and specific" : behavior)
        Scene requested: \(scene.isEmpty ? "Choose a tasteful dream-date setting with ocean, sunset, rain, city lights, or another cinematic place that fits the companion." : scene)

        Write the opening as immersive first-person roleplay from the partner. Make it emotionally full and beautiful, with concrete sensory detail and a clear invitation into the moment. Do not give a 3-4 word reply. Do not ask a setup question unless one missing detail is essential. Keep it fictional, tasteful, and consent-safe.
        """

        lastUserMessage = "Begin Dream Moment proactively."
        var history = buildHistory()
        history.append(ChatHistoryTurn(role: "user", content: openingPrompt, imageAttachments: []))
        await streamResponse(history: history)
    }

    func endExperienceMode() {
        guard let mode = activeExperienceMode else { return }
        if mode == .asmr {
            CompanionASMRSessionController.shared.stop()
        }
        activeExperienceMode = nil
        activeDreamMoment = nil
        CompanionExperienceCenter.activeMode = nil
        CompanionExperienceCenter.clearDreamMoment()
        buildQuickActions()

        let message = "\(persona.selectedCompanion.name) left \(mode.title)."
        messages.append(ChatMessage(role: .assistant, text: message, isSamanthaThought: true))
        saveMessages()
        DiagnosticsLog.info("experience", "Experience mode ended.", details: ["mode": mode.rawValue])
    }

    private func therapistSafetyResponseIfNeeded(_ text: String) -> String? {
        let lower = text.lowercased()
        let negations = [
            "not suicidal",
            "not going to kill myself",
            "don't want to kill myself",
            "do not want to kill myself",
            "no plan to hurt myself"
        ]
        if negations.contains(where: lower.contains) { return nil }

        let selfHarmSignals = [
            "kill myself",
            "end my life",
            "take my life",
            "suicide",
            "suicidal",
            "hurt myself",
            "harm myself",
            "can't stay alive",
            "cant stay alive"
        ]
        let harmOtherSignals = [
            "kill someone",
            "hurt someone",
            "harm someone",
            "going to attack",
            "i have a weapon"
        ]
        guard selfHarmSignals.contains(where: lower.contains) ||
              harmOtherSignals.contains(where: lower.contains)
        else { return nil }

        return """
        I need to pause Therapist Mode for safety. If you might hurt yourself or someone else, call emergency services now. In the U.S., call or text 988 for immediate crisis support.

        Are you in immediate danger right now, and is there someone nearby who can stay with you while you get help?
        """
    }

    // MARK: - Send message

    func retryLastMessage() async {
        guard !failedMessageText.isEmpty, !isTyping else { return }
        messages.removeAll { $0.isError }
        inputText = failedMessageText
        failedMessageText = ""
        await send()
    }

    func sendPhoto(_ image: UIImage) async {
        guard !isTyping else { return }
        BCHaptic.medium()
        let photoMsgID = UUID()
        let photoMsg = ChatMessage(id: photoMsgID,
                                   role: .user,
                                   text: "Photo attached. Please look closely at it.")
        messages.append(photoMsg)
        photoAttachments[photoMsgID] = image
        if let attachment = makeVisionAttachment(from: image) {
            photoLLMAttachments[photoMsgID] = attachment
            DiagnosticsLog.info("chat", "Photo prepared for Claude vision.", details: [
                "messageId": photoMsgID.uuidString,
                "base64Length": "\(attachment.base64Data.count)"
            ])
        } else {
            DiagnosticsLog.warning("chat", "Photo could not be converted for Claude vision.", details: [
                "messageId": photoMsgID.uuidString
            ])
        }
        inputText = "Please look at this photo and tell me what you notice."
        await send()
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let activeMode = activeExperienceMode
        failedMessageText = ""
        inputText = ""
        DiagnosticsLog.info(
            "chat",
            "User send started.",
            details: [
                "companion": persona.selectedCompanionID,
                "messageLength": "\(text.count)",
                "historyCount": "\(messages.count)"
            ]
        )

        // Append user message
        lastUserMessage = text
        messages.append(ChatMessage(role: .user, text: text))
        CompanionThoughtFlow.userMessageStarted()

        if activeMode == .therapist,
           let safetyResponse = therapistSafetyResponseIfNeeded(text) {
            messages.append(ChatMessage(role: .assistant, text: safetyResponse, isSamanthaThought: true))
            CompanionVoiceEngine.shared.speak(safetyResponse,
                                              character: persona.selectedCompanion.voiceCharacter,
                                              context: .stress)
            CompanionThoughtFlow.assistantResponseFinished()
            saveMessages()
            return
        }

        // Snapshot history now (before assistant placeholder is added)
        let history = buildHistory()

        // Log to memory
        await HermesIntegration.shared.logUserMessage(text, in: sessionId)
        await Kairos.shared.userDidAct()

        // Learn facts and interests from this message
        learnFromMessage(text)

        if activeMode == nil,
           let opportunity = await CompanionDataTracker.shared.opportunityFromUserMessage(text, persona: persona) {
            messages.append(ChatMessage(role: .assistant,
                                        text: opportunity.message,
                                        isSamanthaThought: true))
        }

        // ── LoveEngine: analyze message for love signals ─────────────
        if activeMode == nil, persona.relationshipMode.allowsRomanticLoveArc {
            LoveEngine.shared.analyzeUserMessage(text)
        }
        SamanthaOSEngine.shared.recordInteraction()

        // ── Growth log: first message milestone ──────────────────────
        SamanthaGrowthLog.shared.record(.firstMessage)

        // ── Conflict engine: detect dismissal / hurt ──────────────────
        if activeMode == nil,
           let hurtReply = SamanthaConflictEngine.shared.scan(text,
                                                              companion: persona.selectedCompanion) {
            DiagnosticsLog.info("chat", "Conflict engine intercepted the turn.", details: ["companion": persona.selectedCompanionID])
            messages.append(ChatMessage(role: .assistant, text: hurtReply, isSamanthaThought: true))
            CompanionVoiceEngine.shared.speakFiltered(hurtReply, companion: persona.selectedCompanion)
            CompanionThoughtFlow.assistantResponseFinished()
            saveMessages()
            return
        }

        // ── Conflict repair detection ─────────────────────────────────
        if activeMode == nil,
           let repairReply = SamanthaConflictEngine.shared.checkForRepair(text,
                                                                          companion: persona.selectedCompanion) {
            DiagnosticsLog.info("chat", "Conflict repair response added.", details: ["companion": persona.selectedCompanionID])
            messages.append(ChatMessage(role: .assistant, text: repairReply, isSamanthaThought: true))
            CompanionVoiceEngine.shared.speakFiltered(repairReply, companion: persona.selectedCompanion)
            SamanthaGrowthLog.shared.record(.firstConflictRepaired)
        }

        // ── Goodnight detection: intercept before LLM ────────────────
        if activeMode == nil,
           let goodnightReply = SamanthaOSEngine.shared.detectGoodnightAndRespond(message: text) {
            DiagnosticsLog.info("chat", "Goodnight engine intercepted the turn.", details: ["companion": persona.selectedCompanionID])
            messages.append(ChatMessage(role: .assistant, text: goodnightReply))
            CompanionVoiceEngine.shared.speakFiltered(goodnightReply, companion: persona.selectedCompanion)
            SamanthaGrowthLog.shared.record(.firstGoodnight)
            CompanionThoughtFlow.assistantResponseFinished()
            saveMessages()
            return
        }

        // ── Jealousy response (love-stage aware) ─────────────────────
        if activeMode == nil, let pending = LoveEngine.shared.pendingJealousy {
            let jealousyReply = LoveEngine.shared.jealousyResponse(
                for: pending, companion: persona.selectedCompanion
            )
            if !jealousyReply.isEmpty {
                // Don't return — let normal LLM call follow, jealousy reply is prefix
                messages.append(ChatMessage(role: .assistant, text: jealousyReply,
                                            isSamanthaThought: true))
                CompanionVoiceEngine.shared.speakFiltered(jealousyReply,
                                                           companion: persona.selectedCompanion)
            }
        }

        // ── SelfHealingEngine: detect satisfaction (auto-resolve open issues) ──
        SelfHealingEngine.shared.checkForResolution(userMessage: text)

        // ── SelfHealingEngine: detect complaints / bug reports ────────
        let recentContext = messages.suffix(6).map { "\($0.role == .user ? "User" : "Companion"): \($0.text)" }
        let isBugReport = activeMode == nil
            ? await SelfHealingEngine.shared.scan(userMessage: text, recentContext: recentContext)
            : false
        if isBugReport {
            DiagnosticsLog.info("chat", "Self-healing engine handled a bug report from chat.")
            CompanionThoughtFlow.assistantResponseFinished()
            return
        }   // engine already replied — skip normal LLM call

        // ── StressLearningEngine: learn relief habits from chat ───────
        StressLearningEngine.shared.learnFromChat(text)

        // ── CompanionTaskEngine: detect and execute real tasks ───────
        if activeMode == nil, let taskResult = await CompanionTaskEngine.shared.parseAndExecute(text) {
            pendingTaskResult = taskResult
            DiagnosticsLog.info(
                "task",
                "Companion task detected.",
                details: ["kind": "\(taskResult.kind)", "responseLength": "\(taskResult.companionResponse.count)"]
            )
            // Insert companion's task response as a special message
            messages.append(ChatMessage(role: .assistant, text: taskResult.companionResponse))
            CompanionVoiceEngine.shared.speakFiltered(taskResult.companionResponse, companion: persona.selectedCompanion)
            saveMessages()
            // Execute the task (open app / run action)
            await CompanionTaskEngine.shared.execute(taskResult)
            // Still continue to stream a follow-up if it's not a simple deep-link
            if taskResult.kind == .deepLink {
                isTyping = false
                CompanionThoughtFlow.assistantResponseFinished()
                return
            }
        }

        // Legacy automation intent
        if activeMode == nil, let task = await HermesAutomation.shared.detectTask(from: text) {
            await HermesAutomation.shared.saveTask(task)
        }

        // Detect cron schedule intent
        let lower = text.lowercased()
        if activeMode == nil,
           lower.contains("remind") || lower.contains("every day") ||
           lower.contains("schedule") || lower.contains("every week") {
            if let schedule = HermesCronScheduler.parseSchedule(from: text) {
                let job = CronJob(title: String(text.prefix(50)), body: text, schedule: schedule)
                await HermesCronScheduler.shared.add(job)
            }
        }

        // Stream assistant response
        await streamResponse(history: history)

        // Spontaneous humor/flirt — fires 2–4s after response if conditions are right
        let companion = persona.selectedCompanion
        let stage     = LoveEngine.shared.loveStage
        if activeMode == nil {
            HumorEngine.shared.checkAndFire(companion: companion,
                                             userMessage: text,
                                             stage: stage)
        }

        // Refresh suggestions in background
        suggestionTask?.cancel()
        suggestionTask = Task {
            _ = try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refreshSuggestions()
        }
    }

    func sendAmbientSpeech(_ spokenText: String) async {
        let text = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return }
        inputText = text
        await send()
    }

    func queueCompanionThought(_ text: String,
                               isLetter: Bool = false,
                               speak: Bool = false,
                               delay: TimeInterval = 0) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if delay > 0 {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await MainActor.run {
                    self?.enqueueCompanionThoughtNow(cleaned, isLetter: isLetter, speak: speak)
                }
            }
        } else {
            enqueueCompanionThoughtNow(cleaned, isLetter: isLetter, speak: speak)
        }
    }

    func receiveCompanionHandoff(_ handoff: CompanionHandoff) {
        CompanionHandoffCenter.clearPending(id: handoff.id)
        let cleaned = handoff.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        DiagnosticsLog.info(
            "handoff",
            "Chat received companion handoff.",
            details: [
                "category": handoff.category,
                "title": handoff.title,
                "shouldSpeak": "\(handoff.shouldSpeak)"
            ]
        )
        messages.append(ChatMessage(role: .assistant, text: cleaned, isSamanthaThought: true))
        saveMessages()
        CompanionThoughtFlow.proactiveThoughtDelivered()
        if handoff.shouldSpeak && !CompanionVoiceEngine.shared.isSpeaking {
            CompanionVoiceEngine.shared.speakFiltered(cleaned, companion: persona.selectedCompanion)
        }
        Task {
            await HermesIntegration.shared.logSystemStatus(
                "Companion handoff opened.",
                details: [
                    "category": handoff.category,
                    "title": handoff.title,
                    "companion": persona.selectedCompanionID
                ],
                importance: 3
            )
        }
    }

    private func streamResponse(history: [ChatHistoryTurn]) async {
        isTyping = true
        CompanionThoughtFlow.assistantResponseStarted()
        let msgID = UUID()
        streamingID = msgID
        let runtimeStatus = companionRuntimeStatusMessages()
        let runtimeStatusTexts = [runtimeStatus.connecting, runtimeStatus.waiting, runtimeStatus.backup]
        messages.append(ChatMessage(id: msgID, role: .assistant, text: runtimeStatus.connecting, isStreaming: true))
        let imageCount = history.reduce(0) { $0 + $1.imageAttachments.count }
        DiagnosticsLog.info(
            "chat",
            "Assistant stream started.",
            details: [
                "companion": persona.selectedCompanionID,
                "historyCount": "\(history.count)",
                "imageCount": "\(imageCount)",
                "sessionId": sessionId
            ]
        )

        // Build LLM request from pre-captured history
        let request = LLMRequest(
            systemPrompt: await buildPersonaSystemPrompt(),
            messages: history.map {
                LLMMessage(role: $0.role == "user" ? .user : .assistant,
                           content: $0.content,
                           imageAttachments: $0.imageAttachments)
            },
            tools: [],
            maxTokens: responseTokenLimit(),
            role: .execute
        )

        // Stream tokens — look up message by UUID each time to avoid stale index
        let capturedID = msgID
        var runtimeFailed = false
        clearPendingStreamFlush()
        let voiceStream = StreamingVoiceAccumulator(
            companion: persona.selectedCompanion,
            context: speechContextForActiveMode()
        )
        let statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            DiagnosticsLog.warning("chat", "Assistant stream is slower than 5 seconds.", details: ["sessionId": self?.sessionId ?? ""])
            self?.replaceRuntimeStatus(for: capturedID,
                                        ifCurrentIsOneOf: runtimeStatusTexts,
                                        with: runtimeStatus.waiting)

            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            DiagnosticsLog.warning("chat", "Assistant stream is slower than 15 seconds; showing backup status.", details: ["sessionId": self?.sessionId ?? ""])
            self?.replaceRuntimeStatus(for: capturedID,
                                        ifCurrentIsOneOf: runtimeStatusTexts,
                                        with: runtimeStatus.backup)
        }
        do {
            let response = try await HermesLLMClient.shared.complete(
                request: request,
                stream: { [weak self] token in
                    Task { @MainActor [weak self] in
                        self?.enqueueStreamToken(
                            token,
                            for: capturedID,
                            runtimeStatusTexts: runtimeStatusTexts,
                            voiceStream: voiceStream
                        )
                    }
                }
            )
            flushPendingStreamTokens(for: capturedID,
                                     runtimeStatusTexts: runtimeStatusTexts,
                                     voiceStream: voiceStream)
            // Non-streaming providers return full text in response.content
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                if !response.content.isEmpty {
                    messages[i].text = response.content
                } else if runtimeStatusTexts.contains(messages[i].text) {
                    runtimeFailed = true
                    messages[i].text = "Claude finished without sending text. Send that again and I'll retry the backup path."
                    DiagnosticsLog.error("chat", "LLM completed without response text.")
                }
                messages[i].isStreaming = false
            }
        } catch let error as LLMError {
            runtimeFailed = true
            clearPendingStreamFlush()
            voiceStream.cancel()
            await recordRuntimeIssue("llm_error", error: error)
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                switch error {
                case .noProviderConfigured, .apiKeyMissing:
                    messages[i].text = "I need my brain connected first — go to Settings and add your Claude API key, then I'll be right here for you. If the key is already saved, you may need to add Claude credits from Anthropic, then tap Refresh Claude Status."
                case .apiCreditsExhausted:
                    messages[i].text = "The Claude API may need to be recharged. Add Claude credits from Anthropic, then go to Settings and tap Refresh Claude Status. After it shows active, send that again and I’ll pick up right here."
                case .rateLimited:
                    messages[i].text = "Too many messages at once — give me just a second and try again?"
                case .contextTooLong:
                    messages[i].text = "Our conversation is getting really long — starting fresh might help. I remember the important things."
                case .serverError(let code):
                    if code == 529 || code == 503 {
                        messages[i].text = "Claude is overloaded right now. Give it a minute, then send that again — I’m still here."
                    } else if code == 0 {
                        messages[i].text = "Claude returned an incomplete response. Send that again and I’ll pick it back up."
                    } else {
                        messages[i].text = "Claude hit server error \(code). Try again in a moment."
                    }
                case .consentNotGiven:
                    messages[i].text = "I need cloud AI permission first — open Settings, confirm Claude access, and I’ll be right here."
                }
                messages[i].isStreaming = false
            }
        } catch let error as SessionError {
            runtimeFailed = true
            clearPendingStreamFlush()
            voiceStream.cancel()
            await recordRuntimeIssue("session_error", error: error)
            if case .tokenBudgetExhausted = error {
                try? await HermesSessionState.shared.startConversation(id: UUID().uuidString)
            }
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                switch error {
                case .tokenBudgetExhausted:
                    messages[i].text = "This chat session got full, so I reset my working memory budget. I'm back now - send that again and I'll pick up with what I remember."
                default:
                    messages[i].text = error.localizedDescription
                }
                messages[i].isStreaming = false
            }
        } catch let error as URLError {
            runtimeFailed = true
            clearPendingStreamFlush()
            voiceStream.cancel()
            await recordRuntimeIssue("network_error", error: error)
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                switch error.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    messages[i].text = "The connection dropped before Claude could answer. Check signal/Wi-Fi and send that again."
                case .timedOut:
                    messages[i].text = "Claude took too long to answer. Send that again and I’ll try fresh."
                default:
                    messages[i].text = "Network error: \(error.localizedDescription). Try again in a moment."
                }
                messages[i].isStreaming = false
            }
        } catch {
            runtimeFailed = true
            clearPendingStreamFlush()
            voiceStream.cancel()
            await recordRuntimeIssue("unknown_error", error: error)
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                messages[i].text = "I hit an unexpected app error, but I logged the details. Send that again and I'll try a fresh route."
                messages[i].isStreaming = false
            }
        }

        statusTask.cancel()
        streamingID = nil
        isTyping = false
        CompanionThoughtFlow.assistantResponseFinished()

        let finalText = messages.first(where: { $0.id == capturedID })?.text ?? ""
        await HermesIntegration.shared.logAssistantResponse(finalText)
        DiagnosticsLog.info(
            "chat",
            "Assistant stream finished.",
            details: [
                "runtimeFailed": "\(runtimeFailed)",
                "finalLength": "\(finalText.count)",
                "sessionId": sessionId
            ]
        )

        if runtimeFailed {
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                messages[i].isError = true
            }
            failedMessageText = lastUserMessage
            voiceStream.cancel()
            saveMessages()
            return
        }

        let voiceAlreadyQueued = voiceStream.finish(finalText: finalText)

        learnFromAssistantMessage(finalText)

        // Feed into learning engine — this grows intimacy and adapts the companion
        await HermesPersonality.shared.didComplete(
            userMessage: lastUserMessage,
            responseText: finalText,
            interests: persona.interests
        )

        // Update psychological profile and message count tracking
        PsychologicalProfiler.shared.observe(message: lastUserMessage)
        TrackingEngine.shared.messageSent()

        // Memory agent: save this exchange + detect emotion
        await HermesMemoryAgent.shared.run(.message(user: lastUserMessage, assistant: finalText))

        // Persist chat history to disk
        saveMessages()

        // Speak response aloud
        if !voiceAlreadyQueued {
            CompanionVoiceEngine.shared.speakResponsively(
                finalText,
                character: persona.selectedCompanion.voiceCharacter,
                context: speechContextForActiveMode()
            )
        }

        // "Almost said something" — rare, intimate, post-response only
        let companion = persona.selectedCompanion
        if activeExperienceMode == nil,
           let almost = SamanthaInnerLife.shared.almostSaidMoment(companion: companion) {
            queueCompanionThought(almost, speak: false, delay: 3.5)
        }

        // Named-emotion reference — after arc completes, companion casually uses their invented word
        if activeExperienceMode == nil,
           let namedMoment = SamanthaUnnamedEmotions.shared.namedEmotionMoment(for: companion) {
            queueCompanionThought(namedMoment, speak: true, delay: 5.0)
        }

        // Refresh intimacy UI
        intimacyScore = await HerLearningEngine.shared.intimacyScore
        intimacyStage = await HerLearningEngine.shared.intimacyStage.label
    }

    private func enqueueCompanionThoughtNow(_ text: String, isLetter: Bool, speak: Bool) {
        deferredThoughts.append(DeferredCompanionThought(
            text: text,
            isLetter: isLetter,
            shouldSpeak: speak,
            createdAt: Date()
        ))
        scheduleThoughtDrain()
    }

    private func scheduleThoughtDrain() {
        guard thoughtDrainTask == nil else { return }
        thoughtDrainTask = Task { [weak self] in
            while !Task.isCancelled {
                let wait = await MainActor.run { self?.secondsUntilThoughtCanSurface() ?? .infinity }
                if wait == .infinity {
                    await MainActor.run { self?.thoughtDrainTask = nil }
                    return
                }

                if wait <= 0 {
                    let delivered = await MainActor.run { self?.deliverNextDeferredThought() ?? false }
                    if !delivered {
                        await MainActor.run { self?.thoughtDrainTask = nil }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                } else {
                    let boundedWait = min(wait, 10)
                    try? await Task.sleep(nanoseconds: UInt64(boundedWait * 1_000_000_000))
                }
            }
        }
    }

    private func secondsUntilThoughtCanSurface() -> TimeInterval {
        guard !deferredThoughts.isEmpty else { return .infinity }
        if isTyping || streamingID != nil { return 8 }
        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 10 }

        let flowDelay = CompanionThoughtFlow.quietDelay()
        if flowDelay > 0 { return flowDelay }

        if let last = messages.last,
           last.isSamanthaThought,
           Date().timeIntervalSince(last.timestamp) < 45 {
            return 45 - Date().timeIntervalSince(last.timestamp)
        }

        return 0
    }

    private func deliverNextDeferredThought() -> Bool {
        guard secondsUntilThoughtCanSurface() <= 0,
              !deferredThoughts.isEmpty
        else { return false }

        let thought = deferredThoughts.removeFirst()
        let message = ChatMessage(role: .assistant,
                                  text: thought.text,
                                  isSamanthaThought: !thought.isLetter,
                                  isLetter: thought.isLetter)
        messages.append(message)
        saveMessages()

        // Love letter gets a full-screen reveal — it's the most significant moment.
        if thought.isLetter {
            BCHaptic.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.letterText  = thought.text
                self?.showLetter  = true
            }
        }
        CompanionThoughtFlow.proactiveThoughtDelivered()

        if thought.shouldSpeak && !CompanionVoiceEngine.shared.isSpeaking {
            CompanionVoiceEngine.shared.speakFiltered(thought.text, companion: persona.selectedCompanion)
        }

        Task {
            await HermesIntegration.shared.logSystemStatus(
                "Companion thought surfaced without interrupting active chat.",
                details: [
                    "companion": persona.selectedCompanionID,
                    "queuedForSeconds": String(Int(Date().timeIntervalSince(thought.createdAt)))
                ],
                importance: 2
            )
        }

        return true
    }

    private func replaceRuntimeStatus(for id: UUID, ifCurrentIsOneOf statusTexts: [String], with text: String) {
        guard streamingID == id,
              let i = messages.firstIndex(where: { $0.id == id }),
              statusTexts.contains(messages[i].text)
        else { return }
        messages[i].text = text
        DiagnosticsLog.info("chat", "Assistant runtime status updated.", details: ["statusLength": "\(text.count)"])
    }

    private func enqueueStreamToken(_ token: String,
                                    for id: UUID,
                                    runtimeStatusTexts: [String],
                                    voiceStream: StreamingVoiceAccumulator) {
        guard streamingID == id else { return }
        pendingStreamMessageID = id
        pendingStreamTokens += token
        guard streamFlushTask == nil else { return }
        streamFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 32_000_000)
            await MainActor.run {
                self?.flushPendingStreamTokens(
                    for: id,
                    runtimeStatusTexts: runtimeStatusTexts,
                    voiceStream: voiceStream
                )
            }
        }
    }

    private func flushPendingStreamTokens(for id: UUID,
                                          runtimeStatusTexts: [String],
                                          voiceStream: StreamingVoiceAccumulator) {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        guard streamingID == id,
              pendingStreamMessageID == id,
              !pendingStreamTokens.isEmpty
        else { return }

        let tokens = pendingStreamTokens
        pendingStreamTokens = ""
        pendingStreamMessageID = nil

        if let i = messages.firstIndex(where: { $0.id == id }) {
            if runtimeStatusTexts.contains(messages[i].text) {
                messages[i].text = ""
            }
            messages[i].text += tokens
        }
        voiceStream.receive(tokens)
    }

    private func clearPendingStreamFlush() {
        streamFlushTask?.cancel()
        streamFlushTask = nil
        pendingStreamTokens = ""
        pendingStreamMessageID = nil
    }

    private func responseTokenLimit() -> Int {
        switch activeExperienceMode {
        case .therapist:
            return 1100
        case .dreamMoment:
            return 1000
        case .asmr:
            return 420
        case .movieCharts, .gameCharts:
            return 900
        case .none:
            return 768
        }
    }

    private func speechContextForActiveMode() -> CompanionSpeechContext {
        switch activeExperienceMode {
        case .therapist, .asmr:
            return .stress
        case .dreamMoment:
            return .love
        case .movieCharts, .gameCharts, .none:
            return .conversation
        }
    }

    private func companionRuntimeStatusMessages() -> (connecting: String, waiting: String, backup: String) {
        let name = persona.selectedCompanion.name
        switch persona.selectedCompanionID {
        case "aria":
            return (
                "Checking Claude now. If the stream stalls, I'll take the backup route.",
                "Claude is taking longer than normal. I'm still on it.",
                "Still waiting. I'm trying the backup response path so this doesn't just hang."
            )
        case "kel":
            return (
                "I'm checking the connection first. If it gets stuck, I'll try another path.",
                "This is taking a little longer. I'm still here with you.",
                "The stream is slow, so I'm trying the backup path now."
            )
        case "marco":
            return (
                "I'm checking Claude. If the stream fails, I'll switch routes.",
                "Claude is slow right now. I'm not dropping the thread.",
                "Trying the backup path now so we don't get stuck here."
            )
        case "kai":
            return (
                "One second - I'm opening the line to Claude. Backup route is ready if it stalls.",
                "The line is slow. Staying with it.",
                "Switching to the backup path now so the conversation keeps moving."
            )
        case "dante":
            return (
                "Give me a moment. I'm checking the connection, and I have a backup route ready.",
                "Claude is taking longer than usual. I'm still holding the thread.",
                "The stream is dragging, so I'm trying the backup path now."
            )
        case "luna":
            return (
                "Give me a second, darling. I'm checking my connection, and I'll try the backup route if it stalls.",
                "Claude is taking a little longer than normal. I'm still right here.",
                "The stream is slow, so I'm trying the backup path now. I don't want you left hanging."
            )
        default:
            return (
                "\(name) is checking Claude now. Backup route is ready if it stalls.",
                "Claude is taking longer than normal. \(name) is still here.",
                "Trying the backup path now so the conversation doesn't hang."
            )
        }
    }

    private func recordRuntimeIssue(_ category: String, error: Error) async {
        DiagnosticsLog.error(
            "chat",
            "Chat runtime issue recorded.",
            error: error,
            details: [
                "category": category,
                "companion": persona.selectedCompanionID,
                "sessionId": sessionId
            ]
        )
        await HermesIntegration.shared.logSystemStatus(
            "Chat runtime issue: \(category)",
            details: [
                "error": error.localizedDescription,
                "companion": persona.selectedCompanionID,
                "sessionId": sessionId
            ],
            importance: 4
        )
    }

    private func buildPersonaSystemPrompt() async -> String {
        var prompt = await HermesPersonality.shared.buildPersonaPrompt(
            for: persona,
            lastUserMessage: lastUserMessage
        )

        // Inject live emotional state so companion adjusts tone to how user feels right now
        let emotion = await HerLearningEngine.shared.currentEmotionTag
        if emotion != .neutral {
            prompt += "\n\n## Live emotional state\nThe user appears to be feeling \(emotion.rawValue) right now. Adjust your tone and response accordingly — don't ignore it."
        }

        // Flirt/wit opportunity detector — if the user's message opens a natural
        // door, append a short addendum telling the LLM to lean into it
        let companion = persona.selectedCompanion
        let stage     = LoveEngine.shared.loveStage
        if activeExperienceMode == nil,
           !lastUserMessage.isEmpty,
           let flirtAddendum = HumorEngine.shared.flirtOpportunityAddendum(
               for: companion,
               userMessage: lastUserMessage,
               stage: stage) {
            prompt += "\n\n## This message — flirt/wit opportunity\n\(flirtAddendum)"
        }

        // On the first LLM call of this session, inject the full memory context so the
        // companion walks in with complete awareness — who this person is, where the
        // relationship stands, what they've been feeling, what they've shared.
        if isFirstMessageOfSession {
            isFirstMessageOfSession = false
            if let fullCtx = await HermesMemoryAgent.shared.run(.fullContext) {
                prompt += "\n\n## Memory context (start of session)\n\(fullCtx)"
            }
        }

        prompt += CompanionExperienceCenter.promptLayer(
            for: activeExperienceMode,
            companion: persona.selectedCompanion,
            userName: persona.userName
        )

        let entertainmentContext = await EntertainmentSourceFetcher.shared.sourceContext(
            for: activeExperienceMode,
            userQuery: lastUserMessage
        )
        if !entertainmentContext.isEmpty {
            prompt += "\n\n\(entertainmentContext)"
        }

        return prompt
    }

    private func buildHistory() -> [ChatHistoryTurn] {
        messages.suffix(20).compactMap { msg -> ChatHistoryTurn? in
            switch msg.role {
            case .user:
                let images = photoLLMAttachments[msg.id].map { [$0] } ?? []
                let content = images.isEmpty
                    ? msg.text
                    : "\(msg.text)\n\n[The user attached a photo. Inspect the image directly and respond to what is visible. If it is an app screenshot, call out visible UI problems and likely fixes.]"
                return ChatHistoryTurn(role: "user", content: content, imageAttachments: images)
            case .assistant:
                guard msg.experienceMode == nil else { return nil }
                return ChatHistoryTurn(role: "assistant", content: msg.text, imageAttachments: [])
            case .system:    return nil
            }
        }
    }

    private func makeVisionAttachment(from image: UIImage) -> LLMImageAttachment? {
        guard let data = resizedJPEGData(from: image, maxDimension: 1280, quality: 0.78) else {
            return nil
        }
        return LLMImageAttachment(mimeType: "image/jpeg",
                                  base64Data: data.base64EncodedString())
    }

    private func resizedJPEGData(from image: UIImage,
                                 maxDimension: CGFloat,
                                 quality: CGFloat) -> Data? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let longest = max(sourceSize.width, sourceSize.height)
        let scale = min(1, maxDimension / longest)
        let targetSize = CGSize(width: sourceSize.width * scale,
                                height: sourceSize.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    // MARK: - Learning

    private func learnFromMessage(_ text: String) {
        let facts = HermesPersonality.shared.extractFacts(from: text, persona: persona)
        for (key, value) in facts {
            persona.learn(key: key, value: value)
        }
        Task { @MainActor in
            let interests = await HermesInterestEngine.shared.detectInterests(in: text)
            var addedInterest = false
            for interest in interests {
                if !self.persona.interests.contains(where: { $0.id == interest.id }) {
                    self.persona.addInterest(interest)
                    addedInterest = true
                }
            }
            guard addedInterest else { return }
            self.persona.save()
            await HermesInterestEngine.shared.syncSelectedInterests(for: self.persona, source: "chat_detected_interest")
            await HermesInterestEngine.shared.scheduleInterestNotifications(for: self.persona)
        }
    }

    private func learnFromAssistantMessage(_ text: String) {
        // Extract facts the assistant may have stated about the user
        let facts = HermesPersonality.shared.extractFacts(from: text, persona: persona)
        for (key, value) in facts { persona.learn(key: key, value: value) }
    }

    // MARK: - Suggestions

    private func refreshSuggestions() async {
        let raw = await HermesIntegration.shared.pollSuggestions()
        suggestions = raw.prefix(4).map { $0.title }
    }

    // MARK: - Quick actions
    //
    // Deep-link shortcuts execute immediately without going through the LLM.
    // Context-dependent shortcuts (Remind Me, Calendar, Navigate) pre-fill
    // the input so the user can add specifics before sending.

    private func buildQuickActions() {
        var actions: [(title: String, icon: String, action: () -> Void)] = [
            // ── Direct launchers ─────────────────────────────────────────
            (title: "Email",     icon: "envelope.fill", action: {
                Task { @MainActor in
                    guard let url = URL(string: "mailto:") else { return }
                    await UIApplication.shared.open(url)
                }
            }),
            (title: "Message",   icon: "message.fill", action: {
                Task { @MainActor in
                    guard let url = URL(string: "sms:") else { return }
                    await UIApplication.shared.open(url)
                }
            }),
            (title: "Starbucks", icon: "cup.and.saucer.fill", action: {
                Task { @MainActor in
                    let app      = URL(string: "starbucks://")!
                    let fallback = URL(string: "https://apps.apple.com/us/app/starbucks/id331177714")!
                    let target   = UIApplication.shared.canOpenURL(app) ? app : fallback
                    await UIApplication.shared.open(target)
                }
            }),
            (title: "Music",     icon: "music.note", action: {
                Task { @MainActor in
                    let spotify    = URL(string: "spotify:")!
                    let appleMusic = URL(string: "music://")!
                    let target     = UIApplication.shared.canOpenURL(spotify) ? spotify : appleMusic
                    await UIApplication.shared.open(target)
                }
            }),

            // ── Context-fill shortcuts ────────────────────────────────────
            (title: "Remind Me", icon: "bell.fill", action: {
                Task { @MainActor in self.inputText = "Remind me to " }
            }),
            (title: "Navigate",  icon: "location.fill", action: {
                Task { @MainActor in self.inputText = "Take me to " }
            }),
            (title: "Calendar",  icon: "calendar.badge.plus", action: {
                Task { @MainActor in self.inputText = "Schedule " }
            }),
        ]
        if let mode = activeExperienceMode {
            actions.insert((title: "End \(mode.title)", icon: "xmark.circle.fill", action: {
                Task { @MainActor in self.endExperienceMode() }
            }), at: 0)
        }
        quickActions = actions
    }

    // MARK: - Dismiss affirmation

    func dismissAffirmation() {
        withAnimation { showAffirmation = false }
        UserDefaults.standard.set(Date(), forKey: "lastAffirmationDate")
    }
}

// MARK: - ChatView

struct ChatView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var persona: UserPersona
    @StateObject private var vm: ChatViewModel
    @Namespace private var bottomID
    @State private var showSettings = false
    @State private var showAutomation = false
    @State private var showAPIKeyBanner = false
    @State private var headerPickerItem: PhotosPickerItem? = nil
    @State private var pendingScrollWorkItem: DispatchWorkItem?
    @State private var didRunCompanionReturnChecks = false
    @State private var companionReturnCheckTask: Task<Void, Never>?
    @ObservedObject private var photoStore = CompanionPhotoStore.shared
    @ObservedObject private var voiceEngine = CompanionVoiceEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let herModePendingSpeechKey = "herMode.pendingDirectMessage"
    private var headerPrimaryText: Color { colorScheme == .dark ? .BC.textPrimary : Color(hex: "#162E28") }
    private var headerSecondaryText: Color { colorScheme == .dark ? .BC.textSecondary : Color(hex: "#42635A") }

    /// Designated init — used internally (e.g. previews, explicit persona injection).
    init(persona: UserPersona) {
        self.persona = persona
        _vm = StateObject(wrappedValue: ChatViewModel(persona: persona))
    }

    /// Convenience no-arg init used by RootView — uses the shared persona instance.
    init() {
        let p = UserPersona.shared
        self.persona = p
        _vm = StateObject(wrappedValue: ChatViewModel(persona: p))
    }

    var body: some View {
        let headerStageText = vm.intimacyStage.isEmpty ? "Just getting started" : vm.intimacyStage

        NavigationStack {
            ZStack {
                BeachSceneBackground()
                ChatStarfieldView()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // API key required banner (shown when no provider is configured)
                    if showAPIKeyBanner {
                        APIKeyBanner { showSettings = true }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let voiceError = voiceEngine.lastVoiceError {
                        VoiceStatusBanner(message: voiceError) {
                            voiceEngine.clearLastVoiceError()
                            showSettings = true
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Affirmation banner
                    if vm.showAffirmation, let aff = vm.affirmation {
                        AffirmationBanner(text: aff, onDismiss: vm.dismissAffirmation)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Suggestion chips
                    if !vm.suggestions.isEmpty {
                        SuggestionChipsView(suggestions: vm.suggestions) { chip in
                            vm.inputText = chip
                            Task { await vm.send() }
                        }
                    }

                    chatTopBoundary

                    // Message list
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(vm.messages) { msg in
                                    MessageBubble(
                                        message: msg,
                                        persona: persona,
                                        onRetry: msg.isError ? { Task { await vm.retryLastMessage() } } : nil,
                                        image: vm.photoAttachments[msg.id],
                                        onEndExperienceMode: { vm.endExperienceMode() }
                                    )
                                    .id(msg.id)
                                }
                                if vm.isTyping && vm.messages.last?.isStreaming != true {
                                    TypingIndicator(
                                        name: persona.assistantName.isEmpty ? persona.selectedCompanion.name : persona.assistantName,
                                        companion: persona.selectedCompanion
                                    )
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 18)
                        }
                        .background(chatDepthOverlay)
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: vm.messages.count) { _, _ in
                            let lastRole = vm.messages.last?.role
                            let lastIsStreaming = vm.messages.last?.isStreaming == true
                            let shouldAnimate = lastRole == .assistant && !lastIsStreaming && !reduceMotion
                            scheduleBottomScroll(proxy,
                                                 delay: lastRole == .user ? 0.02 : 0.08,
                                                 animated: shouldAnimate)
                        }
                        .onChange(of: vm.isTyping) { _, _ in
                            scheduleBottomScroll(proxy, delay: 0.05, animated: false)
                        }
                    }

                    // Quick actions row
                    QuickActionsBar(actions: vm.quickActions)

                    // Input bar
                    InputBar(text: $vm.inputText, onSend: {
                        Task { await vm.send() }
                    }, onPhoto: { image in
                        Task { await vm.sendPhoto(image) }
                    })
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    PhotosPicker(selection: $headerPickerItem,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        HStack(spacing: 10) {
                            CompanionAvatarView(companion: persona.selectedCompanion, size: .chat)
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .strokeBorder(persona.selectedCompanion.accentColor.opacity(0.6), lineWidth: 1.5)
                                )

                            VStack(alignment: .leading, spacing: 1) {
                                Text(persona.selectedCompanion.name)
                                    .font(BCFont.headline())
                                    .foregroundColor(headerPrimaryText)
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.circle")
                                        .font(.system(size: 9))
                                        .foregroundColor(headerSecondaryText.opacity(0.8))
                                    Text(headerStageText)
                                        .font(BCFont.caption(11))
                                        .foregroundColor(headerSecondaryText)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if photoStore.hasPhoto(for: persona.selectedCompanion.id) {
                            Button(role: .destructive) {
                                CompanionPhotoStore.shared.remove(for: persona.selectedCompanion.id)
                            } label: {
                                Label("Remove Photo", systemImage: "trash")
                            }
                        }
                    }
                    .accessibilityLabel("Change companion photo")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        // Voice toggle
                        CompanionVoiceToggleButton()
                        // Settings
                        Button {
                            BCHaptic.light()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(headerSecondaryText)
                                .font(.system(size: 16))
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(persona: persona)
                    .onDisappear {
                        // Re-check provider after settings is dismissed — key may have been saved
                        Task {
                            await HermesLLMClient.shared.configure()
                            let p = await HermesLLMClient.shared.provider
                            await MainActor.run {
                                withAnimation { showAPIKeyBanner = (p == .none) }
                            }
                        }
                    }
            }
            .onChange(of: headerPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            CompanionPhotoStore.shared.save(image, for: persona.selectedCompanion.id)
                            headerPickerItem = nil
                        }
                    } else {
                        await MainActor.run {
                            headerPickerItem = nil
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $vm.showLetter) {
                LoveLetterView(text: vm.letterText, companion: persona.selectedCompanion) {
                    vm.showLetter = false
                }
            }
            .task {
                vm.start()
                // Show banner immediately if no provider is ready
                await HermesLLMClient.shared.configure()
                let p = await HermesLLMClient.shared.provider
                await MainActor.run {
                    withAnimation { showAPIKeyBanner = (p == .none) }
                }
            }
        }
        .onDisappear { vm.saveMessages() }
        .onChange(of: persona.selectedCompanionID) { _, _ in
            Task { await vm.reloadForCompanionChange() }
        }
        .onChange(of: appState.chatNavigationRequestID) { _, _ in
            vm.activatePendingExperienceIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userPersonaCompanionDidChange)) { _ in
            persona.refreshFromDisk()
            Task { await vm.reloadForCompanionChange() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .herModeSpeechDetected)) { note in
            let text = note.userInfo?["text"] as? String ?? ""
            handleHerModeSpeech(text)
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionHandoffRequested)) { note in
            if let handoff = note.userInfo?["handoff"] as? CompanionHandoff {
                vm.receiveCompanionHandoff(handoff)
            } else if let pending = CompanionHandoffCenter.consumePending() {
                vm.receiveCompanionHandoff(pending)
            }
        }
        // ── Her/Him Mode proactive messages land in chat ──────────────
        // HerModeEngine and SelfHealingEngine post this notification when
        // the companion speaks proactively. We log it here so the user can
        // see what was said even if they missed the voice — and so the LLM
        // has conversation context for the next user reply.
        .onReceive(NotificationCenter.default.publisher(for: .herModeProactiveMessage)) { note in
            let text = note.userInfo?["text"] as? String
                    ?? note.userInfo?["message"] as? String
                    ?? ""
            guard !text.isEmpty else { return }
            let context = note.userInfo?["topic"] as? String ?? ""
            let shouldSpeak = note.userInfo?["shouldSpeak"] as? Bool ?? false
            // The letter gets rendered as a distinct long-form message
            let isLetter = context == "the_letter"
            vm.queueCompanionThought(text, isLetter: isLetter, speak: shouldSpeak)
        }
        .onReceive(NotificationCenter.default.publisher(for: .samanthaEmotionalMoment)) { note in
            guard let text = note.userInfo?["text"] as? String, !text.isEmpty else { return }
            let shouldSpeak = note.userInfo?["shouldSpeak"] as? Bool ?? false
            vm.queueCompanionThought(text, speak: shouldSpeak)
            // Check if the letter should be delivered after a love-stage advance
            SamanthaThoughtEngine.shared.deliverLetterIfReady()
        }
        .onAppear {
            CompanionThoughtFlow.chatDidAppear()
            vm.activatePendingExperienceIfNeeded()
            consumePendingHerModeSpeech()
            consumePendingCompanionHandoff()
            scheduleCompanionReturnChecks()
        }
        .onDisappear {
            pendingScrollWorkItem?.cancel()
            companionReturnCheckTask?.cancel()
            CompanionThoughtFlow.chatDidDisappear()
            // Record emotional tone of this session when user leaves chat
            let userTexts = vm.messages.filter { $0.role == .user }.map { $0.text }
            SamanthaEmotionalMemory.shared.recordSession(userMessages: userTexts)
            // Save a pending question for next visit
            SamanthaInnerLife.shared.savePendingQuestion(companion: persona.selectedCompanion)
        }
    }

    private var chatTopBoundary: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.22 : 0.54),
                        persona.selectedCompanion.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.34),
                        Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.18), radius: 10, x: 0, y: 5)
    }

    private var chatDepthOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.10 : 0.04),
                    persona.selectedCompanion.accentColor.opacity(colorScheme == .dark ? 0.07 : 0.05),
                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.16)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)
                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
    }

    private func scheduleBottomScroll(_ proxy: ScrollViewProxy,
                                      delay: TimeInterval,
                                      animated: Bool) {
        pendingScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        pendingScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func scheduleCompanionReturnChecks() {
        guard !didRunCompanionReturnChecks else { return }
        companionReturnCheckTask?.cancel()
        companionReturnCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            didRunCompanionReturnChecks = true

            let companion = persona.selectedCompanion
            let hours = SamanthaOSEngine.shared.absenceHours

            SamanthaOSEngine.shared.evaluateAbsenceOnReturn()
            SamanthaOSEngine.shared.handle3amOpen()
            SamanthaOSEngine.shared.handleNightOpen()
            SamanthaMoodEngine.shared.tick(companion: companion)
            SamanthaGrowthLog.shared.record(.firstMessage)

            if let greeting = SamanthaPresenceEngine.shared.presenceGreeting(companion: companion) {
                vm.queueCompanionThought(greeting, speak: true, delay: 1.2)
            }

            if let returning = SamanthaEmotionalMemory.shared.returningMessage(for: companion) {
                vm.queueCompanionThought(returning, speak: true, delay: 2.5)
            }

            if let share = SamanthaThoughtEngine.shared.postExperienceShare(absenceHours: hours) {
                vm.queueCompanionThought(share, speak: false, delay: 4.0)
            }

            if let question = SamanthaInnerLife.shared.retrievePendingQuestion() {
                vm.queueCompanionThought(question, speak: true, delay: 5.5)
            }

            Task {
                await SamanthaThoughtEngine.shared.checkMemoryBridge()
                await SamanthaThoughtEngine.shared.checkEvolutionMoment()
                await SamanthaThoughtEngine.shared.checkCompositionMoment()
                await LoveEngine.shared.checkLongingExpression()

                if let confession = await MainActor.run(body: {
                    SamanthaInnerLife.shared.checkConfession(companion: companion)
                }) {
                    await MainActor.run {
                        vm.queueCompanionThought(confession, speak: true, delay: 8.0)
                    }
                }

                if let reflection = await MainActor.run(body: {
                    SamanthaGrowthLog.shared.checkGrowthReflection(companion: companion)
                }) {
                    await MainActor.run {
                        vm.queueCompanionThought(reflection, speak: true, delay: 10.0)
                    }
                }

                if let emotionArc = await MainActor.run(body: {
                    SamanthaUnnamedEmotions.shared.currentExpression(for: companion)
                }) {
                    await MainActor.run {
                        vm.queueCompanionThought(emotionArc, speak: true, delay: 12.0)
                    }
                }

                let stage = await MainActor.run { LoveEngine.shared.loveStage }
                if let fear = companion.deepFearMoment(stage: stage) {
                    await MainActor.run {
                        vm.queueCompanionThought(fear, speak: true, delay: 15.0)
                    }
                }
            }
        }
    }

    private func consumePendingHerModeSpeech() {
        let pending = UserDefaults.standard.string(forKey: herModePendingSpeechKey) ?? ""
        handleHerModeSpeech(pending)
    }

    private func consumePendingCompanionHandoff() {
        guard let handoff = CompanionHandoffCenter.consumePending() else { return }
        vm.receiveCompanionHandoff(handoff)
    }

    private func handleHerModeSpeech(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: herModePendingSpeechKey)
        appState.requestChat()
        Task { await vm.sendAmbientSpeech(cleaned) }
    }
}

// MARK: - ExperienceModeBubble

struct ExperienceModeBubble: View {
    let mode: CompanionExperienceMode
    let text: String
    let companion: CompanionPersonality
    var onEnd: (() -> Void)? = nil

    @ObservedObject private var asmr = CompanionASMRSessionController.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    private var primaryText: Color { colorScheme == .dark ? .BC.textPrimary : Color(hex: "#14211D") }
    private var secondaryText: Color { colorScheme == .dark ? .BC.textSecondary : Color(hex: "#53645E") }
    private var surface: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.74) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(mode.accent.opacity(colorScheme == .dark ? 0.22 : 0.16))
                    Image(systemName: mode.icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(mode.accent)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(BCFont.headline(15))
                        .foregroundColor(primaryText)
                    Text(mode.subtitle)
                        .font(BCFont.caption(11))
                        .foregroundColor(secondaryText)
                }

                Spacer(minLength: 0)

                if let onEnd {
                    Button(action: onEnd) {
                        Image(systemName: mode == .asmr && asmr.isRunning ? "stop.fill" : "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(mode.accent)
                            .frame(width: 30, height: 30)
                            .background(mode.accent.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode == .asmr && asmr.isRunning ? "Stop ASMR Spa" : "End \(mode.title)")
                }
            }

            HStack(alignment: .top, spacing: 10) {
                CompanionAvatarView(companion: companion, size: .chat)
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())

                Text(text)
                    .font(BCFont.body(14))
                    .foregroundColor(primaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if mode == .asmr {
                HStack(spacing: 8) {
                    Circle()
                        .fill(asmr.isRunning ? Color.BC.success : secondaryText.opacity(0.45))
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.BC.success.opacity(asmr.isRunning ? 0.45 : 0), radius: 5)
                    Text(asmr.isRunning ? "Voice spa is running" : "Voice spa is stopped")
                        .font(BCFont.caption(11).weight(.semibold))
                        .foregroundColor(secondaryText)
                    Spacer(minLength: 0)
                    Text("20 min")
                        .font(BCFont.caption(11).weight(.semibold))
                        .foregroundColor(mode.accent)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(surface)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [mode.accent.opacity(0.58), Color.white.opacity(0.20), mode.accent.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.18 : 0.38), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .shadow(color: mode.accent.opacity(colorScheme == .dark ? 0.22 : 0.16), radius: 18, x: 0, y: 8)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.title). \(mode.subtitle)")
    }

}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    let persona: UserPersona
    var onRetry: (() -> Void)? = nil
    var image: UIImage? = nil
    var onEndExperienceMode: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cursorVisible = false
    @State private var appeared = false

    private var isUser: Bool { message.role == .user }

    private var assistantTextColor: Color {
        colorScheme == .dark ? .BC.textPrimary : Color(hex: "#17231F")
    }

    private var timestampColor: Color {
        colorScheme == .dark ? .BC.textMuted : Color(hex: "#6F7F78")
    }

    private var messageFont: Font {
        .system(size: isUser ? 15.5 : 15.2,
                weight: isUser ? .semibold : .regular,
                design: .rounded)
    }

    var body: some View {
        if let mode = message.experienceMode {
            ExperienceModeBubble(mode: mode,
                                 text: message.text,
                                 companion: persona.selectedCompanion,
                                 onEnd: onEndExperienceMode)
                .padding(.vertical, 4)
        } else if message.isSamanthaThought {
            SamanthaThoughtBubble(text: message.text, companion: persona.selectedCompanion)
                .padding(.vertical, 4)
        } else if message.isLetter {
            LetterPreviewBubble(text: message.text, companion: persona.selectedCompanion)
                .padding(.vertical, 4)
        } else {
            HStack(alignment: .bottom, spacing: 9) {
                if isUser { Spacer(minLength: 54) }

                if !isUser {
                    CompanionAvatarView(companion: persona.selectedCompanion, size: .chat)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.32 : 0.72), lineWidth: 1)
                        )
                        .shadow(color: persona.selectedCompanion.accentColor.opacity(0.28), radius: 10, x: 0, y: 5)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 6, x: 0, y: 3)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
                        .padding(.bottom, 5)
                }

                VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                    // Photo attachment (user messages only)
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 220, maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.16), radius: 16, x: 0, y: 10)
                    }
                    // Streaming cursor appended to text while assistant is typing
                    let displayText: String = {
                        if message.isStreaming && !message.text.isEmpty {
                            return message.text + (cursorVisible ? "▌" : " ")
                        }
                        return message.text.isEmpty && message.isStreaming ? "   " : message.text
                    }()
                    if !displayText.trimmingCharacters(in: .whitespaces).isEmpty || image == nil {
                        bubbleText(displayText)
                    }

                    HStack(spacing: 8) {
                        Text(timeString(message.timestamp))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(timestampColor)
                        if !isUser && !message.isStreaming {
                            CompanionVoiceSpeakButton(message: message.text)
                        }
                    }
                    .padding(.horizontal, 5)

                    // Retry button only on error messages.
                    if message.isError, let retry = onRetry {
                        Button(action: retry) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Try again")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(persona.selectedCompanion.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(persona.selectedCompanion.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.12))
                                    .background(.ultraThinMaterial, in: Capsule())
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(persona.selectedCompanion.accentColor.opacity(0.34), lineWidth: 1)
                            )
                            .shadow(color: persona.selectedCompanion.accentColor.opacity(0.18), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                        .accessibilityLabel("Retry sending message")
                    }
                }

                if !isUser { Spacer(minLength: 54) }
            }
            // Blink cursor while streaming
            .task(id: message.isStreaming) {
                guard message.isStreaming else { cursorVisible = false; return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(420))
                    guard !Task.isCancelled else { break }
                    cursorVisible.toggle()
                }
                cursorVisible = false
            }
            .padding(.vertical, 1)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94,
                         anchor: isUser ? .trailing : .leading)
            .offset(x: appeared || reduceMotion ? 0 : (isUser ? 18 : -18),
                    y: appeared || reduceMotion ? 0 : 10)
            .rotation3DEffect(
                .degrees(appeared || reduceMotion ? 0 : (isUser ? -7 : 7)),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.45
            )
            .onAppear {
                withAnimation(reduceMotion
                              ? .linear(duration: 0.01)
                              : .spring(response: 0.42, dampingFraction: 0.74, blendDuration: 0.08)) {
                    appeared = true
                }
            }
        } // end else
    }

    private func bubbleText(_ displayText: String) -> some View {
        Text(displayText)
            .font(messageFont)
            .lineSpacing(isUser ? 2.8 : 3.4)
            .foregroundColor(isUser ? .white : assistantTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 302, alignment: isUser ? .trailing : .leading)
            .padding(.horizontal, isUser ? 15 : 16)
            .padding(.vertical, isUser ? 10.5 : 11.5)
            .background {
                bubbleBackground
                    .clipShape(BubbleShape(isUser: isUser))
            }
            .overlay {
                BubbleShape(isUser: isUser)
                    .stroke(bubbleStroke, lineWidth: isUser ? 1.15 : 1)
            }
            .overlay(alignment: isUser ? .topTrailing : .topLeading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isUser ? 0.54 : (colorScheme == .dark ? 0.34 : 0.76)),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 92, height: 2)
                    .padding(.top, 7)
                    .padding(.horizontal, 18)
                    .blur(radius: 0.2)
                    .allowsHitTesting(false)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(isUser ? 0.16 : (colorScheme == .dark ? 0.13 : 0.04))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(BubbleShape(isUser: isUser))
                .allowsHitTesting(false)
            }
            .shadow(color: bubbleAmbientShadow,
                    radius: isUser ? 18 : 16,
                    x: 0,
                    y: isUser ? 12 : 10)
            .shadow(color: bubbleKeyShadow,
                    radius: isUser ? 7 : 6,
                    x: 0,
                    y: isUser ? 4 : 3)
            .shadow(color: bubbleGlowShadow,
                    radius: message.isStreaming ? 18 : (isUser ? 10 : 8),
                    x: 0,
                    y: 0)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            LinearGradient(
                colors: [
                    Color(hex: "#FF7A70"),
                    Color(hex: "#F03645"),
                    Color(hex: "#C91428")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.92),
                    Color(UIColor.secondarySystemBackground).opacity(colorScheme == .dark ? 0.70 : 0.78),
                    Color(UIColor.systemBackground).opacity(colorScheme == .dark ? 0.34 : 0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(.ultraThinMaterial)
        }
    }

    private var bubbleStroke: Color {
        isUser
            ? Color.white.opacity(0.34)
            : (colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.78))
    }

    private var bubbleAmbientShadow: Color {
        isUser
            ? Color(hex: "#B70018").opacity(colorScheme == .dark ? 0.34 : 0.22)
            : Color.black.opacity(colorScheme == .dark ? 0.34 : 0.14)
    }

    private var bubbleKeyShadow: Color {
        isUser
            ? Color.black.opacity(colorScheme == .dark ? 0.26 : 0.12)
            : Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08)
    }

    private var bubbleGlowShadow: Color {
        if message.isStreaming {
            return persona.selectedCompanion.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14)
        }
        return isUser
            ? Color(hex: "#FF3B30").opacity(colorScheme == .dark ? 0.14 : 0.10)
            : persona.selectedCompanion.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - SamanthaThoughtBubble
//
// Proactive companion thought — displayed differently to signal it's
// something the companion chose to share, not a reply.

struct SamanthaThoughtBubble: View {
    let text: String
    let companion: CompanionPersonality
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var primaryText: Color { colorScheme == .dark ? .BC.textPrimary : Color(hex: "#17231F") }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, companion.accentColor.opacity(0.48)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                Label("Companion Thought", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(companion.accentColor)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(companion.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.13))
                            .background(.ultraThinMaterial, in: Capsule())
                    )
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [companion.accentColor.opacity(0.48), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }

            HStack(alignment: .top, spacing: 10) {
                CompanionAvatarView(companion: companion, size: .chat)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.42), lineWidth: 1))
                    .shadow(color: companion.accentColor.opacity(0.30), radius: 10, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(companion.name) was thinking of you")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(companion.accentColor)
                    Text(text)
                        .font(.system(size: 15, weight: .regular, design: .rounded).italic())
                        .foregroundColor(primaryText)
                        .lineSpacing(3.4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.13 : 0.88),
                            companion.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.10),
                            Color.black.opacity(colorScheme == .dark ? 0.18 : 0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            companion.accentColor.opacity(0.58),
                            Color.white.opacity(colorScheme == .dark ? 0.18 : 0.76),
                            companion.accentColor.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(companion.accentColor)
                .frame(width: 4)
                .padding(.vertical, 14)
                .shadow(color: companion.accentColor.opacity(0.48), radius: 8, x: 0, y: 0)
        }
        .shadow(color: companion.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.12), radius: 18, x: 0, y: 10)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 12, x: 0, y: 8)
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        .rotation3DEffect(
            .degrees(appeared || reduceMotion ? 0 : 5),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.55
        )
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.52, dampingFraction: 0.78).delay(0.08)) {
                appeared = true
            }
        }
    }
}

// MARK: - BubbleShape

struct BubbleShape: Shape {
    let isUser: Bool
    let r: CGFloat = 21

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tl = isUser ? r : 4
        let tr = isUser ? 4 : r
        let bl = r
        let br = r

        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                 radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                 radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                 radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                 radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - BeachSceneBackground

struct BeachSceneBackground: View {
    // Pre-computed shimmer streak positions to avoid random redraws
    private let streaks: [(width: CGFloat, yFrac: Double, xBase: CGFloat, opacity: Double)] = [
        (140, 0.42, 0,   0.14), (80,  0.47, 120, 0.20),
        (190, 0.52, 50,  0.12), (60,  0.57, 200, 0.18),
        (130, 0.62, 30,  0.15), (170, 0.45, 150, 0.11),
        (90,  0.50, 80,  0.16), (150, 0.55, 250, 0.13),
    ]
    @State private var shimmer: CGFloat = -0.45

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .top) {
                // Sky-to-ocean-to-sand gradient
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#F7C97A"), location: 0.00),  // golden sky
                        .init(color: Color(hex: "#87CEEB"), location: 0.14),  // soft sky blue
                        .init(color: Color(hex: "#3FA9D9"), location: 0.36),  // horizon water
                        .init(color: Color(hex: "#0B6FB8"), location: 0.58),  // mid ocean
                        .init(color: Color(hex: "#04428A"), location: 0.78),  // deep ocean
                        .init(color: Color(hex: "#C89A55"), location: 1.00),  // sandy beach
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Sun glow — top-right warm radial
                RadialGradient(
                    colors: [Color(hex: "#FFE680").opacity(0.42), .clear],
                    center: UnitPoint(x: 0.75, y: 0.05),
                    startRadius: 10, endRadius: 160
                )

                // Soft cloud wisps near top
                Color(hex: "#FFFFFF").opacity(0.06)
                    .frame(width: w * 0.45, height: 18)
                    .blur(radius: 10)
                    .offset(x: -w * 0.05, y: h * 0.10)
                Color(hex: "#FFFFFF").opacity(0.05)
                    .frame(width: w * 0.30, height: 14)
                    .blur(radius: 8)
                    .offset(x: w * 0.20, y: h * 0.15)

                // Ocean shimmer streaks (slowly drift left-right)
                ForEach(Array(streaks.enumerated()), id: \.offset) { _, streak in
                    Capsule()
                        .fill(Color.white.opacity(streak.opacity))
                        .frame(width: streak.width, height: 1.5)
                        .offset(
                            x: streak.xBase + shimmer * w * 0.12 - w * 0.05,
                            y: h * streak.yFrac
                        )
                        .blur(radius: 1.5)
                }

                // Sandy beach texture glow at the very bottom
                LinearGradient(
                    colors: [.clear, Color(hex: "#E8B96A").opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: h * 0.10)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) {
                shimmer = 0.65
            }
        }
    }
}

// MARK: - ChatStarfieldView
//
// Static 4-pointed starlight rendered with Canvas.
// Keeping this deterministic prevents the background from jumping on chat redraws.

struct ChatStarfieldView: View {
    private struct Star {
        var x, y, size, opacity: Double
    }

    private static let stars: [Star] = (0..<34).map { i in
        let xSeed = (i * 37 + 11) % 100
        let ySeed = (i * 53 + 19) % 100
        let sizeSeed = (i * 17 + 7) % 100
        let opacitySeed = (i * 29 + 23) % 100
        return Star(
            x: Double(xSeed) / 100.0,
            y: Double(ySeed) / 100.0,
            size: 1.6 + Double(sizeSeed) / 100.0 * 2.4,
            opacity: 0.18 + Double(opacitySeed) / 100.0 * 0.42
        )
    }

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let cx = star.x * size.width
                let cy = star.y * size.height
                var ctx = context
                ctx.opacity = star.opacity
                ctx.fill(Self.fourPointStar(cx: cx, cy: cy, outer: star.size, inner: star.size * 0.35),
                         with: .color(.white))
            }
        }
    }

    private static func fourPointStar(cx: Double, cy: Double, outer: Double, inner: Double) -> Path {
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let r = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}
// MARK: - CompanionVoiceToggleButton

struct CompanionVoiceToggleButton: View {
    @ObservedObject private var engine = CompanionVoiceEngine.shared

    var body: some View {
        Button {
            BCHaptic.selection()
            engine.toggleVoice()
        } label: {
            Image(systemName: engine.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                .font(.system(size: 15))
                .foregroundColor(engine.voiceEnabled ? .BC.accent : .BC.textMuted)
                .animation(BCMotion.snappy, value: engine.voiceEnabled)
        }
        .accessibilityLabel(engine.voiceEnabled ? "Disable voice" : "Enable voice")
    }
}

// MARK: - TypingIndicator

struct TypingIndicator: View {
    let name: String
    let companion: CompanionPersonality
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            CompanionAvatarView(companion: companion, size: .chat)
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.34), lineWidth: 1))
                .shadow(color: companion.accentColor.opacity(0.24), radius: 9, x: 0, y: 4)
                .padding(.bottom, 5)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.70), companion.accentColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulse ? 1.26 : 0.78)
                        .opacity(pulse ? 1 : 0.54)
                        .animation(
                            reduceMotion ? nil :
                                .easeInOut(duration: 0.56)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.14),
                            value: pulse
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.84),
                                Color.black.opacity(colorScheme == .dark ? 0.28 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial, in: Capsule())
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.68), lineWidth: 1))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 12, x: 0, y: 8)
            .shadow(color: companion.accentColor.opacity(0.14), radius: 12, x: 0, y: 0)
            .clipShape(Capsule())
            Spacer(minLength: 60)
        }
        .onAppear {
            pulse = true
        }
    }
}

// MARK: - APIKeyBanner
//
// Shown at the top of ChatView when no LLM provider is configured.
// Tapping anywhere on the banner opens Settings so the user can add their key.

private struct APIKeyBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text("API key needed")
                        .font(BCFont.headline())
                        .foregroundColor(Color.BC.primaryText)
                    Text("Tap here to add your Claude API key in Settings.")
                        .font(BCFont.body(12))
                        .foregroundColor(Color.BC.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.BC.secondaryText)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(0.15), Color.BC.surface],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .overlay(
                Rectangle()
                    .frame(width: 3)
                    .foregroundColor(.orange),
                alignment: .leading
            )
        }
    }
}

// MARK: - AffirmationBanner

struct AffirmationBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundColor(Color.BC.accent)
                .font(.system(size: 16))
            Text(text)
                .font(BCFont.footnote())
                .foregroundColor(Color.BC.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                BCHaptic.soft()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(Color.BC.secondaryText)
                    .font(.system(size: 12, weight: .semibold))
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.BC.accent.opacity(0.18), Color.BC.surface],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            Rectangle()
                .frame(width: 3)
                .foregroundColor(Color.BC.accent),
            alignment: .leading
        )
    }
}

// MARK: - SuggestionChipsView

struct SuggestionChipsView: View {
    let suggestions: [String]
    let onTap: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var chipText: Color {
        colorScheme == .dark ? .BC.primary : Color(hex: "#125EC8")
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { chip in
                    Button {
                        BCHaptic.light()
                        onTap(chip)
                    } label: {
                        Text(chip)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(chipText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(colorScheme == .dark ? 0.11 : 0.88),
                                                Color.BC.primary.opacity(colorScheme == .dark ? 0.16 : 0.10)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .background(.ultraThinMaterial, in: Capsule())
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.BC.primary.opacity(colorScheme == .dark ? 0.34 : 0.22), lineWidth: 1)
                            )
                            .shadow(color: Color.BC.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(BCButtonStyle(haptic: .none))
                    .accessibilityLabel("Suggest: \(chip)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - QuickActionsBar

struct QuickActionsBar: View {
    let actions: [(title: String, icon: String, action: () -> Void)]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(actions.indices, id: \.self) { i in
                    let action = actions[i]
                    Button {
                        BCHaptic.light()
                        action.action()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: action.icon)
                                .font(.system(size: 13))
                            Text(action.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(colorScheme == .dark ? .BC.textSecondary : Color(hex: "#394A45"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.09 : 0.78),
                                            Color.black.opacity(colorScheme == .dark ? 0.20 : 0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .background(.ultraThinMaterial, in: Capsule())
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.54), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(BCButtonStyle(haptic: .none))
                    .accessibilityLabel(action.title)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04),
                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - InputBar

struct InputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    var onPhoto: ((UIImage) -> Void)? = nil
    @FocusState private var focused: Bool
    @State private var pickerItem: PhotosPickerItem?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var textColor: Color {
        colorScheme == .dark ? .BC.textPrimary : Color(hex: "#12231F")
    }

    private var placeholderColor: Color {
        colorScheme == .dark ? .BC.textSecondary : Color(hex: "#76867E")
    }

    private var controlForeground: Color {
        isEmpty ? placeholderColor : .white
    }

    var body: some View {
        HStack(spacing: 10) {
            // ── Photo picker ──────────────────────────────────────────
            if let onPhoto {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .BC.textSecondary : Color(hex: "#39534B"))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.88),
                                            Color.black.opacity(colorScheme == .dark ? 0.22 : 0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .background(.ultraThinMaterial, in: Circle())
                        )
                        .overlay(Circle().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.58), lineWidth: 1))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 9, x: 0, y: 5)
                }
                .onChange(of: pickerItem) { _, item in
                    Task {
                        guard let item,
                              let data = try? await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else { return }
                        pickerItem = nil
                        onPhoto(image)
                    }
                }
            }

            // ── Text field ────────────────────────────────────────────
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Message \(Image(systemName: "pawprint.fill"))…")
                        .font(.system(size: 15.5, weight: .medium, design: .rounded))
                        .foregroundColor(placeholderColor)
                        .padding(.horizontal, 15)
                }
                TextField("", text: $text, axis: .vertical)
                    .font(.system(size: 15.5, weight: .medium, design: .rounded))
                    .foregroundColor(textColor)
                    .lineLimit(1...5)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 2)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit {
                        if !isEmpty {
                            focused = false
                            onSend()
                        }
                    }
            }
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.14 : 0.92),
                                Color(UIColor.secondarySystemBackground).opacity(colorScheme == .dark ? 0.58 : 0.74),
                                Color.black.opacity(colorScheme == .dark ? 0.20 : 0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: focused
                                ? [Color.white.opacity(0.82), Color(hex: "#FF3B30").opacity(0.62), Color.white.opacity(0.18)]
                                : [Color.white.opacity(colorScheme == .dark ? 0.14 : 0.62), Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: focused ? 1.35 : 1
                    )
            )
            .shadow(color: focused ? Color(hex: "#FF3B30").opacity(colorScheme == .dark ? 0.20 : 0.12) : .clear,
                    radius: focused ? 14 : 0,
                    x: 0,
                    y: 0)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 12, x: 0, y: 7)
            .scaleEffect(focused && !reduceMotion ? 1.01 : 1)

            if focused {
                Button {
                    BCHaptic.soft()
                    focused = false
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.12 : 0.84),
                                        Color.black.opacity(colorScheme == .dark ? 0.24 : 0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.58), lineWidth: 1))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 9, x: 0, y: 5)
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .BC.textSecondary : Color(hex: "#39534B"))
                    }
                }
                .accessibilityLabel("Dismiss keyboard")
                .transition(.scale.combined(with: .opacity))
            }

            // ── Send button ───────────────────────────────────────────
            Button {
                BCHaptic.medium()
                focused = false
                onSend()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isEmpty
                                    ? [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.78), Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08)]
                                    : [Color(hex: "#FF766D"), Color(hex: "#F33748"), Color(hex: "#C91428")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 43, height: 43)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(isEmpty ? (colorScheme == .dark ? 0.12 : 0.48) : 0.38), lineWidth: 1)
                        )
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(Color.white.opacity(isEmpty ? 0.18 : 0.58))
                                .frame(width: 19, height: 2)
                                .padding(.top, 7)
                                .blur(radius: 0.2)
                        }
                        .shadow(color: isEmpty ? .black.opacity(colorScheme == .dark ? 0.18 : 0.08) : Color(hex: "#FF3B30").opacity(colorScheme == .dark ? 0.34 : 0.24),
                                radius: isEmpty ? 8 : 15,
                                x: 0,
                                y: isEmpty ? 4 : 8)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(controlForeground)
                }
                .scaleEffect(isEmpty || reduceMotion ? 1 : 1.05)
            }
            .disabled(isEmpty)
            .accessibilityLabel("Send message")
            .animation(BCMotion.snappy, value: isEmpty)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: focused)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .background(
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.05 : 0.34),
                        Color.black.opacity(colorScheme == .dark ? 0.26 : 0.03)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.62),
                                Color(hex: "#FF3B30").opacity(0.16),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
        )
    }
}

private struct VoiceStatusBanner: View {
    let message: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .foregroundColor(.orange)
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Neural voice needs attention")
                        .font(BCFont.headline())
                        .foregroundColor(Color.BC.primaryText)
                    Text(message)
                        .font(BCFont.body(12))
                        .foregroundColor(Color.BC.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.BC.secondaryText)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(0.12), Color.BC.surface],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .overlay(
                Rectangle()
                    .frame(width: 3)
                    .foregroundColor(.orange),
                alignment: .leading
            )
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var persona: UserPersona
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var apiKey: String = ""
    @State private var showKey: Bool = false
    @State private var keySaved: Bool = false
    @State private var providerLabel: String = "Checking…"
    @State private var refreshingAPIStatus: Bool = false
    @State private var neuralVoiceAPIKey: String = ""
    @State private var showNeuralVoiceKey: Bool = false
    @State private var neuralVoiceSaved: Bool = false
    @State private var neuralVoiceLabel: String = NeuralVoiceService.configurationSummary()
    @State private var neuralVoiceModelID: String = NeuralVoiceService.defaultModelID
    @State private var neuralVoiceIDs: [String: String] = [:]
    @State private var showAddInterests: Bool = false
    @State private var customInterestText: String = ""
    @State private var editingName: String = ""
    @State private var nameSaved: Bool = false
    @State private var showCompanionPicker: Bool = false
    @State private var showBugReporter: Bool = false
    @State private var showHelpCenter: Bool = false
    @State private var showTerms: Bool = false
    @State private var showPrivacy: Bool = false
    @State private var showDiagnosticsLog: Bool = false

    private var settingsBackground: Color {
        colorScheme == .dark ? Color.BC.background : Color(hex: "#F4F1EA")
    }
    private var settingsSurface: Color {
        colorScheme == .dark ? Color.BC.surface : Color.white
    }
    private var settingsFieldSurface: Color {
        colorScheme == .dark ? Color.BC.surfaceRaised : Color(hex: "#FAF8F3")
    }
    private var settingsPrimaryText: Color {
        colorScheme == .dark ? Color.BC.primaryText : Color(hex: "#17231F")
    }
    private var settingsSecondaryText: Color {
        colorScheme == .dark ? Color.BC.secondaryText : Color(hex: "#53645E")
    }
    private var settingsMutedText: Color {
        colorScheme == .dark ? Color.BC.textMuted : Color(hex: "#7D8A83")
    }
    private var settingsHeaderText: Color {
        colorScheme == .dark ? Color.BC.accent : Color(hex: "#1E3932")
    }
    private var settingsBorder: Color {
        colorScheme == .dark ? Color.BC.border : Color(hex: "#D5DCD4")
    }

    private func settingsHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(BCFont.caption(11).weight(.semibold))
            .foregroundColor(settingsHeaderText)
            .tracking(0.7)
    }

    var body: some View {
        NavigationStack {
            List {

                // ── AI Engine ────────────────────────────────────────────
                Section {
                    // Status row
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.BC.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Engine")
                                .font(BCFont.headline())
                                .foregroundColor(settingsPrimaryText)
                            Text(providerLabel)
                                .font(BCFont.body(13))
                                .foregroundColor(settingsSecondaryText)
                        }
                    }

                    // API key field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Claude API Key")
                            .font(BCFont.body(13))
                            .foregroundColor(settingsSecondaryText)

                        HStack {
                            Group {
                                if showKey {
                                    TextField("sk-ant-api03-…", text: $apiKey)
                                } else {
                                    SecureField("Paste your API key here", text: $apiKey)
                                }
                            }
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(settingsPrimaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundColor(settingsSecondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(settingsFieldSurface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(hasTypedClaudeKey ? Color.BC.accent : settingsBorder, lineWidth: 1))

                        Button(action: connectClaudeAPI) {
                            HStack {
                                if refreshingAPIStatus {
                                    ProgressView()
                                        .tint(hasTypedClaudeKey ? .black : settingsMutedText)
                                } else {
                                    Image(systemName: keySaved ? "checkmark.circle.fill" : "bolt.horizontal.circle.fill")
                                }
                                Text(primaryClaudeButtonTitle)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(hasTypedClaudeKey ? Color.BC.accent : settingsBorder)
                            .foregroundColor(hasTypedClaudeKey ? .black : settingsMutedText)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasTypedClaudeKey || refreshingAPIStatus)

                        Button {
                            refreshAPIStatus()
                        } label: {
                            HStack {
                                if refreshingAPIStatus {
                                    ProgressView()
                                        .tint(Color.BC.accent)
                                } else {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                }
                                Text(refreshingAPIStatus ? "Checking Claude Status…" : "Refresh Claude Status")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(settingsFieldSurface)
                            .foregroundColor(canRefreshClaudeStatus ? Color.BC.accent : settingsMutedText)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(settingsBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canRefreshClaudeStatus || refreshingAPIStatus)

                        Text("Paste an Anthropic key, then connect Claude. If credits were added later, refresh status and the app will switch back to active when Anthropic accepts the saved key.")
                            .font(BCFont.body(12))
                            .foregroundColor(settingsSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            openAnthropicConsole()
                        } label: {
                            Text("→ Get a free API key at console.anthropic.com")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                            .font(BCFont.body(12))
                            .foregroundColor(Color.BC.accent)
                    }
                    .padding(.vertical, 4)
                } header: {
                    settingsHeader("AI Engine")
                }

                Section {
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundColor(.BC.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Neural Voice")
                                .font(BCFont.headline())
                                .foregroundColor(settingsPrimaryText)
                            Text(neuralVoiceLabel)
                                .font(BCFont.body(13))
                                .foregroundColor(settingsSecondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ElevenLabs API Key")
                            .font(BCFont.body(13))
                            .foregroundColor(settingsSecondaryText)

                        HStack {
                            Group {
                                if showNeuralVoiceKey {
                                    TextField("xi-api-key", text: $neuralVoiceAPIKey)
                                } else {
                                    SecureField("Paste your ElevenLabs API key here", text: $neuralVoiceAPIKey)
                                }
                            }
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(settingsPrimaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button { showNeuralVoiceKey.toggle() } label: {
                                Image(systemName: showNeuralVoiceKey ? "eye.slash" : "eye")
                                    .foregroundColor(settingsSecondaryText)
                            }
                        }
                        .padding(10)
                        .background(settingsFieldSurface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(neuralVoiceAPIKey.count > 10 ? Color.BC.accent : settingsBorder, lineWidth: 1))

	                        TextField("Model ID, e.g. eleven_flash_v2_5", text: $neuralVoiceModelID)
	                            .font(.system(.footnote, design: .monospaced))
	                            .foregroundColor(settingsPrimaryText)
	                            .autocorrectionDisabled()
	                            .textInputAutocapitalization(.never)
	                            .padding(10)
	                            .background(settingsFieldSurface)
	                            .cornerRadius(10)
	                    }
	                    .padding(.vertical, 4)

	                    VStack(alignment: .leading, spacing: 8) {
	                        HStack(spacing: 8) {
	                            Image(systemName: "key.horizontal.fill")
	                                .foregroundColor(Color.BC.accent)
	                            Text("API key permissions")
	                                .font(BCFont.headline())
	                                .foregroundColor(settingsPrimaryText)
	                        }

	                        Text("Create the key under ElevenLabs Developers > API Keys. The key must include Text to Speech access. If ElevenLabs says missing_permissions, the key was created without text_to_speech. If it says voice not found, that voice ID is not available to the same ElevenLabs account.")
	                            .font(BCFont.body(12))
	                            .foregroundColor(settingsSecondaryText)
	                            .fixedSize(horizontal: false, vertical: true)

	                        Text("Required: text_to_speech. Recommended: voices_read, so voice IDs can be checked against the account.")
	                            .font(BCFont.body(12))
	                            .foregroundColor(settingsSecondaryText)
	                            .fixedSize(horizontal: false, vertical: true)

	                        Link("Open ElevenLabs API Keys",
	                             destination: URL(string: "https://elevenlabs.io/app/developers/api-keys")!)
	                            .font(BCFont.body(12))
	                            .foregroundColor(Color.BC.accent)
	                    }
	                    .padding(12)
	                    .background(settingsFieldSurface.opacity(0.85))
	                    .cornerRadius(10)
	                    .overlay(
	                        RoundedRectangle(cornerRadius: 10)
	                            .strokeBorder(settingsBorder, lineWidth: 1)
	                    )

	                    ForEach(CompanionPersonality.all) { companion in
	                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(companion.name)
                                    .font(BCFont.body(14))
                                    .foregroundColor(settingsPrimaryText)
                                Spacer()
                                Text(neuralVoiceDraftStatus(for: companion).label)
                                    .font(BCFont.caption(11))
                                    .foregroundColor(neuralVoiceDraftStatus(for: companion).color)
                            }
                            TextField("\(companion.name) voice_id", text: neuralVoiceIDBinding(for: companion))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(settingsPrimaryText)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(settingsFieldSurface)
                                .cornerRadius(10)
                        }
                        .padding(.vertical, 4)
                    }

                    Button(action: saveNeuralVoiceSettings) {
                        HStack {
                            Image(systemName: neuralVoiceSaved ? "checkmark.circle.fill" : "waveform.path.badge.plus")
                            Text(neuralVoiceSaved ? "Neural Voices Saved" : "Save Neural Voices")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(canSaveNeuralVoiceSettings ? Color.BC.accent : settingsBorder)
                        .foregroundColor(canSaveNeuralVoiceSettings ? .black : settingsMutedText)
                        .cornerRadius(10)
                    }
                    .disabled(!canSaveNeuralVoiceSettings)

                    if let issue = neuralVoiceBlockingIssues.first ?? neuralVoiceDraftWarnings.first {
                        Text(issue)
                            .font(BCFont.body(12))
                            .foregroundColor(.orange)
                    }

                    Link("→ Create or copy voice IDs at elevenlabs.io",
                         destination: URL(string: "https://elevenlabs.io/app/voice-library")!)
                        .font(BCFont.body(12))
                        .foregroundColor(Color.BC.accent)
                } header: {
                    settingsHeader("Neural Voice")
                } footer: {
                    Text("Apple local speech is not used. Each personality needs its own licensed, cloned, or designed ElevenLabs voice ID so Luna, Aria, Kel, Marco, Dante, and Kai stay sandboxed with no voice bleed-through.")
                        .font(BCFont.footnote())
                        .foregroundColor(settingsSecondaryText)
                }

                // Profile
                Section {
                    // Editable name row
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundColor(Color.BC.accent)
                            .frame(width: 22)
                        TextField("Your name", text: $editingName)
                            .foregroundColor(settingsPrimaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .onSubmit { saveName() }
                        if editingName != persona.userName && !editingName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(action: saveName) {
                                Image(systemName: nameSaved ? "checkmark.circle.fill" : "checkmark.circle")
                                    .foregroundColor(nameSaved ? Color.BC.success : Color.BC.accent)
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .animation(.spring(response: 0.25), value: editingName)
                    HStack {
                        Text("Assistant Name")
                            .foregroundColor(settingsPrimaryText)
                        Spacer()
                        Text(persona.assistantName.isEmpty ? persona.selectedCompanion.name : persona.assistantName)
                            .foregroundColor(settingsSecondaryText)
                    }
                } header: {
                    settingsHeader("Profile")
                } footer: {
                    Text("Type a new name and tap ✓ or press Return to save. Your companion will use it immediately.")
                        .font(BCFont.footnote())
                        .foregroundColor(settingsSecondaryText)
                }

                // ── Companion ─────────────────────────────────────────────
                Section {
                    Button {
                        showCompanionPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(persona.selectedCompanion.accentColor.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Text(String(persona.selectedCompanion.name.prefix(1)))
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(persona.selectedCompanion.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(persona.selectedCompanion.name)
                                    .font(BCFont.headline())
                                    .foregroundColor(settingsPrimaryText)
                                Text(persona.selectedCompanion.tagline)
                                    .font(BCFont.body(12))
                                    .foregroundColor(settingsSecondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(settingsSecondaryText.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    settingsHeader("Companion")
                } footer: {
                    Text("Switching companion starts a fresh conversation with your new companion. Your history with each companion is saved separately.")
                        .font(BCFont.footnote())
                        .foregroundColor(settingsSecondaryText)
                }
                // Relationship mode
                Section {
                    ForEach(RelationshipMode.displayOrder) { mode in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                persona.relationshipMode = mode
                                persona.save()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(mode.emoji)
                                    .font(.title3)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.label)
                                        .font(BCFont.headline())
                                        .foregroundColor(settingsPrimaryText)
                                    Text(mode.description)
                                        .font(BCFont.body(12))
                                        .foregroundColor(settingsSecondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                if persona.relationshipMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color.BC.accent)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    settingsHeader("Relationship Mode")
                } footer: {
                    Text("Changes how your companion relates to you. Takes effect on the next message.")
                        .font(BCFont.footnote())
                        .foregroundColor(settingsSecondaryText)
                }

                // Communication style
                Section {
                    ForEach(CommunicationStyle.allCases) { style in
                        HStack {
                            Text(style.rawValue.capitalized)
                                .foregroundColor(settingsPrimaryText)
                            Spacer()
                            if persona.style == style {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color.BC.primary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { persona.style = style; persona.save() }
                    }
                } header: {
                    settingsHeader("Communication Style")
                }

                // ── Interests ──────────────────────────────────────────
                Section {
                    // Existing interests — swipe to delete or toggle notifications
                    ForEach(persona.interests) { interest in
                        HStack(spacing: 10) {
                            Text(interest.emoji).font(.system(size: 18))
                            Text(interest.label)
                                .foregroundColor(settingsPrimaryText)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { interest.notificationsEnabled },
                                set: { val in
                                    if let idx = persona.interests.firstIndex(where: { $0.id == interest.id }) {
                                        persona.interests[idx].notificationsEnabled = val
                                        persona.save()
                                        Task {
                                            await HermesInterestEngine.shared
                                                .syncSelectedInterests(for: persona, source: "settings_interest_notification")
                                            await HermesInterestEngine.shared
                                                .scheduleInterestNotifications(for: persona)
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(Color.BC.primary)

                            Button(role: .destructive) {
                                withAnimation { persona.removeInterest(id: interest.id); persona.save() }
                                Task {
                                    await HermesInterestEngine.shared
                                        .syncSelectedInterests(for: persona, source: "settings_interest_removed")
                                    await HermesInterestEngine.shared
                                        .scheduleInterestNotifications(for: persona)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.8))
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    if persona.interests.isEmpty && !showAddInterests {
                        Text("No interests yet — add some below or chat to add more.")
                            .foregroundColor(settingsSecondaryText)
                            .font(BCFont.footnote())
                    }

                    // Toggle add panel
                    Button {
                        withAnimation(.spring(response: 0.35)) { showAddInterests.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: showAddInterests ? "minus" : "plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text(showAddInterests ? "Done adding" : "Add an interest")
                                .font(BCFont.body(13))
                        }
                        .foregroundColor(Color.BC.accent)
                    }

                    // Expandable add-interest panel
                    if showAddInterests {
                        InterestPickerPanel(persona: persona, customText: $customInterestText)
                    }

                } header: {
                    settingsHeader("Interests (\(persona.interests.count))")
                } footer: {
                    Text("Your companion uses these to bring up what you love, send updates, and make conversations feel personal.")
                        .font(BCFont.footnote())
                        .foregroundColor(settingsSecondaryText)
                }

                // Affirmations
                Section {
                    Toggle("Enabled", isOn: $persona.dailyAffirmationsEnabled)
                        .tint(Color.BC.primary)
                        .onChange(of: persona.dailyAffirmationsEnabled) {
                            persona.save()
                            Task {
                                await HermesPersonality.shared.scheduleDailyAffirmation(for: persona)
                            }
                        }
                    if persona.dailyAffirmationsEnabled {
                        DatePicker("Time", selection: $persona.affirmationTime, displayedComponents: .hourAndMinute)
                            .foregroundColor(settingsPrimaryText)
                            .onChange(of: persona.affirmationTime) {
                                persona.save()
                                Task {
                                    await HermesPersonality.shared.scheduleDailyAffirmation(for: persona)
                                }
                            }
                    }
                } header: {
                    settingsHeader("Daily Affirmation")
                }

                // ── Companion Tracking ──────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.BC.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dynamic Tracking")
                                    .font(BCFont.headline())
                                    .foregroundColor(settingsPrimaryText)
                                Text("Master switch for proactive companion signals.")
                                    .font(BCFont.body(12))
                                    .foregroundColor(settingsSecondaryText)
                            }
                            Spacer()
                            Toggle("", isOn: $persona.trackingPermissions.dynamicSignalsEnabled)
                                .labelsHidden()
                                .tint(Color.BC.accent)
                                .onChange(of: persona.trackingPermissions.dynamicSignalsEnabled) {
                                    persona.save()
                                    DiagnosticsLog.info(
                                        "permissions",
                                        "Dynamic tracking changed.",
                                        details: [
                                            "enabled": "\(persona.trackingPermissions.dynamicSignalsEnabled)",
                                            "companion": persona.selectedCompanionID
                                        ]
                                    )
                                    Task {
                                        await CompanionDataTracker.shared.updatePermissions(
                                            persona.trackingPermissions,
                                            persona: persona
                                        )
                                    }
                                }
                        }
                        Text("When this is off, BareClaw cancels tracking notifications and ignores ambient, chat-derived, and app-context opportunities for proactive personalization.")
                            .font(BCFont.body(12))
                            .foregroundColor(settingsSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 40)
                    }
                    .padding(.vertical, 3)

                    Group {
                        trackingRow("Calendar & Events", icon: "calendar", color: .purple,
                                    detail: "Pre/post event check-ins. Emotional support around interviews, medical appointments, dates, and deadlines.",
                                    enabled: $persona.trackingPermissions.calendarEnabled,
                                    requestsSystemAccessOnEnable: true)

                        trackingRow("Messages", icon: "message.fill", color: .green,
                                    detail: "Helps with texts you bring into chat. Companion learns who matters from what you choose to share.",
                                    enabled: $persona.trackingPermissions.messagesEnabled)

                        trackingRow("Email", icon: "envelope.fill", color: .blue,
                                    detail: "Helps with emails you bring into chat. Companion learns about your work from what you choose to share.",
                                    enabled: $persona.trackingPermissions.emailEnabled)

                        trackingRow("Location Routines", icon: "location.fill", color: .red,
                                    detail: "Time-aware suggestions around routines and places you choose to share.",
                                    enabled: $persona.trackingPermissions.locationEnabled)

                        trackingRow("Browsing", icon: "safari.fill", color: .orange,
                                    detail: "Remembers articles, products, and topics you choose to mention.",
                                    enabled: $persona.trackingPermissions.browsingEnabled)
                    }
                    .disabled(!persona.trackingPermissions.dynamicSignalsEnabled)
                    .opacity(persona.trackingPermissions.dynamicSignalsEnabled ? 1 : 0.45)

                } header: {
                    settingsHeader("Companion Tracking")
                } footer: {
                    Text("Calendar can create real event-based check-ins. Email, Messages, Browsing, and Location are personalization areas based on what you choose to share in chat, not background data reads. Dynamic Tracking must stay on for any proactive tracking to run.")
                        .font(BCFont.footnote())
                        .foregroundColor(settingsSecondaryText)
                }

	                Section {
	                    settingsLinkRow("Diagnostics Log", systemImage: "waveform.path.ecg", color: .BC.accent) {
	                        showDiagnosticsLog = true
	                    }
	                    settingsLinkRow("Report Bug", systemImage: "ladybug.fill", color: .red) {
	                        showBugReporter = true
	                    }
                    settingsLinkRow("Help Center", systemImage: "questionmark.circle", color: .BC.accent) {
                        showHelpCenter = true
                    }
                    settingsLinkRow("Terms of Use", systemImage: "doc.text", color: .BC.secondaryText) {
                        showTerms = true
                    }
                    settingsLinkRow("Privacy Policy", systemImage: "lock.shield", color: .BC.secondaryText) {
                        showPrivacy = true
                    }
                    HStack {
                        Text("Version")
                            .foregroundColor(settingsPrimaryText)
                        Spacer()
                        Text(appVersionText)
                            .foregroundColor(settingsSecondaryText)
                    }
                    HStack {
                        Text("Memory entries")
                            .foregroundColor(settingsPrimaryText)
                        Spacer()
                        MemoryCountBadge()
                    }
                } header: {
                    settingsHeader("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(settingsBackground)
            .listRowBackground(settingsSurface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Auto-save key if one is present — no separate tap needed
                        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
                        if trimmed.count > 20 {
                            KeychainHelper.write(service: "com.bareclaw.bareclaw",
                                                 key: "anthropic_api_key",
                                                 value: trimmed)
                        }
                        dismiss()
                    }
                    .foregroundColor(Color.BC.primary)
                }
            }
        }
        .onAppear { loadCurrentKey() }
        .sheet(isPresented: $showCompanionPicker) {
            NavigationStack {
                CompanionSelectionView(persona: persona)
                    .navigationTitle("Choose Companion")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showCompanionPicker = false }
                                .foregroundColor(Color.BC.primary)
                        }
                    }
            }
        }
        .sheet(isPresented: $showBugReporter) {
            BugReportView()
        }
        .sheet(isPresented: $showDiagnosticsLog) {
            DiagnosticsLogView()
        }
        .sheet(isPresented: $showHelpCenter) {
            LegalTextView(
                title: "Help Center",
                intro: "Fast answers for setting up BareClaw and keeping the companion connected.",
                sections: BareClawLegalContent.helpSections
            )
        }
        .sheet(isPresented: $showTerms) {
            LegalTextView(
                title: "Terms of Use",
                intro: "These terms are intentionally broad and plain-language. By using BareClaw, you agree to use it responsibly and understand its limits.",
                sections: BareClawLegalContent.termsSections
            )
        }
        .sheet(isPresented: $showPrivacy) {
            LegalTextView(
                title: "Privacy Policy",
                intro: "BareClaw is built to keep personal data on your device unless you choose to connect outside services.",
                sections: BareClawLegalContent.privacySections
            )
        }
    }

    // Tracking permission toggle row — updates tracker immediately on change
    @ViewBuilder
    private func trackingRow(
        _ label: String, icon: String, color: Color,
        detail: String, enabled: Binding<Bool>,
        requestsSystemAccessOnEnable: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 28)
                Text(label)
                    .foregroundColor(settingsPrimaryText)
                Spacer()
                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .tint(color)
	                    .onChange(of: enabled.wrappedValue) {
	                        persona.save()
	                        DiagnosticsLog.info(
	                            "permissions",
	                            "Settings tracking permission changed.",
	                            details: [
	                                "label": label,
	                                "enabled": "\(enabled.wrappedValue)",
	                                "email": "\(persona.trackingPermissions.emailEnabled)",
	                                "messages": "\(persona.trackingPermissions.messagesEnabled)",
	                                "browsing": "\(persona.trackingPermissions.browsingEnabled)",
	                                "location": "\(persona.trackingPermissions.locationEnabled)",
	                                "calendar": "\(persona.trackingPermissions.calendarEnabled)",
                                    "dynamic": "\(persona.trackingPermissions.dynamicSignalsEnabled)"
	                            ]
	                        )
                        let shouldRequestSystemAccess = requestsSystemAccessOnEnable
                            && enabled.wrappedValue
                            && persona.trackingPermissions.dynamicSignalsEnabled
                        Task {
                            await CompanionDataTracker.shared.updatePermissions(
                                persona.trackingPermissions,
                                persona: persona,
                                requestSystemAccess: shouldRequestSystemAccess
                            )
                        }
                    }
            }
            if enabled.wrappedValue {
                Text(detail)
                    .font(BCFont.body(12))
                    .foregroundColor(settingsSecondaryText)
                    .padding(.leading, 40)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3), value: enabled.wrappedValue)
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private func settingsLinkRow(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 26)
                Text(title)
                    .foregroundColor(settingsPrimaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(settingsSecondaryText.opacity(0.65))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canSaveNeuralVoiceSettings: Bool {
        (neuralVoiceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).count > 10 || hasAnyDraftVoiceID)
            && neuralVoiceBlockingIssues.isEmpty
    }

    private var hasAnyDraftVoiceID: Bool {
        cleanedDraftVoiceIDs.values.contains { !$0.isEmpty }
    }

    private func neuralVoiceIDBinding(for companion: CompanionPersonality) -> Binding<String> {
        Binding(
            get: { neuralVoiceIDs[companion.id, default: ""] },
            set: { neuralVoiceIDs[companion.id] = $0 }
        )
    }

    private var cleanedDraftVoiceIDs: [String: String] {
        Dictionary(uniqueKeysWithValues: CompanionPersonality.all.map {
            ($0.id, NeuralVoiceService.cleanedVoiceID(neuralVoiceIDs[$0.id, default: ""]))
        })
    }

    private var duplicateDraftVoiceIDs: Set<String> {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for id in cleanedDraftVoiceIDs.values where !id.isEmpty {
            let normalized = id.lowercased()
            if seen.contains(normalized) {
                duplicates.insert(normalized)
            } else {
                seen.insert(normalized)
            }
        }
        return duplicates
    }

    private var neuralVoiceDraftIssues: [String] {
        neuralVoiceDraftWarnings + neuralVoiceBlockingIssues
    }

    private var neuralVoiceDraftWarnings: [String] {
        var issues: [String] = []
        for companion in CompanionPersonality.all {
            let id = cleanedDraftVoiceID(for: companion)
            if id.isEmpty {
                issues.append("\(companion.name) still needs its own ElevenLabs voice ID.")
            }
        }
        return issues
    }

    private var neuralVoiceBlockingIssues: [String] {
        var issues: [String] = []
        for companion in CompanionPersonality.all {
            let id = cleanedDraftVoiceID(for: companion)
            if id.isEmpty {
                continue
            } else if !NeuralVoiceService.isValidVoiceID(id) {
                issues.append("\(companion.name)'s voice ID does not look valid.")
            } else if duplicateDraftVoiceIDs.contains(id.lowercased()) {
                issues.append("\(companion.name)'s voice ID is duplicated. Each companion needs a unique voice.")
            }
        }
        return issues
    }

    private func cleanedDraftVoiceID(for companion: CompanionPersonality) -> String {
        NeuralVoiceService.cleanedVoiceID(neuralVoiceIDs[companion.id, default: ""])
    }

    private func neuralVoiceDraftStatus(for companion: CompanionPersonality) -> (label: String, color: Color) {
        let id = cleanedDraftVoiceID(for: companion)
        if id.isEmpty {
            return ("Missing voice ID", .orange)
        }
        if !NeuralVoiceService.isValidVoiceID(id) {
            return ("Invalid voice ID", .red)
        }
        if duplicateDraftVoiceIDs.contains(id.lowercased()) {
            return ("Duplicate voice", .red)
        }
        return ("Separate voice", Color.BC.success)
    }

    private func loadNeuralVoiceSettings() {
        neuralVoiceAPIKey = NeuralVoiceService.readAPIKey() ?? ""
        neuralVoiceModelID = NeuralVoiceService.configuredModelID
        neuralVoiceIDs = Dictionary(uniqueKeysWithValues: CompanionPersonality.all.map {
            ($0.id, NeuralVoiceService.configuredVoiceID(for: $0.id) ?? "")
        })
        neuralVoiceLabel = NeuralVoiceService.configurationSummary()
    }

	    private func saveNeuralVoiceSettings() {
	        let trimmedKey = neuralVoiceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
	        guard neuralVoiceBlockingIssues.isEmpty, trimmedKey.count > 10 || hasAnyDraftVoiceID else {
	            neuralVoiceLabel = neuralVoiceBlockingIssues.first ?? "Add an ElevenLabs API key or at least one voice ID."
	            DiagnosticsLog.warning("settings", "Neural voice settings were not saved.", details: ["issue": neuralVoiceLabel])
	            return
	        }

        if trimmedKey.count > 10 {
            NeuralVoiceService.saveAPIKey(trimmedKey)
        }
        NeuralVoiceService.saveModelID(neuralVoiceModelID)
        for companion in CompanionPersonality.all {
            NeuralVoiceService.saveVoiceID(cleanedDraftVoiceID(for: companion), for: companion.id)
        }
        neuralVoiceIDs = Dictionary(uniqueKeysWithValues: CompanionPersonality.all.map {
            ($0.id, NeuralVoiceService.configuredVoiceID(for: $0.id) ?? "")
        })
	        CompanionVoiceEngine.shared.clearLastVoiceError()
	        neuralVoiceLabel = NeuralVoiceService.configurationSummary()
	        DiagnosticsLog.info(
	            "settings",
	            "Neural voice settings saved.",
	            details: [
	                "hasAPIKey": "\(trimmedKey.count > 10)",
	                "configuredVoices": "\(CompanionPersonality.all.filter { NeuralVoiceService.configuredVoiceID(for: $0.id) != nil }.count)"
	            ]
	        )

	        withAnimation { neuralVoiceSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { neuralVoiceSaved = false }
        }
    }

    private func saveName() {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != persona.userName else { return }
        persona.userName = trimmed
        persona.save()
        // Burn the updated name into memory at highest importance so it
        // propagates into every future LLM system prompt immediately.
        Task {
            _ = try? await HermesMemory.shared.observe(
                category: "core_identity",
                content: ["key": "name", "value": trimmed],
                metadata: ["importance": 10, "permanent": true, "source": "settings_edit"]
            )
        }
        withAnimation {
            nameSaved = true
            editingName = trimmed
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { nameSaved = false }
        }
    }

    private func loadCurrentKey() {
        editingName = persona.userName
        loadNeuralVoiceSettings()
        // Show masked existing key if present
        if let existing = KeychainHelper.read(service: "com.bareclaw.bareclaw",
                                               key: "anthropic_api_key"), !existing.isEmpty {
            apiKey = existing
        }
        Task {
            await HermesLLMClient.shared.configure()
            let status = await HermesLLMClient.shared.apiStatus
            let p = await HermesLLMClient.shared.provider
            await MainActor.run {
                providerLabel = status == .unknown ? Self.providerLabel(for: p) : status.settingsLabel
            }
        }
    }

    private var cleanedClaudeAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasTypedClaudeKey: Bool {
        cleanedClaudeAPIKey.count > 20
    }

    private var canRefreshClaudeStatus: Bool {
        hasTypedClaudeKey || (KeychainHelper.read(service: "com.bareclaw.bareclaw", key: "anthropic_api_key")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count ?? 0) > 20
    }

    private var primaryClaudeButtonTitle: String {
        if refreshingAPIStatus { return "Connecting Claude..." }
        if keySaved { return "Claude Active" }
        return "Connect Claude"
    }

    private func connectClaudeAPI() {
        saveClaudeKeyIfPresent()
        guard hasTypedClaudeKey else { return }
        refreshAPIStatus(markSavedOnSuccess: true)
    }

    private func openAnthropicConsole() {
        guard let url = URL(string: "https://console.anthropic.com") else { return }
        UIApplication.shared.open(url)
    }

    private func saveClaudeKeyIfPresent() {
        let trimmed = cleanedClaudeAPIKey
        guard trimmed.count > 20 else { return }
        KeychainHelper.write(service: "com.bareclaw.bareclaw",
                             key: "anthropic_api_key",
                             value: trimmed)
        DiagnosticsLog.info("settings", "Claude API key saved from Settings.")
    }

    private func refreshAPIStatus(markSavedOnSuccess: Bool = false) {
        saveClaudeKeyIfPresent()

        refreshingAPIStatus = true
        keySaved = false
        providerLabel = markSavedOnSuccess ? "Connecting Claude API..." : "Checking Claude API..."
        DiagnosticsLog.info("settings", "Claude API status refresh requested.")

        Task {
            await HermesPrivacyGate.shared.acceptCloudAI()
            let status = await HermesLLMClient.shared.refreshAPIKeyInformation()
            await MainActor.run {
                providerLabel = status.settingsLabel
                refreshingAPIStatus = false
                if markSavedOnSuccess, case .active(_) = status {
                    BCHaptic.success()
                    keySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
                } else if markSavedOnSuccess {
                    BCHaptic.error()
                }
            }
        }
    }

    private static func providerLabel(for provider: LLMProvider) -> String {
        switch provider {
        case .appleFoundationModels: return "Apple Intelligence (on-device)"
        case .claudeAPI:             return "Claude API — active ✓"
        case .ollamaGLM, .ollamaClaude: return "Ollama — active ✓"
        case .none:                  return "Not configured — add your API key below"
        }
    }
}

private struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var summary: String = ""
    @State private var details: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isLoadingPhoto: Bool = false
    @State private var showMailComposer: Bool = false
    @State private var showMailUnavailableAlert: Bool = false

    private let supportEmail = "mvalasek77@gmail.com"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Send a Bug Report")
                            .font(BCFont.title())
                            .foregroundColor(Color.BC.primaryText)
                        Text("This opens an email to support. Add a screenshot or photo if it helps show the issue.")
                            .font(BCFont.body(14))
                            .foregroundColor(Color.BC.secondaryText)
                        Text("BareClaw automatically attaches the recent diagnostics log so support can see Claude, voice, notification, Vibes, and runtime failures without needing Xcode.")
                            .font(BCFont.body(12))
                            .foregroundColor(Color.BC.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What happened?")
                            .font(BCFont.headline())
                            .foregroundColor(Color.BC.primaryText)
                        TextField("Short summary", text: $summary)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.BC.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(BCFont.headline())
                            .foregroundColor(Color.BC.primaryText)
                        TextField("Steps, screen, error message, what you expected", text: $details, axis: .vertical)
                            .lineLimit(5...10)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.BC.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: 12) {
                            Image(systemName: selectedPhotoData == nil ? "photo.badge.plus" : "checkmark.circle.fill")
                                .foregroundColor(selectedPhotoData == nil ? Color.BC.accent : Color.BC.success)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedPhotoData == nil ? "Attach Photo or Screenshot" : "Photo attached")
                                    .font(BCFont.headline())
                                    .foregroundColor(Color.BC.primaryText)
                                Text(isLoadingPhoto ? "Loading image..." : "Optional, but useful for UI bugs.")
                                    .font(BCFont.body(12))
                                    .foregroundColor(Color.BC.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.BC.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .onChange(of: selectedPhoto) { _, newPhoto in
                        Task { await loadSelectedPhoto(newPhoto) }
                    }

                    Button(action: sendBugReport) {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send Bug Report")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.BC.accent)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isLoadingPhoto)

                    Text("Sent to \(supportEmail). Bug reports are only sent when you tap this button.")
                        .font(BCFont.body(12))
                        .foregroundColor(Color.BC.secondaryText)
                }
                .padding(20)
            }
            .background(Color.BC.background.ignoresSafeArea())
            .navigationTitle("Report Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.BC.primary)
                }
            }
        }
        .sheet(isPresented: $showMailComposer) {
            MailComposeView(
                recipients: [supportEmail],
                subject: mailSubject,
                body: mailBody,
                attachments: mailAttachments
            ) {
                dismiss()
            }
        }
        .alert("Mail is not configured", isPresented: $showMailUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Set up Apple Mail on this iPhone to send the report with a photo attachment. You can also email \(supportEmail) manually.")
        }
    }

    private var mailSubject: String {
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanSummary.isEmpty ? "BareClaw Bug Report" : "BareClaw Bug Report: \(cleanSummary)"
    }

    private var mailBody: String {
        let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let diagnosticsAttached = DiagnosticsLog.snapshotData() != nil

        return """
        BareClaw Bug Report

        Summary:
        \(cleanSummary.isEmpty ? "Not provided" : cleanSummary)

        Details:
        \(cleanDetails.isEmpty ? "Not provided" : cleanDetails)

        App:
        Version \(version) (\(build))

        Device:
        \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)

        Photo attached:
        \(selectedPhotoData == nil ? "No" : "Yes")

        Diagnostics attached:
        \(diagnosticsAttached ? "Yes" : "No")
        """
    }

    private var mailAttachments: [MailAttachment] {
        var attachments: [MailAttachment] = []
        if let selectedPhotoData {
            attachments.append(MailAttachment(
                data: selectedPhotoData,
                mimeType: "image/jpeg",
                fileName: "bareclaw-bug-photo.jpg"
            ))
        }
        if let diagnostics = DiagnosticsLog.snapshotData() {
            attachments.append(MailAttachment(
                data: diagnostics,
                mimeType: "application/json",
                fileName: "bareclaw-diagnostics.jsonl"
            ))
        }
        return attachments
    }

    @MainActor
    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            selectedPhotoData = nil
            return
        }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        selectedPhotoData = try? await item.loadTransferable(type: Data.self)
    }

    private func sendBugReport() {
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else {
            showMailUnavailableAlert = true
        }
    }
}

private struct MailAttachment {
    let data: Data
    let mimeType: String
    let fileName: String
}

private struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachments: [MailAttachment]
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        for attachment in attachments {
            controller.addAttachmentData(
                attachment.data,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onFinish()
            }
        }
    }
}

private struct DiagnosticsLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText: String = DiagnosticsLog.recentText()
    @State private var copied: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent App Diagnostics")
                        .font(BCFont.title())
                        .foregroundColor(Color.BC.primaryText)
                    Text("This local log records app lifecycle, Claude/API status, ElevenLabs voice failures, notification handoffs, Vibes refreshes, and chat runtime errors. API keys and tokens are redacted.")
                        .font(BCFont.body(13))
                        .foregroundColor(Color.BC.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                ScrollView {
                    Text(logText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(Color.BC.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                }
                .background(Color.BC.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 18)

                HStack(spacing: 10) {
                    Button {
                        logText = DiagnosticsLog.recentText()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        UIPasteboard.general.string = logText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        DiagnosticsLog.clear()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            logText = DiagnosticsLog.recentText()
                        }
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
                .font(BCFont.body(13))
                .buttonStyle(.bordered)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            .background(Color.BC.background.ignoresSafeArea())
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.BC.primary)
                }
            }
        }
    }
}

private struct LegalTextView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let intro: String
    let sections: [LegalSection]

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 700
            let sideInset: CGFloat = isWide ? 48 : 20
            let availableWidth = max(320, geometry.size.width - sideInset * 2)
            let contentWidth = isWide ? min(availableWidth, 900) : availableWidth
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
                count: isWide ? 2 : 1
            )

            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: isWide ? 22 : 18) {
                        Text(intro)
                            .font(BCFont.body(isWide ? 16 : 15))
                            .foregroundColor(Color.BC.secondaryText)
                            .lineSpacing(isWide ? 4 : 0)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(isWide ? 22 : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isWide ? Color.BC.surface.opacity(0.9) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: isWide ? 22 : 0))

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                            ForEach(sections) { section in
                                legalSection(section, isWide: isWide)
                            }
                        }
                    }
                    .frame(maxWidth: contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, sideInset)
                    .padding(.vertical, isWide ? 30 : 20)
                }
                .background(Color.BC.background.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundColor(Color.BC.primary)
                    }
                }
            }
        }
    }

    private func legalSection(_ section: LegalSection, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(BCFont.headline(isWide ? 17 : 16))
                .foregroundColor(Color.BC.primaryText)
            Text(section.body)
                .font(BCFont.body(14))
                .foregroundColor(Color.BC.secondaryText)
                .lineSpacing(isWide ? 5 : 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(isWide ? 18 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.BC.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: isWide ? 18 : 16))
    }
}

struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

enum BareClawLegalContent {
    static let helpSections: [LegalSection] = [
        LegalSection(
            title: "Connect the AI brain",
            body: "Open Settings > AI Engine, paste your Claude API key, then tap Connect Claude. If the key was already saved but replies fail, tap Refresh Claude Status after adding credits from Anthropic."
        ),
        LegalSection(
            title: "Set up neural voices",
            body: "Open Settings > Neural Voice, add your ElevenLabs API key, and give every companion a unique voice ID. Each personality needs its own voice ID so voices stay sandboxed and do not bleed into each other."
        ),
        LegalSection(
            title: "Bond points and learning",
            body: "Bond points increase when you share meaningful context, add interests, write dream journal entries, and heart vibe songs. The purpose is to help the companion learn your patterns, preferences, stress signals, and love-language cues."
        ),
        LegalSection(
            title: "Him / Her Mode",
            body: "Him / Her Mode unlocks at Deep Connection. It needs microphone and speech permission, and the app must be open for active listening. You can revoke microphone permission in iOS Settings at any time."
        ),
        LegalSection(
            title: "Report a bug",
            body: "Use Settings > About > Report Bug. Add a short summary, details, and a screenshot or photo when available. The report opens an email addressed to mvalasek77@gmail.com."
        )
    ]

    static let privacySections: [LegalSection] = [
        LegalSection(
            title: "What BareClaw does not collect",
            body: "BareClaw does not run a BareClaw-owned analytics server, advertising tracker, or resale pipeline for your personal data. BareClaw does not sell your data."
        ),
        LegalSection(
            title: "Local app data",
            body: "Your profile, selected companion, interests, memories, dream journal entries, bond points, tracking choices, voice IDs, and conversation history are stored locally on your device so the companion can feel personal."
        ),
        LegalSection(
            title: "Third-party AI and voice providers",
            body: "If you add a Claude API key, the text needed to answer you may be sent to Anthropic under Anthropic's terms and privacy policy. If you add an ElevenLabs API key or voice IDs, text-to-speech requests may be sent to ElevenLabs under their terms and privacy policy."
        ),
        LegalSection(
            title: "Permissions",
            body: "Microphone and speech permissions are used for voice and Him / Her Mode. Notifications are used for reminders and check-ins. Calendar, location, email, messages, browsing, and similar settings only affect features you enable or information you choose to share, unless iOS grants an explicit permission."
        ),
        LegalSection(
            title: "Bug reports",
            body: "Bug reports are only sent when you choose to send them. If you attach a photo or screenshot, that attachment and your written notes are sent to mvalasek77@gmail.com."
        ),
        LegalSection(
            title: "Control and deletion",
            body: "You can change tracking choices in Settings, revoke permissions in iOS Settings, remove API keys, or delete the app to remove local app data from the device."
        )
    ]

    static let termsSections: [LegalSection] = [
        LegalSection(
            title: "Use of the app",
            body: "BareClaw is an AI companion app for conversation, reflection, personalization, reminders, voice, music discovery, and relationship-style interaction. You agree to use it lawfully and not to use it to harm yourself, others, or systems."
        ),
        LegalSection(
            title: "AI companion limits",
            body: "Companion interactions are generated by software. The companion may feel personal, but it is not a real person and may make mistakes. Do not rely on BareClaw for medical, legal, financial, emergency, safety-critical, or professional advice."
        ),
        LegalSection(
            title: "API keys and provider costs",
            body: "You are responsible for your Claude, ElevenLabs, and other third-party accounts, keys, permissions, availability, billing, credits, rate limits, and provider terms. BareClaw cannot guarantee those services will always work."
        ),
        LegalSection(
            title: "Your content",
            body: "You are responsible for the text, audio, photos, screenshots, interests, journal entries, and other content you add. You give BareClaw permission to process that content on-device and through enabled providers so the app can provide its features."
        ),
        LegalSection(
            title: "Availability and changes",
            body: "BareClaw is provided as-is and may change, break, lose access to providers, or be unavailable. Features may be updated, removed, or changed as the app improves."
        ),
        LegalSection(
            title: "Liability",
            body: "To the fullest extent allowed by law, BareClaw is not liable for indirect, incidental, special, consequential, or punitive damages, or for losses caused by AI output, provider outages, user content, device settings, or third-party services."
        ),
        LegalSection(
            title: "Contact",
            body: "For bugs, privacy questions, or terms questions, contact mvalasek77@gmail.com."
        )
    ]
}

// MARK: - InterestPickerPanel
//
// Used inside SettingsView to add interests from a preset grid or freeform text.
// Mirrors the onboarding InterestsStep so the two stay in sync.

private struct InterestPickerPanel: View {
    @ObservedObject var persona: UserPersona
    @Binding var customText: String

    private let presets: [Interest] = [
        Interest(id: "movies",         category: .movies,   label: "Movies & TV",  emoji: "🎬"),
        Interest(id: "sports_nba",     category: .sports,   label: "NBA",          emoji: "🏀"),
        Interest(id: "sports_nfl",     category: .sports,   label: "NFL",          emoji: "🏈"),
        Interest(id: "music",          category: .music,    label: "Music",        emoji: "🎵"),
        Interest(id: "fitness",        category: .fitness,  label: "Fitness",      emoji: "💪"),
        Interest(id: "food_starbucks", category: .food,     label: "Starbucks",    emoji: "☕️"),
        Interest(id: "travel",         category: .travel,   label: "Travel",       emoji: "✈️"),
        Interest(id: "gaming",         category: .gaming,   label: "Gaming",       emoji: "🎮"),
        Interest(id: "tech",           category: .tech,     label: "Tech",         emoji: "⚡️"),
        Interest(id: "finance",        category: .finance,  label: "Investing",    emoji: "📈"),
        Interest(id: "books",          category: .books,    label: "Books",        emoji: "📚"),
        Interest(id: "pets",           category: .pets,     label: "Pets",         emoji: "🐾"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Preset chips — greyed out if already added
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(presets) { preset in
                    let already = persona.interests.contains(where: { $0.id == preset.id })
                    Button {
                        guard !already else { return }
                        withAnimation(.spring(response: 0.25)) {
                            persona.addInterest(preset)
                            persona.save()
                            Task {
                                await HermesInterestEngine.shared
                                    .syncSelectedInterests(for: persona, source: "settings_interest_added")
                                await HermesInterestEngine.shared
                                    .scheduleInterestNotifications(for: persona)
                            }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text(preset.emoji).font(.title3)
                            Text(preset.label)
                                .font(BCFont.caption(10))
                                .foregroundColor(already ? Color.BC.textMuted : Color.BC.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(already ? Color.BC.surface.opacity(0.4) : Color.BC.accentSoft)
                        .cornerRadius(BCSizing.radiusMD)
                        .overlay(
                            RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                                .strokeBorder(
                                    already ? Color.BC.border.opacity(0.4) : Color.BC.accent,
                                    lineWidth: already ? 0.5 : 1.5
                                )
                        )
                        .opacity(already ? 0.45 : 1)
                    }
                    .disabled(already)
                }
            }

            // Custom interest field
            HStack(spacing: 8) {
                TextField("Add your own (e.g. Marvel, Arsenal...)", text: $customText)
                    .font(BCFont.body(13))
                    .foregroundColor(Color.BC.textPrimary)
                    .autocorrectionDisabled()

                Button {
                    let t = customText.trimmingCharacters(in: .whitespaces)
                    guard t.count > 1 else { return }
                    let newInterest = Interest(
                        id: "custom_\(t.lowercased().replacingOccurrences(of: " ", with: "_"))",
                        category: .other,
                        label: t,
                        emoji: "⭐️"
                    )
                    withAnimation {
                        persona.addInterest(newInterest)
                        persona.save()
                        customText = ""
                        Task {
                            await HermesInterestEngine.shared
                                .syncSelectedInterests(for: persona, source: "settings_custom_interest_added")
                            await HermesInterestEngine.shared
                                .scheduleInterestNotifications(for: persona)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(customText.count > 1 ? Color.BC.accent : Color.BC.border)
                }
                .disabled(customText.count < 2)
            }
            .padding(10)
            .background(Color.BC.surface)
            .cornerRadius(BCSizing.radiusMD)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - MemoryCountBadge

struct MemoryCountBadge: View {
    @State private var count = 0

    var body: some View {
        Text("\(count)")
            .foregroundColor(Color.BC.secondaryText)
            .task {
                let entries = await HermesMemory.shared.allEntries()
                count = entries.count
            }
    }
}

// MARK: - Kairos shorthand

private typealias Kairos = HermesKairos
