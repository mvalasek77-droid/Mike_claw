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
    @StateObject private var persona = UserPersona.load()
    @State private var step: Int = 0

    private let totalSteps = 7   // 0…6 (provider is last)

    var body: some View {
        ZStack {
            Color.OC.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Color.OC.accent : Color.OC.border)
                            .frame(width: i == step ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.4), value: step)
                    }
                }
                .padding(.top, OCSizing.spacingLG)
                .padding(.horizontal, OCSizing.spacingLG)

                // Step content
                Group {
                    switch step {
                    case 0: WelcomeStep()
                    case 1: NamingStep(persona: persona)
                    case 2: StyleStep(persona: persona)
                    case 3: CompanionSelectionView(persona: persona)
                    case 4: InterestsStep(persona: persona)
                    case 5: DataPermissionsView(persona: persona) { advance() }
                    default: ProviderStep(persona: persona, onComplete: finish)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(step)

                // Navigation button (hidden on steps with their own CTA: 5, 6)
                if step < 5 {
                    Button(action: advance) {
                        HStack {
                            Text(nextButtonLabel)
                                .font(OCFont.headline())
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canAdvance ? Color.OC.accent : Color.OC.border)
                        .foregroundColor(canAdvance ? .black : .OC.textMuted)
                        .cornerRadius(OCSizing.radiusLG)
                        .padding(.horizontal, OCSizing.spacingLG)
                    }
                    .padding(.bottom, OCSizing.spacingXL)
                    .disabled(!canAdvance)
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: step)
    }

    private var nextButtonLabel: String {
        switch step {
        case 0: return "Let's go! 🐾"
        case 3: return persona.selectedCompanionID.isEmpty ? "Choose a companion first" : "Meet \(persona.selectedCompanion.name) →"
        default: return "Next"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return !persona.userName.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private func advance() {
        withAnimation { step = min(step + 1, totalSteps) }
    }

    private func finish() {
        persona.onboardingComplete = true
        persona.save()
        Task {
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
        VStack(spacing: OCSizing.spacingLG) {
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
                .font(OCFont.title(30))
                .foregroundColor(.OC.textPrimary)
                .multilineTextAlignment(.center)

            Text("Someone who listens, remembers, and grows with you.\nLet's set things up — it takes under 2 minutes.")
                .font(OCFont.body())
                .foregroundColor(.OC.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OCSizing.spacingLG)

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
        VStack(alignment: .leading, spacing: OCSizing.spacingLG) {
            Spacer()

            VStack(alignment: .leading, spacing: OCSizing.spacingSM) {
                Text("👋 First things first")
                    .font(OCFont.caption())
                    .foregroundColor(.OC.accent)
                Text("What's your name?")
                    .font(OCFont.title())
                    .foregroundColor(.OC.textPrimary)
                Text("Your companion will use it to make things feel personal.")
                    .font(OCFont.body())
                    .foregroundColor(.OC.textSecondary)
            }
            .padding(.horizontal, OCSizing.spacingLG)

            OCTextField("Your first name", text: $persona.userName)
                .focused($focused)
                .padding(.horizontal, OCSizing.spacingLG)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true } }

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Step 2: Communication style

private struct StyleStep: View {
    @ObservedObject var persona: UserPersona

    var body: some View {
        VStack(alignment: .leading, spacing: OCSizing.spacingMD) {
            Spacer()
            VStack(alignment: .leading, spacing: OCSizing.spacingSM) {
                Text("🗣 How should I talk to you?")
                    .font(OCFont.caption())
                    .foregroundColor(.OC.accent)
                Text("Pick your vibe")
                    .font(OCFont.title())
                    .foregroundColor(.OC.textPrimary)
            }
            .padding(.horizontal, OCSizing.spacingLG)

            ForEach(CommunicationStyle.allCases) { style in
                StyleCard(style: style, selected: persona.style == style) {
                    withAnimation(.spring(response: 0.3)) { persona.style = style }
                }
                .padding(.horizontal, OCSizing.spacingLG)
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
            HStack(spacing: OCSizing.spacingMD) {
                Text(style.emoji).font(.title2)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.label).font(OCFont.headline()).foregroundColor(.OC.textPrimary)
                    Text(style.description).font(OCFont.body(13)).foregroundColor(.OC.textSecondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.OC.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(OCSizing.spacingMD)
            .background(selected ? Color.OC.accent.opacity(0.12) : Color.OC.surfaceRaised)
            .cornerRadius(OCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                    .strokeBorder(selected ? Color.OC.accent : Color.OC.border, lineWidth: selected ? 1.5 : 1)
            )
        }
    }
}

// MARK: - Step 4: Interests

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
        VStack(alignment: .leading, spacing: OCSizing.spacingMD) {
            VStack(alignment: .leading, spacing: OCSizing.spacingSM) {
                Text("🌟 What are you into?")
                    .font(OCFont.caption()).foregroundColor(.OC.accent)
                Text("Pick your interests")
                    .font(OCFont.title()).foregroundColor(.OC.textPrimary)
                Text("Your companion will bring these up and send relevant updates.")
                    .font(OCFont.body()).foregroundColor(.OC.textSecondary)
            }
            .padding(.horizontal, OCSizing.spacingLG)

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
                            Text(interest.label).font(OCFont.caption(11)).foregroundColor(.OC.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selected ? Color.OC.accentSoft : Color.OC.surfaceRaised)
                        .cornerRadius(OCSizing.radiusMD)
                        .overlay(
                            RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                                .strokeBorder(selected ? Color.OC.accent : Color.OC.border, lineWidth: selected ? 1.5 : 1)
                        )
                        .scaleEffect(selected ? 1.04 : 1)
                    }
                }
            }
            .padding(.horizontal, OCSizing.spacingLG)

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
                        .font(.title2).foregroundColor(.OC.accent)
                }
            }
            .padding(.horizontal, OCSizing.spacingLG)
        }
    }
}

