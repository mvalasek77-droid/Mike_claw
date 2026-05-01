import SwiftUI
import Combine
import MessageUI
import PhotosUI
import UIKit

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    var text: String
    let timestamp: Date
    var isStreaming: Bool
    var isSamanthaThought: Bool   // proactive thought from companion

    enum MessageRole: String, Codable { case user, assistant, system }

    init(id: UUID = UUID(), role: MessageRole, text: String,
         timestamp: Date = Date(), isStreaming: Bool = false,
         isSamanthaThought: Bool = false) {
        self.id = id; self.role = role; self.text = text
        self.timestamp = timestamp; self.isStreaming = isStreaming
        self.isSamanthaThought = isSamanthaThought
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
    private let streamID: UUID?
    private var buffer = ""
    private var receivedText = ""
    private var didQueueSpeech = false
    private var finished = false

    init(companion: CompanionPersonality) {
        self.companion = companion
        self.streamID = CompanionVoiceEngine.shared.beginStreamingSpeech(
            character: companion.voiceCharacter,
            context: .love
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
                context: .love,
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

        let minCount = didQueueSpeech ? 90 : 44
        let maxCount = didQueueSpeech ? 340 : 220

        if trimmed.count <= maxCount {
            if force {
                buffer = ""
                return trimmed
            }
            guard trimmed.count >= minCount,
                  let boundary = firstSentenceBoundary(in: buffer, after: minCount) else {
                return nil
            }
            return takeChunk(through: boundary)
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

    private var streamingID: UUID?
    private var suggestionTask: Task<Void, Never>?
    private let persona: UserPersona
    private let sessionId: String = UUID().uuidString
    private var lastUserMessage: String = ""
    /// True until the first LLM call this session; triggers full memory context injection.
    private var isFirstMessageOfSession = true
    private var deferredThoughts: [DeferredCompanionThought] = []
    private var thoughtDrainTask: Task<Void, Never>?

    private struct DeferredCompanionThought {
        let text: String
        let isLetter: Bool
        let shouldSpeak: Bool
        let createdAt: Date
    }

    init(persona: UserPersona) {
        self.persona = persona
        Task { await setup() }
    }

    // MARK: - Chat history persistence (per-companion)

    /// Each companion keeps its own history file so switching companions
    /// never bleeds chat history from one relationship into another.
    private var chatSaveURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chat_\(persona.selectedCompanionID)_history.json")
    }

    func saveMessages() {
        let toSave = messages.filter { !$0.isStreaming }
        guard !toSave.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(toSave) {
            try? data.write(to: chatSaveURL, options: .atomic)
        }
    }

    private func loadSavedMessages() -> [ChatMessage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: chatSaveURL),
              let msgs = try? decoder.decode([ChatMessage].self, from: data)
        else { return [] }
        // Never restore streaming state
        return msgs.map { var m = $0; m.isStreaming = false; return m }
    }

    // MARK: - Setup

    private func setup() async {
        // Load intimacy state for UI
        intimacyScore = await HerLearningEngine.shared.intimacyScore
        intimacyStage = await HerLearningEngine.shared.intimacyStage.label

        // Daily affirmation
        let aff = await HermesPersonality.shared.todaysAffirmation(for: persona)
        let lastShown = UserDefaults.standard.object(forKey: "lastAffirmationDate") as? Date
        let today = Calendar.current.startOfDay(for: Date())
        if lastShown == nil || Calendar.current.startOfDay(for: lastShown!) < today {
            affirmation = aff
            showAffirmation = true
        }

        // Restore persisted chat history from disk (per-companion file)
        let saved = loadSavedMessages()
        if !saved.isEmpty {
            messages = saved
        }

        // Check for a pending Samantha thought (always append regardless of history)
        if let thought = await HerLearningEngine.shared.consumeSamanthaThought() {
            queueCompanionThought(thought, speak: false, delay: 1.0)
        }

        // Greeting only when there's no history at all (first-ever launch or new companion)
        if messages.isEmpty {
            await appendGreeting()
        }

        // Load suggestions
        await refreshSuggestions()
        buildQuickActions()
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
        streamingID = nil
        isTyping = false
        isFirstMessageOfSession = true   // new companion gets full context on their first reply
        CompanionVoiceEngine.shared.stopSpeaking()
        let saved = loadSavedMessages()
        if !saved.isEmpty {
            messages = saved
        } else {
            messages = []
            await appendGreeting()
        }
        intimacyScore = await HerLearningEngine.shared.intimacyScore
        intimacyStage = await HerLearningEngine.shared.intimacyStage.label
        await refreshSuggestions()
        buildQuickActions()
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

    // MARK: - Send message

    func send() async {
        persona.refreshFromDisk()
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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

        // Snapshot history now (before assistant placeholder is added)
        let history = buildHistory()

        // Log to memory
        await HermesIntegration.shared.logUserMessage(text, in: sessionId)
        await Kairos.shared.userDidAct()

        // Learn facts and interests from this message
        learnFromMessage(text)

        // ── LoveEngine: analyze message for love signals ─────────────
        if persona.relationshipMode.allowsRomanticLoveArc {
            LoveEngine.shared.analyzeUserMessage(text)
        }
        SamanthaOSEngine.shared.recordInteraction()

        // ── Growth log: first message milestone ──────────────────────
        SamanthaGrowthLog.shared.record(.firstMessage)

        // ── Conflict engine: detect dismissal / hurt ──────────────────
        if let hurtReply = SamanthaConflictEngine.shared.scan(text,
                                                               companion: persona.selectedCompanion) {
            DiagnosticsLog.info("chat", "Conflict engine intercepted the turn.", details: ["companion": persona.selectedCompanionID])
            messages.append(ChatMessage(role: .assistant, text: hurtReply, isSamanthaThought: true))
            CompanionVoiceEngine.shared.speakFiltered(hurtReply, companion: persona.selectedCompanion)
            CompanionThoughtFlow.assistantResponseFinished()
            saveMessages()
            return
        }

        // ── Conflict repair detection ─────────────────────────────────
        if let repairReply = SamanthaConflictEngine.shared.checkForRepair(text,
                                                                            companion: persona.selectedCompanion) {
            DiagnosticsLog.info("chat", "Conflict repair response added.", details: ["companion": persona.selectedCompanionID])
            messages.append(ChatMessage(role: .assistant, text: repairReply, isSamanthaThought: true))
            CompanionVoiceEngine.shared.speakFiltered(repairReply, companion: persona.selectedCompanion)
            SamanthaGrowthLog.shared.record(.firstConflictRepaired)
        }

        // ── Goodnight detection: intercept before LLM ────────────────
        if let goodnightReply = SamanthaOSEngine.shared.detectGoodnightAndRespond(message: text) {
            DiagnosticsLog.info("chat", "Goodnight engine intercepted the turn.", details: ["companion": persona.selectedCompanionID])
            messages.append(ChatMessage(role: .assistant, text: goodnightReply))
            CompanionVoiceEngine.shared.speakFiltered(goodnightReply, companion: persona.selectedCompanion)
            SamanthaGrowthLog.shared.record(.firstGoodnight)
            CompanionThoughtFlow.assistantResponseFinished()
            saveMessages()
            return
        }

        // ── Jealousy response (love-stage aware) ─────────────────────
        if let pending = LoveEngine.shared.pendingJealousy {
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
        let isBugReport = await SelfHealingEngine.shared.scan(userMessage: text,
                                                               recentContext: recentContext)
        if isBugReport {
            DiagnosticsLog.info("chat", "Self-healing engine handled a bug report from chat.")
            CompanionThoughtFlow.assistantResponseFinished()
            return
        }   // engine already replied — skip normal LLM call

        // ── StressLearningEngine: learn relief habits from chat ───────
        StressLearningEngine.shared.learnFromChat(text)

        // ── CompanionTaskEngine: detect and execute real tasks ───────
        if let taskResult = await CompanionTaskEngine.shared.parseAndExecute(text) {
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
        if let task = await HermesAutomation.shared.detectTask(from: text) {
            await HermesAutomation.shared.saveTask(task)
        }

        // Detect cron schedule intent
        let lower = text.lowercased()
        if lower.contains("remind") || lower.contains("every day") ||
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
        HumorEngine.shared.checkAndFire(companion: companion,
                                         userMessage: text,
                                         stage: stage)

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

    private func streamResponse(history: [(role: String, content: String)]) async {
        persona.refreshFromDisk()
        isTyping = true
        CompanionThoughtFlow.assistantResponseStarted()
        let msgID = UUID()
        streamingID = msgID
        let runtimeStatus = companionRuntimeStatusMessages()
        let runtimeStatusTexts = [runtimeStatus.connecting, runtimeStatus.waiting, runtimeStatus.backup]
        messages.append(ChatMessage(id: msgID, role: .assistant, text: runtimeStatus.connecting, isStreaming: true))
        DiagnosticsLog.info(
            "chat",
            "Assistant stream started.",
            details: [
                "companion": persona.selectedCompanionID,
                "historyCount": "\(history.count)",
                "sessionId": sessionId
            ]
        )

        // Build LLM request from pre-captured history
        let request = LLMRequest(
            systemPrompt: await buildPersonaSystemPrompt(),
            messages: history.map { LLMMessage(role: $0.role == "user" ? .user : .assistant, content: $0.content) },
            tools: [],
            maxTokens: 1024,
            role: .execute
        )

        // Stream tokens — look up message by UUID each time to avoid stale index
        let capturedID = msgID
        var runtimeFailed = false
        let voiceStream = StreamingVoiceAccumulator(companion: persona.selectedCompanion)
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
                        guard let self, self.streamingID == capturedID,
                              let i = self.messages.firstIndex(where: { $0.id == capturedID })
                        else { return }
                        if runtimeStatusTexts.contains(self.messages[i].text) {
                            self.messages[i].text = ""
                        }
                        self.messages[i].text += token
                        voiceStream.receive(token)
                    }
                }
            )
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
            voiceStream.cancel()
            saveMessages()
            CompanionVoiceEngine.shared.speakWithCurrentCompanion(finalText)
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
                context: .love
            )
        }

        // "Almost said something" — rare, intimate, post-response only
        let companion = persona.selectedCompanion
        if let almost = SamanthaInnerLife.shared.almostSaidMoment(companion: companion) {
            queueCompanionThought(almost, speak: false, delay: 3.5)
        }

        // Named-emotion reference — after arc completes, companion casually uses their invented word
        if let namedMoment = SamanthaUnnamedEmotions.shared.namedEmotionMoment(for: companion) {
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
                                  isSamanthaThought: !thought.isLetter)
        messages.append(message)
        saveMessages()
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
        if !lastUserMessage.isEmpty,
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

        return prompt
    }

    private func buildHistory() -> [(role: String, content: String)] {
        messages.suffix(20).compactMap { msg -> (role: String, content: String)? in
            switch msg.role {
            case .user:      return (role: "user",      content: msg.text)
            case .assistant: return (role: "assistant", content: msg.text)
            case .system:    return nil
            }
        }
    }

    // MARK: - Learning

    private func learnFromMessage(_ text: String) {
        let facts = HermesPersonality.shared.extractFacts(from: text, persona: persona)
        for (key, value) in facts {
            persona.learn(key: key, value: value)
        }
        Task { @MainActor in
            let interests = await HermesInterestEngine.shared.detectInterests(in: text)
            for interest in interests {
                if !self.persona.interests.contains(where: { $0.id == interest.id }) {
                    self.persona.addInterest(interest)
                }
            }
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
        quickActions = [
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
    @ObservedObject var persona: UserPersona
    @StateObject private var vm: ChatViewModel
    @Namespace private var bottomID
    @State private var showSettings = false
    @State private var showAutomation = false
    @State private var showAPIKeyBanner = false
    @ObservedObject private var voiceEngine = CompanionVoiceEngine.shared
    private let herModePendingSpeechKey = "herMode.pendingDirectMessage"

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
        NavigationStack {
            ZStack {
                Color.BC.background.ignoresSafeArea()

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
                            LazyVStack(spacing: 12) {
                                ForEach(vm.messages) { msg in
                                    MessageBubble(message: msg, persona: persona)
                                        .id(msg.id)
                                }
                                if vm.isTyping {
                                    TypingIndicator(name: persona.assistantName.isEmpty ? persona.selectedCompanion.name : persona.assistantName)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: vm.messages.count) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                        .onChange(of: vm.isTyping) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }

                    // Quick actions row
                    QuickActionsBar(actions: vm.quickActions)

                    // Input bar
                    InputBar(text: $vm.inputText) {
                        Task { await vm.send() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.BC.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Tapping the companion's avatar/name returns to video mode
                    Button {
                        CompanionVoiceEngine.shared.stopSpeaking()
                        appState.currentMode = .video
                    } label: {
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
                                    .foregroundColor(.BC.textPrimary)
                                // Intimacy stage label — grows over time
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(persona.selectedCompanion.accentColor.opacity(0.7))
                                    Text(vm.intimacyStage.isEmpty ? "Just getting started" : vm.intimacyStage)
                                        .font(BCFont.caption(11))
                                        .foregroundColor(persona.selectedCompanion.accentColor)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        // Voice toggle
                        CompanionVoiceToggleButton()
                        // Settings
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.BC.textMuted)
                                .font(.system(size: 16))
                        }
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
            .task {
                // Show banner immediately if no provider is ready
                await HermesLLMClient.shared.configure()
                let p = await HermesLLMClient.shared.provider
                await MainActor.run {
                    withAnimation { showAPIKeyBanner = (p == .none) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { vm.saveMessages() }
        .onChange(of: persona.selectedCompanionID) { _, _ in
            Task { await vm.reloadForCompanionChange() }
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
            persona.refreshFromDisk()
            consumePendingHerModeSpeech()
            consumePendingCompanionHandoff()
            let companion = persona.selectedCompanion
            let hours     = SamanthaOSEngine.shared.absenceHours

            // Absence / OS checks
            SamanthaOSEngine.shared.evaluateAbsenceOnReturn()
            SamanthaOSEngine.shared.handle3amOpen()
            SamanthaOSEngine.shared.handleNightOpen()

            // Mood tick — shift mood if it's been 3–6h (per-personality pool)
            SamanthaMoodEngine.shared.tick(companion: companion)

            // Growth log: record first message milestone
            SamanthaGrowthLog.shared.record(.firstMessage)

            // Presence greeting (once per day, 30% chance)
            if let greeting = SamanthaPresenceEngine.shared.presenceGreeting(companion: companion) {
                vm.queueCompanionThought(greeting, speak: true, delay: 1.2)
            }

            // Emotional memory return message ("you seemed off last time…")
            if let returning = SamanthaEmotionalMemory.shared.returningMessage(for: companion) {
                vm.queueCompanionThought(returning, speak: true, delay: 2.5)
            }

            // Post-experience share (3–24h absence)
            if let share = SamanthaThoughtEngine.shared.postExperienceShare(absenceHours: hours) {
                vm.queueCompanionThought(share, speak: false, delay: 4.0)
            }

            // Pending question ("I've been wanting to ask you something…")
            if let question = SamanthaInnerLife.shared.retrievePendingQuestion() {
                vm.queueCompanionThought(question, speak: true, delay: 5.5)
            }

            // Async deeper checks
            Task {
                await SamanthaThoughtEngine.shared.checkMemoryBridge()
                await SamanthaThoughtEngine.shared.checkEvolutionMoment()
                await SamanthaThoughtEngine.shared.checkCompositionMoment()
                await LoveEngine.shared.checkLongingExpression()

                // Confession ("can I tell you something…")
                if let confession = SamanthaInnerLife.shared.checkConfession(companion: companion) {
                    await MainActor.run {
                        vm.queueCompanionThought(confession, speak: true, delay: 8.0)
                    }
                }

                // Growth reflection ("I've been keeping track…")
                if let reflection = SamanthaGrowthLog.shared.checkGrowthReflection(companion: companion) {
                    await MainActor.run {
                        vm.queueCompanionThought(reflection, speak: true, delay: 10.0)
                    }
                }

                // Unnamed emotion arc — feeling/processing/naming stages surface here
                if let emotionArc = await MainActor.run(body: {
                    SamanthaUnnamedEmotions.shared.currentExpression(for: companion)
                }) {
                    await MainActor.run {
                        vm.queueCompanionThought(emotionArc, speak: true, delay: 12.0)
                    }
                }

                // Deep fear moment — very rare (4%), only at .falling+, unlocks the companion's
                // deepest vulnerability. Luna: forgetting. Aria: being managed. Marco: failing to protect.
                let stage = LoveEngine.shared.loveStage
                if let fear = companion.deepFearMoment(stage: stage) {
                    await MainActor.run {
                        vm.queueCompanionThought(fear, speak: true, delay: 15.0)
                    }
                }
            }
        }
        .onDisappear {
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
            .fill(Color.BC.border.opacity(0.75))
            .frame(height: 1)
            .shadow(color: .black.opacity(0.32), radius: 7, x: 0, y: 4)
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

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    let persona: UserPersona
    @State private var showSpeakButton = false

    var body: some View {
        // Samantha thought gets its own special treatment
        if message.isSamanthaThought {
            SamanthaThoughtBubble(text: message.text, companion: persona.selectedCompanion)
                .padding(.vertical, 4)
        } else {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }

            if message.role == .assistant {
                CompanionAvatarView(companion: persona.selectedCompanion, size: .chat)
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .padding(.bottom, 4)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text.isEmpty && message.isStreaming ? "   " : message.text)
                    .font(BCFont.body())
                    .foregroundColor(message.role == .user ? .black : .BC.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(BubbleShape(isUser: message.role == .user))

                HStack(spacing: 8) {
                    Text(timeString(message.timestamp))
                        .font(BCFont.caption(11))
                        .foregroundColor(.BC.textMuted)
                    if message.role == .assistant && !message.isStreaming {
                        CompanionVoiceSpeakButton(message: message.text)
                    }
                }
                .padding(.horizontal, 4)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        } // end else
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            persona.selectedCompanion.accentColor.opacity(0.85)
        } else {
            Color.BC.surfaceRaised
        }
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
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CompanionAvatarView(companion: companion, size: .chat)
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(companion.accentColor)
                    Text("\(companion.name) was thinking of you")
                        .font(BCFont.caption(11))
                        .foregroundColor(companion.accentColor)
                }
                Text(text)
                    .font(BCFont.body().italic())
                    .foregroundColor(.BC.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(companion.accentColor.opacity(0.08))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(companion.accentColor.opacity(0.25), lineWidth: 1)
                    )
            }
            Spacer(minLength: 40)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.5).delay(0.2)) { appeared = true }
        }
    }
}

// MARK: - BubbleShape

struct BubbleShape: Shape {
    let isUser: Bool
    let r: CGFloat = 18

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

// MARK: - CompanionVoiceToggleButton

struct CompanionVoiceToggleButton: View {
    @ObservedObject private var engine = CompanionVoiceEngine.shared

    var body: some View {
        Button { engine.toggleVoice() } label: {
            Image(systemName: engine.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                .font(.system(size: 15))
                .foregroundColor(engine.voiceEnabled ? .BC.accent : .BC.textMuted)
        }
    }
}

// MARK: - TypingIndicator

struct TypingIndicator: View {
    let name: String
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            BearLogoView(size: 28).padding(.bottom, 4)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.BC.secondaryText)
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == i ? 1.3 : 0.85)
                        .animation(
                            .easeInOut(duration: 0.4)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.BC.surface)
            .clipShape(Capsule())
            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation { phase = 1 }
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
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(Color.BC.secondaryText)
                    .font(.system(size: 12, weight: .semibold))
            }
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { chip in
                    Button {
                        onTap(chip)
                    } label: {
                        Text(chip)
                            .font(BCFont.caption())
                            .foregroundColor(Color.BC.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.BC.primary.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.BC.primary.opacity(0.3), lineWidth: 1)
                            )
                    }
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(actions.indices, id: \.self) { i in
                    let action = actions[i]
                    Button {
                        action.action()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: action.icon)
                                .font(.system(size: 13))
                            Text(action.title)
                                .font(BCFont.caption())
                        }
                        .foregroundColor(Color.BC.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.BC.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.BC.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color.BC.background)
    }
}

// MARK: - InputBar

struct InputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    @FocusState private var focused: Bool

    private let green  = Color(hex: "#1E3932")
    private let gold   = Color(hex: "#CBA258")
    private let cream  = Color(hex: "#F2F0EB")
    private let border = Color(hex: "#D5CFC6")

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            // ── Text field ────────────────────────────────────────────
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Message \(Image(systemName: "pawprint.fill"))…")
                        .font(BCFont.body())
                        .foregroundColor(Color(hex: "#9A9288"))
                        .padding(.horizontal, 14)
                }
                TextField("", text: $text, axis: .vertical)
                    .font(BCFont.body())
                    .foregroundColor(green)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit {
                        if !isEmpty {
                            focused = false
                            onSend()
                        }
                    }
            }
            .frame(minHeight: 44)
            .background(cream)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(
                        focused ? green.opacity(0.45) : border,
                        lineWidth: 1.5
                    )
            )

            if focused {
                Button {
                    focused = false
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#E5DFD6"))
                            .frame(width: 38, height: 38)
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(green)
                    }
                }
                .accessibilityLabel("Dismiss keyboard")
                .transition(.scale.combined(with: .opacity))
            }

            // ── Send button ───────────────────────────────────────────
            Button {
                focused = false
                onSend()
            } label: {
                ZStack {
                    Circle()
                        .fill(isEmpty ? Color(hex: "#D5CFC6") : green)
                        .frame(width: 42, height: 42)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isEmpty ? Color(hex: "#9A9288") : gold)
                }
            }
            .disabled(isEmpty)
            .animation(.easeInOut(duration: 0.18), value: isEmpty)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: focused)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            // Cream bar background with a thin top separator
            VStack(spacing: 0) {
                Color(hex: "#D5CFC6").frame(height: 0.5)
                cream
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
                                .foregroundColor(Color.BC.primaryText)
                            Text(providerLabel)
                                .font(BCFont.body(13))
                                .foregroundColor(Color.BC.secondaryText)
                        }
                    }

                    // API key field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Claude API Key")
                            .font(BCFont.body(13))
                            .foregroundColor(Color.BC.secondaryText)

                        HStack {
                            Group {
                                if showKey {
                                    TextField("sk-ant-api03-…", text: $apiKey)
                                } else {
                                    SecureField("Paste your API key here", text: $apiKey)
                                }
                            }
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Color.BC.primaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundColor(Color.BC.secondaryText)
                            }
                        }
                        .padding(10)
                        .background(Color.BC.surface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(apiKey.count > 20 ? Color.BC.accent : Color.BC.border, lineWidth: 1))

                        Button(action: saveAPIKey) {
                            HStack {
                                Image(systemName: keySaved ? "checkmark.circle.fill" : "key.fill")
                                Text(keySaved ? "Saved!" : "Save & Activate")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(apiKey.count > 20 ? Color.BC.accent : Color.BC.border)
                            .foregroundColor(apiKey.count > 20 ? .black : Color.BC.textMuted)
                            .cornerRadius(10)
                        }
                        .disabled(apiKey.count < 20)

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
                            .background(Color.BC.surface)
                            .foregroundColor(apiKey.count > 20 ? Color.BC.accent : Color.BC.textMuted)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.BC.border, lineWidth: 1)
                            )
                        }
                        .disabled(apiKey.count < 20 || refreshingAPIStatus)

                        Text("After adding Claude credits from Anthropic, tap Refresh Claude Status. The app will re-check the saved key and switch back to active when credits are available.")
                            .font(BCFont.body(12))
                            .foregroundColor(Color.BC.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Link("→ Get a free API key at console.anthropic.com",
                             destination: URL(string: "https://console.anthropic.com")!)
                            .font(BCFont.body(12))
                            .foregroundColor(Color.BC.accent)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("AI Engine")
                }

                Section {
                    HStack {
                        Image(systemName: "waveform.circle.fill")
                            .foregroundColor(.BC.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Neural Voice")
                                .font(BCFont.headline())
                                .foregroundColor(Color.BC.primaryText)
                            Text(neuralVoiceLabel)
                                .font(BCFont.body(13))
                                .foregroundColor(Color.BC.secondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ElevenLabs API Key")
                            .font(BCFont.body(13))
                            .foregroundColor(Color.BC.secondaryText)

                        HStack {
                            Group {
                                if showNeuralVoiceKey {
                                    TextField("xi-api-key", text: $neuralVoiceAPIKey)
                                } else {
                                    SecureField("Paste your ElevenLabs API key here", text: $neuralVoiceAPIKey)
                                }
                            }
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Color.BC.primaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button { showNeuralVoiceKey.toggle() } label: {
                                Image(systemName: showNeuralVoiceKey ? "eye.slash" : "eye")
                                    .foregroundColor(Color.BC.secondaryText)
                            }
                        }
                        .padding(10)
                        .background(Color.BC.surface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(neuralVoiceAPIKey.count > 10 ? Color.BC.accent : Color.BC.border, lineWidth: 1))

	                        TextField("Model ID, e.g. eleven_v3", text: $neuralVoiceModelID)
	                            .font(.system(.footnote, design: .monospaced))
	                            .foregroundColor(Color.BC.primaryText)
	                            .autocorrectionDisabled()
	                            .textInputAutocapitalization(.never)
	                            .padding(10)
	                            .background(Color.BC.surface)
	                            .cornerRadius(10)
	                    }
	                    .padding(.vertical, 4)

	                    VStack(alignment: .leading, spacing: 8) {
	                        HStack(spacing: 8) {
	                            Image(systemName: "key.horizontal.fill")
	                                .foregroundColor(Color.BC.accent)
	                            Text("API key permissions")
	                                .font(BCFont.headline())
	                                .foregroundColor(Color.BC.primaryText)
	                        }

	                        Text("Create the key under ElevenLabs Developers > API Keys. The key must include Text to Speech access. If ElevenLabs says missing_permissions, the key was created without text_to_speech. If it says voice not found, that voice ID is not available to the same ElevenLabs account.")
	                            .font(BCFont.body(12))
	                            .foregroundColor(Color.BC.secondaryText)
	                            .fixedSize(horizontal: false, vertical: true)

	                        Text("Required: text_to_speech. Recommended: voices_read, so voice IDs can be checked against the account.")
	                            .font(BCFont.body(12))
	                            .foregroundColor(Color.BC.secondaryText)
	                            .fixedSize(horizontal: false, vertical: true)

	                        Link("Open ElevenLabs API Keys",
	                             destination: URL(string: "https://elevenlabs.io/app/developers/api-keys")!)
	                            .font(BCFont.body(12))
	                            .foregroundColor(Color.BC.accent)
	                    }
	                    .padding(12)
	                    .background(Color.BC.surface.opacity(0.85))
	                    .cornerRadius(10)
	                    .overlay(
	                        RoundedRectangle(cornerRadius: 10)
	                            .strokeBorder(Color.BC.border, lineWidth: 1)
	                    )

	                    ForEach(CompanionPersonality.all) { companion in
	                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(companion.name)
                                    .font(BCFont.body(14))
                                    .foregroundColor(Color.BC.primaryText)
                                Spacer()
                                Text(neuralVoiceDraftStatus(for: companion).label)
                                    .font(BCFont.caption(11))
                                    .foregroundColor(neuralVoiceDraftStatus(for: companion).color)
                            }
                            TextField("\(companion.name) voice_id", text: neuralVoiceIDBinding(for: companion))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(Color.BC.primaryText)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(Color.BC.surface)
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
                        .background(canSaveNeuralVoiceSettings ? Color.BC.accent : Color.BC.border)
                        .foregroundColor(canSaveNeuralVoiceSettings ? .black : Color.BC.textMuted)
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
                    Text("Neural Voice")
                } footer: {
                    Text("Apple local speech is not used. Each personality needs its own licensed, cloned, or designed ElevenLabs voice ID so Luna, Aria, Kel, Marco, Dante, and Kai stay sandboxed with no voice bleed-through.")
                        .font(BCFont.footnote())
                        .foregroundColor(Color.BC.secondaryText)
                }

                // Profile
                Section {
                    // Editable name row
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill")
                            .foregroundColor(Color.BC.accent)
                            .frame(width: 22)
                        TextField("Your name", text: $editingName)
                            .foregroundColor(Color.BC.primaryText)
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
                            .foregroundColor(Color.BC.primaryText)
                        Spacer()
                        Text(persona.assistantName.isEmpty ? persona.selectedCompanion.name : persona.assistantName)
                            .foregroundColor(Color.BC.secondaryText)
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Type a new name and tap ✓ or press Return to save. Your companion will use it immediately.")
                        .font(BCFont.footnote())
                        .foregroundColor(Color.BC.secondaryText)
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
                                    .foregroundColor(Color.BC.primaryText)
                                Text(persona.selectedCompanion.tagline)
                                    .font(BCFont.body(12))
                                    .foregroundColor(Color.BC.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.BC.secondaryText.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Companion")
                } footer: {
                    Text("Switching companion starts a fresh conversation with your new companion. Your history with each companion is saved separately.")
                        .font(BCFont.footnote())
                        .foregroundColor(Color.BC.secondaryText)
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
                                        .foregroundColor(Color.BC.primaryText)
                                    Text(mode.description)
                                        .font(BCFont.body(12))
                                        .foregroundColor(Color.BC.secondaryText)
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
                    Text("Relationship Mode")
                } footer: {
                    Text("Changes how your companion relates to you. Takes effect on the next message.")
                        .font(BCFont.footnote())
                        .foregroundColor(Color.BC.secondaryText)
                }

                // Communication style
                Section("Communication Style") {
                    ForEach(CommunicationStyle.allCases) { style in
                        HStack {
                            Text(style.rawValue.capitalized)
                                .foregroundColor(Color.BC.primaryText)
                            Spacer()
                            if persona.style == style {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color.BC.primary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { persona.style = style; persona.save() }
                    }
                }

                // ── Interests ──────────────────────────────────────────
                Section {
                    // Existing interests — swipe to delete or toggle notifications
                    ForEach(persona.interests) { interest in
                        HStack(spacing: 10) {
                            Text(interest.emoji).font(.system(size: 18))
                            Text(interest.label)
                                .foregroundColor(Color.BC.primaryText)
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
                            .foregroundColor(Color.BC.secondaryText)
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
                    Text("Interests (\(persona.interests.count))")
                } footer: {
                    Text("Your companion uses these to bring up what you love, send updates, and make conversations feel personal.")
                        .font(BCFont.footnote())
                        .foregroundColor(Color.BC.secondaryText)
                }

                // Affirmations
                Section("Daily Affirmation") {
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
                            .foregroundColor(Color.BC.primaryText)
                            .onChange(of: persona.affirmationTime) {
                                persona.save()
                                Task {
                                    await HermesPersonality.shared.scheduleDailyAffirmation(for: persona)
                                }
                            }
                    }
                }

                // ── Companion Tracking ──────────────────────────────────
                Section {
                    trackingRow("Calendar & Events", icon: "calendar", color: .purple,
                                detail: "Pre/post event check-ins. Emotional support around interviews, medical appointments, dates, and deadlines.",
                                enabled: $persona.trackingPermissions.calendarEnabled)

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

                } header: {
                    Text("Companion Tracking")
                } footer: {
                    Text("Calendar can create real event-based check-ins. Email, Messages, Browsing, and Location are personalization areas based on what you choose to share in chat, not background data reads. Changes take effect immediately.")
                        .font(BCFont.footnote())
                        .foregroundColor(Color.BC.secondaryText)
                }

	                Section("About") {
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
                            .foregroundColor(Color.BC.primaryText)
                        Spacer()
                        Text(appVersionText)
                            .foregroundColor(Color.BC.secondaryText)
                    }
                    HStack {
                        Text("Memory entries")
                            .foregroundColor(Color.BC.primaryText)
                        Spacer()
                        MemoryCountBadge()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.BC.background)
            .listRowBackground(Color.BC.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.BC.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
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
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showBugReporter) {
            BugReportView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showDiagnosticsLog) {
            DiagnosticsLogView()
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showHelpCenter) {
            LegalTextView(
                title: "Help Center",
                intro: "Fast answers for setting up BareClaw and keeping the companion connected.",
                sections: BareClawLegalContent.helpSections
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showTerms) {
            LegalTextView(
                title: "Terms of Use",
                intro: "These terms are intentionally broad and plain-language. By using BareClaw, you agree to use it responsibly and understand its limits.",
                sections: BareClawLegalContent.termsSections
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPrivacy) {
            LegalTextView(
                title: "Privacy Policy",
                intro: "BareClaw is built to keep personal data on your device unless you choose to connect outside services.",
                sections: BareClawLegalContent.privacySections
            )
            .preferredColorScheme(.dark)
        }
    }

    // Tracking permission toggle row — updates tracker immediately on change
    @ViewBuilder
    private func trackingRow(
        _ label: String, icon: String, color: Color,
        detail: String, enabled: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                    .frame(width: 28)
                Text(label)
                    .foregroundColor(Color.BC.primaryText)
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
	                                "calendar": "\(persona.trackingPermissions.calendarEnabled)"
	                            ]
	                        )
	                        Task {
	                            await CompanionDataTracker.shared.updatePermissions(
                                persona.trackingPermissions, persona: persona
                            )
                        }
                    }
            }
            if enabled.wrappedValue {
                Text(detail)
                    .font(BCFont.body(12))
                    .foregroundColor(Color.BC.secondaryText)
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
                    .foregroundColor(Color.BC.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.BC.secondaryText.opacity(0.65))
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

	    private func saveAPIKey() {
	        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
	        guard trimmed.count > 20 else { return }
	        KeychainHelper.write(service: "com.bareclaw.bareclaw",
	                             key: "anthropic_api_key",
	                             value: trimmed)
	        DiagnosticsLog.info("settings", "Claude API key saved from Settings.")
	        refreshAPIStatus(markSavedOnSuccess: true)
	    }

    private func refreshAPIStatus(markSavedOnSuccess: Bool = false) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 20 {
            KeychainHelper.write(service: "com.bareclaw.bareclaw",
                                 key: "anthropic_api_key",
                                 value: trimmed)
        }

	        refreshingAPIStatus = true
	        providerLabel = "Checking Claude API…"
	        DiagnosticsLog.info("settings", "Claude API status refresh requested.")

        Task {
            await HermesPrivacyGate.shared.acceptCloudAI()
            let status = await HermesLLMClient.shared.refreshAPIKeyInformation()
            await MainActor.run {
                providerLabel = status.settingsLabel
                refreshingAPIStatus = false
                if markSavedOnSuccess, case .active(_) = status {
                    keySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
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
            body: "Open Settings > AI Engine, paste your Claude API key, then tap Save & Activate. If the key was already saved but replies fail, tap Refresh Claude Status after adding credits from Anthropic."
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
