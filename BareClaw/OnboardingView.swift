import SwiftUI

// MARK: - CompanionOnboardingView
//
// 8-step personalized setup.
// Step 0 — Welcome
// Step 1 — User's name
// Step 2 — Communication style
// Step 3 — Companion selection  ← NEW
// Step 4 — Interests
// Step 5 — Data permissions     ← NEW
// Step 6 — AI provider setup
// Step 7 — Ready (auto-advances)

struct CompanionOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var persona = UserPersona.shared
    @State private var step: Int = 0

    private let totalSteps = 8   // 0…7 (provider is last)

    var body: some View {
        ZStack {
            Color.BC.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Color.BC.accent : Color.BC.border)
                            .frame(width: i == step ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.4), value: step)
                    }
                }
                .padding(.top, BCSizing.spacingLG)
                .padding(.horizontal, BCSizing.spacingLG)

                // Step content
                Group {
                    switch step {
                    case 0: WelcomeStep()
                    case 1: NamingStep(persona: persona)
                    case 2: RelationshipModeStep(persona: persona)
                    case 3: StyleStep(persona: persona)
                    case 4: CompanionSelectionView(persona: persona)
                    case 5: InterestsStep(persona: persona)
                    case 6: DataPermissionsView(persona: persona) { advance() }
                    default: ProviderStep(persona: persona, onComplete: finish)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(step)

                // Navigation button (hidden on steps with their own CTA: 5, 6)
                if step < 6 {
                    VStack(spacing: 10) {
                        // Pulsing hint arrow on companion step so user knows to scroll up and tap Next
                        if step == 4 && !persona.selectedCompanionID.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color.BC.accent)
                                    .font(.system(size: 14))
                                Text("\(persona.selectedCompanion.name) is ready for you")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.BC.accent)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        Button(action: advance) {
                            HStack {
                                Text(nextButtonLabel)
                                    .font(BCFont.headline())
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canAdvance ? Color.BC.accent : Color.BC.border)
                            .foregroundColor(canAdvance ? .black : .BC.textMuted)
                            .cornerRadius(BCSizing.radiusLG)
                            .padding(.horizontal, BCSizing.spacingLG)
                            .scaleEffect(canAdvance && step == 4 ? 1.03 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                                       value: canAdvance && step == 4)
                        }
                        .padding(.bottom, BCSizing.spacingXL)
                        .disabled(!canAdvance)
                    }
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: step)
    }

    private var nextButtonLabel: String {
        switch step {
        case 0: return "Let's go! 🐾"
        case 4: return persona.selectedCompanionID.isEmpty ? "Choose a companion first" : "Meet \(persona.selectedCompanion.name) →"
        default: return "Next"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return !persona.userName.trimmingCharacters(in: .whitespaces).isEmpty
        case 4: return !persona.selectedCompanionID.isEmpty
        default: return true
        }
    }

    private func advance() {
        withAnimation { step = min(step + 1, totalSteps) }
    }

    private func finish() {
        persona.onboardingComplete = true
        persona.save()
        let nameToSave = persona.userName.trimmingCharacters(in: .whitespaces)
        Task {
            // Burn the user's name into memory at the highest importance level so
            // it is never evicted and is always available to personalise responses.
            if !nameToSave.isEmpty {
                _ = try? await HermesMemory.shared.observe(
                    category: "core_identity",
                    content: ["key": "name", "value": nameToSave],
                    metadata: ["importance": 10, "permanent": true, "source": "onboarding"]
                )
            }
            await HermesInterestEngine.shared.scheduleInterestNotifications(for: persona)
            await HermesPersonality.shared.scheduleDailyAffirmation(for: persona)
            await HermesIntegration.shared.logSessionStart(conversationId: UUID().uuidString)
        }
        withAnimation { appState.completeOnboarding() }
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    @State private var bearScale: CGFloat = 0.6
    @State private var bearOpacity: Double = 0

    var body: some View {
        VStack(spacing: BCSizing.spacingLG) {
            Spacer()
            BearLogoView(size: 120)
                .scaleEffect(bearScale)
                .opacity(bearOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        bearScale = 1; bearOpacity = 1
                    }
                }

            Text("Meet your\npersonal companion")
                .font(BCFont.title(30))
                .foregroundColor(.BC.textPrimary)
                .multilineTextAlignment(.center)

            Text("Someone who listens, remembers, and grows with you.\nLet's set things up — it takes under 2 minutes.")
                .font(BCFont.body())
                .foregroundColor(.BC.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BCSizing.spacingLG)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Step 1: Naming

private struct NamingStep: View {
    @ObservedObject var persona: UserPersona
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BCSizing.spacingLG) {
            Spacer()

            VStack(alignment: .leading, spacing: BCSizing.spacingSM) {
                Text("👋 First things first")
                    .font(BCFont.caption())
                    .foregroundColor(.BC.accent)
                Text("What's your name?")
                    .font(BCFont.title())
                    .foregroundColor(.BC.textPrimary)
                Text("Your companion will use it to make things feel personal.")
                    .font(BCFont.body())
                    .foregroundColor(.BC.textSecondary)
            }
            .padding(.horizontal, BCSizing.spacingLG)

            OCTextField("Your first name", text: $persona.userName)
                .focused($focused)
                .padding(.horizontal, BCSizing.spacingLG)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Step 2: Relationship mode

private struct RelationshipModeStep: View {
    @ObservedObject var persona: UserPersona

    var body: some View {
        VStack(alignment: .leading, spacing: BCSizing.spacingMD) {
            Spacer()

            VStack(alignment: .leading, spacing: BCSizing.spacingSM) {
                Text("💕 What kind of connection?")
                    .font(BCFont.caption())
                    .foregroundColor(.BC.accent)
                Text("Set the vibe")
                    .font(BCFont.title())
                    .foregroundColor(.BC.textPrimary)
                Text("This shapes how your companion relates to you — and which personalities are the best fit.")
                    .font(BCFont.body())
                    .foregroundColor(.BC.textSecondary)
            }
            .padding(.horizontal, BCSizing.spacingLG)

            ForEach(RelationshipMode.allCases) { mode in
                RelationshipModeCard(mode: mode, selected: persona.relationshipMode == mode) {
                    withAnimation(.spring(response: 0.3)) {
                        persona.relationshipMode = mode
                        persona.save()
                    }
                }
                .padding(.horizontal, BCSizing.spacingLG)
            }

            Spacer()
        }
    }
}

private struct RelationshipModeCard: View {
    let mode: RelationshipMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BCSizing.spacingMD) {
                Text(mode.emoji)
                    .font(.title2)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(BCFont.headline())
                        .foregroundColor(.BC.textPrimary)
                    Text(mode.description)
                        .font(BCFont.body(13))
                        .foregroundColor(.BC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.BC.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(BCSizing.spacingMD)
            .background(selected ? Color.BC.accent.opacity(0.12) : Color.BC.surfaceRaised)
            .cornerRadius(BCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                    .strokeBorder(selected ? Color.BC.accent : Color.BC.border, lineWidth: selected ? 1.5 : 1)
            )
        }
    }
}

// MARK: - Step 3: Communication style

private struct StyleStep: View {
    @ObservedObject var persona: UserPersona

    var body: some View {
        VStack(alignment: .leading, spacing: BCSizing.spacingMD) {
            Spacer()
            VStack(alignment: .leading, spacing: BCSizing.spacingSM) {
                Text("🗣 How should I talk to you?")
                    .font(BCFont.caption())
                    .foregroundColor(.BC.accent)
                Text("Pick your vibe")
                    .font(BCFont.title())
                    .foregroundColor(.BC.textPrimary)
            }
            .padding(.horizontal, BCSizing.spacingLG)

            ForEach(CommunicationStyle.allCases) { style in
                StyleCard(style: style, selected: persona.style == style) {
                    withAnimation(.spring(response: 0.3)) { persona.style = style }
                }
                .padding(.horizontal, BCSizing.spacingLG)
            }
            Spacer()
        }
    }
}

private struct StyleCard: View {
    let style: CommunicationStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BCSizing.spacingMD) {
                Text(style.emoji).font(.title2)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.label).font(BCFont.headline()).foregroundColor(.BC.textPrimary)
                    Text(style.description).font(BCFont.body(13)).foregroundColor(.BC.textSecondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.BC.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(BCSizing.spacingMD)
            .background(selected ? Color.BC.accent.opacity(0.12) : Color.BC.surfaceRaised)
            .cornerRadius(BCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                    .strokeBorder(selected ? Color.BC.accent : Color.BC.border, lineWidth: selected ? 1.5 : 1)
            )
        }
    }
}

