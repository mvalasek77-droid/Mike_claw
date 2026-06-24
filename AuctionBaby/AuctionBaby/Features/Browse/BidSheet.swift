import SwiftUI

/// The bid composer. Pick a number you'll spend on a date, add a note, and
/// place it. Quick-add chips make six- and seven-figure bids painless.
struct BidSheet: View {
    let woman: Profile
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Int
    @State private var note: String = ""

    init(woman: Profile) {
        self.woman = woman
        _amount = State(initialValue: woman.startingBid ?? 100)
    }

    private let quickAdds = [50, 100, 1_000, 10_000, 100_000]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Capsule().fill(Theme.hairline).frame(width: 38, height: 5).padding(.top, 8)

                HStack(spacing: 12) {
                    AvatarCircle(name: woman.name, hue: woman.hue, size: 48, copycat: woman.isCopycat)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bidding on \(woman.name)")
                            .font(.system(size: 16, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                        if let floor = woman.startingBid {
                            Text("Floor \(Money.full(floor))").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.gold)
                        } else {
                            Text("No floor — open bidding").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                        }
                    }
                    Spacer()
                }

                if woman.isCopycat {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Copycat — bidding lowers your Auction Credit.")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.copycat)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.copycat.opacity(0.12)))
                }

                // Big amount display.
                VStack(spacing: 4) {
                    Text("Your bid").font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1).foregroundStyle(Theme.inkFaint)
                    Text(Money.full(amount))
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.goldGradient)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5).lineLimit(1)
                    if amount >= 1_000_000 && store.role == .man && store.me.archetype == .trillionaire {
                        Label("Masterpiece-eligible bid", systemImage: "rosette")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.rose)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

                // Quick add chips.
                FlexLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(quickAdds, id: \.self) { add in
                        Button {
                            Haptics.selection()
                            Motion.run(Motion.snap) { amount += add }
                        } label: {
                            Chip(text: "+\(Money.compact(add))", systemImage: "plus", color: Theme.gold)
                        }.buttonStyle(.plain)
                    }
                    Button {
                        Haptics.tap()
                        Motion.run(Motion.snap) { amount = woman.startingBid ?? 100 }
                    } label: { Chip(text: "Reset", systemImage: "arrow.counterclockwise", color: .white) }
                        .buttonStyle(.plain)
                }

                // Note.
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADD A NOTE").font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1).foregroundStyle(Theme.inkFaint)
                    TextField("", text: $note,
                              prompt: Text("Why you? Make the bid count.").foregroundStyle(Theme.inkFaint),
                              axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                }

                PrimaryButton(title: "Place \(Money.compact(amount)) bid", systemImage: "hand.raised.fill",
                              enabled: amount > 0) {
                    store.placeBid(on: woman, amount: amount, note: note)
                    dismiss()
                }

                Text("Bids are offers — nothing's charged until a date actually happens.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).multilineTextAlignment(.center)
                Spacer(minLength: 20)
            }
            .screenPadding()
        }
        .background(AppBackground().opacity(0.4))
        .motion(Motion.snap, value: amount)
    }
}
