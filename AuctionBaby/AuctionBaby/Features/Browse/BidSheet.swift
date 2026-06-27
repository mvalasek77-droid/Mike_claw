import SwiftUI

/// The bid composer. Pick a number you'll spend on a date, add a note, and
/// place it. Quick-add chips make six- and seven-figure bids painless.
struct BidSheet: View {
    let woman: Profile
    let promptContext: Prompt?
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Int
    @State private var note: String = ""
    @State private var showStore = false
    @State private var gild = false

    /// Free bidders are capped on live bids; a Pass lifts it.
    private var atFreeLimit: Bool {
        !storeKit.hasPass && store.activePendingBidCount >= AuctionStore.freeActiveBidLimit
    }

    init(woman: Profile, promptContext: Prompt? = nil) {
        self.woman = woman
        self.promptContext = promptContext
        _amount = State(initialValue: woman.startingBid ?? 100)
    }

    private let quickAdds = [50, 100, 1_000, 10_000, 100_000]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Capsule().fill(Theme.hairline).frame(width: 38, height: 5).padding(.top, 8)

                HStack(spacing: 12) {
                    AvatarCircle(name: woman.name, hue: woman.hue, size: 48, copycat: woman.isCopycat, copycatStyle: woman.copycatStyle)
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

                if let prompt = promptContext {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Bidding on her answer", systemImage: "quote.opening")
                            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                            .foregroundStyle(Theme.rose)
                        Text(prompt.question).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        Text(prompt.answer).font(.system(size: 15, weight: .bold, design: .serif)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.rose.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.rose.opacity(0.4), lineWidth: 0.8))
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
                    if amount >= Archetype.trillionaire.price && store.role == .man && store.me.archetype == .trillionaire {
                        Label("Masterpiece-eligible — pay it & get confirmed", systemImage: "rosette")
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

                if !woman.isCopycat {
                    gildToggle
                }

                if atFreeLimit {
                    VStack(spacing: 8) {
                        Label("You've used all \(AuctionStore.freeActiveBidLimit) free live bids.",
                              systemImage: "hand.raised.slash.fill")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.warning)
                        PrimaryButton(title: "Get a Pass for unlimited bids", systemImage: "sparkles",
                                      gradient: Theme.roseGradient) { showStore = true }
                    }
                } else {
                    PrimaryButton(title: gild ? "Send Gilded bid · \(Money.compact(amount))"
                                              : "Place \(Money.compact(amount)) bid",
                                  systemImage: gild ? "seal.fill" : "hand.raised.fill",
                                  gradient: gild ? Theme.prestigeGradient : Theme.goldGradient,
                                  enabled: amount > 0) {
                        store.placeBid(on: woman, amount: amount, note: note, gilded: gild,
                                       promptRef: promptContext?.question)
                        dismiss()
                    }
                }

                Text("A bid is a letter of intent — no money moves in the app. You pay her in person; she confirms (or flags you) after the date.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).multilineTextAlignment(.center)
                Spacer(minLength: 20)
            }
            .screenPadding()
        }
        .background(AppBackground().opacity(0.4))
        .motion(Motion.snap, value: amount)
        .motion(Motion.snap, value: gild)
        .sheet(isPresented: $showStore) { GavelStoreView().presentationDetents([.large]) }
    }

    private var gildToggle: some View {
        Button { Haptics.selection(); gild.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: gild ? "seal.fill" : "seal")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(gild ? AnyShapeStyle(Theme.prestigeGradient) : AnyShapeStyle(Theme.inkSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gild this bid").font(.system(size: 15, weight: .heavy, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("Pin to the top of her inbox with a gold ribbon — she's far more likely to accept.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text("\(Tally.compact(AuctionStore.gildedBidCost)) ⚖︎")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(gild ? Theme.gold : Theme.inkFaint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM)
                .fill(gild ? Theme.gold.opacity(0.12) : .white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerM)
                .strokeBorder(gild ? Theme.gold.opacity(0.6) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
