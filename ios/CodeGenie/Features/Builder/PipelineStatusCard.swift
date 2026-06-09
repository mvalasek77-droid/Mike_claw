import SwiftUI

// MARK: - Pipeline Status Card (vertical timeline)

/// A vertical timeline card showing all pipeline steps with their current status.
/// The currently-running step pulses/glows, completed steps fade to green,
/// and failed steps show red with a retry button.
struct PipelineStatusCard: View {
    @ObservedObject var pipeline: PipelineRun
    let onRunStep: (PipelineStep) -> Void
    /// Called when the user taps a step's "What's happening?" jargon link.
    let onJargonHelp: (PipelineStep) -> Void

    var body: some View {
        GlassCard(title: "Ship Pipeline", icon: "arrow.triangle.branch", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 0) {
                // Jargon help link
                PipelineJargonTip(
                    text: "Each step prepares your app for the App Store — from quality checks to submission. Tap a step's ⓘ for details.",
                    onTap: { onJargonHelp(.perfection) }
                )
                .padding(.bottom, 12)

                ForEach(PipelineStep.allCases) { step in
                    stepRow(step)
                    if step != PipelineStep.allCases.last {
                        stepConnector(from: step)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
        }
    }

    // MARK: - Step row

    @ViewBuilder
    private func stepRow(_ step: PipelineStep) -> some View {
        let status = pipeline.status(for: step)
        let isActive = status.isRunning
        let isComplete = status.isComplete
        let isFailed = status.isFailed
        let errorMessage: String? = { if case .failed(let msg) = status { return msg } else { return nil } }()

        HStack(spacing: 14) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(isActive ? step.tint.opacity(0.25)
                         : isComplete ? LiquidGlass.success.opacity(0.18)
                         : isFailed ? Color.red.opacity(0.18)
                         : Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(isActive ? step.tint
                                : isComplete ? LiquidGlass.success
                                : isFailed ? Color.red
                                : Color.white.opacity(0.12),
                                lineWidth: isActive ? 2.5 : 1)
                    )

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LiquidGlass.success)
                } else if isFailed {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                } else if isActive {
                    ProgressView()
                        .tint(step.tint)
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: step.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                }
            }
            // Glow ring for active step
            .overlay {
                if isActive {
                    Circle()
                        .strokeBorder(step.tint.opacity(0.5), lineWidth: 2)
                        .frame(width: 48, height: 48)
                        .blur(radius: 4)
                        .opacity(pulseOpacity)
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.rawValue)
                        .font(.system(size: 14, weight: isActive ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isActive ? LiquidGlass.primaryText
                                         : isComplete ? LiquidGlass.primaryText.opacity(0.65)
                                         : isFailed ? LiquidGlass.primaryText
                                         : LiquidGlass.primaryText.opacity(0.45))
                    Button {
                        Haptics.selection()
                        onJargonHelp(step)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LiquidGlass.accent.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("What is \(step.rawValue)?")
                }
                Text(step.subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            }

            Spacer()

            // Status badge / action
            if isFailed {
                Button {
                    onRunStep(step)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Retry")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LiquidGlass.success.opacity(0.75))
            } else if isActive {
                Text(statusEmoji(status: status))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(step.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(step.tint.opacity(0.12), in: Capsule())
            } else {
                // Pending — show manual run button
                Button {
                    onRunStep(step)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Run \(step.rawValue)")
            }
        }
        .padding(.vertical, 4)

        // Error message
        if let errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.8))
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(2)
                Spacer()
            }
            .padding(.leading, 54)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Connector line

    private func stepConnector(from step: PipelineStep) -> some View {
        let idx = PipelineStep.allCases.firstIndex(of: step) ?? 0
        let isComplete = pipeline.status(for: step).isComplete
        let nextStep = PipelineStep.allCases[safe: idx + 1]
        let nextStarted = nextStep.map { !pipeline.status(for: $0).isPending } ?? false

        return Capsule()
            .fill(isComplete ? LiquidGlass.success.opacity(0.4)
                 : nextStarted ? LiquidGlass.accent.opacity(0.3)
                 : Color.white.opacity(0.08))
            .frame(width: 2, height: 16)
            .padding(.leading, 19)  // centre under the 40pt circle
    }

    // MARK: - Helpers

    private func statusEmoji(status: PipelineStepStatus) -> String {
        if status.isRunning { return "Running…" }
        return ""
    }

    /// Pulse animation for the active step.
    @State private var pulsePhase: Bool = false
    private var pulseOpacity: Double {
        pulsePhase ? 0.9 : 0.3
    }
}

// MARK: - Pipeline Run All button

/// A CTA that runs the entire pipeline from the current incomplete step.
struct RunPipelineButton: View {
    @ObservedObject var pipeline: PipelineRun
    let onRun: () -> Void

    var body: some View {
        PrimaryButton(
            title: pipeline.isRunning ? "Pipeline running…" : "Run Pipeline",
            systemImage: "arrow.triangle.branch",
            style: .filled
        ) {
            Haptics.selection()
            onRun()
        }
        .disabled(pipeline.isRunning)
        .accessibilityLabel(pipeline.isRunning ? "Pipeline is running" : "Run entire ship pipeline")
    }
}

// MARK: - Jargon Tip (reused from BuildScreen)

/// Small info button that opens an explanation sheet for a pipeline step.
/// This mirrors `BuildScreen.jargonTip` but is available as a standalone component.
struct PipelineJargonTip: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); onTap() }) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidGlass.accent.opacity(0.9))
                    .padding(.top, 2)
                Text(text)
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
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}