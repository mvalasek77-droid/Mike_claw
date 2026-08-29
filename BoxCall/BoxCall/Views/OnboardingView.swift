import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompleted: Bool
    @State private var page: Int = 0
    @State private var showFullGuide = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomeSlide.tag(0)
                callSlide.tag(1)
                putSlide.tag(2)
                statusSlide.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                Button {
                    if page < 3 {
                        withAnimation { page += 1 }
                    } else {
                        hasCompleted = true
                    }
                } label: {
                    Text(page < 3 ? "Next" : "Start trading")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)

                Button("Read the full guide") { showFullGuide = true }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if page < 3 {
                    Button("Skip") { hasCompleted = true }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showFullGuide) {
            NavigationStack { LearnView() }
        }
    }

    // MARK: - Slides

    private var welcomeSlide: some View {
        slide(emoji: "🎬",
              title: "Trade the opening weekend.",
              body: "BoxCall is an options chain for upcoming movies. Take a position on where each release opens, then let the community roast or applaud your call.")
    }

    private var callSlide: some View {
        slide(emoji: "🟢",
              title: "Betting BIGGER.",
              body: "Pick a movie. Pick a dollar number. If it opens ABOVE your number, you win. Every million above your number pays you more. Max loss is just what you paid to enter. (Real name: a Call.)") {
            PayoffChart(side: .call, strike: 100, premium: 12, multiplier: 1)
                .padding(.horizontal, 8)
        }
    }

    private var putSlide: some View {
        slide(emoji: "🔴",
              title: "Betting SMALLER.",
              body: "Same idea — the other direction. If the movie opens BELOW your number, you win. Every million below pays you more. Max loss is still just the entry price. (Real name: a Put.)") {
            PayoffChart(side: .put, strike: 40, premium: 6, multiplier: 1)
                .padding(.horizontal, 8)
        }
    }

    private var statusSlide: some View {
        slide(emoji: "🏆",
              title: "Play-money. Real status.",
              body: "Every account starts with 1,000 Reel Coins. Winning grants XP, tiers, badges, followers, and season titles.\n\nLosing trades cost coins — max loss on any trade is the premium you paid. If you lose everything, trading pauses. Every Monday at midnight, every account resets with a fresh allowance — 500 RC free, more for subscribers.")
    }

    // MARK: -

    @ViewBuilder
    private func slide<Extra: View>(emoji: String, title: String, body: String,
                                    @ViewBuilder extra: () -> Extra = { EmptyView() }) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 20)
            Text(emoji).font(.system(size: 72))
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(body).font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            extra()
            Spacer(minLength: 20)
        }
        .padding(.bottom, 30)
    }
}
