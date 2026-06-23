import SwiftUI

/// A practical, always-handy reference for what App Store Connect expects, so
/// the user never has to leave the app to remember a spec or a step.
struct ASCGuideView: View {
    // Scaled with Dynamic Type — at the default text size these equal their base
    // values, so the default look is unchanged; they grow when the user does.
    @ScaledMetric(relativeTo: .body) private var s14: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var s13: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var s11: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var stepCircle: CGFloat = 24

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    GlassCard(title: "Required sizes", icon: "ruler") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(ASCDeviceSize.catalog) { size in
                                HStack(spacing: 12) {
                                    Image(systemName: size.isRequired ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(size.isRequired ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.35))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(size.displayName)
                                            .font(.system(size: s14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(LiquidGlass.primaryText)
                                        Text(size.exampleDevices)
                                            .font(.system(size: s11, weight: .medium, design: .rounded))
                                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                                    }
                                    Spacer()
                                    Text(size.resolutionLabel(for: .portrait))
                                        .font(.system(size: s11, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                                }
                            }
                        }
                    }

                    GlassCard(title: "Upload steps", icon: "arrow.up.forward.app") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                stepRow(index + 1, step)
                            }
                        }
                    }

                    GlassCard(title: "Pro tips", icon: "lightbulb.fill", tint: LiquidGlass.warning) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(tips, id: \.self) { tip in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "sparkle").font(.system(size: s11)).foregroundStyle(LiquidGlass.accent).padding(.top, 3)
                                    Text(tip)
                                        .font(.system(size: s13, weight: .regular, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 120)
            }
            .background(LiquidGlassBackground().ignoresSafeArea())
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var intro: some View {
        Text("Apple validates screenshots by exact pixel size. Screenshot Studio always renders at these resolutions, so uploads pass on the first try.")
            .font(.system(size: s14, weight: .regular, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: s13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: stepCircle, height: stepCircle)
                .background(LiquidGlass.auroraGradient, in: Circle())
            Text(text)
                .font(.system(size: s14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private let steps = [
        "Export your set here — every required size renders to the “Screenshot Studio” Photos album.",
        "AirDrop the album to your Mac, or open App Store Connect on the web.",
        "In App Store Connect, open your app → the version → Previews and Screenshots.",
        "Drag each size group into its matching slot. The 6.9\" set auto-fills smaller iPhone sizes.",
        "Save. Apple validates the dimensions instantly — no resizing needed."
    ]

    private let tips = [
        "Turn on Clean status bar so every shot reads 9:41 with full battery — not your actual time and battery level.",
        "A subtle “Pop” enhancement lifts contrast and color without looking edited.",
        "Keep the most compelling screenshot first — it's the one shown in search results.",
        "Use a consistent caption style across all slides for a cohesive store listing.",
        "Captions over ~5 words get truncated on small previews; keep them punchy.",
        "Match your backdrop to your app icon's palette for instant brand recognition.",
        "Landscape screenshots are great for games and iPad-first apps."
    ]
}