// MARK: - Step 5: Interests

private struct InterestsStep: View {
    @ObservedObject var persona: UserPersona
    @State private var customText = ""

    private let suggestions: [Interest] = [
        Interest(id: "movies",        category: .movies,   label: "Movies & TV", emoji: "🎬"),
        Interest(id: "sports_nba",    category: .sports,   label: "NBA",         emoji: "🏀"),
        Interest(id: "sports_nfl",    category: .sports,   label: "NFL",         emoji: "🏈"),
        Interest(id: "music",         category: .music,    label: "Music",       emoji: "🎵"),
        Interest(id: "fitness",       category: .fitness,  label: "Fitness",     emoji: "💪"),
        Interest(id: "food_starbucks",category: .food,     label: "Starbucks",   emoji: "☕️"),
        Interest(id: "travel",        category: .travel,   label: "Travel",      emoji: "✈️"),
        Interest(id: "gaming",        category: .gaming,   label: "Gaming",      emoji: "🎮"),
        Interest(id: "tech",          category: .tech,     label: "Tech",        emoji: "⚡️"),
        Interest(id: "finance",       category: .finance,  label: "Investing",   emoji: "📈"),
        Interest(id: "books",         category: .books,    label: "Books",       emoji: "📚"),
        Interest(id: "pets",          category: .pets,     label: "Pets",        emoji: "🐾"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: BCSizing.spacingMD) {
            VStack(alignment: .leading, spacing: BCSizing.spacingSM) {
                Text("🌟 What are you into?")
                    .font(BCFont.caption()).foregroundColor(.BC.accent)
                Text("Pick your interests")
                    .font(BCFont.title()).foregroundColor(.BC.textPrimary)
                Text("Your companion will bring these up and send relevant updates.")
                    .font(BCFont.body()).foregroundColor(.BC.textSecondary)
            }
            .padding(.horizontal, BCSizing.spacingLG)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(suggestions) { interest in
                    let selected = persona.interests.contains(where: { $0.id == interest.id })
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            if selected { persona.removeInterest(id: interest.id) }
                            else        { persona.addInterest(interest) }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(interest.emoji).font(.title2)
                            Text(interest.label).font(BCFont.caption(11)).foregroundColor(.BC.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selected ? Color.BC.accentSoft : Color.BC.surfaceRaised)
                        .cornerRadius(BCSizing.radiusMD)
                        .overlay(
                            RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                                .strokeBorder(selected ? Color.BC.accent : Color.BC.border, lineWidth: selected ? 1.5 : 1)
                        )
                        .scaleEffect(selected ? 1.04 : 1)
                    }
                }
            }
            .padding(.horizontal, BCSizing.spacingLG)

