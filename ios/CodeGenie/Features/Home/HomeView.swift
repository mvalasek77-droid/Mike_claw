import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var creds = Credentials.shared
    @AppStorage("home.showAdvancedTiles") private var showAdvancedTiles = false
    @State private var showXcodeGuide = false
    @State private var showDescribe = false
    @State private var showSettings = false
    @State private var showTutorial = false
    @State private var showGame = false
    @State private var showXcodeReadiness = false
    @State private var showPairMac = false
    @State private var showAppleDev = false
    @State private var showGitHub = false
    @State private var showFirstBuildPrompt = false
    @State private var xcodeAcknowledged = UserDefaults.standard.bool(forKey: "xcode.readiness.acknowledged")
    @State private var showSampleApps = false
    @State private var showAppOfYearDNA = false
    @State private var showAutomationAudit = false
    @State private var showBugReport = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                primaryAction
                shipReadinessCard
                quickGrid
                if !session.recentJobs.isEmpty { recentJobs }
                else if hasSetupAtLeastOneGate { recentJobsEmptyState }
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
        .sheet(isPresented: $showSampleApps) {
            SampleAppsView()
                .environmentObject(session)
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAppOfYearDNA) {
            AppOfYearPlaybookView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAutomationAudit) {
            LaunchAutomationAuditView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showBugReport) {
            BugReportView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showGame) {
            ZStack(alignment: .topTrailing) {
                GameHomeView()
                Button { showGame = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7), .black.opacity(0.4))
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
        .sheet(isPresented: $showXcodeReadiness, onDismiss: {
            UserDefaults.standard.set(true, forKey: "xcode.readiness.acknowledged")
            xcodeAcknowledged = true
        }) {
            XcodeReadinessView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showPairMac) {
            PairMacView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAppleDev) {
            AppleDevWalkthroughView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showGitHub) {
            GitHubSetupView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showFirstBuildPrompt) {
            FirstBuildPromptView(
                onSetUp: {
                    showFirstBuildPrompt = false
                    showXcodeReadiness = true
                },
                onBuildNow: {
                    UserDefaults.standard.set(true, forKey: "firstBuild.prompt.shown")
                    showFirstBuildPrompt = false
                    showDescribe = true
                },
                onCancel: { showFirstBuildPrompt = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    private func startBuildOrPromptSetup() {
        let macPaired = !creds.backendToken.isEmpty
        let done = [xcodeAcknowledged, macPaired, creds.hasAppleDevCreds, creds.hasGithub].filter { $0 }.count
        let promptShown = UserDefaults.standard.bool(forKey: "firstBuild.prompt.shown")
        if done == 0 && !promptShown {
            showFirstBuildPrompt = true
        } else {
            showDescribe = true
        }
    }

    @ViewBuilder
    private var shipReadinessCard: some View {
        let macPaired = !creds.backendToken.isEmpty
        let appleReady = creds.hasAppleDevCreds
        let githubReady = creds.hasGithub
        let done = [xcodeAcknowledged, macPaired, appleReady, githubReady].filter { $0 }.count
        if done < 4 {
            GlassSurface(tier: .raised, corner: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(LiquidGlass.warning)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(LiquidGlass.warning.opacity(0.18)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Set up shipping")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text("\(done) of 4 done")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        }
                        Spacer()
                    }
                    progressDots(done: done, total: 4)
                    VStack(spacing: 6) {
                        shipRow(icon: "hammer.fill", tint: LiquidGlass.accentSecondary, title: "Xcode", subtitle: xcodeAcknowledged ? "You're caught up." : "What it is, how to install.", done: xcodeAcknowledged) {
                            showXcodeReadiness = true
                        }
                        shipRow(icon: "macbook.and.iphone", tint: LiquidGlass.accent, title: "Pair your Mac", subtitle: macPaired ? "Connected." : "Link this phone to a Mac running Xcode.", done: macPaired) {
                            showPairMac = true
                        }
                        shipRow(icon: "applelogo", tint: LiquidGlass.success, title: "Apple Developer", subtitle: appleReady ? "Connected. TestFlight upload enabled." : "$99/yr program. We'll walk you through it.", done: appleReady) {
                            showAppleDev = true
                        }
                        shipRow(icon: "chevron.left.forwardslash.chevron.right", tint: LiquidGlass.accentSecondary, title: "GitHub", subtitle: githubReady ? "Connected as @\(creds.githubUsername)" : "Back up your code. Studio sync uses this.", done: githubReady) {
                            showGitHub = true
                        }
                    }
                }
                .padding(18)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Ship checklist, \(done) of 4 done")
        }
    }

    private func progressDots(done: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < done ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func shipRow(icon: String, tint: Color, title: String, subtitle: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.selection(); action() }) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(done ? LiquidGlass.success : tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill((done ? LiquidGlass.success : tint).opacity(0.18)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(done ? 0.7 : 1))
                        .strikethrough(done, color: .white.opacity(0.35))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.45))
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done ? "\(title), done" : title)
        .accessibilityHint(done ? "" : subtitle)
    }

    // MARK: Sections

    private var hero: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 10) {
                    CodeGenieLogo(size: 34, animate: false)
                    Text("CodeGenie")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                        .accessibilityLabel("Account")
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Build your next app\nfrom your phone.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .lineSpacing(2)
                Text("CodeGenie wires Claude, GPT, and Xcode together so you can ship to the App Store from anywhere.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
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
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer()
                    Image(systemName: "sparkles").foregroundStyle(LiquidGlass.accent)
                }
                Text("\"A daily habit tracker with streaks and a calm look.\"")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .italic()
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                PrimaryButton(title: "Start a new build", systemImage: "wand.and.stars", style: .filled) {
                    startBuildOrPromptSetup()
                }
            }
            .padding(20)
        }
    }

    private var quickGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                QuickTile(title: "Try a sample",    subtitle: "Watch one build live",  icon: "sparkles",            tint: LiquidGlass.accent)          { showSampleApps = true }
                QuickTile(title: "Watch the tour",  subtitle: "7-step tutorial",       icon: "play.rectangle.fill", tint: LiquidGlass.accentSecondary) { showTutorial = true }
                QuickTile(title: "Xcode steps",     subtitle: "Plain-English primer",  icon: "hammer.fill",         tint: LiquidGlass.warning)         { showXcodeReadiness = true }
                QuickTile(title: "Costs & keys",    subtitle: "Pick your provider",    icon: "creditcard.fill",     tint: LiquidGlass.success)         { showSettings = true }
                if showAdvancedTiles || !session.recentJobs.isEmpty {
                    QuickTile(title: "BitDrop",         subtitle: "Play & set a high score", icon: "gamecontroller.fill", tint: LiquidGlass.accent)        { showGame = true }
                    QuickTile(title: "Award DNA",        subtitle: "App of Year gates",     icon: "trophy.fill",         tint: LiquidGlass.warning)         { showAppOfYearDNA = true }
                    QuickTile(title: "Automation",       subtitle: "Launch audit",          icon: "checklist.checked",   tint: LiquidGlass.accentSecondary) { showAutomationAudit = true }
                    QuickTile(title: "Report bug",       subtitle: "Email support",         icon: "exclamationmark.bubble.fill", tint: LiquidGlass.warning) { showBugReport = true }
                }
            }
            if !showAdvancedTiles && session.recentJobs.isEmpty {
                Button {
                    Haptics.selection()
                    withAnimation(LiquidGlass.motion) { showAdvancedTiles = true }
                } label: {
                    Label("Show more", systemImage: "chevron.down")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
                .accessibilityHint("Reveals BitDrop, award DNA, automation audit, and bug reporting")
            }
        }
    }

    private var recentJobs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent builds")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
            ForEach(session.recentJobs.prefix(4)) { job in
                JobRow(job: job)
            }
        }
    }

    /// Shown when the user has set up at least one ship gate but
    /// hasn't started a build yet. Prevents the home screen from
    /// feeling empty after they've put in onboarding work.
    private var recentJobsEmptyState: some View {
        GlassSurface(tier: .flat, corner: 18) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your finished builds appear here")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Tap Start a new build to make your first one — or watch one assemble live with Try a sample.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your finished builds will appear here once you start a build")
    }

    /// True when at least one of the four ship gates is done. Used to
    /// decide whether the empty-state callout is worth showing — for
    /// a truly fresh user, the shipReadinessCard above is already the
    /// natural next-action, no need to double up.
    private var hasSetupAtLeastOneGate: Bool {
        xcodeAcknowledged
            || !creds.backendToken.isEmpty
            || creds.hasAppleDevCreds
            || creds.hasGithub
    }

    private var xcodeShortcut: some View {
        Button { showXcodeReadiness = true } label: {
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
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("What it is, what to install, and what to open once")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    private var checklistCard: some View {
        GlassCard(title: "Quality checklist", icon: "checkmark.seal.fill", tint: LiquidGlass.success) {
            VStack(alignment: .leading, spacing: 8) {
                ChecklistRow(text: "Build path verified on Xcode 26", done: true)
                ChecklistRow(text: "Sample demo completes without backend", done: true)
                ChecklistRow(text: "Animations, accessibility, dark mode", done: true)
                ChecklistRow(text: "iOS 26 Liquid Glass theme", done: true)
                ChecklistRow(text: "Pricing gate blocks unready paths", done: true)
                ChecklistRow(text: "Perfection Mode: 10,000 virtual probes", done: false)
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
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(subtitle).font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
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
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(job.stage.rawValue)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                }
                Spacer()
                Text("\(Int(job.stage.progress * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
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
                .foregroundStyle(done ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.4))
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(done ? 0.95 : 0.7))
                .strikethrough(done, color: LiquidGlass.primaryText.opacity(0.3))
            Spacer()
        }
    }
}
