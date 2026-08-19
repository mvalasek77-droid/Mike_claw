import SwiftUI

struct TutorialView: View {
    let onFinished: () -> Void
    @State private var step = 0

    private let steps: [TutorialStep] = [
        TutorialStep(
            icon: "house.fill",
            title: "Your Feed",
            body: "Everything starts here — posts from friends and Bro-hoods in one unified feed. Upvote, downvote, and tap into threaded comments.",
            accent: Color(red: 0.36, green: 0.55, blue: 1.0)
        ),
        TutorialStep(
            icon: "person.3.fill",
            title: "Bro-hoods",
            body: "Join communities around what matters to you — fitness, grilling, cars, fatherhood, philosophy, and more. Each has its own feed, moderators, and events.",
            accent: Color(red: 0.20, green: 0.78, blue: 0.55)
        ),
        TutorialStep(
            icon: "bubble.left.and.bubble.right.fill",
            title: "Messages & Marketplace",
            body: "DM friends, chat in groups, and trade gear in the Bro-ket — our built-in marketplace. Buyers and sellers connect through in-app messaging.",
            accent: Color(red: 1.0, green: 0.42, blue: 0.21)
        ),
        TutorialStep(
            icon: "shield.lefthalf.filled",
            title: "Your Space, Your Rules",
            body: "Report, block, or mute anyone from the ··· menu on any post, comment, or profile. Community moderators keep Bro-hoods on track.",
            accent: Color(red: 0.42, green: 0.55, blue: 0.95)
        ),
        TutorialStep(
            icon: "star.fill",
            title: "Earn Bro Cred",
            body: "Your reputation is built through upvotes, awards, and contributions. Bro Cred is earned — not bought.",
            accent: Color(red: 0.95, green: 0.68, blue: 0.22)
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: Tokens.Spacing.xxl) {
                let current = steps[step]

                Image(systemName: current.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(current.accent)
                    .frame(height: 64)
                    .id(step)
                    .transition(.scale.combined(with: .opacity))

                VStack(spacing: Tokens.Spacing.md) {
                    Text(current.title)
                        .font(Tokens.Typography.title)
                        .id("title-\(step)")
                        .transition(.push(from: .trailing))

                    Text(current.body)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(Tokens.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .id("body-\(step)")
                        .transition(.push(from: .trailing))
                }
            }
            .padding(.horizontal, Tokens.Spacing.xl)

            Spacer()

            VStack(spacing: Tokens.Spacing.lg) {
                pageIndicator

                Button {
                    if step < steps.count - 1 {
                        withAnimation(Tokens.Motion.gentle) { step += 1 }
                    } else {
                        onFinished()
                    }
                } label: {
                    Text(step < steps.count - 1 ? "Next" : "Let's Go")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if step < steps.count - 1 {
                    Button("Skip") { onFinished() }
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Color.textSecondary)
                }
            }
            .padding(.horizontal, Tokens.Spacing.xl)
            .padding(.bottom, Tokens.Spacing.xxl)
        }
        .animation(Tokens.Motion.gentle, value: step)
    }

    private var pageIndicator: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule()
                    .fill(i == step ? steps[step].accent : Tokens.Color.textSecondary.opacity(0.3))
                    .frame(width: i == step ? 24 : 8, height: 8)
            }
        }
        .animation(Tokens.Motion.snappy, value: step)
    }
}

private struct TutorialStep {
    let icon: String
    let title: String
    let body: String
    let accent: Color
}
