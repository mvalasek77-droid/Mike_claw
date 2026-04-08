import SwiftUI
import Combine

// MARK: - ChatMessage

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    var text: String
    let timestamp: Date
    var isStreaming: Bool
    var isSamanthaThought: Bool   // proactive thought from companion

    enum MessageRole { case user, assistant, system }

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

    init(persona: UserPersona) {
        self.persona = persona
        Task { await setup() }
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

        // Check for a pending Samantha thought (proactive companion message)
        if let thought = await HerLearningEngine.shared.consumeSamanthaThought() {
            messages.append(ChatMessage(role: .assistant, text: thought, isSamanthaThought: true))
        }

        // Greeting if no pending Samantha thought and first launch today
        if messages.isEmpty {
            let companion = persona.selectedCompanion
            let name = persona.userName.isEmpty ? "" : " \(persona.userName)"
            let hour = Calendar.current.component(.hour, from: Date())
            let stage = await HerLearningEngine.shared.intimacyStage
            let greeting = stageAwareGreeting(name: name, hour: hour, stage: stage, companion: companion)
            messages.append(ChatMessage(role: .assistant, text: greeting))
        }

        // Load suggestions
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
            return "Good \(timeGreeting)\(name). I'm \(companion.name) — I'm really glad you're here. What's going on with you today?"
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
        Kairos.shared.userDidAct()

        // Learn facts and interests from this message
        learnFromMessage(text)

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
            try? await Task.sleep(nanoseconds: 1_000_000_000)
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
            responseText: finalText
        )

        // Speak response aloud
        CompanionVoiceEngine.shared.speakWithCurrentCompanion(finalText)

        // Refresh intimacy UI
        intimacyScore = await HerLearningEngine.shared.intimacyScore
        intimacyStage = await HerLearningEngine.shared.intimacyStage.label
    }

    private func buildPersonaSystemPrompt() async -> String {
        await HermesPersonality.shared.buildPersonaPrompt(
            for: persona,
            lastUserMessage: lastUserMessage
        )
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
        let facts = HermesPersonality.shared.extractFactsSync(from: text, persona: persona)
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
        let facts = HermesPersonality.shared.extractFactsSync(from: text, persona: persona)
        for (key, value) in facts { persona.learn(key: key, value: value) }
    }

    // MARK: - Suggestions

    private func refreshSuggestions() async {
        let raw = await HermesIntegration.shared.pollSuggestions()
        suggestions = raw.prefix(4).map { $0.title }
    }

    // MARK: - Quick actions

    private func buildQuickActions() {
        quickActions = [
            (title: "Send Email",  icon: "envelope.fill", action: {
                Task { @MainActor in self.inputText = "Write an email to " }
            }),
            (title: "Remind Me",   icon: "bell.fill", action: {
                Task { @MainActor in self.inputText = "Remind me to " }
            }),
            (title: "Add to Cal",  icon: "calendar.badge.plus", action: {
                Task { @MainActor in self.inputText = "Schedule " }
            }),
            (title: "Play Music",  icon: "music.note", action: {
                Task { @MainActor in self.inputText = "Play " }
            }),
            (title: "Navigate",    icon: "location.fill", action: {
                Task { @MainActor in self.inputText = "Navigate to " }
            }),
            (title: "Starbucks",   icon: "cup.and.saucer.fill", action: {
                Task { @MainActor in self.inputText = "Open Starbucks for me" }
            }),
        ]
    }

    // MARK: - Dismiss affirmation

    func dismissAffirmation() {
        withAnimation { showAffirmation = false }
        UserDefaults.standard.set(Date(), forKey: "lastAffirmationDate")
    }
}

// MARK: - HermesPersonality sync helper (for use on MainActor)

extension HermesPersonality {
    /// Synchronous wrapper — safe to call from non-async context on MainActor.
    nonisolated func extractFactsSync(from text: String, persona: UserPersona) -> [String: String] {
        // We can't call actor methods synchronously, so replicate the logic here
        var facts: [String: String] = [:]
        let lower = text.lowercased()
        let nbaTeams = ["lakers","celtics","warriors","bulls","nets","knicks","heat","spurs","bucks"]
        let nflTeams = ["chiefs","patriots","cowboys","packers","eagles","49ers","ravens","broncos"]
        for team in nbaTeams where lower.contains(team) { facts["favorite_nba_team"] = team.capitalized }
        for team in nflTeams where lower.contains(team) { facts["favorite_nfl_team"] = team.capitalized }
        if lower.contains("starbucks")  { facts["likes_starbucks"] = "true" }
        if lower.contains("pizza")      { facts["likes_pizza"]     = "true" }
        if lower.contains("gym") || lower.contains("workout") { facts["is_active"] = "true" }
        if lower.contains("work from home") || lower.contains("wfh") { facts["works_from_home"] = "true" }
        return facts
    }
}

