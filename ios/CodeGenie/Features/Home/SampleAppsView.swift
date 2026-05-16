import SwiftUI

/// First-run magic. Shows three sample apps; the user picks one to
/// **watch CodeGenie build live** (no tokens, no backend hit, no
/// signup gate) or to **start a real build pre-filled** with that
/// sample's brief.
///
/// We deliberately do not gate this behind onboarding. A first-time
/// user can see CodeGenie work before paying anything.
struct SampleAppsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var samples: [SampleApp] = []
    @State private var demoSample: SampleApp?
    @State private var prefillSample: SampleApp?

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    ForEach(samples) { sample in
                        SampleCard(
                            sample: sample,
                            onTap: { handleTap(sample) }
                        )
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .task { samples = SampleApp.loadAll() }
        .fullScreenCover(item: $demoSample) { sample in
            DemoBuildScreen(sample: sample)
                .environmentObject(session)
        }
        .sheet(item: $prefillSample) { sample in
            DescribeAppView(initial: sample.description) { description in
                prefillSample = nil
                _ = session.startBuild(from: description)
                dismiss()
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try a sample")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Pick one to watch a real build happen, or to start your own from that brief.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleTap(_ sample: SampleApp) {
        Haptics.selection()
        if sample.demoPlayable {
            demoSample = sample
        } else {
            prefillSample = sample
        }
    }
}

// MARK: - Sample card

private struct SampleCard: View {
    let sample: SampleApp
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassSurface(tier: .raised, corner: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: sample.iconSystemName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(tintColor)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(tintColor.opacity(0.18)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.title)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text(sample.subtitle)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(tintColor)
                        }
                        Spacer()
                        if sample.demoPlayable {
                            badge("LIVE", tint: LiquidGlass.success)
                        }
                    }
                    Text(sample.prompt)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        Image(systemName: "quote.opening").font(.system(size: 9))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.45))
                        Text(sample.outcome)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .italic()
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    }
                    HStack {
                        Spacer()
                        Text(sample.demoPlayable
                             ? "Tap to watch (~\(sample.estimatedSeconds)s)"
                             : "Tap to start your build")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(tintColor)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tintColor)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sample.title), \(sample.subtitle)")
        .accessibilityHint(sample.demoPlayable
            ? "Plays a live demo build of this app"
            : "Opens the build form pre-filled with this brief")
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(tint.opacity(0.22), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.5)))
            .foregroundStyle(tint)
            .tracking(0.6)
            .accessibilityHidden(true)
    }

    private var tintColor: Color {
        switch sample.tint {
        case "accent":          LiquidGlass.accent
        case "accentSecondary": LiquidGlass.accentSecondary
        case "success":         LiquidGlass.success
        case "warning":         LiquidGlass.warning
        default:                LiquidGlass.accent
        }
    }
}
