import SwiftUI

/// Re-runnable slide deck. Onboarding wraps it on first launch; the
/// "Watch the tour again" entry on Home + Settings opens it as a sheet.
///
/// Two modes:
///   * `.onboarding`  — user is brand new, finish button advances out of
///                      the splash and into the app.
///   * `.replay`      — user has finished onboarding once; the deck is
///                      re-watchable, finish dismisses the sheet.
struct TutorialView: View {
    enum Mode: Equatable {
        case onboarding
        case replay
    }

    var mode: Mode = .replay
    var onFinish: () -> Void

    @State private var index: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private let slides = OnboardingSlide.all

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $index) {
                ForEach(slides.indices, id: \.self) { i in
                    slideCard(slides[i])
                        .tag(i)
                        .padding(.horizontal, 20)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: index) { _, _ in Haptics.selection() }

            VStack(spacing: 16) {
                pageDots
                actionRow
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.top, 12)
        .background(LiquidGlassBackground().ignoresSafeArea())
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                CodeGenieLogo(size: 32, animate: !reduceMotion)
                Text("CodeGenie")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            Spacer()
            Button(mode == .onboarding ? "Skip" : "Close") {
                Haptics.selection()
                finish()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            .accessibilityLabel(mode == .onboarding ? "Skip onboarding" : "Close tutorial")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func slideCard(_ slide: OnboardingSlide) -> some View {
        VStack(spacing: 20) {
            GlassSurface(tier: .raised) {
                VStack(spacing: 16) {
                    OnboardingIllustrationView(kind: slide.illustration)
                        .frame(height: 320)
                        .frame(maxWidth: .infinity)
                        .background(
                            RadialGradient(
                                colors: [slide.palette[0].opacity(0.35), .clear],
                                center: .center, startRadius: 30, endRadius: 220
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(20)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(slide.chapter)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .accessibilityHidden(true)

                Text(slide.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(slide.body)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .lineSpacing(3)

                if let tip = slide.xcodeTip {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hammer.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(LiquidGlass.warning)
                            .accessibilityHidden(true)
                        Text(tip)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LiquidGlass.warning.opacity(0.25), lineWidth: 0.7)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Xcode tip: \(tip)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .contain)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? LiquidGlass.accent : .white.opacity(0.25))
                    .frame(width: i == index ? 22 : 7, height: 7)
                    .animation(Motion.spring, value: index)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Slide \(index + 1) of \(slides.count)")
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if index > 0 {
                PrimaryButton(title: "Back", systemImage: "chevron.left", style: .ghost) {
                    withAnimation(Motion.smooth) { index -= 1 }
                }
                .frame(maxWidth: 130)
                .accessibilityLabel("Previous slide")
            }
            PrimaryButton(
                title: index == slides.count - 1 ? finishCTA : "Next",
                systemImage: index == slides.count - 1 ? finishIcon : "chevron.right",
                style: .filled
            ) {
                if index == slides.count - 1 {
                    finish()
                } else {
                    withAnimation(Motion.smooth) { index += 1 }
                }
            }
            .accessibilityLabel(index == slides.count - 1 ? finishCTA : "Next slide")
        }
    }

    private var finishCTA: String {
        switch mode {
        case .onboarding: "Start building"
        case .replay:     "Got it"
        }
    }

    private var finishIcon: String {
        switch mode {
        case .onboarding: "wand.and.stars"
        case .replay:     "checkmark"
        }
    }

    private func finish() {
        onFinish()
        if mode == .replay { dismiss() }
    }
}

#Preview { TutorialView { } }