// MARK: - Step 6: Provider setup

private struct ProviderStep: View {
    @ObservedObject var persona: UserPersona
    let onComplete: () -> Void

    @State private var apiKey = ""
    @State private var showKey = false
    @State private var checking = false
    @State private var appleAvailable = AppleFoundationModelsBridge.isAvailable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OCSizing.spacingLG) {
                VStack(alignment: .leading, spacing: OCSizing.spacingSM) {
                    Text("🧠 Power up your AI")
                        .font(OCFont.caption()).foregroundColor(.OC.accent)
                    Text("Choose your AI engine")
                        .font(OCFont.title()).foregroundColor(.OC.textPrimary)
                    Text("\(persona.selectedCompanion.name) runs on the engine you choose.")
                        .font(OCFont.body()).foregroundColor(.OC.textSecondary)
                }
                .padding(.horizontal, OCSizing.spacingLG)

                ProviderCard(
                    icon: "applelogo",
                    iconColor: .OC.success,
                    title: "Apple Intelligence",
                    subtitle: "On-device. Free. Private. Requires iPhone 15 Pro or later with iOS 26+.",
                    badge: appleAvailable ? "Available ✓" : "Not available on this device",
                    badgeColor: appleAvailable ? .OC.success : .OC.textMuted,
                    isAvailable: appleAvailable
                ) {
                    Task {
                        await HermesPrivacyGate.shared.acceptOnDeviceOnly()
                        await HermesLLMClient.shared.configure()
                    }
                    onComplete()
                }
                .padding(.horizontal, OCSizing.spacingLG)

                HStack {
                    Rectangle().fill(Color.OC.border).frame(height: 1)
                    Text("or").font(OCFont.caption()).foregroundColor(.OC.textMuted)
                    Rectangle().fill(Color.OC.border).frame(height: 1)
                }
                .padding(.horizontal, OCSizing.spacingLG)

                VStack(alignment: .leading, spacing: OCSizing.spacingSM) {
                    ProviderCard(
                        icon: "cloud.fill",
                        iconColor: .OC.primary,
                        title: "Claude AI",
                        subtitle: "Works on all iPhones right now. Requires a free API key from Anthropic.",
                        badge: "Recommended for Day 1",
                        badgeColor: .OC.primary,
                        isAvailable: true,
                        action: nil
                    )
                    .padding(.horizontal, OCSizing.spacingLG)

                    VStack(alignment: .leading, spacing: OCSizing.spacingSM) {
                        if let consoleURL = URL(string: "https://console.anthropic.com") {
                            Link("→ Get your free API key at console.anthropic.com",
                                 destination: consoleURL)
                                .font(OCFont.caption())
                                .foregroundColor(.OC.primary)
                        }

                        HStack {
                            Group {
                                if showKey {
                                    TextField("sk-ant-...", text: $apiKey)
                                } else {
                                    SecureField("Paste your API key here", text: $apiKey)
                                }
                            }
                            .font(OCFont.mono())
                            .foregroundColor(.OC.textPrimary)

                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                                    .foregroundColor(.OC.textMuted)
                            }
                        }
                        .padding(OCSizing.spacingMD)
                        .background(Color.OC.surface)
                        .cornerRadius(OCSizing.radiusMD)
                        .overlay(
                            RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                                .strokeBorder(apiKey.isEmpty ? Color.OC.border : Color.OC.primary, lineWidth: 1)
                        )

                        Button(action: saveAndContinue) {
                            HStack {
                                if checking {
                                    ProgressView().tint(.black).scaleEffect(0.8)
                                } else {
                                    Text("Save & Meet \(persona.selectedCompanion.name)")
                                        .font(OCFont.headline())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(apiKey.count > 20 ? Color.OC.primary : Color.OC.border)
                            .foregroundColor(apiKey.count > 20 ? .white : .OC.textMuted)
                            .cornerRadius(OCSizing.radiusLG)
                        }
                        .disabled(apiKey.count < 20 || checking)
                    }
                    .padding(.horizontal, OCSizing.spacingLG)
                }
            }
            .padding(.vertical, OCSizing.spacingLG)
        }
    }

    private func saveAndContinue() {
        checking = true
        KeychainHelper.write(service: "com.openclaw.appclaw",
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
            HStack(alignment: .top, spacing: OCSizing.spacingMD) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isAvailable ? iconColor : .OC.textMuted)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: OCSizing.spacingXS) {
                    HStack {
                        Text(title).font(OCFont.headline()).foregroundColor(isAvailable ? .OC.textPrimary : .OC.textMuted)
                        Text(badge).ocBadge(badgeColor)
                    }
                    Text(subtitle).font(OCFont.body(13)).foregroundColor(.OC.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if action != nil && isAvailable {
                    Image(systemName: "arrow.right").foregroundColor(.OC.textMuted)
                }
            }
            .padding(OCSizing.spacingMD)
            .background(isAvailable ? Color.OC.surfaceRaised : Color.OC.surface.opacity(0.5))
            .cornerRadius(OCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                    .strokeBorder(Color.OC.border, lineWidth: 1)
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
            .font(OCFont.body())
            .foregroundColor(.OC.textPrimary)
            .padding(OCSizing.spacingMD)
            .background(Color.OC.surface)
            .cornerRadius(OCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: OCSizing.radiusMD)
                    .strokeBorder(text.isEmpty ? Color.OC.border : Color.OC.primary, lineWidth: 1)
            )
    }
}
