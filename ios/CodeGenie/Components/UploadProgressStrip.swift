import SwiftUI

/// Live progress strip for the TestFlight ship-stage. Shows the
/// current phase (validate / upload), the latest altool line,
/// and how many lines have streamed so far.
///
/// Hidden when no `testflight.upload.progress` event has fired yet
/// for the bound `SwarmClient` — the orchestrator doesn't ship on
/// every build, so the absence is normal.
struct UploadProgressStrip: View {
    @ObservedObject var tracker: UploadProgressTracker

    var body: some View {
        if tracker.phase != nil || tracker.finished {
            GlassSurface(tier: .deep, corner: 18) {
                HStack(spacing: 12) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(label)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            phasePill
                        }
                        Text(tracker.latestLine ?? "Waiting for first line…")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .accessibilityLabel(tracker.latestLine ?? "")
                    }
                    Spacer()
                    Text("\(tracker.lineCount)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        .accessibilityLabel("\(tracker.lineCount) lines streamed")
                }
                .padding(14)
            }
            .accessibilityElement(children: .contain)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18)).frame(width: 44, height: 44)
            if tracker.finished {
                Image(systemName: tracker.ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tracker.ok ? LiquidGlass.success : .red.opacity(0.85))
            } else {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var phasePill: some View {
        if let p = tracker.phase {
            Text(p.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(LiquidGlass.accent.opacity(0.22), in: Capsule())
                .overlay(Capsule().strokeBorder(LiquidGlass.accent.opacity(0.45)))
                .foregroundStyle(LiquidGlass.accent)
        }
    }

    private var label: String {
        if tracker.finished {
            return tracker.ok ? "Upload complete" : "Upload failed"
        }
        return tracker.phase == .upload ? "Uploading to TestFlight" : "Validating archive"
    }

    private var tint: Color {
        if tracker.finished { return tracker.ok ? LiquidGlass.success : .red }
        return LiquidGlass.accent
    }
}
