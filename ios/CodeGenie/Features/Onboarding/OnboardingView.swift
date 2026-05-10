import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var index: Int = 0
    @State private var slideOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                CodeGenieLogo(size: 32, animate: false)
                Text("CodeGenie")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button("Skip") {
                Haptics.selection()
                onFinish()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
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

                Text(slide.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(slide.body)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineSpacing(3)

                if let tip = slide.xcodeTip {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hammer.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(LiquidGlass.warning)
                        Text(tip)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LiquidGlass.warning.opacity(0.25), lineWidth: 0.7)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? LiquidGlass.accent : .white.opacity(0.25))
                    .frame(width: i == index ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if index > 0 {
                PrimaryButton(title: "Back", systemImage: "chevron.left", style: .ghost) {
                    withAnimation(.smooth(duration: 0.4)) { index -= 1 }
                }
                .frame(maxWidth: 130)
            }
            PrimaryButton(
                title: index == slides.count - 1 ? "Start building" : "Next",
                systemImage: index == slides.count - 1 ? "wand.and.stars" : "chevron.right",
                style: .filled
            ) {
                if index == slides.count - 1 {
                    onFinish()
                } else {
                    withAnimation(.smooth(duration: 0.4)) { index += 1 }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        LiquidGlassBackground().ignoresSafeArea()
        OnboardingView { }
    }
}
