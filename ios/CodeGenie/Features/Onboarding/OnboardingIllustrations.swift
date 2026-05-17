import SwiftUI

/// Hand-built cartoon illustrations using only SF Symbols and SwiftUI shapes.
/// We deliberately avoid bundled images so the app stays small and every
/// illustration animates and adapts to dark mode for free.
struct OnboardingIllustrationView: View {
    let kind: OnboardingSlide.Illustration
    @State private var bob: Bool = false
    @State private var spin: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch kind {
            case .macWithXcode:                            macWithXcode
            case .projectInitialized:                      projectInitialized
            case .cursorLink:                              cursorLink
            case .aiTraining:                              aiTraining
            case .appBuilding:                             appBuilding
            case .iconForge:                               iconForge
            case .pricing:                                 pricing
            case .simulatorToDevice:                       simulatorToDevice
            case let .videoPlaceholder(caption, videoURL): videoPlaceholder(caption: caption, videoURL: videoURL)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            Motion.run(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { bob = true }
            Motion.run(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityHidden(true)
    }

    // MARK: Slide 1 — Mac with Xcode

    private var macWithXcode: some View {
        ZStack {
            cartoonOrbits
            cartoonShape(systemName: "macbook", size: 180, color: .white, offsetY: bob ? -6 : 6)
            cartoonShape(systemName: "hammer.fill", size: 56, color: LiquidGlass.accent, offsetX: -52, offsetY: -50, rotation: bob ? -8 : 8)
            cartoonShape(systemName: "swift", size: 44, color: .orange, offsetX: 52, offsetY: -54, rotation: bob ? 12 : -6)
        }
    }

    // MARK: Slide 2 — Project initialized

    private var projectInitialized: some View {
        ZStack {
            cartoonOrbits
            cartoonShape(systemName: "folder.fill.badge.plus", size: 150, color: .white, offsetY: bob ? -4 : 4)
            cartoonShape(systemName: "doc.text.fill", size: 38, color: .blue, offsetX: -60, offsetY: 50, rotation: -10)
            cartoonShape(systemName: "doc.text.fill", size: 38, color: .cyan, offsetX: 0, offsetY: 65, rotation: 6)
            cartoonShape(systemName: "doc.text.fill", size: 38, color: .purple, offsetX: 60, offsetY: 50, rotation: 14)
        }
    }

    // MARK: Slide 3 — AI link to Cursor

    private var cursorLink: some View {
        ZStack {
            cartoonOrbits
            cartoonShape(systemName: "cursorarrow.rays", size: 130, color: .white, offsetX: -60, offsetY: bob ? -2 : 2)
            cartoonShape(systemName: "arrow.left.and.right", size: 40, color: LiquidGlass.success, offsetY: 0)
            cartoonShape(systemName: "brain.head.profile", size: 130, color: .pink, offsetX: 60, offsetY: bob ? 2 : -2)
        }
    }

    // MARK: Slide 4 — AI training

    private var aiTraining: some View {
        ZStack {
            cartoonOrbits
            cartoonShape(systemName: "books.vertical.fill", size: 120, color: .white, offsetX: -55)
            cartoonShape(systemName: "sparkles", size: 60, color: .yellow, offsetX: 0, offsetY: -50, rotation: spin ? 360 : 0)
            cartoonShape(systemName: "brain.head.profile", size: 120, color: LiquidGlass.accentSecondary, offsetX: 55, offsetY: bob ? 4 : -4)
        }
    }

    // MARK: Slide 5 — App being built

    private var appBuilding: some View {
        ZStack {
            cartoonOrbits
            cartoonShape(systemName: "iphone.gen3", size: 180, color: .white, offsetY: bob ? -4 : 4)
            cartoonShape(systemName: "bolt.fill", size: 36, color: .yellow, offsetX: -55, offsetY: -55, rotation: spin ? 30 : -30)
            cartoonShape(systemName: "wand.and.stars", size: 50, color: LiquidGlass.accentSecondary, offsetX: 60, offsetY: -40, rotation: spin ? -20 : 20)
            cartoonShape(systemName: "chevron.left.forwardslash.chevron.right", size: 36, color: LiquidGlass.success, offsetX: 50, offsetY: 60)
        }
    }

    // MARK: Slide 6 — Icon forging

    private var iconForge: some View {
        ZStack {
            cartoonOrbits
            // App icon canvas
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(LiquidGlass.auroraGradient)
                .frame(width: 160, height: 160)
                .overlay(Image(systemName: "wand.and.stars")
                    .font(.system(size: 70, weight: .bold))
                    .foregroundStyle(LiquidGlass.primaryText))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
                .rotationEffect(.degrees(bob ? -3 : 3))
            cartoonShape(systemName: "paintbrush.pointed.fill", size: 48, color: .pink, offsetX: -70, offsetY: -70, rotation: -25)
            cartoonShape(systemName: "sparkles", size: 40, color: .yellow, offsetX: 70, offsetY: -65, rotation: spin ? 360 : 0)
        }
    }

    // MARK: Slide 7 — Pricing

    private var pricing: some View {
        ZStack {
            cartoonOrbits
            cartoonShape(systemName: "dollarsign.circle.fill", size: 120, color: LiquidGlass.success, offsetY: bob ? -6 : 6)
            cartoonShape(systemName: "checkmark.seal.fill",     size: 44,  color: LiquidGlass.success, offsetX: -68, offsetY: -54, rotation: bob ? -6 : 6)
            cartoonShape(systemName: "shield.lefthalf.filled",  size: 44,  color: LiquidGlass.warning, offsetX: 70,  offsetY: -50, rotation: bob ? 6 : -6)
            cartoonShape(systemName: "sparkles",                size: 30,  color: LiquidGlass.accent,  offsetX: -52, offsetY: 60,  rotation: bob ? 8 : -8)
            cartoonShape(systemName: "applelogo",               size: 32,  color: .white.opacity(0.85), offsetX: 56, offsetY: 60, rotation: bob ? -4 : 4)
        }
    }

    // MARK: Slide 8 — Simulator to device

    private var simulatorToDevice: some View {
        ZStack {
            cartoonOrbits
            cartoonShape(systemName: "display", size: 140, color: .white, offsetX: -60, offsetY: bob ? -3 : 3)
            cartoonShape(systemName: "arrow.right", size: 40, color: LiquidGlass.success, rotation: bob ? 5 : -5)
            cartoonShape(systemName: "iphone.gen3", size: 140, color: .green, offsetX: 60, offsetY: bob ? 3 : -3)
        }
    }

    // MARK: Helpers

    // MARK: Video placeholder slot

    /// Rendered when a slide opts into a video-style frame instead of
    /// a hand-built cartoon. Until a real `videoURL` is supplied we
    /// show a styled "video coming soon" pane with the slide's
    /// caption. Drop in an `AVPlayer`-backed view once bundled clips
    /// land and the caption can become a play-state badge.
    @ViewBuilder
    private func videoPlaceholder(caption: String, videoURL: URL?) -> some View {
        ZStack {
            cartoonOrbits
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                )
                .frame(width: 260, height: 156)
                .overlay(
                    VStack(spacing: 10) {
                        Image(systemName: videoURL == nil ? "play.rectangle" : "play.rectangle.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white.opacity(videoURL == nil ? 0.55 : 0.95))
                            .accessibilityHidden(true)
                        Text(videoURL == nil ? "Video coming soon" : "Tap to play")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .textCase(.uppercase)
                            .tracking(1.2)
                        Text(caption)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .lineLimit(2)
                    }
                )
                .shadow(color: .black.opacity(0.45), radius: 22, x: 0, y: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(videoURL == nil ? "Video placeholder. \(caption). Real clip coming soon." : "Tutorial video: \(caption)")
    }

    private var cartoonOrbits: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.10), lineWidth: 1).frame(width: 280, height: 280)
            Circle().stroke(.white.opacity(0.06), lineWidth: 1).frame(width: 360, height: 360)
            Circle()
                .fill(LiquidGlass.accent.opacity(0.18))
                .frame(width: 12, height: 12)
                .offset(x: 140)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
    }

    private func cartoonShape(systemName: String, size: CGFloat, color: Color,
                              offsetX: CGFloat = 0, offsetY: CGFloat = 0,
                              rotation: Double = 0) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .bold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.45), radius: 18, x: 0, y: 8)
            .offset(x: offsetX, y: offsetY)
            .rotationEffect(.degrees(rotation))
    }
}
