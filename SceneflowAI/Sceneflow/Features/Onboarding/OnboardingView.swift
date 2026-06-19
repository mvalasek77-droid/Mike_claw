import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0

    private struct Slide {
        let symbol: String
        let title: String
        let body: String
    }

    private let slides: [Slide] = [
        .init(symbol: "keyboard.fill",
              title: "Write like a pro",
              body: "An editor that formats screenplay elements as you type. Return and Tab do exactly what you expect — scene headings, action, dialogue, transitions."),
        .init(symbol: "rectangle.grid.2x2.fill",
              title: "Structure your story",
              body: "Break your story on the beat board, start from Save the Cat or the Hero's Journey, and watch your page count and runtime update live."),
        .init(symbol: "sparkles",
              title: "AI that respects your voice",
              body: "Continue a scene, punch up dialogue, get honest coverage notes, and check character voice — built in, not bolted on."),
        .init(symbol: "tag.fill",
              title: "A quarter of the price",
              body: "Everything pro screenwriting apps charge ~$99/year for, plus AI, for $24.99/year. Save \(Pricing.savingsPercent)%.")
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    let slide = slides[index]
                    VStack(spacing: 22) {
                        Spacer()
                        Image(systemName: slide.symbol)
                            .font(.system(size: 72, weight: .bold))
                            .foregroundStyle(Palette.marqueeGradient)
                        Text(slide.title)
                            .font(.displayMedium)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.primaryText)
                        Text(slide.body)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.secondaryText)
                            .padding(.horizontal, 28)
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            PrimaryButton(title: page == slides.count - 1 ? "Start writing" : "Next") {
                if page == slides.count - 1 {
                    onFinish()
                } else {
                    Motion.run(.spring) { page += 1 }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Button("Skip") { onFinish() }
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .padding(.bottom, 12)
        }
    }
}
