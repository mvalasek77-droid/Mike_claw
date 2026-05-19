import SwiftUI

/// Fully automated, video-style preview of the build flow happening
/// on the user's Mac. The user watches; they don't tap. After the
/// flow finishes the view auto-dismisses so it feels like a clip
/// you watched, not a screen you navigated to.
///
/// Replaces `RemoteBuildView`'s interactive surface for the
/// "Open simulator preview" CTA on BuildScreen. The user wanted the
/// preview to "show the Mac side" and "just go through the flow of
/// the process in the video" — no buttons mid-play.
struct AutomatedPreviewView: View {
    let job: BuildJob
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex: Int = 0
    @State private var progress: Double = 0
    @State private var glow: Bool = false
    @State private var finished: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps: [AutoStep] = AutoStep.all
    private let stepSeconds: Double = 2.4

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 22) {
                ribbonHeader
                macWindow
                captionStack
                progressRail
                if finished { finalChip }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            // Belt-and-braces: nothing inside the flow content is
            // tappable. Even if a future addition adds an
            // accidentally-clickable element here, hits go through.
            // The only interactive control is the corner × overlay
            // below.
            .allowsHitTesting(false)

            // Tiny escape hatch in the corner — same size + opacity
            // as a system close. Deliberately not a primary control;
            // the experience is supposed to feel like a clip.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        Haptics.selection()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                    .accessibilityLabel("Stop preview and close")
                    .padding(.trailing, 16).padding(.top, 16)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .task { await runFlow() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Watching your Mac build \(job.description.title). \(steps[stepIndex].title).")
    }

    // MARK: - Sections

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.10),
                    Color(red: 0.06, green: 0.08, blue: 0.18),
                    Color(red: 0.10, green: 0.04, blue: 0.18),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if !reduceMotion {
                Circle()
                    .fill(LiquidGlass.accent.opacity(0.20))
                    .frame(width: 360, height: 360)
                    .blur(radius: 80)
                    .offset(x: glow ? -120 : 120, y: glow ? -200 : -260)
                    .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: glow)
            }
        }
        .ignoresSafeArea()
        .onAppear { glow = true }
    }

    private var ribbonHeader: some View {
        VStack(spacing: 4) {
            Text("Live from your Mac")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(1.6)
            Text(job.description.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    /// Stylised macOS window. We draw the traffic lights + a faux
    /// Xcode title bar + a content panel that shows the current
    /// step's "frame" — so the user actually sees the Mac doing the
    /// work, not just text.
    private var macWindow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.21)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 0.16, green: 0.81, blue: 0.31)).frame(width: 11, height: 11)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill").font(.system(size: 10, weight: .bold))
                    Text("Xcode — \(job.description.title)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Color.clear.frame(width: 33)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.07))

            ZStack {
                steps[stepIndex].mockSurface(progress: progress)
                    .transition(.opacity)
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.07, green: 0.08, blue: 0.11))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
    }

    private var captionStack: some View {
        VStack(spacing: 4) {
            Text(steps[stepIndex].title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
            Text(steps[stepIndex].subtitle)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .id(stepIndex)
        .transition(.opacity)
    }

    private var progressRail: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, _ in
                Capsule()
                    .fill(idx <= stepIndex ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private var finalChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(LiquidGlass.success)
            Text("Ready to share")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.white.opacity(0.08), in: Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Flow driver

    @MainActor
    private func runFlow() async {
        Haptics.tap(intensity: 0.6, sharpness: 0.6)
        for idx in steps.indices {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.35)) {
                stepIndex = idx
                progress = 0
            }
            await animateProgress(over: stepSeconds)
        }
        withAnimation(.easeInOut(duration: 0.45)) { finished = true }
        Haptics.success()
        // Hold the final frame for a beat so the user reads it, then
        // auto-dismiss. They can tap × earlier if they want out.
        try? await Task.sleep(nanoseconds: 1_900_000_000)
        await MainActor.run { dismiss() }
    }

    @MainActor
    private func animateProgress(over seconds: Double) async {
        let tickCount = reduceMotion ? 1 : Int(seconds * 20)
        let perTick = seconds / Double(max(1, tickCount))
        for i in 1...max(1, tickCount) {
            try? await Task.sleep(nanoseconds: UInt64(perTick * 1_000_000_000))
            progress = Double(i) / Double(max(1, tickCount))
        }
    }
}

// MARK: - Step model

private struct AutoStep {
    let icon: String
    let title: String
    let subtitle: String
    let mock: SurfaceKind

