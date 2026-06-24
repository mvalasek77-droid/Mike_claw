import SwiftUI

/// Post-date review. Role-adaptive: the bidder rates her on the five traits and
/// logs what he actually spent; the lot delivers the deadbeat verdict.
struct RateDateView: View {
    let match: Match
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    // shared
    @State private var stars = 5
    @State private var text = ""
    // man → woman
    @State private var traitScores: [Trait: Int] = Dictionary(uniqueKeysWithValues: Trait.allCases.map { ($0, 4) })
    @State private var categories: Set<String> = []
    @State private var spent: Int
    // woman → man
    @State private var paidInFull = true

    private let categoryPool = ["Wine bars", "Art openings", "Tasting menus", "Live music",
                                "Hiking", "Travel", "Theatre", "Coffee crawls", "Dancing"]

    init(match: Match) {
        self.match = match
        _spent = State(initialValue: match.bid.amount)
    }

    private var isMan: Bool { store.role == .man }
    private var other: Profile { match.other(for: store.role ?? .man) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Capsule().fill(Theme.hairline).frame(width: 38, height: 5).padding(.top, 8)

                VStack(spacing: 6) {
                    AvatarCircle(name: other.name, hue: other.hue, size: 64, copycat: other.isCopycat, copycatStyle: other.copycatStyle)
                    Text("How was your date with \(other.name)?")
                        .font(.system(size: 18, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                }

                GlassCard(title: "Overall", icon: "star.fill", tint: Theme.gold) {
                    HStack { Spacer(); StarPicker(value: $stars); Spacer() }
                }

                if isMan {
                    GlassCard(title: "Rate the date", icon: "slider.horizontal.3", tint: Theme.rose) {
                        VStack(spacing: 14) {
                            ForEach(Trait.allCases) { trait in
                                HStack {
                                    Label(trait.rawValue, systemImage: trait.systemImage)
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                                    Spacer()
                                    StarPicker(value: Binding(
                                        get: { traitScores[trait] ?? 4 },
                                        set: { traitScores[trait] = $0 }), tint: Theme.rose)
                                    .scaleEffect(0.72)
                                }
                            }
                        }
                    }

                    GlassCard(title: "Tag her interests", icon: "tag.fill", tint: Theme.gold) {
                        Text("Help future bidders — what's she into?")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                        FlowChips(items: categoryPool, selected: $categories)
                    }

                    GlassCard(title: "What you actually spent", icon: "creditcard.fill", tint: Theme.gold) {
                        Text("You bid \(Money.full(match.bid.amount)). Be honest — she rates your reliability.")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                        Text(Money.full(spent))
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(spent >= match.bid.amount ? Theme.success : Theme.danger)
                            .frame(maxWidth: .infinity)
                        Slider(value: Binding(get: { Double(spent) },
                                              set: { spent = Int($0) }),
                               in: 0...Double(max(match.bid.amount, 1))).tint(Theme.gold)
                        if spent < match.bid.amount {
                            Label("Paying under your bid flags you as a deadbeat.", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.danger)
                        }
                    }
                } else {
                    GlassCard(title: "Did he spend it?", icon: "checkmark.shield.fill", tint: Theme.gold) {
                        Text("He bid \(Money.full(match.bid.amount)). Did he actually pay it?")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        Toggle(isOn: $paidInFull.animation(Motion.snap)) {
                            Text(paidInFull ? "Paid in full — a gentleman" : "Deadbeat — talked big, paid small")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(paidInFull ? Theme.success : Theme.danger)
                        }
                        .tint(Theme.success)
                        if match.bid.qualifiesForMasterpiece {
                            Label(paidInFull ? "This mints your Masterpiece." : "No payment, no Masterpiece.",
                                  systemImage: "rosette")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(paidInFull ? Theme.rose : Theme.inkFaint)
                        }
                    }
                }

                GlassCard(title: "Review", icon: "text.bubble.fill") {
                    TextField("", text: $text,
                              prompt: Text("A line for the record…").foregroundStyle(Theme.inkFaint), axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        .lineLimit(2...5)
                }

                PrimaryButton(title: "Post review", systemImage: "paperplane.fill",
                              gradient: isMan ? Theme.goldGradient : Theme.roseGradient) {
                    submit()
                    dismiss()
                }
                Spacer(minLength: 20)
            }
            .screenPadding()
        }
        .background(AppBackground().opacity(0.5))
    }

    private func submit() {
        if isMan {
            store.completeAsMan(match, stars: stars, traits: traitScores,
                                categories: Array(categories),
                                text: text.isEmpty ? "Good evening out." : text,
                                actuallySpent: spent)
        } else {
            store.completeAsWoman(match, paid: paidInFull, stars: stars,
                                  text: text.isEmpty ? (paidInFull ? "He delivered." : "All talk.") : text)
        }
    }
}