            HStack {
                OCTextField("Add your own (e.g. Marvel, Lakers...)", text: $customText)
                Button {
                    let t = customText.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    persona.addInterest(Interest(id: "custom_\(t.lowercased().replacingOccurrences(of: " ", with: "_"))",
                                                  category: .other, label: t, emoji: "⭐️"))
                    customText = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2).foregroundColor(.BC.accent)
                }
            }
            .padding(.horizontal, BCSizing.spacingLG)
        }
    }
}

// MARK: - Step 7: Provider setup

private struct ProviderStep: View {
    @ObservedObject var persona: UserPersona
    let onComplete: () -> Void

    @State private var apiKey = ""
    @State private var showKey = false
    @State private var checking = false
    @State private var appleAvailable = AppleFoundationModelsBridge.isAvailable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BCSizing.spacingLG) {
                VStack(alignment: .leading, spacing: BCSizing.spacingSM) {
                    Text("🧠 Power up your AI")
                        .font(BCFont.caption()).foregroundColor(.BC.accent)
                    Text("Choose your AI engine")
                        .font(BCFont.title()).foregroundColor(.BC.textPrimary)
                    Text("\(persona.selectedCompanion.name) runs on the engine you choose.")
                        .font(BCFont.body()).foregroundColor(.BC.textSecondary)
                }
                .padding(.horizontal, BCSizing.spacingLG)

                ProviderCard(
                    icon: "applelogo",
                    iconColor: .BC.success,
                    title: "Apple Intelligence",
                    subtitle: "On-device. Free. Private. Requires iPhone 15 Pro or later with iOS 26+.",
                    badge: appleAvailable ? "Available ✓" : "Not available on this device",
                    badgeColor: appleAvailable ? .BC.success : .BC.textMuted,
                    isAvailable: appleAvailable
                ) {
                    Task {
                        await HermesPrivacyGate.shared.acceptOnDeviceOnly()
                        await HermesLLMClient.shared.configure()
                    }
                    onComplete()
                }
                .padding(.horizontal, BCSizing.spacingLG)

                HStack {
                    Rectangle().fill(Color.BC.border).frame(height: 1)
                    Text("or").font(BCFont.caption()).foregroundColor(.BC.textMuted)
                    Rectangle().fill(Color.BC.border).frame(height: 1)
                }
                .padding(.horizontal, BCSizing.spacingLG)

                VStack(alignment: .leading, spacing: BCSizing.spacingSM) {
                    ProviderCard(
                        icon: "cloud.fill",
                        iconColor: .BC.primary,
                        title: "Claude AI",
                        subtitle: "Works on all iPhones right now. Requires a free API key from Anthropic.",
                        badge: "Recommended for Day 1",
                        badgeColor: .BC.primary,
                        isAvailable: true,
                        action: nil
                    )
                    .padding(.horizontal, BCSizing.spacingLG)

                    VStack(alignment: .leading, spacing: BCSizing.spacingSM) {
                        if let consoleURL = URL(string: "https://console.anthropic.com") {
                            Link("→ Get your free API key at console.anthropic.com",
                                 destination: consoleURL)
                                .font(BCFont.caption())
                                .foregroundColor(.BC.primary)
                        }

                        HStack {
                            Group {
                                if showKey {
                                    TextField("sk-ant-...", text: $apiKey)
                                } else {
                                    SecureField("Paste your API key here", text: $apiKey)
                                }
                            }
                            .font(BCFont.mono())
                            .foregroundColor(.BC.textPrimary)

                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundColor(.BC.textMuted)
                            }
                        }
                        .padding(BCSizing.spacingMD)
                        .background(Color.BC.surface)
                        .cornerRadius(BCSizing.radiusMD)
                        .overlay(
                            RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                                .strokeBorder(apiKey.isEmpty ? Color.BC.border : Color.BC.primary, lineWidth: 1)
                        )

                        Button(action: saveAndContinue) {
                            HStack {
                                if checking {
                                    ProgressView().tint(.black).scaleEffect(0.8)
                                } else {
                                    Text("Save & Meet \(persona.selectedCompanion.name)")
                                        .font(BCFont.headline())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(apiKey.count > 20 ? Color.BC.primary : Color.BC.border)
                            .foregroundColor(apiKey.count > 20 ? .white : .BC.textMuted)
                            .cornerRadius(BCSizing.radiusLG)
                        }
                        .disabled(apiKey.count < 20 || checking)

                        // Skip option — user can add the key later in Settings
                        Button(action: onComplete) {
                            Text("Skip for now — I'll add it in Settings later")
                                .font(BCFont.body(13))
                                .foregroundColor(.BC.textMuted)
                                .underline()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, BCSizing.spacingLG)
                }
            }
            .padding(.vertical, BCSizing.spacingLG)
        }
    }

    private func saveAndContinue() {
        checking = true
        KeychainHelper.write(service: "com.bareclaw.bareclaw",
                             key: "anthropic_api_key",
                             value: apiKey.trimmingCharacters(in: .whitespaces))
        Task {
            await HermesPrivacyGate.shared.acceptCloudAI()
            // Configure LLM client immediately — without this the provider stays .none all session
            await HermesLLMClient.shared.configure()
            await MainActor.run { checking = false }
            onComplete()
        }
    }
}

