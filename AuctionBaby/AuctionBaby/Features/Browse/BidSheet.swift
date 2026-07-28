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
    @State private var insure = false

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
                    AvatarCircle(name: woman.name, hue: woman.hue, photoName: woman.photoName, size: 48)
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
                        Label("Your bid will mention this answer", systemImage: "quote.opening")
                            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                            .foregroundStyle(Theme.rose)
                        Text(prompt.question).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        Text(prompt.answer).font(.system(size: 15, weight: .bold, design: .serif)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Same as any other bid — the money, the rules, the ratings are identical. Her answer just rides along at the top of your bid so she knows what caught your eye.")
                            .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.rose.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.rose.opacity(0.4), lineWidth: 0.8))
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
                    if amount >= Bid.masterpieceBid && store.role == .man && store.me.archetype == .trillionaire {
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

                gildToggle
                insuranceToggle

                intentCallout

                if atFreeLimit {
                    VStack(spacing: 8) {
                        Label("You've used all \(AuctionStore.freeActiveBidLimit) free live bids.",
                              systemImage: "hand.raised.slash.fill")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.warning)
                        PrimaryButton(title: "Get a Pass for unlimited bids", systemImage: "sparkles",
                                      gradient: Theme.roseGradient) { showStore = true }
                        whisperFallback
                    }
                } else {
                    PrimaryButton(title: gild ? "Send Gilded Bid · \(Money.compact(amount))"
                                              : "Place \(Money.compact(amount)) bid",
                                  systemImage: gild ? "seal.fill" : "hand.raised.fill",
                                  gradient: gild ? Theme.prestigeGradient : Theme.goldGradient,
                                  enabled: amount > 0) {
                        store.placeBid(on: woman, amount: amount, note: note, gilded: gild,
                                       insured: insure, promptRef: promptContext?.question)
                        dismiss()
                    }
                    whisperFallback
                }

                Text("Spend your bid on the date — the meal, the drinks, the night. She keeps the receipts and confirms it after. Never wire money or send a personal deposit; the app has no way to send money to another user, by design.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint).multilineTextAlignment(.center)
                Spacer(minLength: 20)
            }
            .screenPadding()
        }
        .background(AppBackground().opacity(0.4))
        .motion(Motion.snap, value: amount)
        .motion(Motion.snap, value: gild)
        .sheet(isPresented: $showStore) { PaywallView(trigger: .bidLimit) }
    }

    /// The commitment reminder shown right at the point of placing a bid: what
    /// the number actually means — the money you'll spend on the date itself
    /// (dinner, drinks, the experience) — and how she'll confirm it (receipts).
    private var intentCallout: some View {
        HStack(spacing: 10) {
            Image(systemName: "signature")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("The money you'll spend on the date")
                    .font(.system(size: 13, weight: .heavy, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text("Dinner, drinks, the experience — not a payment to her. She keeps the receipts so it can be confirmed after.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.gold.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your bid is the money you'll spend on the date itself. She keeps the receipts so it can be confirmed after.")
    }

    /// Bid Insurance — small Gavel premium; if she declines you get it back
    /// plus a Gilded Bid credit. Fixes the sting of a flat "no" without
    /// letting you self-cancel for free profit.
    private var insuranceToggle: some View {
        Button { Haptics.selection(); insure.toggle() } label: {
            HStack(spacing: 12) {
                Image(systemName: insure ? "shield.checkerboard" : "shield")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(insure ? Theme.verify : Theme.inkSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bid Insurance").font(.system(size: 15, weight: .heavy, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("If she declines, your premium comes back — and the gild fee too, if you gilded.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text("\(Tally.compact(AuctionStore.bidInsuranceCost)) ⚖︎")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(insure ? Theme.verify : Theme.inkFaint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM)
                .fill(insure ? Theme.verify.opacity(0.12) : .white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerM)
                .strokeBorder(insure ? Theme.verify.opacity(0.6) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Whisper Bid — anonymous, free, no credit hit. A "reserve nod" that
    /// tests the water before committing a real number. Hidden on copycats.
    @ViewBuilder private var whisperFallback: some View {
        if !woman.isCopycat {
            Button {
                store.placeWhisper(on: woman)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ear.fill")
                    Text("Whisper — no Gavels, no credit hit")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.rose)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Capsule().stroke(Theme.rose.opacity(0.55), lineWidth: 1.2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send an anonymous whisper to \(woman.name)")
        }
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