    enum SurfaceKind { case opening, compiling, linking, testing, screenshots, booting, ready }

    @ViewBuilder
    func mockSurface(progress: Double) -> some View {
        switch mock {
        case .opening:    OpeningSurface(progress: progress)
        case .compiling:  CompilingSurface(progress: progress)
        case .linking:    LinkingSurface(progress: progress)
        case .testing:    TestingSurface(progress: progress)
        case .screenshots: ScreenshotSurface(progress: progress)
        case .booting:    BootingSurface(progress: progress)
        case .ready:      ReadySurface()
        }
    }

    static let all: [AutoStep] = [
        .init(icon: "hammer.fill",  title: "Opening Xcode",          subtitle: "Loading your project on your Mac.",              mock: .opening),
        .init(icon: "doc.text",     title: "Compiling Swift",        subtitle: "Translating SwiftUI into a real iOS binary.",    mock: .compiling),
        .init(icon: "link",         title: "Linking",                subtitle: "Stitching frameworks + your code together.",     mock: .linking),
        .init(icon: "checkmark.shield", title: "Running tests",      subtitle: "Catching regressions before you see them.",      mock: .testing),
        .init(icon: "camera.fill",  title: "Capturing screenshots", subtitle: "Driving the simulator for each device size.",    mock: .screenshots),
        .init(icon: "iphone",       title: "Booting simulator",      subtitle: "Spinning up an iPhone on your Mac.",             mock: .booting),
        .init(icon: "checkmark.seal.fill", title: "Ready to test",   subtitle: "Build complete. Closing in a moment.",           mock: .ready),
    ]
}

// MARK: - Mock content surfaces (intentionally lightweight)

private struct OpeningSurface: View {
    let progress: Double
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
                .scaleEffect(0.85 + 0.15 * progress)
            Text("Loading scheme…")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

private struct CompilingSurface: View {
    let progress: Double
    private let lines = [
        "→ Compile App.swift",
        "→ Compile HomeView.swift",
        "→ Compile BuildScreen.swift",
        "→ Compile TideTimesPreview.swift",
        "→ Compile Credentials.swift",
        "→ Compile CompanionBridge.swift",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                let shown = Double(idx) / Double(lines.count) <= progress
                HStack(spacing: 6) {
                    Image(systemName: shown ? "checkmark" : "circle.dotted")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(shown ? LiquidGlass.success : .white.opacity(0.35))
                    Text(line)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(shown ? 0.85 : 0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

private struct LinkingSurface: View {
    let progress: Double
    var body: some View {
        ZStack {
            ForEach(0..<8) { i in
                let a = Double(i) / 8.0 * .pi * 2
                let r: CGFloat = 70
                Circle()
                    .fill(LiquidGlass.accent.opacity(0.85))
                    .frame(width: 10, height: 10)
                    .offset(x: cos(a) * r, y: sin(a) * r)
                    .opacity(Double(i) / 8.0 <= progress ? 1 : 0.2)
            }
            Image(systemName: "link")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(LiquidGlass.primaryText)
        }
    }
}

private struct TestingSurface: View {
    let progress: Double
    private let tests = [
        "HomeViewTests · primaryActionRenders",
        "BuildScreenTests · costMeterBindsToTracker",
        "CredentialsTests · keysPersistToKeychain",
        "CompanionBridgeTests · authResponse",
        "TideTimesPreviewTests · spotSwitchHaptic",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(tests.enumerated()), id: \.offset) { idx, t in
                let pass = Double(idx) / Double(tests.count) <= progress
                HStack(spacing: 6) {
                    Image(systemName: pass ? "checkmark.seal.fill" : "circle.dotted")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(pass ? LiquidGlass.success : .white.opacity(0.35))
                    Text(t)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(pass ? 0.85 : 0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

private struct ScreenshotSurface: View {
    let progress: Double
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { i in
                let shown = Double(i) / 3.0 <= progress
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 56, height: 122)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.6)
                    )
                    .opacity(shown ? 1 : 0.15)
                    .scaleEffect(shown ? 1 : 0.9)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: shown)
            }
        }
    }
}

private struct BootingSurface: View {
    let progress: Double
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black)
                .frame(width: 130, height: 230)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
            VStack(spacing: 6) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(progress < 0.5 ? 1 : 1 - (progress - 0.5) * 2)
                if progress > 0.4 {
                    ProgressView(value: progress, total: 1)
                        .tint(.white)
                        .frame(width: 80)
                }
            }
        }
    }
}

private struct ReadySurface: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(LiquidGlass.success)
            Text("Build complete on your Mac")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
