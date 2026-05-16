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
    @State private var startedAt: Date = .now
    @State private var showAppleDevSetup: Bool = false
    @State private var showReleaseExplainer: Bool = false
    @State private var jargonHelp: JargonTerm?
    @State private var shipBanner: String?

    enum JargonTerm: String, Identifiable {
        case pipeline, bitdrop, perfection
        var id: String { rawValue }
        var title: String {
            switch self {
            case .pipeline:   "Pipeline"
            case .bitdrop:    "BitDrop"
            case .perfection: "Perfection Mode"
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

    private let builder: BuilderService = LocalSimulatedBuilder()
    /// Whether to show the "live" UI surface (cost badge, retry badge,
    /// transcript card, upload progress strip). True for either a real
    /// backend run OR a canned demo — both stream `SwarmEvent`s
    /// through `swarm` and the user shouldn't see a different layout.
    private var useRemote: Bool {
        if demoSampleID != nil { return true }
        let creds = Credentials.shared
        guard !creds.backendURL.isEmpty else { return false }
        switch creds.authMode {
        case .byok:
            return creds.hasAnyKey
        case .subscription:
            return !creds.backendToken.isEmpty
        case .codegenie:
            return BillingStore.shared.canStartHostedBuild
        }
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
        .onChange(of: swarm.stage) { _, newStage in
            mirrorSwarmStage(newStage)
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
        .sheet(item: $jargonHelp) { term in
            jargonExplainSheet(term)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAppleDevSetup) {
            AppleDevWalkthroughView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showReleaseExplainer) {
            ReleaseStageExplainer(
                onChoose: { choice in
                    UserDefaults.standard.set(true, forKey: "release.explainer.seen")
                    showReleaseExplainer = false
                    switch choice {
                    case .testflight, .appStore:
                        Task { await submitToAppStore(skipExplainer: true) }
                    case .learnMore:
                        if let url = URL(string: "https://developer.apple.com/distribute/") {
                            openURL(url)
                        }
                    }
                },
                onCancel: { showReleaseExplainer = false }
            )
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
        .onDisappear {
            builderTask?.cancel()
            builder.cancel(initialJob.id)
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

    private var stageList: some View {
        GlassCard(title: "Pipeline", icon: "list.bullet.rectangle", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 8) {
                jargonTip("Each row is one of the 8 AI agents working on your app — architect, coder, designer, tester. They run in order; the green dot is the current step.") {
                    jargonHelp = .pipeline
                }
                ForEach(BuildJob.Stage.allCases.filter { $0 != .failed && $0 != .shipping }, id: \.self) { s in
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

    /// True once live spend has crossed 80% of the cap but the cap
    /// itself hasn't been hit. Gives the user a chance to react before
    /// the build halts mid-agent.
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

    /// Shown when `stage` flips to `.failed`. Replaces the silent log
    /// line with an actionable surface: last 5 log lines, retry,
    /// resume from checkpoint, escape hatch.
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

    /// One-line preview that opens a focused jargon-explainer sheet
    /// when tapped. Used inside Pipeline / BitDrop / Perfection cards.
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
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(LiquidGlass.success)
                            .accessibilityHidden(true)
                        Text("Build green")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("Ready to test in the cloud simulator. Run Perfection Mode before App Store handoff.")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                            .multilineTextAlignment(.center)
                        if let jobID = swarm.jobID {
                            PrimaryButton(
                                title: perfectionRunning ? "Running Perfection Mode..." : "Run Perfection Mode",
                                systemImage: "checkmark.seal.fill",
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
                        PrimaryButton(title: "Open simulator preview", systemImage: "play.rectangle.fill", style: .filled) {
                            let job = BuildJob(description: initialJob.description, stage: .readyForTest)
                            session.openPreview(for: job)
                        }
                        PrimaryButton(title: "Submit to App Store", systemImage: "paperplane.fill", style: .glass) {
                            Task { await submitToAppStore() }
                        }
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
                .frame(maxHeight: 620)
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
        if !DemoSwarmDriver.play(into: swarm, sampleID: sampleID) {
            push(.err, formattedTime(), "sample script missing: \(sampleID)")
            mirrorSwarmStage(.failed)
        }
    }

    private func runRemoteBuild() async {
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
                id = try await swarm.startBuild(spec: AppSpec(initialJob.description))
            }
            swarm.openStream(jobID: id)
        } catch {
            // Fall back to the local simulator so the user always sees progress.
            appendLog(for: .planning)
            await runLocalFallback(reason: "\(error)")
        }
    }

    private func mirrorSwarmStage(_ newStage: BuildJob.Stage) {
        guard useRemote else { return }
        guard stage != newStage else { return }
        Motion.run(.spring(response: 0.5, dampingFraction: 0.85)) {
            stage = newStage
        }
        appendLog(for: newStage)
        if newStage == .readyForTest,
           let jobID = swarm.jobID,
           demoSampleID == nil {
            startPerfectionIfNeeded(jobID: jobID)
        }
        if newStage == .readyForTest || newStage == .failed {
            Telemetry.shared.recordBuildFinished(
                succeeded: newStage == .readyForTest,
                retries: costs.retryAttempts,
                secondsElapsed: Date().timeIntervalSince(startedAt)
            )
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
    /// rebuild. Four preconditions in order:
    ///   1. Perfection Mode must be green.
    ///   2. Apple Developer credentials must exist.
    ///   3. The TestFlight-vs-App-Store explainer runs once per device.
    ///   4. Then `/ship` fires.
    private func submitToAppStore(skipExplainer: Bool = false) async {
        if swarm.jobID != nil && perfectionRun?.isReady != true {
            shipBanner = "Run Perfection Mode and clear blockers before App Store submission."
            Haptics.warning()
            return
        }
        guard Credentials.shared.hasAppleDevCreds else {
            showAppleDevSetup = true
            Haptics.warning()
            return
        }
        let seenExplainer = UserDefaults.standard.bool(forKey: "release.explainer.seen")
        if !seenExplainer && !skipExplainer {
            showReleaseExplainer = true
            Haptics.selection()
            return
        }
        guard let jobID = swarm.jobID,
              let cfg = ShipConfig.fromCredentials(
                bundleID: defaultBundleID(for: initialJob.description.title)
              ) else {
            shipBanner = "Could not assemble ship config."
            Haptics.error()
            return
        }
        do {
            let readiness = try await swarm.runReleaseReadiness(jobID: jobID, ship: cfg)
            guard readiness.isReadyForTestFlight else {
                shipBanner = readiness.nextActions.first ?? readiness.summary
                Haptics.warning()
                return
            }
            try await swarm.ship(jobID: jobID, config: cfg)
            shipBanner = "Submitted — watch the transcript for processing status."
            Haptics.success()
        } catch {
            shipBanner = "Submit failed: \(error)"
            Haptics.error()
        }
    }

    private func runPerfection(jobID: String) async {
        perfectionRunning = true
        perfectionError = nil
        defer { perfectionRunning = false }
        do {
            let run = try await swarm.runPerfection(jobID: jobID)
            perfectionRun = run
            shipBanner = run.isReady
                ? "Perfection Mode passed — App Store handoff unlocked."
                : "Perfection Mode found blockers. Fix them, then rerun."
            if run.isReady { Haptics.success() } else { Haptics.warning() }
        } catch {
            perfectionError = "Could not run Perfection Mode: \(error)"
            Haptics.error()
        }
    }

    private func startPerfectionIfNeeded(jobID: String) {
        guard !perfectionAutostarted, !perfectionRunning, perfectionRun == nil else { return }
        perfectionAutostarted = true
        shipBanner = "Perfection Mode is running automatically."
        Task { await runPerfection(jobID: jobID) }
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
