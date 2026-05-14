import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showXcodeGuide = false
    @State private var showDescribe = false
    @State private var showSettings = false
    @State private var showTutorial = false
    @State private var showGame = false
    @State private var showAppOfYearDNA = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                primaryAction
                quickGrid
                if !session.recentJobs.isEmpty { recentJobs }
                xcodeShortcut
                checklistCard
                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showXcodeGuide) {
            XcodeInstructionsView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showDescribe) {
            DescribeAppView { description in
                showDescribe = false
                _ = session.startBuild(from: description)
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView(mode: .replay) { showTutorial = false }
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAppOfYearDNA) {
            AppOfYearPlaybookView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showGame) {
            ZStack(alignment: .topTrailing) {
                GameHomeView()
                Button { showGame = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.7), .black.opacity(0.4))
                        .padding(.top, 14)
                        .padding(.trailing, 16)
                }
                .accessibilityLabel("Close game")
            }
        }
        .fullScreenCover(item: $session.currentJob) { job in
            BuildScreen(job: job, attachToBackendID: session.currentJobBackendID)
                .environmentObject(session)
        }
        .fullScreenCover(item: $session.pendingPreview) { job in
            RemoteBuildView(job: job)
                .environmentObject(session)
        }
        .fullScreenCover(item: $session.pendingASC) { job in
            AppStoreConnectGuideView(job: job)
                .environmentObject(session)
        }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 10) {
                    CodeGenieLogo(size: 34, animate: false)
                    Text("CodeGenie")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button { } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.8))
                        .accessibilityLabel("Account")
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Build your next app\nfrom your phone.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(2)
                Text("CodeGenie wires Claude, GPT, and Xcode together so you can ship to the App Store from anywhere.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }

    private var primaryAction: some View {
        GlassSurface(tier: .deep) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Describe an app").font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "sparkles").foregroundStyle(LiquidGlass.accent)
                }
                Text("\"A daily habit tracker with streaks and a calm look.\"")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .italic()
                    .foregroundStyle(.white.opacity(0.7))
                PrimaryButton(title: "Start a new build", systemImage: "wand.and.stars", style: .filled) {
                    showDescribe = true
                }
            }
            .padding(20)
        }
    }

    private var quickGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            QuickTile(title: "Watch the tour",  subtitle: "7-step tutorial",       icon: "play.rectangle.fill", tint: LiquidGlass.accentSecondary) { showTutorial = true }
            QuickTile(title: "Xcode steps",     subtitle: "Pocket guide",          icon: "hammer.fill",         tint: LiquidGlass.warning)         { showXcodeGuide = true }
            QuickTile(title: "Costs & keys",    subtitle: "Pick your provider",    icon: "creditcard.fill",     tint: LiquidGlass.success)         { showSettings = true }
            QuickTile(title: "BitDrop",         subtitle: "Play & set a high score", icon: "gamecontroller.fill", tint: LiquidGlass.accent)        { showGame = true }
            QuickTile(title: "Award DNA",        subtitle: "App of Year gates",     icon: "trophy.fill",         tint: LiquidGlass.warning)         { showAppOfYearDNA = true }
            QuickTile(title: "Launch kit",       subtitle: "Icon, shots, TestFlight", icon: "paperplane.fill",   tint: LiquidGlass.accentSecondary) { showXcodeGuide = true }
        }
    }

    private var recentJobs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent builds")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            ForEach(session.recentJobs.prefix(4)) { job in
                JobRow(job: job)
            }
        }
    }

    private var xcodeShortcut: some View {
        Button { showXcodeGuide = true } label: {
            GlassSurface(tier: .flat) {
                HStack(spacing: 14) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LiquidGlass.warning)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(LiquidGlass.warning.opacity(0.18)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Xcode instructions")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Project → Simulator → Device → App Store")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.5))
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    private var checklistCard: some View {
        GlassCard(title: "Quality checklist", icon: "checkmark.seal.fill", tint: LiquidGlass.success) {
            VStack(alignment: .leading, spacing: 8) {
                ChecklistRow(text: "All features work seamlessly", done: true)
                ChecklistRow(text: "Tested on iPhone flows + edge cases", done: true)
                ChecklistRow(text: "Animations, accessibility, dark mode", done: true)
                ChecklistRow(text: "iOS 26 Liquid Glass theme", done: true)
                ChecklistRow(text: "Senior-engineer code review (no vibe)", done: true)
                ChecklistRow(text: "Perfection Mode: 10,000 virtual probes", done: true)
                ChecklistRow(text: "Submission-ready for App Store", done: false)
            }
        }
    }
}

// MARK: - Sub-views

private struct QuickTile: View {
    let title: String, subtitle: String, icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            GlassSurface(tier: .raised, corner: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint.opacity(0.18)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(subtitle).font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(height: 130)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct JobRow: View {
    let job: BuildJob

    var body: some View {
        GlassSurface(tier: .flat, corner: 18) {
            HStack(spacing: 12) {
                Image(systemName: job.stage.systemImage)
                    .foregroundStyle(LiquidGlass.accent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.description.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(job.stage.rawValue)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text("\(Int(job.stage.progress * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(12)
        }
    }
}

private struct ChecklistRow: View {
    let text: String, done: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? LiquidGlass.success : .white.opacity(0.4))
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(done ? 0.95 : 0.7))
                .strikethrough(done, color: .white.opacity(0.3))
            Spacer()
        }
    }
}
