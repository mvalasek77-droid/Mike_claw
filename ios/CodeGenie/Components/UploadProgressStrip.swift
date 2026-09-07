import SwiftUI

/// Live progress strip for the TestFlight ship-stage. Shows the
/// current phase, the latest line from Apple's toolchain, and how many
/// lines have streamed so far.
///
/// It covers packaging as well as upload, because the archive is the
/// long half of shipping and a strip that only appeared for the upload
/// would leave the slowest minutes looking like a hang.
///
/// Hidden until the ship stage actually starts for the bound
/// `SwarmClient` — the orchestrator doesn't ship on every build, so
/// the absence is normal.
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
                    .foregroundStyle(tracker.ok ? LiquidGlass.success : LiquidGlass.error.opacity(0.85))
            } else {
                Image(systemName: workingSymbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
        }
        .accessibilityHidden(true)
    }

    /// A cloud icon during a local archive would be a lie about what
    /// the machine is doing.
    private var workingSymbol: String {
        switch tracker.phase {
        case .archive:       "hammer.fill"
        case .export:        "signature"
        case .validate:      "checkmark.shield.fill"
        case .upload, .none: "icloud.and.arrow.up.fill"
        }
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
            return tracker.ok ? "It's on TestFlight" : "It didn't go through"
        }
        return tracker.phase?.title ?? "Getting your app ready"
    }

    private var tint: Color {
        if tracker.finished { return tracker.ok ? LiquidGlass.success : LiquidGlass.error }
        return LiquidGlass.accent
    }
}
