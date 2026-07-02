import SwiftUI
import StoreKit
import UIKit

/// Why the paywall fired. Each trigger gets its own hook line so the pitch
/// lands at the moment of peak intent — the core of the conversion design.
enum PaywallTrigger {
    case rankReveal          // "am I winning?" tapped on a locked rank row
    case bidLimit            // out of free live bids
    case filters             // tried a premium filter
    case readReceipts        // wanted Seen/Delivered
    case general             // browsed in from the store

    var headline: String {
        switch self {
        case .rankReveal: return "She's comparing bids.\nSee where you stand."
        case .bidLimit: return "Out of free bids.\nThe floor doesn't wait."
        case .filters: return "Cut the noise.\nBid only on your type."
        case .readReceipts: return "She read it.\nKnow the moment she does."
        case .general: return "Win the bid\nyou can't see."
        }
    }

    var icon: String {
        switch self {
        case .rankReveal: return "chart.bar.fill"
        case .bidLimit: return "hand.raised.slash.fill"
        case .filters: return "slider.horizontal.3"
        case .readReceipts: return "checkmark.message.fill"
        case .general: return "crown.fill"
        }
    }

    /// The tier pre-selected when the paywall opens — the cheapest tier that
    /// actually solves the trigger.
    var suggestedTier: StoreKitService.PassTier {
        switch self {
        case .readReceipts: return .blackcard
        case .filters: return .reserve
        default: return .paddle
        }
    }
}

/// The subscription paywall. One screen, three tiers, a benefits matrix, and a
/// single CTA — shown at peak-intent moments rather than on launch.
struct PaywallView: View {
    var trigger: PaywallTrigger = .general
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @Environment(\.dismiss) private var dismiss

    @State private var selected: StoreKitService.PassTier
    @State private var appear = false

    init(trigger: PaywallTrigger = .general) {
        self.trigger = trigger
        _selected = State(initialValue: trigger.suggestedTier)
    }

    /// (label, lowest tier that includes it)
    private let benefits: [(String, StoreKitService.PassTier)] = [
        ("Unlimited live bids", .paddle),
        ("See if you're the top bid", .paddle),
        ("1 Spotlight Boost every week", .paddle),
        ("Reveal her reserve price", .reserve),
        ("Auto-rebid to stay on top", .reserve),
        ("Advanced filters (verified-only, interests)", .reserve),
        ("Read receipts — Seen / Delivered", .blackcard),
        ("Priority placement in every inbox", .blackcard),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    tierPicker
                    benefitsMatrix
                    cta
                    footer
                    Spacer(minLength: 16)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground(glow: Theme.rose))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.inkSoft).frame(width: 30, height: 30)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") { Task { await storeKit.restore() } }
                        .font(.system(size: 13)).foregroundStyle(Theme.inkFaint)
                }
            }
            .overlay { if storeKit.isWorking { workingOverlay } }
        }
        .onAppear { Motion.run(.spring(response: 0.55, dampingFraction: 0.75)) { appear = true } }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: trigger.icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 68, height: 68)
                .background(Circle().fill(Theme.goldGradient))
                .depth(34, strong: true)
                .scaleEffect(appear ? 1 : 0.6)
            Text(trigger.headline)
                .font(.system(size: 28, weight: .heavy, design: .serif))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .opacity(appear ? 1 : 0)
            Text("Auction Baby Pass")
                .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                .foregroundStyle(Theme.gold)
        }
        .padding(.top, 4)
    }

    private var tierPicker: some View {
        HStack(spacing: 10) {
            ForEach(StoreKitService.PassTier.allCases) { tier in
                tierCard(tier)
            }
        }
    }

    private func tierCard(_ tier: StoreKitService.PassTier) -> some View {
        let isSelected = tier == selected
        let product = storeKit.subscriptions.first { $0.id == tier.productID }
        return Button {
            Haptics.selection()
            Motion.run(Motion.snap) { selected = tier }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tier.systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.gold : Theme.inkFaint)
                Text(tier.title)
                    .font(.system(size: 13, weight: .heavy, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(product?.displayPrice ?? fallbackPrice(tier))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSelected ? Theme.gold : Theme.inkSoft)
                Text("/ month").font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous)
                    .fill(isSelected ? Theme.gold.opacity(0.12) : .white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous)
                    .strokeBorder(isSelected ? Theme.gold : Theme.hairline, lineWidth: isSelected ? 1.5 : 0.8)
            )
            .scaleEffect(isSelected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
    }

    private func fallbackPrice(_ tier: StoreKitService.PassTier) -> String {
        switch tier {
        case .paddle: return "$19.99"
        case .reserve: return "$39.99"
        case .blackcard: return "$99.99"
        }
    }

    private var benefitsMatrix: some View {
        GlassSurface(corner: Theme.cornerL) {
            VStack(spacing: 0) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { i, benefit in
                    let tiers = StoreKitService.PassTier.allCases
                    let included = (tiers.firstIndex(of: benefit.1) ?? 0) <= (tiers.firstIndex(of: selected) ?? 0)
                    HStack(spacing: 10) {
                        Image(systemName: included ? "checkmark.circle.fill" : "lock.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(included ? Theme.success : Theme.inkFaint)
                        Text(benefit.0)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(included ? Theme.ink : Theme.inkFaint)
                        Spacer()
                        if !included {
                            Text(benefit.1.title)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.rose)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    if i < benefits.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 40) }
                }
            }
        }
    }

    private var cta: some View {
        VStack(spacing: 10) {
            if storeKit.isSubscribed(to: selected) {
                Label("\(selected.title) is active", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.success)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
            } else {
                PrimaryButton(title: "Continue with \(selected.title)",
                              systemImage: "sparkles",
                              gradient: selected == .blackcard ? Theme.prestigeGradient : Theme.goldGradient,
                              enabled: subscriptionProduct != nil || !storeKit.subscriptions.isEmpty) {
                    subscribe()
                }
                if subscriptionProduct == nil {
                    Text("Products load from the App Store — in the simulator, run with the bundled StoreKit configuration.")
                        .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var subscriptionProduct: Product? {
        storeKit.subscriptions.first { $0.id == selected.productID }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Auto-renews monthly until cancelled at least 24h before the period ends. Billed to your Apple ID; manage in Settings.")
                .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                Link("Terms", destination: URL(string: "https://auctionbaby.app/terms")!)
                Link("Privacy", destination: URL(string: "https://auctionbaby.app/privacy")!)
            }
            .font(.system(size: 11, weight: .semibold)).tint(Theme.gold)
        }
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            ProgressView().controlSize(.large).tint(Theme.gold)
        }
    }

    private func subscribe() {
        guard let product = subscriptionProduct else { return }
        Task {
            let outcome = await storeKit.purchase(product)
            if outcome == .success {
                Haptics.success()
                store.toastFlash("Welcome to \(selected.title). The floor looks different from up here.")
                dismiss()
            }
        }
    }
}
