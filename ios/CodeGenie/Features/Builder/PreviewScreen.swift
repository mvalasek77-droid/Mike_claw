import SwiftUI

/// Phase 2: Preview the built app on the Mac's simulator, report bugs,
/// and confirm the app looks good before moving to Perfection.
///
/// Transitions:
///  • "Open on Mac" → opens Xcode, starts simulator mirror
///  • Bug text + "Fix it" → sends patch request, stays on preview
///  • "Looks great!" → transitions to PerfectionScorecardView
///  • "Skip to Ship" → jumps directly to ShipConfirmView
struct PreviewScreen: View {
    let job: BuildJob
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @StateObject private var bridge = CompanionBridge()
    @StateObject private var runner = RemoteRunnerSession()
    @StateObject private var pipeline = PipelineClient()

    @State private var macStatus: MacState = .disconnected
    @State private var bugDescription: String = ""
    @State private var isPatching: Bool = false
    @State private var patchResult: PipelineClient.PatchResult?
    @State private var showingPairMac: Bool = false
    @State private var navigateToPerfection: Bool = false
    @State private var navigateToShip: Bool = false

    enum MacState {
        case disconnected
        case connecting
        case connected
        case opening
        case streaming

        var label: String {
            switch self {
            case .disconnected:  "Not paired"
            case .connecting:    "Connecting to Mac…"
            case .connected:     "Paired — opening Xcode…"
            case .opening:       "Launching simulator…"
            case .streaming:     "Simulator running"
            }
        }

        var tint: Color {
            switch self {
            case .disconnected: LiquidGlass.primaryText.opacity(0.4)
            case .connecting:   LiquidGlass.warning
            case .connected:    LiquidGlass.accent
            case .opening:      LiquidGlass.warning
            case .streaming:    LiquidGlass.success
            }
        }
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    if macStatus == .disconnected {
                        pairPromptSection
                    } else {
                        simulatorSection
                        statusSection
                    }
                    bugReportSection
                    actionsSection
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .task { await connectAndOpen() }
        .onDisappear { runner.disconnect() }
        .sheet(isPresented: $showingPairMac) { PairMacView() }
        .navigationDestination(isPresented: $navigateToPerfection) {
            PerfectionScorecardView(job: job, pipeline: pipeline)
        }
        .navigationDestination(isPresented: $navigateToShip) {
            ShipConfirmView(job: job, pipeline: pipeline)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Preview your app")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Try it live on your Mac's simulator, then report any bugs.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            }
            Spacer()
        }
    }

    // MARK: - Pair prompt

    private var pairPromptSection: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(spacing: 16) {
                Image(systemName: "iphone.and.arrow.left.and.mac.and.arrow.right")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                Text("Pair your Mac to preview")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("CodeGenie opens the built app in Xcode on your Mac and streams the simulator to your iPhone.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
                PrimaryButton(title: "Pair Mac", systemImage: "link", style: .filled) {
                    showingPairMac = true
                }
            }
            .padding(24)
        }
    }

    // MARK: - Simulator mirror

    private var simulatorSection: some View {
        GlassSurface(tier: .raised, corner: 24) {
            GeometryReader { proxy in
                let w = min(proxy.size.width - 40, 300)
                let h = w * (852.0 / 393.0)

                ZStack {
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 36)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)

                    Capsule().fill(.black).frame(width: 110, height: 28)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.05)))
                        .offset(y: -h / 2 + 26)

                    Group {
                        if let preview = runner.previewImage {
                            preview
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: macStatus == .streaming ? "iphone.radiowaves.left.and.right" : "slowmo")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(LiquidGlass.primaryText)
                                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: macStatus == .streaming)
                                Text(macStatus.label)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText)
                                if macStatus == .connecting || macStatus == .opening {
                                    ProgressView().tint(LiquidGlass.primaryText)
                                }
                            }
                        }
                    }
                    .frame(width: w - 16, height: h - 16)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
                .frame(width: w, height: h)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 460)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        GlassSurface(tier: .flat, corner: 16) {
            HStack(spacing: 12) {
                Image(systemName: "macbook")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(macStatus.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Xcode on your Mac")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(runner.runnerInfo)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
                Spacer()
                if runner.latencyMs > 0 {
                    Text("\(Int(runner.latencyMs))ms")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                }
            }
            .padding(12)
        }
    }

    // MARK: - Bug report

    private var bugReportSection: some View {
        GlassSurface(tier: .deep, corner: 16) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LiquidGlass.warning)
                    Text("Report a bug")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer()
                }

                TextField("What's wrong? e.g. Button overlaps the header on iPhone SE", text: $bugDescription, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))

                if let result = patchResult, result.ok {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(LiquidGlass.success)
                        Text(result.message)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.success)
                    }
                    .transition(.opacity)
                }

                PrimaryButton(
                    title: isPatching ? "Fixing…" : "Fix it",
                    systemImage: "wrench.and.screwdriver.fill",
                    style: .filled
                ) {
                    Task { await submitPatch() }
                }
                .disabled(bugDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPatching)
                .opacity(bugDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "Looks great! → Perfection checks", systemImage: "checkmark.shield.fill", style: .filled) {
                Haptics.success()
                navigateToPerfection = true
            }
            PrimaryButton(title: "Skip to Ship", systemImage: "paperplane.fill", style: .glass) {
                Haptics.selection()
                navigateToShip = true
            }
        }
    }

    // MARK: - Actions (logic)

    private func connectAndOpen() async {
        guard bridge.status == .connected else {
            macStatus = .disconnected
            return
        }
        macStatus = .connected
        await openInXcode()
    }

    private func openInXcode() async {
        macStatus = .opening
        do {
            try await bridge.openXcodeProject("")
            macStatus = .streaming
            await runner.connect(jobID: job.id)
        } catch {
            macStatus = .connecting
            await runner.connect(jobID: job.id)
            macStatus = .streaming
        }
    }

    private func submitPatch() async {
        let text = bugDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPatching = true
        defer { isPatching = false }
        do {
            // Use the job's description to get a backend ID if available
            let jobID = session.currentJobBackendID ?? ""
            let result = try await pipeline.patchBuild(jobID: jobID, bugDescription: text)
            withAnimation { patchResult = result }
            Haptics.success()
            bugDescription = ""
        } catch {
            Haptics.error()
        }
    }
}