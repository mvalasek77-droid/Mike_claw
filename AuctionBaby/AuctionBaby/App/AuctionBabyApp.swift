import SwiftUI

@main
struct AuctionBabyApp: App {
    @StateObject private var store = AuctionStore()
    @StateObject private var storeKit = StoreKitService()
    // Payout-Worker client — owned at app root so the admin console and any
    // payout screens share one configuration.
    @StateObject private var backend = BackendService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(storeKit)
                .environmentObject(backend)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .task {
                    storeKit.onCredit = { [weak store] gavels in store?.creditGavels(gavels) }
                    storeKit.onRevoke = { [weak store] gavels in store?.revokeGavels(gavels) }
                    storeKit.onBoost = { [weak store] in store?.activateBoost() }
                    await storeKit.loadProducts()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await store.refreshPendingRefunds(storeKit: storeKit) }
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var showSplash = true

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()

            Group {
                if showSplash {
                    SplashView { Motion.run(.easeInOut(duration: 0.45)) { showSplash = false } }
                        .transition(.opacity)
                } else if !store.isRegistered {
                    OnboardingView()
                        .transition(.opacity)
                } else {
                    MainTabView()
                        .transition(.opacity)
                }
            }

            // Global toast overlay.
            if let toast = store.toast {
                VStack {
                    ToastView(text: toast).padding(.top, 8)
                    Spacer()
                }
                .zIndex(10)
                .allowsHitTesting(false)
            }

            // Full-screen "SOLD!" match celebration.
            if let celebration = store.celebration {
                MatchCelebrationView(celebration: celebration) { store.celebration = nil }
                    .zIndex(20)
                    .transition(.opacity)
            }
        }
        .motion(.easeInOut(duration: 0.3), value: store.celebration)
        .motion(.easeInOut(duration: 0.45), value: showSplash)
        .motion(.easeInOut(duration: 0.45), value: store.isRegistered)
        .motion(Motion.snap, value: store.toast)
    }
}

/// Brief branded splash with the gavel-heart mark and slogan.
struct SplashView: View {
    var onDone: () -> Void
    @State private var appear = false
    @State private var strike = false

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            VStack(spacing: 18) {
                BrandMark(size: 108)
                    .scaleEffect(appear ? 1 : 0.7)
                    .rotationEffect(.degrees(strike ? 0 : -14), anchor: .bottomTrailing)
                    .opacity(appear ? 1 : 0)

                Wordmark(size: 34)
                    .opacity(appear ? 1 : 0)

                Text("Find a high value man,\nfind out what you're worth.")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.inkSoft)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            Motion.run(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true }
            Motion.run(.spring(response: 0.4, dampingFraction: 0.5).delay(0.3)) { strike = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { onDone() }
        }
    }
}