// MARK: - ChatView

struct ChatView: View {
    @ObservedObject var persona: UserPersona
    @StateObject private var vm: ChatViewModel
    @Namespace private var bottomID
    @State private var showSettings = false
    @State private var showAutomation = false

    init(persona: UserPersona) {
        self.persona = persona
        _vm = StateObject(wrappedValue: ChatViewModel(persona: persona))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.OC.background.ignoresSafeArea()

                VStack(spacing: 0) {
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
                                    TypingIndicator(name: persona.assistantName)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: vm.messages.count) { _ in
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                        .onChange(of: vm.isTyping) { _ in
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
                    HStack(spacing: 10) {
                        // Companion avatar circle
                        CompanionAvatarView(companion: persona.selectedCompanion, size: .chat)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(persona.selectedCompanion.accentColor.opacity(0.6), lineWidth: 1.5)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(persona.selectedCompanion.name)
                                .font(OCFont.headline())
                                .foregroundColor(.OC.textPrimary)
                            // Intimacy stage label — grows over time
                            Text(vm.intimacyStage.isEmpty ? "Just getting started" : vm.intimacyStage)
                                .font(OCFont.caption(11))
                                .foregroundColor(persona.selectedCompanion.accentColor)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        // Voice toggle
                        CompanionVoiceToggleButton()
                        // Settings
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.OC.textMuted)
                                .font(.system(size: 16))
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(persona: persona)
            }
        }
        .preferredColorScheme(.dark)
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
            return
        }

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
                    .font(OCFont.body())
                    .foregroundColor(message.role == .user ? .black : .OC.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(BubbleShape(isUser: message.role == .user))

                HStack(spacing: 8) {
                    Text(timeString(message.timestamp))
                        .font(OCFont.caption(11))
                        .foregroundColor(.OC.textMuted)
                    if message.role == .assistant && !message.isStreaming {
                        CompanionVoiceSpeakButton(message: message.text)
                    }
                }
                .padding(.horizontal, 4)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            persona.selectedCompanion.accentColor.opacity(0.85)
        } else {
            Color.OC.surfaceRaised
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
                        .font(OCFont.caption(11))
                        .foregroundColor(companion.accentColor)
                }
                Text(text)
                    .font(OCFont.body().italic())
                    .foregroundColor(.OC.textPrimary)
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
                .foregroundColor(engine.voiceEnabled ? .OC.accent : .OC.textMuted)
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
                        .fill(Color.OC.secondaryText)
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
            .background(Color.OC.surface)
            .clipShape(Capsule())
            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation { phase = 1 }
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
                .foregroundColor(Color.OC.accent)
                .font(.system(size: 16))
            Text(text)
                .font(OCFont.footnote)
                .foregroundColor(Color.OC.primaryText)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(Color.OC.secondaryText)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.OC.accent.opacity(0.18), Color.OC.surface],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            Rectangle()
                .frame(width: 3)
                .foregroundColor(Color.OC.accent),
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
                            .font(OCFont.caption)
                            .foregroundColor(Color.OC.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.OC.primary.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.OC.primary.opacity(0.3), lineWidth: 1)
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
                                .font(OCFont.caption)
                        }
                        .foregroundColor(Color.OC.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.OC.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.OC.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color.OC.background)
    }
}

// MARK: - InputBar

