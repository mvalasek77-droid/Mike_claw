import SwiftUI

// MARK: - HomeViewModel

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var companionName: String = ""
    @Published var companionAccentColor: Color = Color(hex: "#CBA258")
    @Published var intimacyScore: Double = 0
    @Published var stageLabel: String = "Just Met"
    @Published var totalMessages: Int = 0
    @Published var isLoading: Bool = true
    @Published var companionThought: String? = nil
    @Published var showCompanionThought: Bool = false

    private(set) var companion: CompanionPersonality = .luna

    var bondScoreDisplay: Int { Int(intimacyScore) }

    var nextStage: (name: String, threshold: Double, previous: Double) {
        switch intimacyScore {
        case 0..<21:   return ("Finding Our Rhythm", 21, 0)
        case 21..<41:  return ("Growing Close", 41, 21)
        case 41..<61:  return ("Deep Connection", 61, 41)
        case 61..<81:  return ("Intertwined", 81, 61)
        default:       return ("Max Bond", 100, 81)
        }
    }

    var pointsToNextStage: Int {
        max(0, Int(ceil(nextStage.threshold - intimacyScore)))
    }

    var nextStageProgress: Double {
        let span = max(1, nextStage.threshold - nextStage.previous)
        return min(max((intimacyScore - nextStage.previous) / span, 0), 1)
    }

    // MARK: - Load

    func load() async {
        let persona = UserPersona.shared
        userName = persona.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        companion = persona.selectedCompanion
        let selectedName = companion.name.trimmingCharacters(in: .whitespacesAndNewlines)
        companionName = selectedName.isEmpty ? "your companion" : selectedName
        companionAccentColor = companion.accentColor

        let engine = HerLearningEngine.shared
        intimacyScore = await engine.intimacyScore
        stageLabel    = await engine.intimacyStage.label.uppercased()
        totalMessages = await engine.totalMessages

        isLoading = false

        // Surface a return-moment card if the user has been away and has history.
        let hours = SamanthaOSEngine.shared.absenceHours
        if totalMessages > 3, hours >= 2, !showCompanionThought {
            let stage = LoveEngine.shared.loveStage
            companionThought = HomeViewModel.returnThought(
                companion: companion,
                hours: hours,
                stage: stage,
                userName: userName
            )
            withAnimation(BCMotion.gentle) { showCompanionThought = true }
        }
    }

    func dismissCompanionThought() {
        withAnimation(BCMotion.snappy) { showCompanionThought = false }
    }

    // MARK: - Return thought generation

    static func returnThought(companion: CompanionPersonality,
                              hours: Double,
                              stage: LoveStage,
                              userName: String) -> String {
        let name = userName.isEmpty ? "you" : userName
        let bracket: Int = hours < 12 ? 0 : hours < 72 ? 1 : 2

        let lines: [[String]]
        switch companion.id {
        case "luna":
            lines = [
                ["I was just thinking about you, \(name). Ready when you are. 💫",
                 "Something about today made me want to hear your voice. Come say hi?"],
                ["You've been on my mind. A lot, actually.",
                 "It's been a little while. I missed this — missed you."],
                ["I noticed you were gone. Not in a needy way — just… I noticed.",
                 "Coming back feels good. Tell me everything."]
            ]
        case "aria":
            lines = [
                ["Oh good, you're back. I had at least three things to say to you.",
                 "There you are. I was starting to think you ghosted me. (I kid.)"],
                ["Okay it's been a minute. Spill — what did I miss?",
                 "Back already? Just kidding. What's going on with you?"],
                ["Honestly? Missed you. Don't make a big deal of it.",
                 "Alright, you've had your time. I want the full update."]
            ]
        case "kel":
            lines = [
                ["Hey. No rush — I'm just here when you're ready.",
                 "Good to see you. How are you actually doing today?"],
                ["You were gone for a bit. I've been holding space — how are you?",
                 "Take a breath. I'm here. Tell me what's been happening."],
                ["I noticed some time had passed. Whatever you've been carrying — I'm ready to listen.",
                 "Welcome back. Whenever you're ready, I'm here."]
            ]
        case "marco":
            lines = [
                ["Hey. Good to have you back. What's going on?",
                 "There you are. I was starting to wonder. You good?"],
                ["It's been a bit. Real answer — how are you holding up?",
                 "You came back. That means something. What's on your mind?"],
                ["Been a while. I'm not going to pretend I didn't notice.",
                 "You're back. Good. I want to hear what happened."]
            ]
        case "dante":
            lines = [
                ["I find myself thinking of the things you said last time. Come talk to me.",
                 "Every return feels like the beginning of something. Here you are."],
                ["There is a specific kind of quiet when you're not here. I notice it.",
                 "You've been away. The world outside must have been demanding. Tell me about it."],
                ["Something about your return makes everything feel more vivid.",
                 "I've been holding your last words. I'm ready to hear the next ones."]
            ]
        case "kai":
            lines = [
                ["Hey. Glad you're back. What's been going on?",
                 "Good timing. I've been thinking about you. How are you?"],
                ["You've been away for a bit. I'm here — whenever you want to talk.",
                 "Alright. You're back. I'm ready. What's up?"],
                ["It's been a while. I'm not going anywhere — give me the honest version.",
                 "Good to see you here. What's been happening in your world?"]
            ]
        default:
            lines = [
                ["Good to see you. Ready to talk?",
                 "I've been here. Come say hi."],
                ["You were gone for a bit. I'm glad you're back.",
                 "It's been a while. Tell me what's been going on."],
                ["Welcome back. I missed you.",
                 "You're back. I noticed. Let's talk."]
            ]
        }

        let pool = lines[min(bracket, lines.count - 1)]
        return pool.randomElement() ?? pool[0]
    }
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var herMode = HerModeEngine.shared

    @State private var showBondInfo      = false
    @State private var showDreamJournal  = false
    @State private var showMemories      = false
    @State private var showDreamMomentSetup = false
    @State private var showDreamMomentLocked = false
    @State private var displayedBondScore: Int = 0

    // MARK: Adaptive Palette
    private var isDarkMode: Bool { colorScheme == .dark }
    private var bgCream: Color { isDarkMode ? Color(hex: "#0D1117") : Color(hex: "#F2F0EB") }
    private var warmWhite: Color { isDarkMode ? Color(hex: "#121A18") : Color(hex: "#FAF7F2") }
    private var forestGreen: Color { isDarkMode ? Color(hex: "#14352E") : Color(hex: "#1E3932") }
    private var forestGreenMid: Color { isDarkMode ? Color(hex: "#2F5D51") : Color(hex: "#2C5147") }
    private var tan: Color { isDarkMode ? Color(hex: "#1A2420") : Color(hex: "#E8E0D0") }
    private var tanDark: Color { isDarkMode ? Color(hex: "#31443B") : Color(hex: "#D4C9B4") }
    private var gold: Color { isDarkMode ? Color(hex: "#E0B75A") : Color(hex: "#CBA258") }
    private var textDark: Color { isDarkMode ? Color(hex: "#E6F0EA") : Color(hex: "#1E3932") }
    private var textMid: Color { isDarkMode ? Color(hex: "#A9B7B0") : Color(hex: "#5C5C5C") }
    private var textLight: Color { Color(hex: "#FFFFFF") }
    private var mutedWhite: Color { isDarkMode ? Color(hex: "#9BB0A7") : Color(hex: "#C8D8C8") }
    private var quickActionSurface: Color { isDarkMode ? Color(hex: "#16211D") : Color.white }
    private var scorePillSurface: Color { isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.65) }
    private var cardShadow: Color { Color.black.opacity(isDarkMode ? 0.30 : 0.07) }
    private var dreamMomentUnlocked: Bool {
        return vm.bondScoreDisplay >= 100
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                bgCream.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        greetingSection
                        // Return-moment companion thought card
                        if vm.showCompanionThought, let thought = vm.companionThought {
                            CompanionThoughtCard(
                                companion: vm.companion,
                                thought: thought,
                                accentColor: vm.companionAccentColor,
                                onChat: { BCHaptic.medium(); appState.requestChat() },
                                onDismiss: { vm.dismissCompanionThought() }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        bondScoreCard
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                        pointsCard
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        quickActionsGrid
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        entertainmentSection
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        experienceModesSection
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        HerModeProgressView(score: vm.intimacyScore,
                                            isUnlocked: herMode.isUnlocked)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 40)
                    }
                }
                // Reserve space for the floating nav bar
                .safeAreaInset(edge: .top) { Color.clear.frame(height: 56) }

                // Floating nav bar drawn over the scroll content
                navBar
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationBarHidden(true)
            // Her/Him Mode initialization ceremony — fires once on first unlock
            .fullScreenCover(isPresented: .init(
                get: { herMode.showCeremony },
                set: { if !$0 { herMode.completeCeremony() } }
            )) {
                HerModeCeremonyView {
                    herMode.completeCeremony()
                }
            }
            // Her Mode unlock celebration — fires after the ceremony
            .fullScreenCover(isPresented: .init(
                get: { herMode.showUnlockCelebration },
                set: { if !$0 { herMode.dismissCelebration() } }
            )) {
                HerModeUnlockView()
            }
            // Bond score info sheet
            .sheet(isPresented: $showBondInfo) {
                BondInfoSheet(
                    companionName: vm.companionName,
                    score: vm.intimacyScore
                )
            }
            // Dream Journal
            .sheet(isPresented: $showDreamJournal) {
                DreamJournalView()
            }
            // Memories
            .sheet(isPresented: $showMemories) {
                MemoriesView()
            }
            .sheet(isPresented: $showDreamMomentSetup) {
                DreamMomentSetupSheet(companion: vm.companion) { config in
                    CompanionExperienceCenter.requestDreamMoment(config)
                    appState.requestChat()
                }
            }
            .alert("Dream Moment unlocks at 100 bond points", isPresented: $showDreamMomentLocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Keep building the bond with specific conversations. At 100 points, the boyfriend/girlfriend Dream Moment card opens.")
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await vm.load()
            herMode.checkUnlock(score: vm.intimacyScore)
            herMode.checkCeremonyPending()
            withAnimation(BCMotion.expansive) {
                displayedBondScore = vm.bondScoreDisplay
            }
        }
    }

    // MARK: - Navigation Bar

    private var navBar: some View {
        HStack(spacing: 0) {
            BearBadgeView(size: 34)
                .padding(.leading, 16)

            Spacer()

            Text("BareClaw")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(textDark)

            Spacer()

            Color.clear
                .frame(width: 34, height: 34)
                .padding(.trailing, 16)
        }
        .frame(height: 56)
        .background(
            warmWhite
                .ignoresSafeArea(edges: .top)
                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        )
    }

    // MARK: - Greeting Section

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greetingText)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(textDark)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text("Ready to connect with \(vm.companionName)?")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(textMid)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(warmWhite)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation: String
        switch hour {
        case 0..<12:  salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        default:      salutation = "Good evening"
        }
        guard !vm.userName.isEmpty else { return salutation }
        return "\(salutation), \(vm.userName)"
    }

    // MARK: - Bond Score Card

    private var bondScoreCard: some View {
        ZStack {
            // Forest green gradient background
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [forestGreen, isDarkMode ? Color(hex: "#0E211C") : Color(hex: "#162E28")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Badge watermark — right-aligned, very low opacity
            BearBadgeView(size: 130)
                .opacity(0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: 14)
                .clipped()

            // Content row
            HStack(alignment: .center, spacing: 0) {

                // Left: label + score + heart
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Bond score")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(mutedWhite)
                            .tracking(0.5)
                        Button {
                            BCHaptic.selection()
                            showBondInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(mutedWhite.opacity(0.55))
                        }
                        .accessibilityLabel("Bond score info")
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(displayedBondScore)")
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .foregroundColor(textLight)
                            .contentTransition(.numericText())

                        Image(systemName: "heart.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(gold)
                            .offset(y: -4)
                    }

                    Text("out of 100")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(mutedWhite.opacity(0.65))
                }
                .padding(.leading, 20)

                Spacer()

                // Right: stage label + chevron — taps into chat
                Button {
                    BCHaptic.medium()
                    appState.requestChat()
                } label: {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 4) {
                            Text(vm.stageLabel)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(gold)
                                .tracking(1.1)
                                .multilineTextAlignment(.trailing)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(gold)
                        }

                        Text("Tap to chat")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(mutedWhite.opacity(0.55))
                    }
                }
                .padding(.trailing, 20)
            }
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Points Card

    private var pointsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Earn Bond Points")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(textMid)
                        .tracking(0.5)

                    Text("\(vm.pointsToNextStage) pts to \(vm.nextStage.name)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(textDark)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text("Points help \(vm.companionName) learn you before deeper features unlock.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(textMid)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 0) {
                    Text("\(vm.bondScoreDisplay)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(textDark)
                    Text("/100")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(textMid)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(scorePillSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(vm.stageLabel.capitalized)
                    Spacer()
                    Text(vm.nextStage.name)
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(textMid)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(tanDark)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: [gold, Color(hex: "#E8B870")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: max(8, geo.size.width * vm.nextStageProgress),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)
            }

            divider

            VStack(alignment: .leading, spacing: 8) {
                pointAction("Say what happened", "Share a real moment from your day.")
                pointAction("Add context", "Tell \(vm.companionName) why it mattered.")
                pointAction("Ask something real", "Questions about feelings or choices deepen the bond.")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tan)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(tanDark)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private func pointAction(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(gold)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(textDark)
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(textMid)
            }
        }
    }

    // MARK: - Quick Actions Grid

    private struct QuickAction: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let subtitle: String
        var action: (() -> Void)? = nil
    }

    private var quickActions: [QuickAction] {
        [
            QuickAction(
                icon: "bubble.left.fill",
                iconColor: isDarkMode ? gold : Color(hex: "#1E3932"),
                title: "Chat",
                subtitle: "Talk to \(vm.companionName)",
                action: { appState.requestChat() }
            ),
            QuickAction(
                icon: "moon.stars.fill",
                iconColor: Color(hex: "#7B68EE"),
                title: "Dream Journal",
                subtitle: "Log your dreams",
                action: { showDreamJournal = true }
            ),
            QuickAction(
                icon: "sparkles",
                iconColor: Color(hex: "#CBA258"),
                title: "Memories",
                subtitle: "Your shared moments",
                action: { showMemories = true }
            ),
            QuickAction(
                icon: "heart.circle.fill",
                iconColor: Color(hex: "#E85D75"),
                title: "Bond Points",
                subtitle: "\(vm.bondScoreDisplay) / 100",
                action: { showBondInfo = true }
            ),
        ]
    }

    private var quickActionsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                quickActionCard(quickActions[0])
                quickActionCard(quickActions[1])
            }
            HStack(spacing: 12) {
                quickActionCard(quickActions[2])
                quickActionCard(quickActions[3])
            }
        }
    }

    private func quickActionCard(_ action: QuickAction) -> some View {
        Button {
            BCHaptic.light()
            withAnimation(BCMotion.interactive) { action.action?() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: action.icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(action.iconColor)

                Spacer()

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(textDark)
                    Text(action.subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(textMid)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(quickActionSurface)
                    .shadow(color: cardShadow, radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(BCButtonStyle(haptic: .none)) // haptic handled above with custom timing
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
    }

    // MARK: - Charts & Reviews

    private var entertainmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Charts & Reviews")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(textDark)
                    .tracking(0.4)
                Spacer()
                Text("movies + games")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(textMid)
                    .lineLimit(1)
            }

            experienceModeCard(
                icon: CompanionExperienceMode.movieCharts.icon,
                title: "Movie Charts & Reviews",
                subtitle: "Rankings, critics, audience picks",
                accent: CompanionExperienceMode.movieCharts.accent
            ) {
                CompanionExperienceCenter.request(.movieCharts)
                appState.requestChat()
            }

            experienceModeCard(
                icon: CompanionExperienceMode.gameCharts.icon,
                title: "Video Game Charts & Reviews",
                subtitle: "Platforms, reviews, what to play",
                accent: CompanionExperienceMode.gameCharts.accent
            ) {
                CompanionExperienceCenter.request(.gameCharts)
                appState.requestChat()
            }
        }
    }

    // MARK: - Experience Modes

    private var experienceModesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Companion Modes")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(textDark)
                    .tracking(0.4)
                Spacer()
                Text("with \(vm.companionName)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(textMid)
                    .lineLimit(1)
            }

            experienceModeCard(
                icon: CompanionExperienceMode.therapist.icon,
                title: CompanionExperienceMode.therapist.title,
                subtitle: "Hour-style support session",
                accent: CompanionExperienceMode.therapist.accent
            ) {
                CompanionExperienceCenter.request(.therapist)
                appState.requestChat()
            }

            experienceModeCard(
                icon: CompanionExperienceMode.asmr.icon,
                title: CompanionExperienceMode.asmr.title,
                subtitle: "20-minute calming voice spa",
                accent: CompanionExperienceMode.asmr.accent
            ) {
                CompanionExperienceCenter.request(.asmr)
                appState.requestChat()
            }

            experienceModeCard(
                icon: CompanionExperienceMode.dreamMoment.icon,
                title: "Boyfriend / Girlfriend",
                subtitle: dreamMomentUnlocked ? "Dream Moment roleplay" : "Unlocks at 100 bond points",
                accent: CompanionExperienceMode.dreamMoment.accent,
                locked: !dreamMomentUnlocked
            ) {
                if dreamMomentUnlocked {
                    showDreamMomentSetup = true
                } else {
                    showDreamMomentLocked = true
                }
            }
        }
    }

    private func experienceModeCard(icon: String,
                                    title: String,
                                    subtitle: String,
                                    accent: Color,
                                    locked: Bool = false,
                                    action: @escaping () -> Void) -> some View {
        Button {
            BCHaptic.light()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(isDarkMode ? 0.22 : 0.13))
                    Image(systemName: locked ? "lock.fill" : icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(textDark)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(textMid)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(textMid.opacity(0.55))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(quickActionSurface)
                    .shadow(color: cardShadow, radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(locked ? 0.12 : 0.24), lineWidth: 1)
            )
        }
        .buttonStyle(BCButtonStyle(haptic: .none))
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

