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
                    instantGradeRail
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
            Text("Pick a finished-feeling brief with its own mood, payoff, and App of the Year signal.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var instantGradeRail: some View {
        if !samples.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LiquidGlass.warning)
                        .accessibilityHidden(true)
                    Text("Instant Grade")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer()
                    Text("award fit")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                        .textCase(.uppercase)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(samples) { sample in
                            GradeRailCard(sample: sample) {
                                handleTap(sample)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func handleTap(_ sample: SampleApp) {
        Haptics.experienceStart()
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
                    experienceHeader
                    Text(sample.prompt)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                        .lineLimit(3)
                    signalGrid
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
        .accessibilityLabel("\(sample.title), \(sample.subtitle), instant grade \(sample.instantGradeScore) out of 10")
        .accessibilityValue(sample.instantGradeSignals.joined(separator: ", "))
        .accessibilityHint(sample.demoPlayable
            ? "Plays a live demo build of this app"
            : "Opens the build form pre-filled with this brief")
    }

    private var experienceHeader: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(headerGradient)
            HStack(spacing: 12) {
                Image(systemName: sample.iconSystemName)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.white.opacity(0.18)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.26)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(sample.title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if sample.demoPlayable {
                            liveBadge
                        }
                    }
                    Text(sample.subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                    Text(sample.instantGradeLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                GradeScoreBadge(score: sample.instantGradeScore, foreground: .white)
            }
            .padding(12)
        }
        .frame(minHeight: 92)
        .accessibilityElement(children: .combine)
    }

    private var signalGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(sample.instantGradeSignals.prefix(3)), id: \.self) { signal in
                GradeSignalChip(text: signal, tint: tintColor)
            }
        }
    }

    private var liveBadge: some View {
        Text("LIVE")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.white.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.28)))
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }

    private var tintColor: Color {
        SampleVisuals.tint(for: sample.tint)
    }

    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: [
                SampleVisuals.tint(for: sample.tint).opacity(0.92),
                SampleVisuals.partnerTint(for: sample.tint).opacity(0.82),
                Color.black.opacity(0.30)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct GradeRailCard: View {
    let sample: SampleApp
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: sample.iconSystemName)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(tint.opacity(0.16)))
                        .accessibilityHidden(true)
                    Spacer()
                    GradeScoreBadge(score: sample.instantGradeScore, foreground: tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(sample.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .lineLimit(1)
                    Text(sample.instantGradeLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                if let firstSignal = sample.instantGradeSignals.first {
                    Text(firstSignal)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.66))
                        .lineLimit(1)
                }
            }
            .padding(13)
            .frame(width: 176, alignment: .topLeading)
            .frame(minHeight: 122, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.24), partnerTint.opacity(0.16), .white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sample.title), instant grade \(sample.instantGradeScore) out of 10")
        .accessibilityValue(sample.instantGradeLabel)
        .accessibilityHint(sample.instantGradeSignals.joined(separator: ", "))
    }

    private var tint: Color {
        SampleVisuals.tint(for: sample.tint)
    }

    private var partnerTint: Color {
        SampleVisuals.partnerTint(for: sample.tint)
    }
}

private struct GradeScoreBadge: View {
    let score: Int
    let foreground: Color

    var body: some View {
        VStack(spacing: 0) {
            Text("\(score)")
                .font(.system(size: 19, weight: .black, design: .rounded))
            Text("/10")
                .font(.system(size: 8, weight: .black, design: .rounded))
        }
        .foregroundStyle(foreground)
        .frame(width: 44, height: 44)
        .background(Circle().fill(foreground.opacity(0.15)))
        .overlay(Circle().strokeBorder(foreground.opacity(0.34)))
        .accessibilityHidden(true)
    }
}

private struct GradeSignalChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.22)))
    }
}

private enum SampleVisuals {
    static func tint(for key: String) -> Color {
        switch key {
        case "accent":          LiquidGlass.accent
        case "accentSecondary": LiquidGlass.accentSecondary
        case "success":         LiquidGlass.success
        case "warning":         LiquidGlass.warning
        case "rose":            Color(red: 1.00, green: 0.47, blue: 0.66)
        case "mint":            Color(red: 0.22, green: 0.78, blue: 0.65)
        default:                LiquidGlass.accent
        }
    }

    static func partnerTint(for key: String) -> Color {
        switch key {
        case "accent":          Color(red: 0.14, green: 0.78, blue: 0.86)
        case "accentSecondary": Color(red: 1.00, green: 0.52, blue: 0.74)
        case "success":         Color(red: 0.95, green: 0.63, blue: 0.25)
        case "warning":         Color(red: 1.00, green: 0.38, blue: 0.22)
        case "rose":            Color(red: 0.72, green: 0.58, blue: 1.00)
        case "mint":            Color(red: 0.36, green: 0.62, blue: 1.00)
        default:                LiquidGlass.accentSecondary
        }
    }
}
