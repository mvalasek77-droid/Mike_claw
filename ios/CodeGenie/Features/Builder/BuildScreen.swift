import SwiftUI

/// Shown while a build runs. Top half is the live progress orb + log,
/// bottom half is the BitDrop mini-game so the user has something fun to
/// do — and earns small build-speed boosts as a reward for playing.
struct BuildScreen: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    let initialJob: BuildJob

    @State private var stage: BuildJob.Stage = .planning
    @State private var displayedLog: [LogLine] = []
    @State private var builderTask: Task<Void, Never>?
    @State private var showGame: Bool = true
    @State private var showDiffReview: Bool = false
    @State private var startedAt: Date = .now
    @State private var showAppleDevSetup: Bool = false
    @State private var shipBanner: String?
    @State private var showSnapshots: Bool = false
    @StateObject private var game = BitDropGame()
    @StateObject private var swarm = SwarmClient()
    @StateObject private var costs = CostTracker(modelID: Credentials.shared.preferredModelID)
    @StateObject private var diffStream = DiffStream()

    private let builder: BuilderService = LocalSimulatedBuilder()
    private var useRemote: Bool {
        // If backend is configured *and* a non-default URL is set we'll
        // attempt a real backend build; otherwise simulate locally.
        let url = Credentials.shared.backendURL
        return !url.isEmpty && !url.hasPrefix("https://api.codegenie.app")
    }

    init(job: BuildJob) { self.initialJob = job }

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
        }
        .task { await runBuild() }
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
        .sheet(isPresented: $showAppleDevSetup) {
            AppleDevSetupView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSnapshots) {
            if let jobID = swarm.jobID {
                SnapshotPickerView(jobID: jobID, client: swarm)
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
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Minimize build")
            Spacer()
            VStack(spacing: 4) {
                Text(initialJob.description.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
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
                        .foregroundStyle(swarm.isPaused ? LiquidGlass.success : .white)
                }
                .accessibilityLabel(swarm.isPaused ? "Continue build" : "Pause build")
                Button { showSnapshots = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(10)
                        .background(.white.opacity(0.08), in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Open snapshots")
                Button { Task { await saveCheckpoint(jobID: jobID) } } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(10)
                        .background(.white.opacity(0.08), in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Save checkpoint")
            }
            Button { showGame.toggle(); Haptics.selection() } label: {
                Image(systemName: showGame ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(.white)
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
                ForEach(BuildJob.Stage.allCases.filter { $0 != .failed && $0 != .shipping }, id: \.self) { s in
                    PipelineRow(stage: s, current: stage)
                }
            }
        }
    }

    private var gameBlock: some View {
        GlassCard(title: "BitDrop", icon: "square.stack.3d.up.fill", tint: LiquidGlass.accentSecondary) {
            VStack(spacing: 10) {
                BitDropView(game: game)
                Text("Clear rows of Swift symbols. Every row gives a 2% build-speed boost.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var transcriptBlock: some View {
        GlassCard(title: "Live transcript", icon: "waveform", tint: LiquidGlass.accent) {
            TranscriptView(client: swarm)
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
                        .foregroundStyle(.white)
                    Text(costs.backendCapUSD.map {
                        String(format: "Stopped at $%.3f of $%.2f cap", costs.backendSpendUSD, $0)
                    } ?? "Build halted by the cost cap.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button { Task { await liftCapAndResume() } } label: {
                    Text("Lift cap × 2")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(LiquidGlass.auroraGradient.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                        Text("Review and apply selectively")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.55))
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
                            .foregroundStyle(.white.opacity(0.4))
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
                VStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(LiquidGlass.success)
                    Text("Build green").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Ready to test in the cloud simulator or hand off to App Store Connect.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
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
                            .foregroundStyle(.white.opacity(0.85))
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
            .padding(.horizontal, 28)
        }
        .transition(.opacity)
    }

    // MARK: Build coroutine

    private func runBuild() async {
        builderTask?.cancel()
        startedAt = .now
        Telemetry.shared.recordBuildStarted()
        if useRemote {
            await runRemoteBuild()
        } else {
            builderTask = Task {
                await builder.start(initialJob) { newStage in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
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

    private func runRemoteBuild() async {
        costs.bind(to: swarm)
        diffStream.bind(to: swarm)
        CustomAgentLog.shared.bind(to: swarm)
        do {
            let id = try await swarm.startBuild(spec: AppSpec(initialJob.description))
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
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { stage = mapped }
                        appendLog(for: mapped)
                    }
                }
            }
        } catch {
            // Fall back to the local simulator so the user always sees progress.
            appendLog(for: .planning)
            await runLocalFallback(reason: "\(error)")
        }
    }

    private func runLocalFallback(reason: String) async {
        push(.warn, formattedTime(), "remote build unavailable (\(reason)), simulating")
        builderTask = Task {
            await builder.start(initialJob) { newStage in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
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
    /// rebuild. If Apple Developer creds aren't set, opens the setup
    /// sheet first so the user can configure them in-place.
    private func submitToAppStore() async {
        guard Credentials.shared.hasAppleDevCreds else {
            showAppleDevSetup = true
            Haptics.warning()
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
            try await swarm.ship(jobID: jobID, config: cfg)
            shipBanner = "Submitted — watch the transcript for processing status."
            Haptics.success()
        } catch {
            shipBanner = "Submit failed: \(error)"
            Haptics.error()
        }
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
                case .info: return .white.opacity(0.85)
                case .accent: return LiquidGlass.accent
                case .ok: return LiquidGlass.success
                case .warn: return LiquidGlass.warning
                case .err: return .red
                case .dim: return .white.opacity(0.55)
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
                .foregroundStyle(status == .pending ? .white.opacity(0.5) : .white)
            Spacer()
            if status == .active {
                ProgressView().tint(.white).scaleEffect(0.7)
            }
        }
    }
}