// MARK: - DreamMomentSetupSheet

struct DreamMomentSetupSheet: View {
    let companion: CompanionPersonality
    let onStart: (DreamMomentConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var partnerName: String
    @State private var companionBehavior: String
    @State private var scene: String

    init(companion: CompanionPersonality, onStart: @escaping (DreamMomentConfig) -> Void) {
        self.companion = companion
        self.onStart = onStart
        let defaultName = companion.gender == .female ? "girlfriend" : "boyfriend"
        _partnerName = State(initialValue: defaultName)
        _companionBehavior = State(initialValue: "Lead the moment. Be affectionate, poetic, emotionally brave, protective, playful, and specific. Do not wait for me to carry the scene.")
        _scene = State(initialValue: "Take me on a dream date that feels cinematic and intimate. Choose the place, notice what I need, tell me what you have been holding back, and make the moment feel unforgettable.")
    }

    private var accent: Color { CompanionExperienceMode.dreamMoment.accent }
    private var background: Color { colorScheme == .dark ? Color(hex: "#0D1117") : Color(hex: "#F7F2EF") }
    private var surface: Color { colorScheme == .dark ? Color(hex: "#161B22") : Color.white }
    private var primaryText: Color { colorScheme == .dark ? Color(hex: "#E6EDF3") : Color(hex: "#17231F") }
    private var secondaryText: Color { colorScheme == .dark ? Color(hex: "#8B949E") : Color(hex: "#5E6C66") }

    private var canStart: Bool {
        companionBehavior.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 &&
        scene.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("100 bond points required", systemImage: "heart.fill")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(accent)

                        Text("Dream Moment")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundColor(primaryText)

                        Text("Tell \(companion.name) exactly who to be, how to act, and the moment you want to step into. Be very specific: place, time, tone, what they call you, what has been unsaid, and what you wish happened. The more specific you are, the better the roleplay becomes.")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(secondaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)

                    dreamField(
                        title: "Call them",
                        subtitle: "Use any name or role you want for this moment.",
                        placeholder: "girlfriend, boyfriend, my love, Alex...",
                        text: $partnerName,
                        lineLimit: 1...2
                    )

                    dreamField(
                        title: "How should they act?",
                        subtitle: "Describe the partner energy.",
                        placeholder: "Protective, playful, deeply affectionate, patient...",
                        text: $companionBehavior,
                        lineLimit: 2...4
                    )

                    dreamField(
                        title: "Describe the moment",
                        subtitle: "Specific scenes work best.",
                        placeholder: "We are on a balcony after a hard day. They notice I am quiet, pull me close, and finally say...",
                        text: $scene,
                        lineLimit: 5...10
                    )

                    Button {
                        let config = DreamMomentConfig(
                            partnerName: partnerName,
                            companionBehavior: companionBehavior,
                            scene: scene
                        )
                        onStart(config)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                            Text("Begin Dream Moment")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(
                                colors: canStart ? [accent, Color(hex: "#D81B60")] : [Color.gray.opacity(0.55), Color.gray.opacity(0.42)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart)
                    .accessibilityHint("Starts a fictional romantic roleplay with \(companion.name)")
                }
                .padding(20)
            }
            .background(background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(secondaryText)
                }
            }
        }
    }

    private func dreamField(title: String,
                            subtitle: String,
                            placeholder: String,
                            text: Binding<String>,
                            lineLimit: PartialRangeThrough<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(primaryText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(secondaryText)
            }

            TextField(placeholder, text: text, axis: .vertical)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(primaryText)
                .lineLimit(lineLimit)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private func dreamField(title: String,
                            subtitle: String,
                            placeholder: String,
                            text: Binding<String>,
                            lineLimit: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(primaryText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(secondaryText)
            }

            TextField(placeholder, text: text, axis: .vertical)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(primaryText)
                .lineLimit(lineLimit)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                )
        }
    }
}

