import SwiftUI

/// A practical, always-handy reference for what App Store Connect expects, so
/// the user never has to leave the app to remember a spec or a step.
struct ASCGuideView: View {
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
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(LiquidGlass.primaryText)
                                        Text(size.exampleDevices)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                                    }
                                    Spacer()
                                    Text(size.resolutionLabel(for: .portrait))
                                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
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
                                    Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(LiquidGlass.accent).padding(.top, 3)
                                    Text(tip)
                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                                }
                            }
                        }
                    }

                    RoadmapCard()
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
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(LiquidGlass.auroraGradient, in: Circle())
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
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
        "Keep the most compelling screenshot first — it's the one shown in search results.",
        "Use a consistent caption style across all slides for a cohesive store listing.",
        "Captions over ~5 words get truncated on small previews; keep them punchy.",
        "Match your backdrop to your app icon's palette for instant brand recognition.",
        "Landscape screenshots are great for games and iPad-first apps."
    ]
}

/// The public feature roadmap, surfaced in-app so the product feels alive.
struct RoadmapCard: View {
    private let items: [(status: String, color: Color, title: String, detail: String)] = [
        ("Now", LiquidGlass.success, "Frames, backdrops & captions", "Pixel-exact export to every App Store Connect size."),
        ("Next", LiquidGlass.accent, "Text & sticker overlays", "Drop annotations and badges anywhere on the canvas."),
        ("Next", LiquidGlass.accent, "Template gallery", "One-tap professional layouts tuned per category."),
        ("Later", LiquidGlass.warning, "Localized caption sets", "Manage every App Store language from one project."),
        ("Later", LiquidGlass.warning, "App Preview video frames", "The same studio treatment for 15–30s previews.")
    ]

    var body: some View {
        GlassCard(title: "Roadmap", icon: "map.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(item.status)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(item.color.opacity(0.85), in: Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text(item.detail)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
