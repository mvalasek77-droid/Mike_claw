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
        let selectedName = persona.selectedCompanion.name.trimmingCharacters(in: .whitespacesAndNewlines)
        companionName = selectedName.isEmpty ? "your companion" : selectedName
        companionAccentColor = persona.selectedCompanion.accentColor

        let engine = HerLearningEngine.shared
        intimacyScore = await engine.intimacyScore
        stageLabel    = await engine.intimacyStage.label.uppercased()
        totalMessages = await engine.totalMessages

        isLoading = false
    }
}

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var herMode = HerModeEngine.shared

    @State private var showBondInfo     = false
    @State private var showDreamJournal = false
    @State private var showMemories     = false

    // MARK: Palette (warm Starbucks-inspired light theme)
    private let bgCream        = Color(hex: "#F2F0EB")
    private let warmWhite      = Color(hex: "#FAF7F2")
    private let forestGreen    = Color(hex: "#1E3932")
    private let forestGreenMid = Color(hex: "#2C5147")
    private let tan            = Color(hex: "#E8E0D0")
    private let tanDark        = Color(hex: "#D4C9B4")
    private let gold           = Color(hex: "#CBA258")
    private let textDark       = Color(hex: "#1E3932")
    private let textMid        = Color(hex: "#5C5C5C")
    private let textLight      = Color(hex: "#FFFFFF")
    private let mutedWhite     = Color(hex: "#C8D8C8")

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                bgCream.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        greetingSection
                        bondScoreCard
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                        pointsCard
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        quickActionsGrid
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
        }
        .navigationViewStyle(.stack)
        .task {
            await vm.load()
            herMode.checkUnlock(score: vm.intimacyScore)
            herMode.checkCeremonyPending()
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
                        colors: [forestGreen, Color(hex: "#162E28")],
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
                        Text("\(vm.bondScoreDisplay)")
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .foregroundColor(textLight)

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
                .background(Color.white.opacity(0.65))
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
                iconColor: Color(hex: "#1E3932"),
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
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(BCButtonStyle(haptic: .none)) // haptic handled above with custom timing
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
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
                            Text("Unlocks at 61 bond points — the Deep Connection stage.")
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

// MARK: - Preview

#if DEBUG_PREVIEWS
#Preview {
    HomeView()
        .environmentObject(AppState())
}
#endif