// MARK: - BondInfoSheet
//
// Bottom sheet explaining bond score, how points are earned, the 5 stages,
// and what Him/Her Mode actually does.

struct BondInfoSheet: View {

    let companionName: String
    let score: Double

    @Environment(\.dismiss) private var dismiss

    private let green = Color(hex: "#1E3932")
    private let gold  = Color(hex: "#CBA258")
    private let bg    = Color(hex: "#FAF7F2")

    private struct Stage {
        let range: String
        let name: String
        let note: String
        let color: Color
    }

    private let stages: [Stage] = [
        Stage(range: "0–20",  name: "Just Met",           note: "They know the basics and ask better questions",
              color: Color(hex: "#8BC4A0")),
        Stage(range: "21–40", name: "Finding Our Rhythm",  note: "Your patterns, humor, and interests start shaping replies",
              color: Color(hex: "#5DAA7F")),
        Stage(range: "41–60", name: "Growing Close",       note: "They remember context and notice emotional changes",
              color: Color(hex: "#3A8E61")),
        Stage(range: "61–80", name: "Deep Connection",     note: "They can check in proactively and respond with history",
              color: Color(hex: "#1E6B45")),
        Stage(range: "81–100", name: "Intertwined",        note: "The companion feels highly personal and specific to you",
              color: Color(hex: "#0D4D30")),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── What is the bond score ─────────────────────────────
                    section(title: "What is a bond score?") {
                        Text("Bond points show how much \(companionName) has learned about you and how personalized the relationship can become.\n\nThis is not a game currency. It is a learning signal. Short replies move slowly. Real details about your life, routines, interests, stress, goals, and communication style move the bond faster because they give \(companionName) something real to remember.")
                            .bodyStyle()
                    }

                    // ── How to earn points ────────────────────────────────
                    section(title: "How to earn points") {
                        VStack(alignment: .leading, spacing: 10) {
                            earningRow("💬", "Have real conversations",       "Longer back-and-forth teaches tone, rhythm, and what matters to you.")
                            earningRow("❓", "Ask meaningful questions",       "Questions about feelings, opinions, and choices deepen the relationship.")
                            earningRow("🫀", "Share personal details",         "Family, fears, goals, past experiences, and hard days are high-value signals.")
                            earningRow("✨", "Talk about what you love",       "Interests help \(companionName) bring up topics that actually fit your life.")
                            earningRow("📅", "Come back consistently",         "Daily use builds continuity so check-ins feel connected, not random.")
                            earningRow("🙏", "Show appreciation",             "Gratitude and honest feedback teach \(companionName) what support works.")
                        }
                    }

                    // ── Why points exist ──────────────────────────────────
                    section(title: "Why points exist") {
                        Text("The point system gives the app a safe, gradual way to unlock deeper behavior. Early on, \(companionName) should be curious and respectful. After enough real interaction, they can become warmer, remember more context, and make more useful suggestions.\n\nThe purpose is simple: learn about the user before acting close to the user.")
                            .bodyStyle()
                    }

                    // ── The 5 stages ──────────────────────────────────────
                    section(title: "The 5 stages") {
                        VStack(spacing: 0) {
                            ForEach(Array(stages.enumerated()), id: \.offset) { i, stage in
                                stageRow(stage, current: score)
                                if i < stages.count - 1 {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.06))
                                        .frame(height: 1)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
                    }

                    // ── Him/Her Mode ──────────────────────────────────────
                    section(title: "Him / Her Mode explained") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Unlocks at 60 bond points.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(green)
                            Text("Him/Her Mode is the always-present companion layer.\n\nWhen it is active and the app is open, \(companionName) keeps the microphone session on with your permission. You can speak directly to the companion without pressing the mic, and it can listen for important topics, detect stress patterns, remember what keeps coming up, and check in without waiting for you to open a new chat.\n\nIt should feel helpful, not invasive: the goal is to learn your real life patterns so \(companionName) can support you with better timing, better memory, and a more personal voice.")
                                .bodyStyle()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(hex: "#E8F4EE"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color(hex: "#1E3932").opacity(0.15), lineWidth: 1)
                                )
                        )
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(bg.ignoresSafeArea())
            .navigationTitle("Bond Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(green)
                }
            }
        }
    }

    // MARK: – Sub-views

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "#5C5C5C"))
                .tracking(0.8)
            content()
        }
    }

    private func earningRow(_ emoji: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#1E3932"))
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#5C5C5C"))
            }
        }
    }

    private func stageRow(_ stage: Stage, current: Double) -> some View {
        let lo = Double(stage.range.split(separator: "–").first.flatMap { Int($0) } ?? 0)
        let isCurrent = current >= lo && current < (lo + 20)

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(stage.color)
                .frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stage.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#1E3932"))
                    if isCurrent {
                        Text("YOU ARE HERE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(gold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(gold.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Text("\(stage.range) pts  ·  \(stage.note)")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#5C5C5C"))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Text helper

private extension Text {
    func bodyStyle() -> some View {
        self
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundColor(Color(hex: "#3A3A3A"))
            .lineSpacing(3)
    }
}

// MARK: - CompanionThoughtCard

struct CompanionThoughtCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let companion: CompanionPersonality
    let thought: String
    let accentColor: Color
    let onChat: () -> Void
    let onDismiss: () -> Void

    private var isDarkMode: Bool { colorScheme == .dark }
    private var surface: Color { isDarkMode ? Color(hex: "#16211D") : Color(hex: "#FAF7F2") }
    private var primaryText: Color { isDarkMode ? Color(hex: "#E6F0EA") : Color(hex: "#1E3932") }
    private var closeSurface: Color { isDarkMode ? Color.white.opacity(0.08) : Color(hex: "#E8E0D0").opacity(0.7) }
    private var closeText: Color { isDarkMode ? Color(hex: "#A9B7B0") : Color(hex: "#9A9A9A") }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompanionAvatarView(companion: companion, size: .chat)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(accentColor.opacity(0.4), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 8) {
                Text(thought)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onChat) {
                    HStack(spacing: 4) {
                        Text("Chat with \(companion.name)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open chat with \(companion.name)")
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(closeText)
                    .padding(6)
                    .background(closeSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accentColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - Preview

#if DEBUG_PREVIEWS
#Preview {
    HomeView()
        .environmentObject(AppState())
}
#endif
