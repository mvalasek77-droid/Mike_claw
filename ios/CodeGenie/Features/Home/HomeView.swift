import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var creds = Credentials.shared
    @State private var showXcodeGuide = false
    @State private var showDescribe = false
    @State private var showSettings = false
    @State private var showTutorial = false
    @State private var showGame = false
    @State private var showXcodeReadiness = false
    @State private var showAppleDev = false
    @State private var showGitHub = false
    @State private var xcodeAcknowledged = UserDefaults.standard.bool(forKey: "xcode.readiness.acknowledged")
    @State private var showFirstBuildPrompt = false
    @StateObject private var ascStore = ASCSubmissionStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                journeyCard
                if nextStep.action != .describeApp { primaryAction }
                shipReadinessCard
                if !session.recentJobs.isEmpty { recentJobs }
                quickGrid
                xcodeShortcut
                // Clears the floating tab bar.
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            ascStore.objectWillChange.send()
            session.objectWillChange.send()
        }
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
        .fullScreenCover(item: $session.pendingPreview, onDismiss: {
            session.returnToBuildAfterPreview()
        }) { job in
            BuiltAppView(job: job)
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
                onSetUp:   { showFirstBuildPrompt = false; showXcodeReadiness = true },
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

    /// First-time gate. If the user has zero ship gates done and hasn't
    /// already dismissed this prompt, ask whether they want to set
    /// shipping up before building or proceed straight to the
    /// describe-an-app flow. After the first time the user is trusted
    /// to know what they're doing.
    private func startBuildOrPromptSetup() {
        let done = [xcodeAcknowledged, creds.hasAppleDevCreds, creds.hasGithub].filter { $0 }.count
        let promptShown = UserDefaults.standard.bool(forKey: "firstBuild.prompt.shown")
        if done == 0 && !promptShown {
            showFirstBuildPrompt = true
        } else {
            showDescribe = true
        }
    }

    // MARK: Ship readiness

    /// The one-time things worth doing before the guide asks for them.
    /// Hides itself once they're done.
    @ViewBuilder
    private var shipReadinessCard: some View {
        let appleReady = creds.hasAppleDevCreds
        let githubReady = creds.hasGithub
        let xcodeReady = xcodeAcknowledged
        let done = [xcodeReady, appleReady, githubReady].filter { $0 }.count
        if done < 3 {
            GlassSurface(tier: .raised, corner: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(LiquidGlass.warning)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(LiquidGlass.warning.opacity(0.18)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Get ahead")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text("\(done) of 3 done — things with a wait, worth starting early.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        }
                        Spacer()
                    }
                    progressDots(done: done, total: 3)
                    VStack(spacing: 6) {
                        shipRow(
                            icon: "hammer.fill",
                            tint: LiquidGlass.accentSecondary,
                            title: "Xcode",
                            subtitle: xcodeReady ? "You're caught up." : "A big download on your Mac. Start it now.",
                            done: xcodeReady
                        ) { showXcodeReadiness = true }

                        shipRow(
                            icon: "applelogo",
                            tint: LiquidGlass.success,
                            title: "Apple Developer",
                            subtitle: appleReady ? "Details saved." : "The $99/yr program. Approval can take a day.",
                            done: appleReady
                        ) { showAppleDev = true }

                        shipRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            tint: LiquidGlass.accentSecondary,
                            title: "GitHub (optional)",
                            subtitle: githubReady ? "Connected as @\(creds.githubUsername)" : "Back up your code. We'll help you sign up.",
                            done: githubReady
                        ) { showGitHub = true }
                    }
                }
                .padding(18)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Ship checklist — \(done) of 3 done")
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
        .accessibilityLabel(done ? "\(title) — done" : title)
        .accessibilityHint(done ? "" : subtitle)
    }

    // MARK: Sections

    // MARK: Your next step

    private var journeyFacts: Journey.Facts {
        let latest = session.recentJobs.first
        return Journey.Facts(
            buildInProgressTitle: session.pendingResume?.description.title,
            latestJobID: latest?.id,
            latestJobTitle: latest?.description.title,
            latestJobStage: latest?.stage,
            submission: ascStore.primary
        )
    }

    private var nextStep: Journey.NextStep { Journey.nextStep(journeyFacts) }

    /// The one thing to do now. Everything else on Home is reference;
    /// this is the path.
    private var journeyCard: some View {
        let next = nextStep
        return GlassSurface(tier: .deep) {
            VStack(alignment: .leading, spacing: 14) {
                journeyRail(next)

                VStack(alignment: .leading, spacing: 6) {
                    Text(next.eyebrow)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(next.isWaiting ? LiquidGlass.primaryText.opacity(0.6) : LiquidGlass.accent)
                        .textCase(.uppercase)
                        .tracking(1)
                        .lineLimit(1)
                    Text(next.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(next.detail)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Your next step. \(next.title). \(next.detail)")

                PrimaryButton(
                    title: next.buttonTitle,
                    systemImage: next.isWaiting ? "clock" : "arrow.right",
                    style: next.isWaiting ? .glass : .filled
                ) { perform(next.action) }
                .accessibilityIdentifier("journey.primaryAction")

                if next.action == .resumeBuild {
                    Button("Not now") {
                        Haptics.selection()
                        session.clearResumeRecord()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHint("Hides this reminder. The build stays in your Apps tab.")
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("journey.card")
    }

    /// Five dots from idea to live, so the user always knows how far
    /// along the whole trip they are — not just the current screen.
    private func journeyRail(_ next: Journey.NextStep) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Journey.Milestone.allCases) { milestone in
                let reached = Journey.reached(milestone, for: next)
                let isCurrent = milestone == next.milestone && !reached
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(reached ? AnyShapeStyle(LiquidGlass.success)
                                  : isCurrent ? AnyShapeStyle(LiquidGlass.auroraGradient)
                                  : AnyShapeStyle(Color.white.opacity(0.12)))
                            .frame(width: 22, height: 22)
                        if reached {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(milestone.label)
                        .font(.system(size: 10, weight: isCurrent ? .bold : .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(reached || isCurrent ? 0.9 : 0.45))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(railDescription(next))
    }

    private func railDescription(_ next: Journey.NextStep) -> String {
        let done = Journey.Milestone.allCases.filter { Journey.reached($0, for: next) }.count
        return "Stage \(min(done + 1, Journey.Milestone.allCases.count)) of \(Journey.Milestone.allCases.count): \(next.milestone.label)"
    }

    private func perform(_ action: Journey.Action) {
        switch action {
        case .describeApp, .startAnother:
            startBuildOrPromptSetup()
        case .resumeBuild:
            session.resumePendingBuild()
        case .openLatestBuild:
            if let job = session.recentJobs.first {
                session.openJob(job, backendID: session.backendJobIDs[job.id])
            }
        case .openSubmission(let jobID):
            if let job = session.recentJobs.first(where: { $0.id == jobID }) {
                session.openAppStoreConnect(for: job)
            }
        }
    }

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
                Button {
                    Haptics.selection()
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityHint("Keys, costs, and shipping setup")
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Build your next app\nfrom your phone.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .lineSpacing(2)
                Text("Describe it, watch it get built, and follow one step at a time until it's on the App Store.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }

    /// Starting another app, when the journey card is busy with one
    /// already under way.
    private var primaryAction: some View {
        Button {
            Haptics.selection()
            startBuildOrPromptSetup()
        } label: {
            GlassSurface(tier: .flat, corner: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LiquidGlass.accent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a new build")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("Describe another app")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Start a new build. Describe another app.")
    }

    /// Reference material, below the path. Four tiles, all of which
    /// do something for someone who has never shipped an app.
    private var quickGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            QuickTile(title: "How it works", subtitle: "The 7-step tour",        icon: "play.rectangle.fill", tint: LiquidGlass.accentSecondary) { showTutorial = true }
            QuickTile(title: "Costs & keys", subtitle: "What a build costs",     icon: "creditcard.fill",     tint: LiquidGlass.success)         { showSettings = true }
            QuickTile(title: "Xcode steps",  subtitle: "Pocket guide",           icon: "hammer.fill",         tint: LiquidGlass.warning)         { showXcodeGuide = true }
            QuickTile(title: "BitDrop",      subtitle: "A game for the wait",    icon: "gamecontroller.fill", tint: LiquidGlass.accent)          { showGame = true }
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
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("Project → Simulator → Device → App Store")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Xcode instructions. Project, Simulator, Device, App Store.")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
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
                    Text(job.stage.label)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.description.title), \(job.stage.label), \(Int(job.stage.progress * 100)) percent")
    }
}
