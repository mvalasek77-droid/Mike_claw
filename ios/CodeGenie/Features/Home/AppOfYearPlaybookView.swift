import SwiftUI

struct AppOfYearPlaybookView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    formulaCard
                    segments
                    winners
                    launchGate
                    Color.clear.frame(height: 28)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("App of the Year DNA")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("A decade of Apple winners distilled into CodeGenie's launch standard.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.72))
            }
            .accessibilityLabel("Close App of the Year DNA")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formulaCard: some View {
        GlassSurface(tier: .deep, corner: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LiquidGlass.accent)
                        .accessibilityHidden(true)
                    Text("The launch formula")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                }
                VStack(alignment: .leading, spacing: 10) {
                    FormulaRow(number: "01", title: "One impossible-feeling action", detail: "A moment users could not do this well before.")
                    FormulaRow(number: "02", title: "Instant emotional payoff", detail: "Calm, confidence, expression, connection, or delight on first launch.")
                    FormulaRow(number: "03", title: "Native Apple leverage", detail: "Camera, motion, haptics, widgets, watch, shortcuts, accessibility, or on-device intelligence.")
                    FormulaRow(number: "04", title: "Proof before polish", detail: "Screenshots, privacy, performance, offline behavior, and review blockers are resolved before TestFlight.")
                }
            }
            .padding(18)
        }
    }

    private var segments: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Segments CodeGenie now enforces")
            ForEach(AppOfYearSegment.all) { segment in
                SegmentCard(segment: segment)
            }
        }
    }

    private var winners: some View {
        GlassCard(title: "Last 10 iPhone winners", icon: "trophy.fill", tint: LiquidGlass.warning) {
            VStack(spacing: 8) {
                ForEach(AppOfYearWinner.lastTen) { winner in
                    HStack(spacing: 10) {
                        Text(String(winner.year))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidGlass.warning)
                            .frame(width: 42, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(winner.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text(winner.lesson)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var launchGate: some View {
        GlassCard(title: "Perfection Mode addition", icon: "checkmark.shield.fill", tint: LiquidGlass.success) {
            VStack(alignment: .leading, spacing: 8) {
                AwardChecklistRow(text: "First-run payoff visible")
                AwardChecklistRow(text: "App Store story drafted")
                AwardChecklistRow(text: "Icon and screenshots planned")
                AwardChecklistRow(text: "Native Apple capability used")
                AwardChecklistRow(text: "Cultural or personal utility named")
            }
        }
    }
}

private struct AppOfYearWinner: Identifiable, Hashable {
    let year: Int
    let name: String
    let lesson: String
    var id: Int { year }

    static let lastTen: [AppOfYearWinner] = [
        .init(year: 2025, name: "Tiimo", lesson: "Turns chaotic planning into a calm visual timeline."),
        .init(year: 2024, name: "Kino", lesson: "Makes cinematic capture feel native to iPhone."),
        .init(year: 2023, name: "AllTrails", lesson: "Builds community around real-world exploration."),
        .init(year: 2022, name: "BeReal", lesson: "Centers authenticity and a daily shared ritual."),
        .init(year: 2021, name: "Toca Life World", lesson: "Gives kids a flexible world for self-expression."),
        .init(year: 2020, name: "Wakeout!", lesson: "Fits useful movement into life at home."),
        .init(year: 2019, name: "Spectre Camera", lesson: "Uses AI to make a hard camera technique simple."),
        .init(year: 2018, name: "Procreate Pocket", lesson: "Compresses pro creative power into a phone-sized canvas."),
        .init(year: 2017, name: "Calm", lesson: "Owns a wellness ritual with focused emotional design."),
        .init(year: 2016, name: "Prisma", lesson: "Transforms ordinary photos into distinctive art.")
    ]
}

private struct AppOfYearSegment: Identifiable {
    let title: String
    let icon: String
    let tint: Color
    let examples: String
    let gate: String
    var id: String { title }

    static let all: [AppOfYearSegment] = [
        .init(
            title: "Calm utility",
            icon: "calendar.badge.clock",
            tint: LiquidGlass.success,
            examples: "Tiimo, Wakeout!, Calm",
            gate: "The core flow must lower friction or stress within one minute."
        ),
        .init(
            title: "Creator superpower",
            icon: "camera.filters",
            tint: LiquidGlass.accent,
            examples: "Kino, Spectre, Procreate Pocket, Prisma",
            gate: "The app must make one advanced skill feel effortless on iPhone."
        ),
        .init(
            title: "Human connection",
            icon: "person.2.wave.2.fill",
            tint: LiquidGlass.accentSecondary,
            examples: "AllTrails, BeReal, Toca Life World",
            gate: "The experience needs a reason to return, share, or build identity."
        ),
        .init(
            title: "Native craft",
            icon: "iphone.gen3.radiowaves.left.and.right",
            tint: LiquidGlass.warning,
            examples: "Camera, haptics, widgets, accessibility, watch",
            gate: "The product should feel impossible as a generic web wrapper."
        ),
        .init(
            title: "Store story",
            icon: "bag.badge.plus",
            tint: .pink,
            examples: "Icon, screenshots, privacy, metadata",
            gate: "The App Store package must explain the payoff before review."
        )
    ]
}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
            .textCase(.uppercase)
    }
}

private struct FormulaRow: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(LiquidGlass.accent)
                .frame(width: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SegmentCard: View {
    let segment: AppOfYearSegment

    var body: some View {
        GlassSurface(tier: .raised, corner: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: segment.icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(segment.tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(segment.tint.opacity(0.17)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(segment.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Spacer()
                    }
                    Text(segment.examples)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(segment.tint.opacity(0.95))
                    Text(segment.gate)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AwardChecklistRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LiquidGlass.success)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.92))
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}