private struct ProviderCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String
    let badgeColor: Color
    let isAvailable: Bool
    let action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            HStack(alignment: .top, spacing: BCSizing.spacingMD) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isAvailable ? iconColor : .BC.textMuted)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: BCSizing.spacingXS) {
                    HStack {
                        Text(title).font(BCFont.headline()).foregroundColor(isAvailable ? .BC.textPrimary : .BC.textMuted)
                        Text(badge).bcBadge(badgeColor)
                    }
                    Text(subtitle).font(BCFont.body(13)).foregroundColor(.BC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if action != nil && isAvailable {
                    Image(systemName: "arrow.right").foregroundColor(.BC.textMuted)
                }
            }
            .padding(BCSizing.spacingMD)
            .background(isAvailable ? Color.BC.surfaceRaised : Color.BC.surface.opacity(0.5))
            .cornerRadius(BCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                    .strokeBorder(Color.BC.border, lineWidth: 1)
            )
        }
        .disabled(!isAvailable || action == nil)
    }
}

// MARK: - Shared text field style

struct OCTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .font(BCFont.body())
            .foregroundColor(.BC.textPrimary)
            .padding(BCSizing.spacingMD)
            .background(Color.BC.surface)
            .cornerRadius(BCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                    .strokeBorder(text.isEmpty ? Color.BC.border : Color.BC.primary, lineWidth: 1)
            )
    }
}
