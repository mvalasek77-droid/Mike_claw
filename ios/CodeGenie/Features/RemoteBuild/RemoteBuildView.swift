import SwiftUI

/// Live preview of the freshly built app. Streams an iOS Simulator session
/// from a hosted macOS runner back to the user's phone. The runner mirrors
/// what the user sees so they can interact with the app exactly as it will
/// behave on a real device.
///
/// The runner is provisioned on demand from the CodeGenie backend — see
/// `Services/RemoteRunnerSession.swift`. This view is the player only.
struct RemoteBuildView: View {
    let job: BuildJob
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = RemoteRunnerSession()
    @State private var showingShareSheet = false

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                topBar
                deviceFrame
                statusBlock
                actions
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
        .task { await runner.connect(jobID: job.id) }
        .onDisappear { runner.disconnect() }
    }

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
                    Circle().fill(runner.state.tint).frame(width: 6, height: 6)
                    Text(runner.state.label).font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                }
            }
            Spacer()
            Button { showingShareSheet = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .padding(10)
                    .background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(LiquidGlass.primaryText)
            }
        }
    }

    private var deviceFrame: some View {
        // Stylised iPhone frame around a streamed video texture. We render
        // a placeholder render-loop while the runner is provisioning so the
        // user has visual feedback that something is happening.
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
        .frame(height: 580)
    }

    private var statusBlock: some View {
        GlassSurface(tier: .flat, corner: 16) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(LiquidGlass.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hosted runner")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(runner.runnerInfo)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
                Spacer()
                Text("\(Int(runner.latencyMs))ms")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
            }
            .padding(12)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Send to my iPhone (TestFlight)", systemImage: "iphone.gen3", style: .filled) {
                runner.sendToTestFlight()
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Open on Mac", systemImage: "macbook", style: .glass) {
                    runner.openInDesktopXcode()
                }
                PrimaryButton(title: "App Store", systemImage: "paperplane.fill", style: .glass) {
                    runner.handoffToAppStoreConnect()
                }
            }
        }
    }
}

private struct StreamingPlaceholder: View {
    let state: RemoteRunnerSession.State
    @State private var phase: CGFloat = 0
    var body: some View {
        ZStack {
            LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 12) {
                Image(systemName: state == .failed ? "exclamationmark.triangle.fill" : "antenna.radiowaves.left.and.right")
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