struct InputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Message \(Image(systemName: "pawprint.fill"))…")
                        .font(OCFont.body)
                        .foregroundColor(Color.OC.secondaryText.opacity(0.6))
                        .padding(.horizontal, 14)
                }
                TextField("", text: $text, axis: .vertical)
                    .font(OCFont.body)
                    .foregroundColor(Color.OC.primaryText)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend()
                        }
                    }
            }
            .frame(minHeight: 44)
            .background(Color.OC.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(focused ? Color.OC.primary.opacity(0.5) : Color.OC.border, lineWidth: 1)
            )

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? Color.OC.secondaryText : Color.OC.background)
                    .frame(width: 40, height: 40)
                    .background(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.OC.surface
                        : Color.OC.primary
                    )
                    .clipShape(Circle())
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .animation(.easeInOut(duration: 0.15), value: text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.OC.background)
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

    var body: some View {
        NavigationStack {
            List {

                // ── AI Engine ────────────────────────────────────────────
                Section {
                    // Status row
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.OC.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Engine")
                                .font(OCFont.headline())
                                .foregroundColor(Color.OC.primaryText)
                            Text(providerLabel)
                                .font(OCFont.body(13))
                                .foregroundColor(Color.OC.secondaryText)
                        }
                    }

                    // API key field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Claude API Key")
                            .font(OCFont.body(13))
                            .foregroundColor(Color.OC.secondaryText)

                        HStack {
                            Group {
                                if showKey {
                                    TextField("sk-ant-api03-…", text: $apiKey)
                                } else {
                                    SecureField("Paste your API key here", text: $apiKey)
                                }
                            }
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(Color.OC.primaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundColor(Color.OC.secondaryText)
                            }
                        }
                        .padding(10)
                        .background(Color.OC.surface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(apiKey.count > 20 ? Color.OC.accent : Color.OC.border, lineWidth: 1))

                        Button(action: saveAPIKey) {
                            HStack {
                                Image(systemName: keySaved ? "checkmark.circle.fill" : "key.fill")
                                Text(keySaved ? "Saved!" : "Save & Activate")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(apiKey.count > 20 ? Color.OC.accent : Color.OC.border)
                            .foregroundColor(apiKey.count > 20 ? .black : Color.OC.textMuted)
                            .cornerRadius(10)
                        }
                        .disabled(apiKey.count < 20)

                        Link("→ Get a free API key at console.anthropic.com",
                             destination: URL(string: "https://console.anthropic.com")!)
                            .font(OCFont.body(12))
                            .foregroundColor(Color.OC.accent)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("AI Engine")
                }

                // Profile
                Section("Profile") {
                    HStack {
                        Text("Your Name")
                            .foregroundColor(Color.OC.primaryText)
                        Spacer()
                        Text(persona.userName.isEmpty ? "Not set" : persona.userName)
                            .foregroundColor(Color.OC.secondaryText)
                    }
                    HStack {
                        Text("Assistant Name")
                            .foregroundColor(Color.OC.primaryText)
                        Spacer()
                        Text(persona.assistantName.isEmpty ? "Claw" : persona.assistantName)
                            .foregroundColor(Color.OC.secondaryText)
                    }
                }

                // Communication style
                Section("Communication Style") {
                    ForEach(CommunicationStyle.allCases) { style in
                        HStack {
                            Text(style.rawValue.capitalized)
                                .foregroundColor(Color.OC.primaryText)
                            Spacer()
                            if persona.style == style {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color.OC.primary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { persona.style = style; persona.save() }
                    }
                }

                // Interests
                Section("Interests (\(persona.interests.count))") {
                    ForEach(persona.interests) { interest in
                        HStack {
                            Text(interest.emoji)
                            Text(interest.label)
                                .foregroundColor(Color.OC.primaryText)
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
                            .tint(Color.OC.primary)
                        }
                    }
                    if persona.interests.isEmpty {
                        Text("No interests yet — chat to add some!")
                            .foregroundColor(Color.OC.secondaryText)
                            .font(OCFont.footnote)
                    }
                }

                // Affirmations
                Section("Daily Affirmation") {
                    Toggle("Enabled", isOn: $persona.dailyAffirmationsEnabled)
                        .tint(Color.OC.primary)
                        .onChange(of: persona.dailyAffirmationsEnabled) { _ in
                            persona.save()
                            Task {
                                await HermesPersonality.shared.scheduleDailyAffirmation(for: persona)
                            }
                        }
                    if persona.dailyAffirmationsEnabled {
                        DatePicker("Time", selection: $persona.affirmationTime, displayedComponents: .hourAndMinute)
                            .foregroundColor(Color.OC.primaryText)
                            .onChange(of: persona.affirmationTime) { _ in
                                persona.save()
                                Task {
                                    await HermesPersonality.shared.scheduleDailyAffirmation(for: persona)
                                }
                            }
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundColor(Color.OC.primaryText)
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(Color.OC.secondaryText)
                    }
                    HStack {
                        Text("Memory entries")
                            .foregroundColor(Color.OC.primaryText)
                        Spacer()
                        MemoryCountBadge()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.OC.background)
            .listRowBackground(Color.OC.surface)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.OC.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadCurrentKey() }
    }

    private func loadCurrentKey() {
        // Show masked existing key if present
        if let existing = KeychainHelper.read(service: "com.openclaw.appclaw",
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
        KeychainHelper.write(service: "com.openclaw.appclaw",
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

// MARK: - MemoryCountBadge

struct MemoryCountBadge: View {
    @State private var count = 0

    var body: some View {
        Text("\(count)")
            .foregroundColor(Color.OC.secondaryText)
            .task {
                let entries = await HermesMemory.shared.allEntries()
                count = entries.count
            }
    }
}

// MARK: - Kairos shorthand

private typealias Kairos = HermesKairos
