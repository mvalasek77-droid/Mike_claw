import SwiftUI

// MARK: - MainTabView
//
// Root tab container for BareClaw.
// Tabs: Home (0) | Chat (1) | Vibes (2) | You (3)
//
// Observes appState.currentMode — when it flips to .chat, programmatically
// jumps to tab 1 so any part of the app can trigger the chat screen.

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Int = 0

    /// Forest green matches the home screen palette used throughout the app.
    private let tabTint = Color(hex: "#1E3932")

    var body: some View {
        TabView(selection: $selectedTab) {

            // MARK: Tab 0 — Home
            HomeView()
                .environmentObject(appState)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // MARK: Tab 1 — Chat
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.fill")
                }
                .tag(1)

            // MARK: Tab 2 — Vibes
            CompanionTikTokView()
                .environmentObject(appState)
                .tabItem {
                    Label("Vibes", systemImage: "play.square.stack.fill")
                }
                .tag(2)

            // MARK: Tab 3 — You
            ProfileView()
                .tabItem {
                    Label("You", systemImage: "person.fill")
                }
                .tag(3)
        }
        .tint(tabTint)
        // React to mode changes driven from anywhere in the app
        .onChange(of: appState.currentMode) { newMode in
            if newMode == .chat {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = 1
                }
            }
        }
    }
}

// MARK: - ProfileViewModel

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var userName:       String = ""
    @Published var companionName:  String = ""
    @Published var companionId:    String = "luna"
    @Published var companionGender: CompanionGender = .female
    @Published var accentColor:    Color  = Color(hex: "#CBA258")
    @Published var intimacyScore:  Double = 0
    @Published var stageLabel:     String = "Just Met"
    @Published var stageNumber:    Int    = 1
    @Published var totalMessages:  Int    = 0
    @Published var memoriesCount:  Int    = 0
    @Published var isLoading:      Bool   = true

    func load() async {
        let persona    = UserPersona.load()
        userName       = persona.userName.isEmpty ? "Friend" : persona.userName
        let companion  = persona.selectedCompanion
        companionName  = companion.name
        companionId    = companion.id
        companionGender = companion.gender
        accentColor    = companion.accentColor

        let engine = HerLearningEngine.shared
        intimacyScore  = await engine.intimacyScore
        let stage      = await engine.intimacyStage
        stageLabel     = stage.label
        stageNumber    = stage.rawValue
        totalMessages  = await engine.totalMessages

        let facts      = await HermesMemory.shared.entries(for: "user_fact")
        memoriesCount  = facts.count

        isLoading = false
    }

    /// 0–1 progress within the current 20-point stage band.
    var stageProgress: Double {
        let lower = Double(stageNumber - 1) * 20.0
        let upper = Double(stageNumber)     * 20.0
        let clamped = min(max(intimacyScore, lower), upper)
        return (clamped - lower) / 20.0
    }

    var bondScoreDisplay: Int { Int(intimacyScore) }
}

// MARK: - ProfileView

struct ProfileView: View {
    @StateObject private var vm = ProfileViewModel()

    private let bg     = Color(hex: "#F2F0EB")
    private let green  = Color(hex: "#1E3932")
    private let gold   = Color(hex: "#CBA258")
    private let tan    = Color(hex: "#E8E0D0")
    private let card   = Color(hex: "#FFFFFF")
    private let mid    = Color(hex: "#5C5C5C")

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if vm.isLoading {
                ProgressView()
                    .tint(green)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                        statsSection
                        bondSection
                        stageSection
                        Spacer(minLength: 32)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .task { await vm.load() }
    }

    // MARK: – Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            // Portrait + username
            ZStack(alignment: .bottom) {
                // Companion portrait — tall, full-width
                IllustratedPortraitView(
                    gender:      vm.companionGender,
                    companionId: vm.companionId,
                    accentColor: vm.accentColor,
                    size:        UIScreen.main.bounds.width,
                    clipToCircle: false
                )
                .frame(height: 320)
                .clipped()

                // Gradient fade to bg
                LinearGradient(
                    colors: [.clear, bg.opacity(0.85), bg],
                    startPoint: .init(x: 0.5, y: 0.55),
                    endPoint:   .bottom
                )
                .frame(height: 320)

                // Name + greeting
                VStack(spacing: 4) {
                    Text(vm.companionName)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(green)
                    Text("Your companion")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(mid)
                }
                .padding(.bottom, 20)
            }

            // User greeting
            Text("Hey, \(vm.userName) 👋")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(green.opacity(0.75))
                .padding(.top, 4)
                .padding(.bottom, 20)
        }
    }

    // MARK: – Stats row

    private var statsSection: some View {
        HStack(spacing: 12) {
            statCard(value: "\(vm.totalMessages)", label: "Messages", icon: "bubble.left.and.bubble.right.fill")
            statCard(value: "\(vm.memoriesCount)", label: "Memories", icon: "heart.text.square.fill")
            statCard(value: "\(vm.bondScoreDisplay)", label: "Bond Score", icon: "star.fill")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(gold)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(green)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(mid)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(card)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }

    // MARK: – Bond card

    private var bondSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bond Level")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                    Text(vm.stageLabel)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                // Badge watermark
                BearBadgeView(size: 52)
                    .opacity(0.18)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gold)
                        .frame(width: geo.size.width * vm.stageProgress, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(vm.bondScoreDisplay) pts")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(gold)
                Spacer()
                Text("Stage \(vm.stageNumber) of 5")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.55))
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#2A4A42"), green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: – Stage roadmap

    private let stages: [(String, String)] = [
        ("Just Met",           "star"),
        ("Finding Our Rhythm", "music.note"),
        ("Growing Close",      "leaf.fill"),
        ("Deep Connection",    "heart.fill"),
        ("Intertwined",        "infinity")
    ]

    private var stageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relationship Journey")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(green)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { idx, stage in
                    let reached = (idx + 1) <= vm.stageNumber
                    let current = (idx + 1) == vm.stageNumber

                    HStack(spacing: 14) {
                        // Icon circle
                        ZStack {
                            Circle()
                                .fill(reached ? green : tan)
                                .frame(width: 36, height: 36)
                            if current {
                                Circle()
                                    .strokeBorder(gold, lineWidth: 2)
                                    .frame(width: 36, height: 36)
                            }
                            Image(systemName: stage.1)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(reached ? .white : Color(hex: "#9A9288"))
                        }

                        // Label
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stage.0)
                                .font(.system(size: 14, weight: current ? .bold : .medium, design: .rounded))
                                .foregroundColor(reached ? green : mid)
                            if current {
                                Text("Current stage")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(gold)
                            }
                        }

                        Spacer()

                        if reached && !current {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(green.opacity(0.65))
                                .font(.system(size: 16))
                        } else if current {
                            Text("\(Int(vm.stageProgress * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(gold)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(current ? gold.opacity(0.06) : Color.clear)

                    if idx < stages.count - 1 {
                        Divider()
                            .background(tan)
                            .padding(.leading, 46 + 16)
                    }
                }
            }
            .background(card)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    MainTabView()
        .environmentObject(AppState())
}
#endif
