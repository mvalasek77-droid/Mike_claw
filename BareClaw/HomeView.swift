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

    // Streak / engagement data (derived from message history in future)
    @Published var streakDays: Int = 3
    @Published var daysRemaining: Int = 2
    @Published var completedDayIndices: Set<Int> = [0, 1, 2]   // M=0 T=1 W=2 T=3

    private let calendar = Calendar.current

    /// 0-based index into [M, T, W, T] matching today's weekday (clamped to 0–3).
    var todayDayIndex: Int {
        let weekday = calendar.component(.weekday, from: Date())
        // weekday: Sun=1, Mon=2, Tue=3, … Sat=7  →  Mon=0, Tue=1, …
        let mondayBased = (weekday + 5) % 7
        return min(mondayBased, 3)
    }

    var todayWeekdayName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return fmt.string(from: Date())
    }

    /// 0.0–1.0 progress between 20 and 50 bond points.
    var bondPointsProgress: Double {
        let clamped = min(max(intimacyScore, 20), 50)
        return (clamped - 20) / 30.0
    }

    var bondScoreDisplay: Int { Int(intimacyScore) }

    // MARK: - Load

    func load() async {
        let persona = UserPersona.load()
        userName = persona.userName.isEmpty ? "Friend" : persona.userName
        companionName = persona.selectedCompanion.name
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
                        streakCard
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        quickActionsGrid
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                        // Her Mode progress / status
                        HerModeProgressView(score: vm.intimacyScore,
                                            isUnlocked: HerModeEngine.shared.isUnlocked)
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
            .preferredColorScheme(.light)
            // Her Mode unlock celebration
            .fullScreenCover(isPresented: .init(
                get: { HerModeEngine.shared.showUnlockCelebration },
                set: { if !$0 { HerModeEngine.shared.dismissCelebration() } }
            )) {
                HerModeUnlockView()
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await vm.load()
            // Check if Her Mode should be unlocked based on current score
            HerModeEngine.shared.checkUnlock(score: vm.intimacyScore)
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

            HStack(spacing: 2) {
                Button {
                    // notifications tapped
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(textDark)
                        .frame(width: 38, height: 38)
                }
                Button {
                    // profile tapped
                } label: {
                    Image(systemName: "person.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(textDark)
                        .frame(width: 38, height: 38)
                }
            }
            .padding(.trailing, 8)
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
                .fixedSize(horizontal: false, vertical: true)

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
        let name = vm.userName.isEmpty ? "Friend" : vm.userName
        return "\(salutation), \(name) 🐾"
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
                    Text("Bond score")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(mutedWhite)
                        .tracking(0.5)

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
                    appState.currentMode = .chat
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

    // MARK: - Streak Card

    private let dayLabels = ["M", "T", "W", "T"]

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header: earn label + points + days remaining ──────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("Earn")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(textMid)
                    .tracking(0.5)

                Text("50 Bond Points")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(textDark)

                Text("\(vm.daysRemaining) day\(vm.daysRemaining == 1 ? "" : "s") remaining")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(textMid)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // ── Day bubbles: M T W T ──────────────────────────────────────
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    dayBubble(index: i)
                }
            }
            .padding(.horizontal, 20)

            // ── Italic motivational subtitle ──────────────────────────────
            Text("It's \(vm.todayWeekdayName)! Ready...go!")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .italic()
                .foregroundColor(textMid)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            // ── Divider ───────────────────────────────────────────────────
            divider
                .padding(.top, 14)

            // ── Progress bar: 20♥ → 50♥ ──────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("20♥")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(textMid)
                    Spacer()
                    Text("50♥")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(textMid)
                }

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
                                width: max(8, geo.size.width * vm.bondPointsProgress),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // ── Divider ───────────────────────────────────────────────────
            divider
                .padding(.top, 14)

            // ── Rules bullet list ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text("Chat at least 4 days in a row")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(textDark)

                VStack(alignment: .leading, spacing: 6) {
                    streakBullet("Send at least one message each day")
                    streakBullet("Your streak resets at midnight")
                    streakBullet("Bonus points unlock at stage 4+")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
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

    private func dayBubble(index: Int) -> some View {
        let isCompleted = vm.completedDayIndices.contains(index)
        let isToday     = index == vm.todayDayIndex

        return ZStack {
            // Base fill: dark green if completed, clear if not
            Circle()
                .fill(isCompleted ? forestGreen : Color.clear)
                .frame(width: 44, height: 44)

            // Outline ring for incomplete days
            if !isCompleted {
                Circle()
                    .strokeBorder(forestGreen.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
            }

            // Gold outer ring for today's bubble
            if isToday {
                Circle()
                    .strokeBorder(gold, lineWidth: 2.5)
                    .frame(width: 50, height: 50)
            }

            Text(dayLabels[index])
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(isCompleted ? textLight : textDark.opacity(0.55))
        }
        .frame(width: 50, height: 50)
    }

    private func streakBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(gold)
                .frame(width: 5, height: 5)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(textMid)
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
                action: { appState.currentMode = .chat }
            ),
            QuickAction(
                icon: "moon.stars.fill",
                iconColor: Color(hex: "#7B68EE"),
                title: "Dream Journal",
                subtitle: "Log your dreams"
            ),
            QuickAction(
                icon: "sparkles",
                iconColor: Color(hex: "#CBA258"),
                title: "Memories",
                subtitle: "Your shared moments"
            ),
            QuickAction(
                icon: "heart.circle.fill",
                iconColor: Color(hex: "#E85D75"),
                title: "Bond Points",
                subtitle: "\(vm.bondScoreDisplay) / 100"
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
            action.action?()
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
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    HomeView()
        .environmentObject(AppState())
}
#endif
