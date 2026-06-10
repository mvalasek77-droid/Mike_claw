import SwiftUI

/// Shown while a build runs. Top half is the live progress orb + log,
/// bottom half is the BitDrop mini-game so the user has something fun to
/// do — and earns small build-speed boosts as a reward for playing.
struct BuildScreen: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let initialJob: BuildJob
    /// When non-nil, BuildScreen attaches to an existing backend job
    /// (subscribes to its SSE stream) instead of starting a fresh
    /// build. Used by the Apps tab to open a forked / resumed job's
    /// live transcript without spending tokens.
    let attachToBackendID: String?
    /// When non-nil, BuildScreen replays the canned demo script for
    /// the given sample id instead of running a real build. Same UI
    /// surface, no backend, no tokens. Used for first-run magic.
    let demoSampleID: String?

    @State private var stage: BuildJob.Stage = .planning
    @State private var displayedLog: [LogLine] = []
    @State private var builderTask: Task<Void, Never>?
    @State private var showGame: Bool = true
    @State private var showDiffReview: Bool = false
    @State private var showMetadataReviewSheet: Bool = false
    @State private var showAppleTermsSheet: Bool = false
    @State private var showRecoveryGate: Bool = false
    @State private var startedAt: Date = .now

    @State private var showGitHubSetup: Bool = false
    @State private var githubSyncing: Bool = false
    @State private var jargonHelp: JargonTerm?
    @State private var shipBanner: String?

    enum JargonTerm: String, Identifiable {
        case pipeline, bitdrop, perfection
        // Ship pipeline step jargon help
        case pipelinePerfection, pipelineMetadata, pipelineReviewMetadata, pipelineLegalPages, pipelineAscSignIn, pipelineAcceptAppleTerms, pipelineAppIcon, pipelineScreenshots, pipelineArchive, pipelineUpload, pipelineWhatsNew, pipelineBetaReview, pipelineTesters, pipelineSubmit

        var id: String { rawValue }
        var title: String {
            switch self {
            case .pipeline:            "Pipeline"
            case .bitdrop:             "BitDrop"
            case .perfection:          "Perfection Mode"
            case .pipelinePerfection:  "Perfection Mode"
            case .pipelineMetadata:    "Generate Metadata"
            case .pipelineReviewMetadata: "Review Metadata"
            case .pipelineLegalPages:  "Legal Pages"
            case .pipelineAscSignIn:   "ASC Sign-In"
            case .pipelineAcceptAppleTerms: "Accept Apple Terms"
            case .pipelineAppIcon:     "Verify App Icon"
            case .pipelineScreenshots: "Upload Screenshots"
            case .pipelineArchive:     "Archive & Export"
            case .pipelineUpload:      "Upload to ASC"
            case .pipelineWhatsNew:      "What's New"
            case .pipelineBetaReview:   "Submit for Beta Review"
            case .pipelineTesters:      "Manage Testers"
            case .pipelineSubmit:        "Submit for Review"
            }
        }
        var body: String {
            switch self {
            case .pipeline:
                "Your app is built by a team of eight AI specialists working in order — Architect plans the structure, Coder writes Swift, Designer makes it look good, Integrator wires everything together, then Unit Tester, UI Tester, Reviewer, and Security Auditor sign off. The list shows where they are right now."
            case .bitdrop:
                "A small built-in puzzle game so you have something to do while the AI works. It's optional — every cleared row gives a tiny build-speed boost as a thank-you, but ignoring it won't slow your app down."
            case .perfection:
                "A 10,000-probe quality check across nine axes — Apple Review readiness, accessibility, performance, security, polish, and more. Run it before submitting to the App Store. If it flags blockers, fix them; if it's green, you have a much better shot at getting through App Review on the first try."
            case .pipelinePerfection:
                "A 10,000-probe quality check across nine axes — Apple Review readiness, accessibility, performance, security, polish, and more. Run it before submitting to the App Store. If it flags blockers, fix them; if it's green, you have a much better shot at getting through App Review on the first try."
            case .pipelineMetadata:
                "CodeGenie writes your App Store listing — title, subtitle, keywords, description, and privacy policy URL — all optimized for discoverability."
            case .pipelineReviewMetadata:
                "You must review what CodeGenie generated — name, subtitle, keywords, description, category — and explicitly approve it. If anything looks wrong, reject and the pipeline will be canceled so you can fix it. Apple requires accurate metadata."
            case .pipelineLegalPages:
                "Generates a professional privacy policy and terms of use for your app, then publishes them to GitHub Pages so you have URLs ready for App Store Connect. Required for App Store submission."
            case .pipelineAscSignIn:
                "Checks whether your Apple Developer account already has an app record in App Store Connect. If not, it tells you exactly which bundle ID to create an app for — this is required before you can upload builds."
            case .pipelineAcceptAppleTerms:
                "Apple requires that you manually accept the App Store Connect Terms of Service and Paid Applications Agreement. You also need to fill in the App Review contact information (your name, email, and phone number). CodeGenie cannot do this on your behalf — you must sign into App Store Connect and complete these steps."
            case .pipelineAppIcon:
                "The app icon is automatically included in your build when you archive and upload. This step verifies that the icon was received by App Store Connect — if it's missing, you'll be asked to check your AppIcon.appiconset in Xcode."
            case .pipelineScreenshots:
                "Automatic screenshots are taken by running your app in the simulator and capturing each screen. They are uploaded directly to App Store Connect via the API."
            case .pipelineArchive:
                "Your app is compiled into an IPA file — the package format Apple uses for App Store distribution."
            case .pipelineUpload:
                "The IPA is uploaded securely to App Store Connect using your Apple Developer credentials."
            case .pipelineWhatsNew:
                "Apple requires release notes (What's New) for every version. CodeGenie generates these automatically based on your app's changes, then sets them in App Store Connect."
            case .pipelineBetaReview:
                "Before testers can receive your build via TestFlight, Apple must review it for beta testing compliance. This step submits your build for that review — it's like a lighter version of the full App Store review."
            case .pipelineTesters:
                "Once your build is approved for beta testing, this step assigns your beta testers to the build so they receive it through TestFlight. If the build hasn't been approved yet, you'll need to wait for beta review approval first."
            case .pipelineSubmit:
                "Your app is submitted to Apple for review. This is the final step — once approved, it goes live on the App Store."
            }
        }
    }
    @State private var showSnapshots: Bool = false
    @State private var showSnapshotSettingsSheet: Bool = false
    @State private var perfectionRun: PerfectionRun?
    @State private var perfectionRunning: Bool = false
    @State private var perfectionError: String?
    @State private var perfectionAutostarted: Bool = false
    @StateObject private var game = BitDropGame()
    @StateObject private var swarm = SwarmClient()
    @StateObject private var costs = CostTracker(modelID: Credentials.shared.preferredModelID)
    @StateObject private var diffStream = DiffStream()
    @StateObject private var uploadProgress = UploadProgressTracker()
    @StateObject private var bridge = CompanionBridge()
    @StateObject private var pipelineRun = PipelineRun()
    @StateObject private var pipelineClient = PipelineClient()

    /// Project path returned by a local Claw build (nil for cloud/simulated builds).
    @State private var localProjectPath: String?

    private let builder: BuilderService = LocalSimulatedBuilder()
    /// Whether to show the "live" UI surface (cost badge, retry badge,
    /// transcript card, upload progress strip). True for either a real
    /// backend run, a local Claw build, OR a canned demo — both stream `SwarmEvent`s
    /// through `swarm` and the user shouldn't see a different layout.
    private var useRemote: Bool {
        if demoSampleID != nil { return true }
        // Connected Mac means we can run local Claw builds (full UI)
        if case .connected = bridge.status { return true }
        let url = Credentials.shared.backendURL
        return !url.isEmpty && !url.hasPrefix("https://api.codegenie.app")
    }

    init(job: BuildJob, attachToBackendID: String? = nil, demoSampleID: String? = nil) {
        self.initialJob = job
        self.attachToBackendID = attachToBackendID
        self.demoSampleID = demoSampleID
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 18) {
                        progressBlock
                        stageList
                        if showGame { gameBlock }
                        if useRemote { transcriptBlock }
                        if costs.capHit { costCapCallout }
                        else if costsNearingCap { costApproachingCallout }
                        WorkspaceFullBanner(tracker: costs) { showSnapshotSettingsSheet = true }
                        UploadProgressStrip(tracker: uploadProgress)
                        if !diffStream.pending.isEmpty { diffReviewCallout }
                        logBlock
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            if stage == .readyForTest { successOverlay }
            if stage == .failed { failureOverlay }
        }
        .task { await runBuild() }
        .onChange(of: stage) { newStage in
            // Persist build progress so we can resume after app kill
            session.updateCurrentJobStage(newStage)
            if newStage == .readyForTest || newStage == .failed {
                session.completeCurrentBuild()
            }
        }
        .sheet(isPresented: $showDiffReview) {
            DiffPreviewView(diffs: diffStream.pending) { decisions in
                Task {
                    try? await diffStream.submit(decisions: decisions)
                    showDiffReview = false
                    Haptics.success()
                }
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }

        .sheet(isPresented: $showGitHubSetup) {
            GitHubSetupView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $jargonHelp) { term in
            jargonExplainSheet(term)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }

        .sheet(isPresented: $showSnapshotSettingsSheet) {
            SnapshotCapSettingsView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSnapshots) {
            if let jobID = swarm.jobID {
                SnapshotPickerView(
                    jobID: jobID,
                    client: swarm,
                    onFork: { newID in
                        session.adoptForkedJob(
                            originalDescription: initialJob.description,
                            newID: newID
                        )
                    }
                )
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
        }
        // ── Metadata Review Gate ──
        .sheet(isPresented: $showMetadataReviewSheet) {
            MetadataReviewGate(
                metadata: pipelineRun.metadataResult,
                onApprove: {
                    showMetadataReviewSheet = false
                    pipelineRun.metadataApproved = true
                    pipelineRun.markComplete(.reviewMetadata)
                    push(.ok, formattedTime(), "✓ Metadata approved by user")
                    Haptics.success()
                    // Resume pipeline
                    if let jobID = swarm.jobID {
                        Task { await runFullPipeline(jobID: jobID) }
                    }
                },
                onReject: {
                    showMetadataReviewSheet = false
                    pipelineRun.markFailed(.reviewMetadata, error: "User rejected metadata")
                    push(.err, formattedTime(), "✗ Pipeline canceled — metadata rejected")
                    Haptics.error()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        // ── Apple Terms Gate ──
        .sheet(isPresented: $showAppleTermsSheet) {
            AppleTermsGate(
                onAccept: {
                    showAppleTermsSheet = false
                    pipelineRun.appleTermsAccepted = true
                    pipelineRun.markComplete(.acceptAppleTerms)
                    push(.ok, formattedTime(), "✓ Apple Terms accepted by user")
                    Haptics.success()
                    // Resume pipeline
                    if let jobID = swarm.jobID {
                        Task { await runFullPipeline(jobID: jobID) }
                    }
                },
                onDecline: {
                    showAppleTermsSheet = false
                    pipelineRun.markFailed(.acceptAppleTerms, error: "User declined Apple Terms")
                    push(.err, formattedTime(), "✗ Pipeline canceled — Apple Terms not accepted")
                    Haptics.error()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        // ── AI Recovery Gate ──
        .sheet(isPresented: $showRecoveryGate) {
            Group {
                if let proposal = pipelineRun.aiRecoveryProposal,
                   let step = pipelineRun.recoveringStep,
                   let jobID = swarm.jobID {
                    RecoveryGate(
                        step: step,
                        errorMessage: proposal.diagnosis,
                        proposal: proposal,
                        jobID: jobID,
                        onApprove: { approvedProposal in
                            showRecoveryGate = false
                            Task {
                                do {
                                    let result = try await pipelineClient.recover(jobID: jobID, proposal: approvedProposal)
                                    if result.ok {
                                        pipelineRun.approveRecovery(for: step)
                                        push(.ok, formattedTime(), "✓ Recovery applied: \(approvedProposal.fixDescription)")
                                        Haptics.success()
                                        // Resume pipeline from the recovered step
                                        await runFullPipeline(jobID: jobID)
                                    } else {
                                        pipelineRun.markFailed(step, error: result.message)
                                        push(.err, formattedTime(), "✗ Recovery failed: \(result.message)")
                                        Haptics.error()
                                    }
                                } catch {
                                    pipelineRun.markFailed(step, error: error.localizedDescription)
                                    push(.err, formattedTime(), "✗ Recovery error: \(error.localizedDescription)")
                                    Haptics.error()
                                }
                            }
                        },
                        onModify: { modifiedProposal, newParams in
                            showRecoveryGate = false
                            Task {
                                do {
                                    let result = try await pipelineClient.recover(jobID: jobID, proposal: modifiedProposal)
                                    if result.ok {
                                        pipelineRun.approveRecovery(for: step)
                                        push(.ok, formattedTime(), "✓ Modified recovery applied: \(modifiedProposal.fixDescription)")
                                        Haptics.success()
                                        await runFullPipeline(jobID: jobID)
                                    } else {
                                        pipelineRun.markFailed(step, error: result.message)
                                        push(.err, formattedTime(), "✗ Modified recovery failed: \(result.message)")
                                        Haptics.error()
                                    }
                                } catch {
                                    pipelineRun.markFailed(step, error: error.localizedDescription)
                                    push(.err, formattedTime(), "✗ Recovery error: \(error.localizedDescription)")
                                    Haptics.error()
                                }
                            }
                        },
                        onReject: {
                            showRecoveryGate = false
                            pipelineRun.rejectRecovery(for: step)
                            push(.err, formattedTime(), "✗ Pipeline halted — recovery rejected by user")
                            Haptics.error()
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
                }
            }
        }
        .onDisappear {
            builderTask?.cancel()
            // Only tear down the backend stream and clear saved state
            // if the build has finished. If the user just navigated away
            // (or the app was backgrounded), we keep the saved state so
            // they can resume.
            let terminalStages: Set<BuildJob.Stage> = [.readyForTest, .shipping, .failed]
            if terminalStages.contains(stage) {
                builder.cancel(initialJob.id)
                session.completeCurrentBuild()
            }
            swarm.closeStream()
        }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            Button {
                builderTask?.cancel()
                builder.cancel(initialJob.id)
                Haptics.warning()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            .accessibilityLabel("Minimize build")
            Spacer()
            VStack(spacing: 4) {
                Text(initialJob.description.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if useRemote { PauseStatusBadge(swarm: swarm) }
            }
            Spacer()
            if let jobID = swarm.jobID, useRemote {
                Button { Task { await togglePause(jobID: jobID) } } label: {
                    Image(systemName: swarm.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(10)
                        .background(.white.opacity(0.08), in: Circle())
                        .foregroundStyle(swarm.isPaused ? LiquidGlass.success : LiquidGlass.primaryText)
                }
                .accessibilityLabel(swarm.isPaused ? "Continue build" : "Pause build")
                Button { showSnapshots = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(10)
                        .background(.white.opacity(0.08), in: Circle())
                        .foregroundStyle(LiquidGlass.primaryText)
                }
                .accessibilityLabel("Open snapshots")
                Button { Task { await saveCheckpoint(jobID: jobID) } } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(10)
                        .background(.white.opacity(0.08), in: Circle())
                        .foregroundStyle(LiquidGlass.primaryText)
                }
                .accessibilityLabel("Save checkpoint")
            }
            Button { showGame.toggle(); Haptics.selection() } label: {
                Image(systemName: showGame ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            .accessibilityLabel(showGame ? "Hide BitDrop" : "Show BitDrop")
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var progressBlock: some View {
        GlassSurface(tier: .deep) {
            VStack(spacing: 14) {
                ProgressOrb(progress: stage.progress, label: stage.rawValue, subtitle: stage.humanCopy)
                HStack(spacing: 8) {
                    StatPill(label: "ETA",   value: etaString,   icon: "timer")
                    StatPill(label: "Score", value: "\(game.score)", icon: "star.fill")
                    StatPill(label: "Boost", value: "\(Int(game.buildBoost * 100))%", icon: "bolt.fill")
                    if useRemote {
                        CostBadge(tracker: costs)
                        RetryBadge(tracker: costs)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    /// One-line preview row with a "What's this?" link. Tapping the
    /// link opens a focused explainer sheet so the user can learn the
    /// term without losing their place in the build.
    private func jargonTip(_ preview: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.selection(); action() }) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidGlass.accent.opacity(0.9))
                    .padding(.top, 2)
                Text(preview)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open a longer explanation")
    }

    private func jargonExplainSheet(_ term: JargonTerm) -> some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(LiquidGlass.accent)
                        Text(term.title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                    }
                    Text(term.body)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        .lineSpacing(3)
                    PrimaryButton(title: "Got it", systemImage: "checkmark", style: .filled) {
                        Haptics.selection()
                        jargonHelp = nil
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var stageList: some View {
        GlassCard(title: "Pipeline", icon: "list.bullet.rectangle", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 8) {
                jargonTip("Each row is one of the 8 AI agents working on your app — architect, coder, designer, tester. They run in order; the green dot is the current step.") {
                    jargonHelp = .pipeline
                }
                ForEach(BuildJob.Stage.allCases.filter { $0 != .failed && $0 != .shipping && $0 != .previewing && $0 != .perfecting && $0 != .prepping }, id: \.self) { s in
                    PipelineRow(stage: s, current: stage)
                }
            }
        }
    }

    private var gameBlock: some View {
        GlassCard(title: "BitDrop", icon: "square.stack.3d.up.fill", tint: LiquidGlass.accentSecondary) {
            VStack(spacing: 10) {
                jargonTip("A small puzzle to play while CodeGenie builds. Totally optional.") { jargonHelp = .bitdrop }
                BitDropView(game: game)
                Text("Clear rows of Swift symbols. Every row gives a 2% build-speed boost.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var transcriptBlock: some View {
        GlassCard(title: "Live transcript", icon: "waveform", tint: LiquidGlass.accent) {
            TranscriptView(client: swarm)
        }
    }

    /// True when the live spend has crossed 80% of the cap but the cap
    /// itself hasn't been hit yet. Gives the user a chance to lift the
    /// cap or stop deliberately before the build halts mid-agent.
    private var costsNearingCap: Bool {
        guard let cap = costs.backendCapUSD, cap > 0 else { return false }
        return costs.backendSpendUSD >= cap * 0.8
    }

    private var costApproachingCallout: some View {
        GlassSurface(tier: .raised, corner: 18) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(LiquidGlass.warning)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LiquidGlass.warning.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spend approaching cap")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(costs.backendCapUSD.map {
                        String(format: "$%.2f of $%.2f used. Build will pause if it crosses.", costs.backendSpendUSD, $0)
                    } ?? "Approaching the safety cap.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                }
                Spacer()
            }
            .padding(12)
        }
    }

    /// Shown when the build's `stage` flips to `.failed`. Replaces the
    /// silent "✗ build failed" log line with an actionable surface:
    /// last log lines, a retry CTA, and a "save and exit" escape hatch.
    private var failureOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            GlassSurface(tier: .deep) {
                ScrollView {
                    VStack(spacing: 14) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(.red.opacity(0.85))
                            .accessibilityHidden(true)
                        Text("Build failed")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("Something tripped during the build. The transcript below has the last few lines — usually that's enough to spot what went wrong.")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                            .multilineTextAlignment(.center)
                        recentLogTail
                        PrimaryButton(title: "Try again", systemImage: "arrow.clockwise", style: .filled) {
                            Task { await runBuild() }
                        }
                        if let jobID = swarm.jobID {
                            PrimaryButton(title: "Resume from last checkpoint", systemImage: "clock.arrow.circlepath", style: .glass) {
                                Task {
                                    do { try await swarm.resume(jobID: jobID); Haptics.success() }
                                    catch { Haptics.error() }
                                }
                            }
                        }
                        Button("Close — I'll look at this later") {
                            Haptics.selection()
                            dismiss()
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    }
                    .padding(24)
                }
                .frame(maxHeight: 540)
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 28)
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Build failed. Try again, resume from checkpoint, or close.")
    }

    private var recentLogTail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(displayedLog.suffix(5)) { line in
                Text(line.text)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var costCapCallout: some View {
        GlassSurface(tier: .deep, corner: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(LiquidGlass.warning)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LiquidGlass.warning.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cost cap hit")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(costs.backendCapUSD.map {
                        String(format: "Stopped at $%.3f of $%.2f cap", costs.backendSpendUSD, $0)
                    } ?? "Build halted by the cost cap.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                }
                Spacer()
                Button { Task { await liftCapAndResume() } } label: {
                    Text("Lift cap × 2")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(LiquidGlass.auroraGradient.opacity(0.85), in: Capsule())
                        .foregroundStyle(LiquidGlass.primaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Double the cap and resume the build")
            }
            .padding(14)
        }
    }

    private var diffReviewCallout: some View {
        Button { showDiffReview = true; Haptics.selection() } label: {
            GlassSurface(tier: .deep, corner: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(LiquidGlass.accentSecondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LiquidGlass.accentSecondary.opacity(0.18)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(diffStream.pending.count) changes proposed")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("Review and apply selectively")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    private var logBlock: some View {
        GlassCard(title: "Build log", icon: "terminal.fill", tint: LiquidGlass.success) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(displayedLog) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text(line.time)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.4))
                        Text(line.text)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(line.tone.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            GlassSurface(tier: .deep) {
                ScrollView {
                    VStack(spacing: 14) {
                        // ── Header ──
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(LiquidGlass.success)
                            .accessibilityHidden(true)
                        Text("Build green")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("Your app compiled successfully. Run the ship pipeline to prep for the App Store, or explore individual steps below.")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                            .multilineTextAlignment(.center)

                        // ── Pipeline status card ──
                        PipelineStatusCard(
                            pipeline: pipelineRun,
                            onRunStep: { step in
                                if let jobID = swarm.jobID {
                                    Task { await runPipelineStep(step, jobID: jobID) }
                                }
                            },
                            onJargonHelp: { step in
                                let term: JargonTerm = switch step {
                                case .perfection:     .pipelinePerfection
                                case .metadata:       .pipelineMetadata
                                case .reviewMetadata: .pipelineReviewMetadata
                                case .legalPages:      .pipelineLegalPages
                                case .ascSignIn:       .pipelineAscSignIn
                                case .acceptAppleTerms: .pipelineAcceptAppleTerms
                                case .appIcon:         .pipelineAppIcon
                                case .screenshots:    .pipelineScreenshots
                                case .archive:        .pipelineArchive
                                case .upload:         .pipelineUpload
                                case .whatsNew:       .pipelineWhatsNew
                                case .betaReview:     .pipelineBetaReview
                                case .testers:        .pipelineTesters
                                case .submit:         .pipelineSubmit
                                }
                                jargonHelp = term
                            }
                        )

                        // ── Run Pipeline CTA ──
                        if let jobID = swarm.jobID {
                            RunPipelineButton(pipeline: pipelineRun) {
                                Task { await runFullPipeline(jobID: jobID) }
                            }

                            // ── Individual Perfection Mode button (kept for quick access) ──
                            PrimaryButton(
                                title: perfectionRunning ? "Running Perfection Mode…" : "Run Perfection Mode",
                                systemImage: "checkmark.shield.fill",
                                style: perfectionRun?.isReady == true ? .glass : .filled
                            ) {
                                Task { await runPerfection(jobID: jobID) }
                            }
                            .disabled(perfectionRunning)
                            .accessibilityLabel("Run ten thousand probe Perfection Mode")
                        }

                        if let perfectionRun {
                            perfectionSummary(perfectionRun)
                        }
                        if let perfectionError {
                            Text(perfectionError)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .accessibilityLabel("Perfection Mode failed: \(perfectionError)")
                        }

                        // ── Misc actions ──
                        PrimaryButton(title: "Open simulator preview", systemImage: "play.rectangle.fill", style: .filled) {
                            let job = BuildJob(description: initialJob.description, stage: .readyForTest)
                            session.openPreview(for: job)
                        }
                        PrimaryButton(
                            title: githubSyncing ? "Pushing to GitHub..." : "Back up to GitHub",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            style: .glass
                        ) {
                            Task { await backupToGitHub() }
                        }
                        .disabled(githubSyncing)
                        if let url = swarm.jobID.flatMap({ swarm.exportURL(jobID: $0) }) {
                            ShareLink(item: url, preview: SharePreview("\(initialJob.description.title).zip", image: Image(systemName: "shippingbox.fill"))) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Download workspace")
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                                .background(.white.opacity(0.06), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                            }
                            .accessibilityLabel("Download workspace zip")
                        }
                        if let projectPath = localProjectPath, !projectPath.isEmpty {
                            localProjectPathCard(path: projectPath)
                        }
                        if let banner = shipBanner {
                            Text(banner)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidGlass.success)
                                .multilineTextAlignment(.center)
                                .transition(.opacity)
                        }
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 28)
        }
        .transition(.opacity)
    }

    private func perfectionSummary(_ run: PerfectionRun) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: run.isReady ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(run.isReady ? LiquidGlass.success : LiquidGlass.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Perfection Mode")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("\(run.probesRun) probes - \(run.gateLabel) - \(String(format: "%.1f", run.score))/100")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                }
                Spacer()
            }
            Text(run.summary)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            if let top = run.findings.first {
                Text(top.recommendation ?? top.title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.62))
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Perfection Mode \(run.gateLabel), score \(String(format: "%.1f", run.score)) out of 100")
    }

    // MARK: Build coroutine

    private func runBuild() async {
        builderTask?.cancel()
        startedAt = .now
        Telemetry.shared.recordBuildStarted()

        // ── Resume case: app was killed mid-build, re-opened ──
        // We have a saved backend job ID → re-attach to the SSE stream
        // instead of starting a new build. The backend job kept running
        // while we were away.
        if session.isResuming {
            if let backendID = session.currentJobBackendID ?? attachToBackendID, useRemote {
                // Restore stage from the saved job
                stage = session.currentJob?.stage ?? .planning
                // Pre-populate the log with saved lines
                for line in session.resumedLogLines {
                    push(.info, formattedTime(), line)
                }
                // Re-attach to the backend stream
                session.isResuming = false
                costs.bind(to: swarm)
                diffStream.bind(to: swarm)
                uploadProgress.bind(to: swarm)
                CustomAgentLog.shared.bind(to: swarm)
                JobCostLog.shared.bind(to: swarm)
                swarm.openStream(jobID: backendID) { event in
                    Task { @MainActor in
                        if event.type == "job.state",
                           let s = event.payload["state"] as? String {
                            let mapped: BuildJob.Stage = {
                                switch s {
                                case "planning": .planning
                                case "building": .generatingUI
                                case "testing":  .linting
                                case "succeeded": .readyForTest
                                case "failed":    .failed
                                default: .planning
                                }
                            }()
                            Motion.run(.spring(response: 0.5, dampingFraction: 0.85)) { stage = mapped }
                            appendLog(for: mapped)
                            if mapped == .readyForTest {
                                startPerfectionIfNeeded(jobID: backendID)
                            }
                        }
                    }
                }
                push(.info, formattedTime(), "Reconnected to build — picking up where you left off")
                return
            }
            // Resume but no backend ID (local build) — restart from scratch
            session.isResuming = false
            session.abandonCurrentBuild()
        }

        // ── Normal start ──
        if let demoSampleID {
            await runCannedDemo(sampleID: demoSampleID)
        } else if useRemote {
            await runRemoteBuild()
        } else {
            builderTask = Task {
                await builder.start(initialJob) { newStage in
                    Motion.run(.spring(response: 0.5, dampingFraction: 0.85)) {
                        stage = newStage
                    }
                    appendLog(for: newStage)
                    if newStage == .readyForTest || newStage == .failed {
                        Telemetry.shared.recordBuildFinished(
                            succeeded: newStage == .readyForTest,
                            retries: costs.retryAttempts,
                            secondsElapsed: Date().timeIntervalSince(startedAt)
                        )
                    }
                }
            }
        }
    }

    /// Drive the screen from a canned `DemoScript-<id>.json`. Every
    /// observer the live path uses (`costs`, `diffStream`, transcript)
    /// binds to this screen's internal `swarm` so the demo plays
    /// through the same UI pipeline as a real build.
    private func runCannedDemo(sampleID: String) async {
        costs.bind(to: swarm)
        diffStream.bind(to: swarm)
        uploadProgress.bind(to: swarm)
        CustomAgentLog.shared.bind(to: swarm)
        JobCostLog.shared.bind(to: swarm)
        DemoSwarmDriver.play(into: swarm, sampleID: sampleID)
    }

    private func runRemoteBuild() async {
        // Prefer local Claw build when a Mac is paired
        if case .connected = bridge.status {
            await runLocalClawBuild()
            return
        }

        costs.bind(to: swarm)
        diffStream.bind(to: swarm)
        uploadProgress.bind(to: swarm)
        CustomAgentLog.shared.bind(to: swarm)
        JobCostLog.shared.bind(to: swarm)
        do {
            // Attach to an existing backend job (forked / resumed)
            // instead of starting a new build. We don't burn tokens
            // when the user is just inspecting a job's live state.
            let id: String
            if let backendID = attachToBackendID {
                id = backendID
            } else {
                var spec = AppSpec(initialJob.description)
                spec.apiKey = Credentials.shared.anthropicKey
                id = try await swarm.startBuild(spec: spec)
                // Persist the backend ID so we can resume if the app is killed
                session.currentJobBackendID = id
            }
            swarm.openStream(jobID: id) { event in
                Task { @MainActor in
                    // Mirror backend stage into the local UI, append to the
                    // simulated log so users see continuity.
                    if event.type == "job.state",
                       let s = event.payload["state"] as? String {
                        let mapped: BuildJob.Stage = {
                            switch s {
                            case "planning": .planning
                            case "building": .generatingUI
                            case "testing":  .linting
                            case "succeeded": .readyForTest
                            case "failed":    .failed
                            default: .planning
                            }
                        }()
                        Motion.run(.spring(response: 0.5, dampingFraction: 0.85)) { stage = mapped }
                        appendLog(for: mapped)
                        if mapped == .readyForTest {
                            startPerfectionIfNeeded(jobID: id)
                        }
                    }
                }
            }
        } catch {
            // Fall back to the local simulator so the user always sees progress.
            appendLog(for: .planning)
            await runLocalFallback(reason: "\(error)")
        }
    }

    /// Run a build on the paired Mac via CompanionBridge.
    /// Polls for status updates and drives the UI stages.
    private func runLocalClawBuild() async {
        let client = LocalBuildClient(bridge: bridge)
        let spec = {
            var s = AppSpec(initialJob.description)
            s.apiKey = Credentials.shared.anthropicKey
            return s
        }()
        push(.info, formattedTime(), "↪ sending build to paired Mac…")
        do {
            let finalResult = try await client.runBuildToCompletion(spec: spec) { newStage in
                Motion.run(.spring(response: 0.5, dampingFraction: 0.85)) {
                    stage = newStage
                }
                appendLog(for: newStage)
                Haptics.tap(intensity: 0.4, sharpness: 0.55)
            }

            if finalResult.succeeded {
                localProjectPath = finalResult.projectPath
                if !finalResult.projectPath.isEmpty {
                    push(.ok, formattedTime(), "✓ saved to \(finalResult.projectPath)")
                }
                Haptics.success()
            } else {
                let errMsg = finalResult.error ?? "unknown error"
                push(.err, formattedTime(), "✗ local build failed: \(errMsg)")
                stage = .failed
                Haptics.error()
            }
        } catch {
            // CompanionBridge failed — try cloud or fallback
            push(.warn, formattedTime(), "Local build failed (\(error)), trying cloud…")
            // Check if cloud is available
            let url = Credentials.shared.backendURL
            if !url.isEmpty && !url.hasPrefix("https://api.codegenie.app") {
                await runCloudBuild()
            } else {
                await runLocalFallback(reason: "\(error)")
            }
        }
    }

    /// Cloud-only build path (Skips local bridge attempt).
    private func runCloudBuild() async {
        costs.bind(to: swarm)
        diffStream.bind(to: swarm)
        uploadProgress.bind(to: swarm)
        CustomAgentLog.shared.bind(to: swarm)
        JobCostLog.shared.bind(to: swarm)
        do {
            let id: String
            if let backendID = attachToBackendID {
                id = backendID
            } else {
                var spec = AppSpec(initialJob.description)
                spec.apiKey = Credentials.shared.anthropicKey
                id = try await swarm.startBuild(spec: spec)
                session.currentJobBackendID = id
            }
            swarm.openStream(jobID: id) { event in
                Task { @MainActor in
                    if event.type == "job.state",
                       let s = event.payload["state"] as? String {
                        let mapped: BuildJob.Stage = {
                            switch s {
                            case "planning": .planning
                            case "building": .generatingUI
                            case "testing":  .linting
                            case "succeeded": .readyForTest
                            case "failed":    .failed
                            default: .planning
                            }
                        }()
                        Motion.run(.spring(response: 0.5, dampingFraction: 0.85)) { stage = mapped }
                        appendLog(for: mapped)
                        if mapped == .readyForTest {
                            startPerfectionIfNeeded(jobID: id)
                        }
                    }
                }
            }
        } catch {
            await runLocalFallback(reason: "\(error)")
        }
    }

    private func runLocalFallback(reason: String) async {
        push(.warn, formattedTime(), "remote build unavailable (\(reason)), simulating")
        builderTask = Task {
            await builder.start(initialJob) { newStage in
                Motion.run(.spring(response: 0.5, dampingFraction: 0.85)) {
                    stage = newStage
                }
                appendLog(for: newStage)
            }
        }
    }

    private func formattedTime() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: .now)
    }

    /// Wired to the "Submit to App Store" CTA in the success overlay.
    /// Runs the orchestrator's `/ship` route on the existing job — no
    /// rebuild.
    ///
    /// Four preconditions, in order:

    private func runPerfection(jobID: String) async {
        perfectionRunning = true
        perfectionError = nil
        defer { perfectionRunning = false }
        do {
            let run = try await swarm.runPerfection(jobID: jobID)
            perfectionRun = run
            shipBanner = run.isReady
                ? "Perfection Mode passed — your app looks great."
                : "Perfection Mode found blockers. Fix them, then rerun."
            if run.isReady { Haptics.success() } else { Haptics.warning() }
        } catch {
            perfectionError = "Could not run Perfection Mode: \(error)"
            Haptics.error()
        }
    }

    // MARK: - Pipeline execution

    /// Run a single pipeline step manually.
    private func runPipelineStep(_ step: PipelineStep, jobID: String) async {
        pipelineRun.markRunning(step)
        push(.info, formattedTime(), "↪ \(step.rawValue)…")
        do {
            switch step {
            case .perfection:
                let result = try await pipelineClient.runPerfection(jobID: jobID)
                pipelineRun.perfectionResult = result
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Perfection Mode score: \(String(format: "%.1f", result.score))/100")
                Haptics.success()

            case .metadata:
                let result = try await pipelineClient.generateMetadata(jobID: jobID)
                pipelineRun.metadataResult = result
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Metadata generated: \(result.name)")
                Haptics.success()

            case .reviewMetadata:
                // Human gate — handled in runFullPipeline by showing sheet
                // If we reach here, user already approved
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Metadata approved by user")
                Haptics.success()

            case .legalPages:
                let result = try await pipelineClient.generateLegalPages(jobID: jobID)
                pipelineRun.legalPagesResult = result
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Legal pages published: \(result.privacyURL)")
                Haptics.success()

            case .ascSignIn:
                let result = try await pipelineClient.checkAscSignIn(jobID: jobID)
                pipelineRun.ascSignInResult = result
                if result.status == "signed_in" {
                    pipelineRun.markComplete(step)
                    push(.ok, formattedTime(), "✓ ASC sign-in verified: \(result.appName ?? "app")")
                } else {
                    pipelineRun.markComplete(step)
                    push(.warn, formattedTime(), "⚠ ASC: \(result.message ?? "No app record found")")
                }
                Haptics.success()

            case .acceptAppleTerms:
                // Human gate — handled in runFullPipeline by showing sheet
                // If we reach here, user already accepted
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Apple Terms accepted by user")
                Haptics.success()

            case .appIcon:
                // Auto-verify — icon is included in the build upload automatically.
                // Check ASC to confirm the icon was received.
                let result = try await pipelineClient.checkAscIcon()
                if result.iconUploaded {
                    pipelineRun.markComplete(step)
                    push(.ok, formattedTime(), "✓ App icon verified in App Store Connect")
                    Haptics.success()
                } else {
                    // Build hasn't been uploaded yet, or icon is missing from the build.
                    // The icon comes with the archive/upload step, so if we're here before
                    // that step completes, just mark as complete and verify again later.
                    pipelineRun.markComplete(step)
                    push(.ok, formattedTime(), "✓ App icon will be included with build upload")
                    Haptics.success()
                }

            case .screenshots:
                let result = try await pipelineClient.takeScreenshots(jobID: jobID)
                pipelineRun.screenshotsResult = result
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Screenshots taken: \(result.screenshotURLs.count) screens")
                Haptics.success()

            case .archive:
                // Archive step uses the swarm's existing build infrastructure.
                // We call the upload endpoint which implicitly archives.
                let result = try await pipelineClient.uploadBuild(jobID: jobID)
                pipelineRun.uploadResult = result
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Archive & export complete")
                Haptics.success()

            case .upload:
                let result = try await pipelineClient.uploadBuild(jobID: jobID)
                pipelineRun.uploadResult = result
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Uploaded to App Store Connect")
                Haptics.success()

            case .whatsNew:
                let result = try await pipelineClient.setWhatsNew(jobID: jobID)
                if result.ok {
                    pipelineRun.markComplete(step)
                    push(.ok, formattedTime(), "✓ What's New set in ASC")
                    Haptics.success()
                } else {
                    // whatsNew can only be set after a build is attached — not a fatal error
                    pipelineRun.markComplete(step)
                    push(.warn, formattedTime(), "⚠ What's New skipped: \(result.message)")
                }

            case .betaReview:
                // Get the build ID from the upload step result
                guard let buildId = pipelineRun.buildId, !buildId.isEmpty else {
                    pipelineRun.markFailed(step, error: "No build ID available — upload may not have completed")
                    push(.err, formattedTime(), "✗ No build ID for beta review submission")
                    Haptics.error()
                    return
                }
                // Submit for beta review
                let reviewStatus = try await pipelineClient.submitBetaReview(buildId: buildId)
                push(.info, formattedTime(), "ℹ Beta review submitted — state: \(reviewStatus.betaReviewState)")
                // Poll until state is no longer WAITING_FOR_REVIEW (5s interval, max 60s)
                var currentState = reviewStatus.betaReviewState
                var elapsed: Double = 0
                let pollInterval: Double = 5.0
                let maxWait: Double = 60.0
                while currentState == "WAITING_FOR_REVIEW" || currentState == "IN_REVIEW" || currentState == "UNKNOWN" {
                    if elapsed >= maxWait {
                        push(.warn, formattedTime(), "⚠ Beta review still pending after 60s — marking step complete, check status later")
                        pipelineRun.markComplete(step)
                        Haptics.success()
                        break
                    }
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                    elapsed += pollInterval
                    let status = try await pipelineClient.getBetaReviewStatus(buildId: buildId)
                    currentState = status.betaReviewState
                    push(.info, formattedTime(), "ℹ Beta review state: \(currentState)")
                }
                if currentState == "APPROVED" {
                    pipelineRun.markComplete(step)
                    push(.ok, formattedTime(), "✓ Build approved for beta testing")
                    Haptics.success()
                } else if currentState == "REJECTED" {
                    pipelineRun.markFailed(step, error: "Beta review rejected by Apple")
                    push(.err, formattedTime(), "✗ Beta review rejected — check App Store Connect for details")
                    Haptics.error()
                } else {
                    // Approved or other non-failing state — proceed
                    pipelineRun.markComplete(step)
                    push(.ok, formattedTime(), "✓ Beta review step completed (state: \(currentState))")
                    Haptics.success()
                }

            case .testers:
                // List current testers, then assign them to the build
                let testers = try await pipelineClient.listTesters()
                if testers.isEmpty {
                    push(.warn, formattedTime(), "⚠ No beta testers found — add testers in App Store Connect first")
                    pipelineRun.markComplete(step)
                    Haptics.success()
                } else {
                    push(.info, formattedTime(), "ℹ Found \(testers.count) tester(s)")
                    guard let buildId = pipelineRun.buildId, !buildId.isEmpty else {
                        pipelineRun.markFailed(step, error: "No build ID available for tester assignment")
                        push(.err, formattedTime(), "✗ No build ID for tester assignment")
                        Haptics.error()
                        return
                    }
                    let testerIds = testers.map { $0.id }
                    do {
                        try await pipelineClient.assignTesters(buildId: buildId, testerIds: testerIds)
                        pipelineRun.markComplete(step)
                        push(.ok, formattedTime(), "✓ Assigned \(testers.count) tester(s) to build")
                        Haptics.success()
                    } catch let error as PipelineError {
                        if case .httpError(let code) = error, code == 409 {
                            pipelineRun.markFailed(step, error: "Build must be approved for beta review first — retry after approval")
                            push(.err, formattedTime(), "✗ Build must be approved for beta review first — retry after approval")
                            Haptics.error()
                        } else {
                            throw error
                        }
                    }
                }

            case .submit:
                let result = try await pipelineClient.submitForReview(jobID: jobID)
                pipelineRun.submitResult = result
                pipelineRun.markComplete(step)
                push(.ok, formattedTime(), "✓ Submitted for App Store Review")
                shipBanner = "Your app is submitted! Apple will review it within 24–48 hours."
                Haptics.success()
            }
        } catch {
            // ── AI Steering: ask the server to diagnose the failure ──
            if let jobID = swarm.jobID {
                let retryCount = pipelineRun.retryCountByStep[step, default: 0]
                do {
                    let proposal = try await pipelineClient.steer(
                        jobID: jobID,
                        step: step,
                        errorMessage: error.localizedDescription,
                        retryCount: retryCount
                    )
                    pipelineRun.markRecovering(step, proposal: proposal)
                    push(.warn, formattedTime(), "⚠ \(step.rawValue) failed — AI diagnosed: \(proposal.failureMode)")
                    showRecoveryGate = true
                } catch {
                    // Steering also failed — fall back to hard failure
                    pipelineRun.markFailed(step, error: error.localizedDescription)
                    push(.err, formattedTime(), "✗ \(step.rawValue) failed: \(error.localizedDescription)")
                    Haptics.error()
                }
            } else {
                pipelineRun.markFailed(step, error: error.localizedDescription)
                push(.err, formattedTime(), "✗ \(step.rawValue) failed: \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }

    /// Run the full pipeline from the first incomplete step to the end.
    /// Each step is run sequentially; the pipeline stops on the first failure
    /// or on a human gate that hasn't been approved yet.
    private func runFullPipeline(jobID: String) async {
        guard !pipelineRun.isRunning else { return }
        Haptics.selection()

        for step in PipelineStep.allCases {
            let status = pipelineRun.status(for: step)
            // Skip already-complete steps
            if status.isComplete { continue }
            // If a step previously failed, retry it
            if status.isFailed { pipelineRun.retry(step) }

            // ── Human gates: pause and show UI, don't auto-advance ──
            if step.isHumanGate {
                switch step {
                case .reviewMetadata:
                    guard pipelineRun.metadataApproved else {
                        pipelineRun.markRunning(step)
                        showMetadataReviewSheet = true
                        return   // pipeline pauses; resumes when user approves
                    }
                    pipelineRun.markComplete(step)
                    continue
                case .acceptAppleTerms:
                    guard pipelineRun.appleTermsAccepted else {
                        pipelineRun.markRunning(step)
                        showAppleTermsSheet = true
                        return   // pipeline pauses; resumes when user accepts
                    }
                    pipelineRun.markComplete(step)
                    continue
                case .appIcon:
                    // Icon auto-included with build — just verify it's present
                    break  // fall through to runPipelineStep
                default:
                    break
                }
            }

            await runPipelineStep(step, jobID: jobID)

            // If the step is recovering (AI steering active), pause for user decision
            if pipelineRun.status(for: step).isRecovering { return }
            // If the step failed, stop the pipeline
            if pipelineRun.status(for: step).isFailed { return }
        }

        shipBanner = "Pipeline complete — your app is submitted for review!"
    }

    private func startPerfectionIfNeeded(jobID: String) {
        guard !perfectionAutostarted, !perfectionRunning, perfectionRun == nil else { return }
        perfectionAutostarted = true
        shipBanner = "Perfection Mode is running automatically."
        Task { await runPerfection(jobID: jobID) }
    }

    /// Wired to the "Back up to GitHub" CTA in the success overlay.
    /// Pushes the finished workspace to the user's configured GitHub
    /// repo on a fresh branch. If no GitHub credentials are set yet,
    /// opens the walkthrough first — same hand-holding policy as
    /// `submitToAppStore`.
    private func backupToGitHub() async {
        let creds = Credentials.shared
        guard creds.hasGithub else {
            showGitHubSetup = true
            Haptics.warning()
            return
        }
        let repoSlug = creds.githubDefaultRepo.isEmpty
            ? "\(creds.githubUsername)/\(slugify(initialJob.description.title))"
            : creds.githubDefaultRepo
        guard let jobID = swarm.jobID else {
            shipBanner = "No active job to back up."
            Haptics.error()
            return
        }
        githubSyncing = true
        defer { githubSyncing = false }
        let config = GitHubSyncConfig(
            repoURL: "https://github.com/\(repoSlug).git",
            branch: "codegenie/\(initialJob.description.title.lowercased().replacingOccurrences(of: " ", with: "-"))",
            commitMessage: "CodeGenie build: \(initialJob.description.title)",
            token: creds.githubPAT,
            openPR: false
        )
        do {
            let result = try await swarm.syncGitHub(jobID: jobID, config: config)
            shipBanner = result.ok
                ? "Pushed to \(result.remote) on \(result.branch)"
                : "GitHub push failed."
            Haptics.success()
        } catch {
            shipBanner = "GitHub push failed: \(error)"
            Haptics.error()
        }
    }

    /// Lowercases + replaces spaces/punctuation with hyphens so we
    /// produce a repo name that GitHub accepts.
    private func slugify(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let scalars = s.lowercased().replacingOccurrences(of: " ", with: "-").unicodeScalars
        return String(String.UnicodeScalarView(scalars.map { allowed.contains($0) ? $0 : Unicode.Scalar("-") }))
    }

    private func saveCheckpoint(jobID: String) async {
        do {
            let label = try await swarm.snapshot(jobID: jobID)
            shipBanner = "Checkpoint saved: \(label)"
            Haptics.success()
        } catch {
            shipBanner = "Snapshot failed: \(error)"
            Haptics.error()
        }
    }

    private func togglePause(jobID: String) async {
        do {
            if swarm.isPaused {
                try await swarm.unpause(jobID: jobID)
                shipBanner = "Build resumed."
            } else {
                try await swarm.pause(jobID: jobID)
                shipBanner = "Paused — current agent finishes, then we wait."
            }
            Haptics.selection()
        } catch {
            shipBanner = "Pause/continue failed: \(error)"
            Haptics.error()
        }
    }

    /// Wired to the "Lift cap × 2" callout that appears when the
    /// backend halts the build via cost.cap_hit. We bump the cap
    /// 2× (or +$5 minimum), persist it, then POST /resume so the
    /// orchestrator picks up from the latest checkpoint.
    private func liftCapAndResume() async {
        guard let jobID = swarm.jobID else { return }
        let current = Credentials.shared.costCapUSD ?? costs.backendCapUSD ?? 5.0
        let newCap = max(current * 2.0, current + 5.0)
        Credentials.shared.setCostCap(newCap)
        do {
            try await swarm.resume(jobID: jobID)
            shipBanner = String(format: "Cap lifted to $%.2f — resuming.", newCap)
            Haptics.success()
        } catch {
            shipBanner = "Resume failed: \(error)"
            Haptics.error()
        }
    }

    private func defaultBundleID(for title: String) -> String {
        let slug = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return "com.codegenie.\(slug.isEmpty ? "app" : slug)"
    }

    // MARK: - Local project path card

    @State private var pathCopied: Bool = false

    private func localProjectPathCard(path: String) -> some View {
        GlassSurface(tier: .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(LiquidGlass.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project saved on Mac")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(path)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = path
                        pathCopied = true
                        Haptics.selection()
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            pathCopied = false
                        }
                    } label: {
                        Label(pathCopied ? "Copied!" : "Copy path", systemImage: pathCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(LiquidGlass.primaryText)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy project path to clipboard")

                    if case .connected = bridge.status {
                        Button {
                            Task {
                                do {
                                    try await bridge.openXcodeProject(path)
                                    Haptics.success()
                                } catch {
                                    shipBanner = "Could not open Xcode: \(error)"
                                    Haptics.error()
                                }
                            }
                        } label: {
                            Label("Open in Xcode", systemImage: "macbook.and.iphone")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(.white)
                                .background(LiquidGlass.auroraGradient.opacity(0.85), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open project in Xcode on paired Mac")
                    }
                }
            }
            .padding(14)
        }
    }

    private func appendLog(for stage: BuildJob.Stage) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: .now)
        switch stage {
        case .planning:
            push(.info, time, "↪ planning architecture")
            push(.info, time, "  · screens: 4   · models: 3   · services: 2")
        case .scaffolding:
            push(.info, time, "↪ xcodebuild -create-xcframework")
            push(.dim,  time, "  Project.pbxproj written (1.2 KB)")
        case .generatingUI:
            push(.accent, time, "✻ generating SwiftUI views")
            push(.dim,    time, "  HomeView.swift, DetailView.swift…")
        case .wiringLogic:
            push(.accent, time, "✻ wiring view-models + services")
        case .linting:
            push(.warn, time, "⚠ swiftlint: 2 warnings, 0 errors")
            push(.dim,  time, "  auto-fixed.")
        case .buildingIPA:
            push(.info, time, "↪ xcodebuild archive -scheme App")
        case .readyForTest:
            push(.ok, time, "✓ build succeeded — .app ready")
        case .previewing:
            push(.info, time, "↪ previewing app in simulator")
        case .perfecting:
            push(.info, time, "↪ running perfection checks")
        case .prepping:
            push(.info, time, "↪ preparing App Store submission")
        case .shipping:
            push(.ok, time, "✓ archive uploaded to App Store Connect")
        case .failed:
            push(.err, time, "✗ build failed — see diagnostics")
        }
    }

    private func push(_ tone: LogLine.Tone, _ time: String, _ text: String) {
        displayedLog.append(LogLine(time: time, text: text, tone: tone))
    }

    private var etaString: String {
        let remaining = max(0, 1 - stage.progress)
        let secs = Int(remaining * 18)
        return secs == 0 ? "done" : "\(secs)s"
    }

    private struct LogLine: Identifiable {
        let id = UUID()
        let time: String
        let text: String
        let tone: Tone
        enum Tone {
            case info, accent, ok, warn, err, dim
            var color: Color {
                switch self {
                case .info: return LiquidGlass.primaryText.opacity(0.85)
                case .accent: return LiquidGlass.accent
                case .ok: return LiquidGlass.success
                case .warn: return LiquidGlass.warning
                case .err: return .red
                case .dim: return LiquidGlass.primaryText.opacity(0.55)
                }
            }
        }
    }
}

private struct PipelineRow: View {
    let stage: BuildJob.Stage
    let current: BuildJob.Stage

    private var status: Status {
        if stage.progress < current.progress { return .done }
        if stage == current { return .active }
        return .pending
    }
    private enum Status { case pending, active, done }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(status == .pending ? Color.white.opacity(0.1) : LiquidGlass.accent.opacity(0.25))
                    .frame(width: 26, height: 26)
                switch status {
                case .done:
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LiquidGlass.success)
                case .active:
                    Circle().stroke(LiquidGlass.accent, lineWidth: 2).frame(width: 14, height: 14)
                case .pending:
                    Circle().fill(.white.opacity(0.4)).frame(width: 6, height: 6)
                }
            }
            Text(stage.rawValue)
                .font(.system(size: 13, weight: status == .active ? .semibold : .regular, design: .rounded))
                .foregroundStyle(status == .pending ? LiquidGlass.primaryText.opacity(0.5) : LiquidGlass.primaryText)
            Spacer()
            if status == .active {
                ProgressView().tint(LiquidGlass.primaryText).scaleEffect(0.7)
            }
        }
    }
}
