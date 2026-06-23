import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private let slides: [Slide] = [
        Slide(icon: "photo.on.rectangle.angled",
              title: "Start with a raw shot",
              body: "Drop in any screenshot straight from your iPhone. No exact sizing, no fuss — we handle the rest."),
        Slide(icon: "wand.and.stars",
              title: "Frame it beautifully",
              body: "Add a device frame, a gradient backdrop, and a marketing headline. A live, pixel-accurate preview updates as you go."),
        Slide(icon: "checkmark.seal.fill",
              title: "Export, ready to upload",
              body: "Render every App Store Connect size at the exact pixels Apple requires — saved to a tidy Photos album for upload.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    SlideView(slide: slide).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Motion.smooth, value: page)

            PageDots(count: slides.count, index: page)
                .padding(.vertical, 18)

            VStack(spacing: 12) {
                PrimaryButton(
                    title: page == slides.count - 1 ? "Get started" : "Continue",
                    systemImage: page == slides.count - 1 ? "arrow.right.circle.fill" : nil
                ) {
                    if page < slides.count - 1 {
                        Motion.run(Motion.spring) { page += 1 }
                    } else {
                        onFinish()
                    }
                }

                if page < slides.count - 1 {
                    Button("Skip") { onFinish() }
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }

    struct Slide {
        let icon: String
        let title: String
        let body: String
    }
}

private struct SlideView: View {
    let slide: OnboardingView.Slide
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LiquidGlass.auroraGradient.opacity(0.22))
                    .frame(width: 168, height: 168)
                    .blur(radius: 12)
                Image(systemName: slide.icon)
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(LiquidGlass.auroraGradient)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 12) {
                Text(slide.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .multilineTextAlignment(.center)
                Text(slide.body)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            Spacer()
            Spacer()
        }
        .onAppear { withAnimation(Motion.smooth) { appeared = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slide.title). \(slide.body)")
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.25)))
                    .frame(width: i == index ? 22 : 8, height: 8)
                    .animation(Motion.spring, value: index)
            }
        }
        .accessibilityHidden(true)
    }
}
