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
                    if store.role == .man {
                        balance
                        if store.demoMode { demoSection }
                        gavelSection
                    }
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
                        .foregroundStyle(Theme.inkSoft).font(.dynamicScaled(13, relativeTo: .footnote))
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
                Image(systemName: "hammer.fill").font(.dynamicScaled(20, weight: .bold, relativeTo: .title3))
                    .foregroundStyle(.black).frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.goldGradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Gavels").font(.dynamicScaled(11, weight: .bold, design: .rounded, relativeTo: .caption2))
                        .foregroundStyle(Theme.inkFaint)
                    Text(Tally.compact(store.wallet))
                        .font(.dynamicScaled(26, weight: .heavy, design: .rounded, relativeTo: .title1))
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

    // MARK: Demo Mode (App Review)

    /// Free counterparts of every paid product, shown only in Demo Mode so a
    /// reviewer can exercise the full economy without a sandbox purchase. The
    /// real IAP products stay visible below for the production-path check.
    private var demoSection: some View {
        GlassCard(title: "Demo Mode · everything free", icon: "testtube.2", tint: Theme.verify) {
            VStack(spacing: 10) {
                Text("For App Review. The real IAP products below remain live so the sandbox purchase path can be verified in the same session.")
                    .font(.dynamicScaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    demoChip("+5,000 Gavels") { store.addDemoGavels(5_000) }
                    demoChip("+30,000 Gavels") { store.addDemoGavels(30_000) }
                }
                HStack(spacing: 8) {
                    demoChip("Free Boost") { store.activateBoost() }
                    demoChip(storeKit.demoTier == nil ? "Free Black Card Pass" : "Pass active ✓") {
                        storeKit.demoTier = .blackcard
                        Haptics.success()
                        store.toastFlash("Demo Black Card active — every Pass perk unlocked.")
                    }
                }
            }
        }
    }

    private func demoChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                .foregroundStyle(Theme.verify)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.verify.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Gavels

    private var gavelSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Top up Gavels", subtitle: "Spend them on status. Bids are always free.")
            if storeKit.gavelPacks.isEmpty {
                unavailableCard
            } else {
                let packs = storeKit.gavelPacks   // sorted low → high price
                let base = packs.first.flatMap { p -> Double? in
                    let price = NSDecimalNumber(decimal: p.price).doubleValue
                    return price > 0 ? Double(StoreKitService.gavels(for: p.id)) / price : nil
                }
                ForEach(Array(packs.enumerated()), id: \.element.id) { index, product in
                    GavelPackRow(product: product,
                                 badge: valueBadge(product, index: index, count: packs.count, base: base)) {
                        Task { await buy(product) }
                    }
                }
            }
        }
    }

    /// A "+X% BONUS" / "BEST VALUE" chip computed from the *real* prices, so it
    /// stays accurate whatever the App Store prices are set to. The cheapest
    /// pack is the baseline (no badge); the priciest is flagged best value.
    private func valueBadge(_ product: Product, index: Int, count: Int, base: Double?) -> String? {
        guard let base, base > 0 else { return nil }
        if index == count - 1 { return "BEST VALUE" }
        let price = NSDecimalNumber(decimal: product.price).doubleValue
        guard price > 0 else { return nil }
        let rate = Double(StoreKitService.gavels(for: product.id)) / price
        let bonus = Int((rate / base - 1) * 100 + 0.5)
        return bonus >= 5 ? "+\(bonus)% BONUS" : nil
    }

    private var unavailableCard: some View {
        GlassCard(tint: Theme.warning) {
            Text("Store products aren't loaded yet. In a sandbox/TestFlight build they appear here.")
                .font(.dynamicScaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft)
            if store.demoMode {
                GhostButton(title: "Demo: +10,000 Gavels (no charge)", systemImage: "wand.and.stars") {
                    store.addDemoGavels()
                }
            }
        }
    }

    // MARK: Boost

    @ViewBuilder private var boostSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Spotlight Boost", subtitle: "30 minutes at the very top of the floor.")
            GlassSurface(corner: Theme.cornerL, tint: Theme.rose) {
                HStack(spacing: 14) {
                    Image(systemName: "bolt.fill").font(.dynamicScaled(20, weight: .bold, relativeTo: .title3))
                        .foregroundStyle(.black).frame(width: 46, height: 46)
                        .background(Circle().fill(Theme.roseGradient))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Spotlight Boost").font(.dynamicScaled(16, weight: .heavy, design: .serif, relativeTo: .callout))
                            .foregroundStyle(Theme.ink)
                        if store.isBoosted, let until = store.boostUntil {
                            HStack(spacing: 4) {
                                Text("Active ·").font(.dynamicScaled(12, weight: .semibold, relativeTo: .caption1)).foregroundStyle(Theme.rose)
                                Text(timerInterval: Date.now...max(until, Date.now.addingTimeInterval(1)), countsDown: true)
                                    .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1)).foregroundStyle(Theme.rose)
                            }
                        } else {
                            Text("Jump to the top of every feed for 30 minutes.")
                                .font(.dynamicScaled(12, relativeTo: .caption1)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer()
                    if let boost = storeKit.boostProduct {
                        Button { Task { await buy(boost) } } label: {
                            Text(store.isBoosted ? "Extend" : boost.displayPrice)
                                .font(.dynamicScaled(15, weight: .heavy, design: .rounded, relativeTo: .subheadline)).foregroundStyle(.black)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(Capsule().fill(Theme.roseGradient))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            if storeKit.hasPass && store.canClaimWeeklyBoost() {
                GhostButton(title: "Claim your free weekly Boost (Pass perk)",
                            systemImage: "gift.fill", tint: Theme.rose) {
                    store.claimWeeklyBoost()
                }
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
            Text("Gavels are a one-time purchase of in-app currency. Passes are auto-renewable subscriptions billed to your Apple ID; they renew unless canceled at least 24h before the period ends. Manage or cancel in Settings.")
                .font(.dynamicScaled(10, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
            HStack(spacing: 14) {
                if let termsURL = BackendConfig.termsURL {
                    Link("Terms", destination: termsURL)
                }
                if let privacyURL = BackendConfig.privacyURL {
                    Link("Privacy", destination: privacyURL)
                }
            }
            .font(.dynamicScaled(11, weight: .semibold, relativeTo: .caption2)).tint(Theme.gold)
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
        let outcome = await storeKit.purchase(product, appAccountToken: store.appAccountToken)
        if outcome == .success { Haptics.success() }
        else if outcome == .failed { Haptics.error() }
    }
}

private struct GavelPackRow: View {
    let product: Product
    var badge: String? = nil
    var onBuy: () -> Void

    private var gavels: Int { StoreKitService.gavels(for: product.id) }

    var body: some View {
        GlassSurface(corner: Theme.cornerL) {
            HStack(spacing: 14) {
                Image(systemName: "hammer.fill").font(.dynamicScaled(18, weight: .bold, relativeTo: .body))
                    .foregroundStyle(Theme.gold).frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.gold.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(Tally.compact(gavels)) Gavels")
                            .font(.dynamicScaled(16, weight: .heavy, design: .serif, relativeTo: .callout)).foregroundStyle(Theme.ink)
                        if let badge {
                            Text(badge)
                                .font(.dynamicScaled(9, weight: .heavy, design: .rounded, relativeTo: .caption2))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.goldGradient))
                        }
                    }
                    Text(product.displayName).font(.dynamicScaled(12, relativeTo: .caption1)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Button(action: onBuy) {
                    Text(product.displayPrice)
                        .font(.dynamicScaled(15, weight: .heavy, design: .rounded, relativeTo: .subheadline)).foregroundStyle(.black)
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
                    Image(systemName: tier.systemImage).font(.dynamicScaled(16, weight: .bold, relativeTo: .callout))
                        .foregroundStyle(tier == .blackcard ? .black : Theme.rose)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(tier == .blackcard
                                                  ? AnyShapeStyle(Theme.goldGradient)
                                                  : AnyShapeStyle(Theme.rose.opacity(0.16))))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tier.title).font(.dynamicScaled(17, weight: .heavy, design: .serif, relativeTo: .body))
                            .foregroundStyle(Theme.ink)
                        if let product {
                            Text("\(product.displayPrice) / month").font(.dynamicScaled(12, weight: .semibold, relativeTo: .caption1))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    Spacer()
                    if active {
                        Text("ACTIVE").font(.dynamicScaled(9, weight: .heavy, design: .rounded, relativeTo: .caption2))
                            .foregroundStyle(.black).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.success))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tier.perks, id: \.self) { perk in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.dynamicScaled(12, relativeTo: .caption1))
                                .foregroundStyle(Theme.success)
                            Text(perk).font(.dynamicScaled(13, weight: .medium, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft)
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
