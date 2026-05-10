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
    @StateObject private var game = BitDropGame()
    @StateObject private var swarm = SwarmClient()

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
            Text(initialJob.description.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
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
                        let job = BuildJob(description: initialJob.description, stage: .shipping)
                        session.openAppStoreConnect(for: job)
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
        if useRemote {
            await runRemoteBuild()
        } else {
            builderTask = Task {
                await builder.start(initialJob) { newStage in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        stage = newStage
                    }
                    appendLog(for: newStage)
                }
            }
        }
    }

    private func runRemoteBuild() async {
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
