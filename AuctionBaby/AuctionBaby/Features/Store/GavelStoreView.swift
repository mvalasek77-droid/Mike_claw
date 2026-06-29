import SwiftUI
import StoreKit

/// The store: buy Gavels (consumable currency for status) and subscribe to an
/// Auction Baby Pass. The only real-money surfaces in the app.
struct GavelStoreView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    balance
                    gavelSection
                    boostSection
                    passSection
                    footer
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 8)
            }
            .background(AppBackground())
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.gold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Restore") { Task { await storeKit.restore() } }
                        .foregroundStyle(Theme.inkSoft).font(.system(size: 13))
                }
            }
            .overlay { if storeKit.isWorking { workingOverlay } }
            .alert("Store error", isPresented: errorBinding) {
                Button("OK") { storeKit.errorMessage = nil }
            } message: { Text(storeKit.errorMessage ?? "") }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { storeKit.errorMessage != nil }, set: { if !$0 { storeKit.errorMessage = nil } })
    }

    private var balance: some View {
        GlassCard(tint: Theme.gold) {
            HStack(spacing: 12) {
                Image(systemName: "hammer.fill").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black).frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.goldGradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Gavels").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                    Text(Tally.compact(store.wallet))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.gold).contentTransition(.numericText())
                }
                Spacer()
                if let tier = storeKit.activeTier {
                    Chip(text: tier.title, systemImage: tier.systemImage, color: Theme.rose, filled: true)
                }
            }
        }
        .motion(Motion.snap, value: store.wallet)
    }

    // MARK: Gavels

    private var gavelSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Top up Gavels", subtitle: "Spend them on status. Bids are always free.")
            if storeKit.gavelPacks.isEmpty {
                unavailableCard
            } else {
                ForEach(storeKit.gavelPacks, id: \.id) { product in
                    GavelPackRow(product: product) { Task { await buy(product) } }
                }
            }
        }
    }

    private var unavailableCard: some View {
        GlassCard(tint: Theme.warning) {
            Text("Store products aren't loaded. In a sandbox/TestFlight build they appear here. For now, use the demo top-up:")
                .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
            GhostButton(title: "Demo: +10,000 Gavels (no charge)", systemImage: "wand.and.stars") {
                store.addDemoGavels()
            }
        }
    }

    // MARK: Boost

    @ViewBuilder private var boostSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Spotlight Boost", subtitle: "30 minutes at the very top of the floor.")
            GlassSurface(corner: Theme.cornerL, tint: Theme.rose) {
                HStack(spacing: 14) {
                    Image(systemName: "bolt.fill").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black).frame(width: 46, height: 46)
                        .background(Circle().fill(Theme.roseGradient))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Spotlight Boost").font(.system(size: 16, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        if store.isBoosted, let until = store.boostUntil {
                            HStack(spacing: 4) {
                                Text("Active ·").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.rose)
                                Text(timerInterval: Date.now...max(until, Date.now.addingTimeInterval(1)), countsDown: true)
                                    .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.rose)
                            }
                        } else {
                            Text("Jump to the top of every feed for 30 minutes.")
                                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer()
                    if let boost = storeKit.boostProduct {
                        Button { Task { await buy(boost) } } label: {
                            Text(store.isBoosted ? "Extend" : boost.displayPrice)
                                .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(Capsule().fill(Theme.roseGradient))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: Pass

    private var passSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Auction Baby Pass", subtitle: "Win the bid you can't see.")
            ForEach(StoreKitService.PassTier.allCases) { tier in
                let product = storeKit.subscriptions.first { $0.id == tier.productID }
                PassRow(tier: tier, product: product, active: storeKit.isSubscribed(to: tier)) {
                    if let product { Task { await buy(product) } }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Gavels are a one-time purchase of in-app currency. Passes are auto-renewable subscriptions billed to your Apple ID; they renew unless cancelled at least 24h before the period ends. Manage or cancel in Settings.")
                .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
            HStack(spacing: 14) {
                Link("Terms", destination: URL(string: "https://auctionbaby.app/terms")!)
                Link("Privacy", destination: URL(string: "https://auctionbaby.app/privacy")!)
            }
            .font(.system(size: 11, weight: .semibold)).tint(Theme.gold)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 6)
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            ProgressView().controlSize(.large).tint(Theme.gold)
        }
    }

    private func buy(_ product: Product) async {
        let outcome = await storeKit.purchase(product)
        if outcome == .success { Haptics.success() }
        else if outcome == .failed { Haptics.error() }
    }
}

private struct GavelPackRow: View {
    let product: Product
    var onBuy: () -> Void

    private var gavels: Int { StoreKitService.gavels(for: product.id) }

    var body: some View {
        GlassSurface(corner: Theme.cornerL) {
            HStack(spacing: 14) {
                Image(systemName: "hammer.fill").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.gold).frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.gold.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Tally.compact(gavels)) Gavels")
                        .font(.system(size: 16, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                    Text(product.displayName).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Button(action: onBuy) {
                    Text(product.displayPrice)
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.goldGradient))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
    }
}

private struct PassRow: View {
    let tier: StoreKitService.PassTier
    let product: Product?
    let active: Bool
    var onSubscribe: () -> Void

    var body: some View {
        GlassSurface(corner: Theme.cornerL, tint: tier == .blackcard ? Theme.gold : .white) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: tier.systemImage).font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tier == .blackcard ? .black : Theme.rose)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(tier == .blackcard
                                                  ? AnyShapeStyle(Theme.goldGradient)
                                                  : AnyShapeStyle(Theme.rose.opacity(0.16))))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tier.title).font(.system(size: 17, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        if let product {
                            Text("\(product.displayPrice) / month").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    Spacer()
                    if active {
                        Text("ACTIVE").font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.success))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tier.perks, id: \.self) { perk in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
                                .foregroundStyle(Theme.success)
                            Text(perk).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                if !active {
                    PrimaryButton(title: product == nil ? "Unavailable" : "Subscribe",
                                  systemImage: "sparkles",
                                  gradient: tier == .blackcard ? Theme.goldGradient : Theme.roseGradient,
                                  enabled: product != nil) {
                        onSubscribe()
                    }
                }
            }
            .padding(16)
        }
    }
}
