import SwiftUI
import Combine

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
            messages.append(ChatMessage(role: .assistant, text: thought, isSamanthaThought: true))
            saveMessages()
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
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        // Append user message
        lastUserMessage = text
        messages.append(ChatMessage(role: .user, text: text))

        // Snapshot history now (before assistant placeholder is added)
        let history = buildHistory()

        // Log to memory
        await HermesIntegration.shared.logUserMessage(text, in: sessionId)
        await Kairos.shared.userDidAct()

        // Learn facts and interests from this message
        learnFromMessage(text)

        // ── SelfHealingEngine: detect complaints / bug reports ────────
        let isBugReport = await SelfHealingEngine.shared.scan(userMessage: text)
        if isBugReport { return }   // engine already replied — skip normal LLM call

        // ── StressLearningEngine: learn relief habits from chat ───────
        // e.g. "I always watch Netflix when I'm stressed" → teach the engine
        StressLearningEngine.shared.learnFromChat(text)

        // ── SiriTaskEngine: detect and execute real tasks ────────────
        if let taskResult = await SiriTaskEngine.shared.parseAndExecute(text) {
            pendingTaskResult = taskResult
            // Insert companion's task response as a special message
            messages.append(ChatMessage(role: .assistant, text: taskResult.companionResponse))
            // Execute the task (open app / run action)
            await SiriTaskEngine.shared.execute(taskResult)
            // Still continue to stream a follow-up if it's not a simple deep-link
            if taskResult.kind == .deepLink {
                isTyping = false
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

        // Refresh suggestions in background
        suggestionTask?.cancel()
        suggestionTask = Task {
            _ = try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refreshSuggestions()
        }
    }

    private func streamResponse(history: [(role: String, content: String)]) async {
        isTyping = true
        let msgID = UUID()
        streamingID = msgID
        messages.append(ChatMessage(id: msgID, role: .assistant, text: "", isStreaming: true))

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
        do {
            let response = try await HermesLLMClient.shared.complete(
                request: request,
                stream: { [weak self] token in
                    Task { @MainActor [weak self] in
                        guard let self, self.streamingID == capturedID,
                              let i = self.messages.firstIndex(where: { $0.id == capturedID })
                        else { return }
                        self.messages[i].text += token
                    }
                }
            )
            // Non-streaming providers return full text in response.content
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                if messages[i].text.isEmpty { messages[i].text = response.content }
                messages[i].isStreaming = false
            }
        } catch let error as LLMError {
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                switch error {
                case .noProviderConfigured, .apiKeyMissing:
                    messages[i].text = "I need my brain connected first — go to Settings and add your Claude API key, then I'll be right here for you. 💛"
                case .rateLimited:
                    messages[i].text = "Too many messages at once — give me just a second and try again?"
                case .contextTooLong:
                    messages[i].text = "Our conversation is getting really long — starting fresh might help. I remember the important things."
                default:
                    messages[i].text = "Something went wrong on my end. Try again in a moment?"
                }
                messages[i].isStreaming = false
            }
        } catch {
            if let i = messages.firstIndex(where: { $0.id == capturedID }) {
                messages[i].text = "Something went wrong on my end. Try again in a moment?"
                messages[i].isStreaming = false
            }
        }

        streamingID = nil
        isTyping = false

        let finalText = messages.first(where: { $0.id == capturedID })?.text ?? ""
        await HermesIntegration.shared.logAssistantResponse(finalText)
        learnFromAssistantMessage(finalText)

        // Feed into learning engine — this grows intimacy and adapts the companion
        await HermesPersonality.shared.didComplete(
            userMessage: lastUserMessage,
            responseText: finalText,
            interests: persona.interests
        )

        // Memory agent: save this exchange + detect emotion
        await HermesMemoryAgent.shared.run(.message(user: lastUserMessage, assistant: finalText))

        // Persist chat history to disk
        saveMessages()

        // Speak response aloud
        CompanionVoiceEngine.shared.speakWithCurrentCompanion(finalText)

        // Refresh intimacy UI
        intimacyScore = await HerLearningEngine.shared.intimacyScore
        intimacyStage = await HerLearningEngine.shared.intimacyStage.label
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
                    self.persona.interests.append(interest)
                }
            }
            self.persona.save()
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

    /// Designated init — used internally (e.g. previews, explicit persona injection).
    init(persona: UserPersona) {
        self.persona = persona
        _vm = StateObject(wrappedValue: ChatViewModel(persona: persona))
    }

    /// Convenience no-arg init used by RootView — loads the stored persona from disk.
    init() {
        let p = UserPersona.load()
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
                            let p = await HermesLLMClient.shared.provider
                            await MainActor.run {
                                withAnimation { showAPIKeyBanner = (p == .none) }
                            }
                        }
                    }
            }
            .task {
                // Show banner immediately if no provider is ready
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
            let msg = ChatMessage(role: .assistant, text: text, isSamanthaThought: true)
            vm.messages.append(msg)
            vm.saveMessages()
        }
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
                .lineLimit(2)
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
                        if !isEmpty { onSend() }
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

            // ── Send button ───────────────────────────────────────────
            Button(action: onSend) {
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

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var persona: UserPersona
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var showKey: Bool = false
    @State private var keySaved: Bool = false
    @State private var providerLabel: String = "Checking…"
    @State private var showAddInterests: Bool = false
    @State private var customInterestText: String = ""
    @State private var editingName: String = ""
    @State private var nameSaved: Bool = false
    @State private var showCompanionPicker: Bool = false

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

                        Link("→ Get a free API key at console.anthropic.com",
                             destination: URL(string: "https://console.anthropic.com")!)
                            .font(BCFont.body(12))
                            .foregroundColor(Color.BC.accent)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("AI Engine")
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
                    ForEach(RelationshipMode.allCases) { mode in
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
                                                .scheduleInterestNotifications(for: persona)
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(Color.BC.primary)

                            Button(role: .destructive) {
                                withAnimation { persona.removeInterest(id: interest.id); persona.save() }
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
                                detail: "Opens Messages for you. Companion learns who matters from what you share in chat.",
                                enabled: $persona.trackingPermissions.messagesEnabled)

                    trackingRow("Email", icon: "envelope.fill", color: .blue,
                                detail: "Opens Mail for you. Companion learns about your work from what you share.",
                                enabled: $persona.trackingPermissions.emailEnabled)

                    trackingRow("Location Routines", icon: "location.fill", color: .red,
                                detail: "Time-aware suggestions around your commute, gym, and going-out routines.",
                                enabled: $persona.trackingPermissions.locationEnabled)

                    trackingRow("Browsing", icon: "safari.fill", color: .orange,
                                detail: "Surfaces interests from what you read. All analysis stays on-device.",
                                enabled: $persona.trackingPermissions.browsingEnabled)

                } header: {
                    Text("Companion Tracking")
                } footer: {
                    Text("When ON, your companion notices meaningful moments and reaches out — supportively before a hard appointment, celebratory after a win. When OFF, zero data from that source is ever accessed. Changes take effect immediately.")
                        .font(BCFont.footnote())
                        .foregroundColor(Color.BC.secondaryText)
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundColor(Color.BC.primaryText)
                        Spacer()
                        Text("1.0.0")
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
        // Show masked existing key if present
        if let existing = KeychainHelper.read(service: "com.bareclaw.bareclaw",
                                               key: "anthropic_api_key"), !existing.isEmpty {
            apiKey = existing
        }
        Task {
            let p = await HermesLLMClient.shared.provider
            await MainActor.run {
                switch p {
                case .appleFoundationModels: providerLabel = "Apple Intelligence (on-device)"
                case .claudeAPI:             providerLabel = "Claude API — active ✓"
                case .none:                  providerLabel = "Not configured — add your API key below"
                }
            }
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 20 else { return }
        KeychainHelper.write(service: "com.bareclaw.bareclaw",
                             key: "anthropic_api_key",
                             value: trimmed)
        Task {
            await HermesPrivacyGate.shared.acceptCloudAI()
            await HermesLLMClient.shared.configure()
            await MainActor.run {
                keySaved = true
                providerLabel = "Claude API — active ✓"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
            }
        }
    }
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
                            Task { await HermesInterestEngine.shared
                                .scheduleInterestNotifications(for: persona) }
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
                        Task { await HermesInterestEngine.shared
                            .scheduleInterestNotifications(for: persona) }
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
