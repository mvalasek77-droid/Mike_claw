import SwiftUI
import Combine

/// Preview screen that opens the built app in Xcode on the user's Mac
/// and streams the simulator output back to the iPhone.
///
/// Flow:
///  1. User taps "Open simulator preview" after build completes.
///  2. This view tells the paired Mac (via CompanionBridge) to open the
///     Xcode project and launch the iOS Simulator.
///  3. The simulator mirrors to the iPhone — the user sees a live
///     preview of the app running.
///  4. The user can type improvements/feedback which get sent back as
///     a rebuild prompt to iterate on the app.
struct SimulatorPreviewView: View {
    let job: BuildJob
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @StateObject private var bridge = CompanionBridge()
    @StateObject private var runner = RemoteRunnerSession()
    @State private var improvementText: String = ""
    @State private var isSendingImprovement: Bool = false
    @State private var improvement_sent: Bool = false
    @State private var macStatus: MacConnectionStatus = .disconnected
    @State private var showingPairMac: Bool = false

    enum MacConnectionStatus {
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
            case .opening:        "Launching simulator…"
            case .streaming:      "Simulator running"
            }
        }

        var tint: Color {
            switch self {
            case .disconnected:  LiquidGlass.primaryText.opacity(0.4)
            case .connecting:    LiquidGlass.warning
            case .connected:     LiquidGlass.accent
            case .opening:       LiquidGlass.warning
            case .streaming:     LiquidGlass.success
            }
        }
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                topBar
                if macStatus == .disconnected {
                    pairMacPrompt
                } else {
                    deviceFrame
                    statusBlock
                }
                improvementSection
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
        .task { await connectAndOpen() }
        .onDisappear { runner.disconnect() }
        .sheet(isPresented: $showingPairMac) {
            PairMacView()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .padding(10)
                    .background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            Spacer()
            VStack(spacing: 1) {
                Text(job.description.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                HStack(spacing: 4) {
                    Circle().fill(macStatus.tint).frame(width: 6, height: 6)
                    Text(macStatus.label)
                        .font(.caption2)
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                }
            }
            Spacer()
            Button { showingPairMac = true } label: {
                Image(systemName: "macbook.and.iphone")
                    .padding(10)
                    .background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            .accessibilityLabel("Pair Mac settings")
        }
    }

    // MARK: - Pair Mac prompt (shown when not connected)

    private var pairMacPrompt: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(spacing: 16) {
                Image(systemName: "iphone.and.arrow.left.and.mac.and.arrow.right")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)

                Text("Pair your Mac to preview")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)

                Text("CodeGenie opens the built app in Xcode on your Mac and streams the simulator to your iPhone. Pair your Mac first.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)

                PrimaryButton(title: "Pair Mac", systemImage: "link", style: .filled) {
                    showingPairMac = true
                }
            }
            .padding(24)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Device frame (simulator stream)

    private var deviceFrame: some View {
        GeometryReader { proxy in
            let w = min(proxy.size.width, 320)
            let h = w * (852.0 / 393.0)  // iPhone 16 aspect

            ZStack {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 38)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)

                // Dynamic Island
                Capsule().fill(.black).frame(width: 110, height: 28)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.05)))
                    .offset(y: -h / 2 + 26)

                // Streamed content
                Group {
                    if let preview = runner.previewImage {
                        preview
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        StreamingPlaceholder(state: runner.state)
                    }
                }
                .frame(width: w - 16, height: h - 16)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            }
            .frame(width: w, height: h)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 480)
    }

    // MARK: - Status block

    private var statusBlock: some View {
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

    // MARK: - Improvement input

    private var improvementSection: some View {
        GlassSurface(tier: .deep, corner: 16) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LiquidGlass.accent)
                    Text("Describe improvements")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer()
                }

                TextField("e.g. Make the button bigger, change title to…", text: $improvementText, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))

                if improvement_sent {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(LiquidGlass.success)
                        Text("Improvement sent — rebuilding…")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.success)
                    }
                } else {
                    PrimaryButton(
                        title: isSendingImprovement ? "Sending…" : "Rebuild with improvements",
                        systemImage: "arrow.triangle.2.circlepath",
                        style: .filled
                    ) {
                        Task { await sendImprovement() }
                    }
                    .disabled(improvementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingImprovement)
                    .opacity(improvementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private func connectAndOpen() async {
        // If already paired via settings, try to use that connection
        // Otherwise, we show the pair-prompt UI
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
            // Tell the Mac runner to open the Xcode project and run the simulator
            // The backend knows the project path from the build job
            try await bridge.openXcodeProject("")  // path resolved server-side from jobID
            macStatus = .streaming

            // Start streaming the simulator visuals
            await runner.connect(jobID: job.id)
        } catch {
            // If bridge fails, still try the remote runner (cloud-hosted fallback)
            macStatus = .connecting
            await runner.connect(jobID: job.id)
            macStatus = .streaming
        }
    }

    private func sendImprovement() async {
        let text = improvementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSendingImprovement = true
        defer { isSendingImprovement = false }

        // Use the existing SwarmClient to start a new build with the improvement prompt
        // The new build inherits the same app description but appends the improvement text
        var newDesc = job.description
        newDesc = AppDescription(
            id: UUID(),
            title: newDesc.title,
            prompt: newDesc.prompt + "\n\nImprovement: " + text,
            category: newDesc.category,
            style: newDesc.style,
            features: newDesc.features
        )
        dismiss()
        session.startBuildAndOpen(from: newDesc)
    }
}

// MARK: - Streaming placeholder

private struct StreamingPlaceholder: View {
    let state: RemoteRunnerSession.State
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 12) {
                Image(systemName: state == .failed ? "exclamationmark.triangle.fill" : "iphone.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(state == .failed ? LiquidGlass.warning : LiquidGlass.primaryText)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: state != .failed)
                Text(state.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                if state == .connecting || state == .provisioning {
                    ProgressView().tint(LiquidGlass.primaryText)
                }
            }
        }
    }
}