import SwiftUI

@main
struct AuctionBabyApp: App {
    @StateObject private var store = AuctionStore()
    @StateObject private var storeKit = StoreKitService()
    // Payout-Worker client — owned at app root so the admin console and any
    // payout screens share one configuration.
    @StateObject private var backend = BackendService()
    // Slice 1 of the spine: Sign in with Apple → server user identity. Owned
    // at app root so onboarding, settings, and every later slice observe the
    // same auth state. Falls back to no-op when AB_AUTH_URL isn't configured.
    @StateObject private var auth = AuthService()
    // Slice 2: push notifications. Singleton because AppDelegate needs a
    // stable reference before SwiftUI @StateObject wiring has run.
    @StateObject private var push = PushService.shared
    // Slice 3: real (server-owned) verification. Coordinates with AuthService
    // — the blue check flips when the server reports verifiedAt is present.
    @StateObject private var verification = VerificationService()
    // Slice 4: the matching backend (real bids/matches/messages between two
    // signed-in users). Wired at app root; UI migration is 4b+ (today the
    // on-device sim is still what the screens read from).
    @StateObject private var matching = MatchingService()
    // Slice 4b0: syncs the local Profile to the server-side public profile
    // so OTHER users' floor feeds can see it. Register + updateProfile
    // trigger uploads when signed in; local-only sessions are untouched.
    @StateObject private var profileSync = ProfileService()
    /// Minimal UIKit AppDelegate — the only way to receive APNs device tokens
    /// in a SwiftUI app. Its sole job is to forward the token to PushService.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(storeKit)
                .environmentObject(backend)
                .environmentObject(auth)
                .environmentObject(push)
                .environmentObject(verification)
                .environmentObject(matching)
                .environmentObject(profileSync)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .task {
                    // Sign-out → un-register the APNs device token, so a
                    // signed-out user never keeps receiving pushes on their
                    // still-installed app.
                    auth.onSignedOut = { [weak push] in await push?.onSignedOut() }
                    // Server flipped verified_at (via webhook / admin / push)
                    // → flip the local blue check to match, in one place.
                    auth.onVerified = { [weak store] in store?.verifyMe() }
                    // Slice 4b0: any profile mutation → mirror it to the
                    // server so OTHER users' floors see the change. Demo Mode
                    // is skipped (no real account), and local-only sessions
                    // are a silent no-op inside ProfileService.
                    store.onProfileChanged = { [weak profileSync, weak store] profile in
                        guard let store, !store.demoMode else { return }
                        Task { _ = await profileSync?.uploadMyProfile(from: profile) }
                    }
                    storeKit.onCredit = { [weak store] gavels in store?.creditGavels(gavels) }
                    storeKit.onRevoke = { [weak store] gavels in store?.revokeGavels(gavels) }
                    storeKit.onBoost = { [weak store] in store?.activateBoost() }
                    storeKit.onStatusPurchased = { [weak store] tier in store?.equipArchetype(tier) }
                    storeKit.onStatusRevoked = { [weak store, weak storeKit] tier in
                        store?.revokeArchetype(tier) { storeKit?.owns($0) ?? false }
                    }
                    storeKit.demoOwnsAllStatus = store.demoMode
                    store.ownsArchetype = { [weak storeKit] tier in storeKit?.owns(tier) ?? false }
                    await storeKit.loadProducts()
                    let tier = storeKit.activeTier
                    store.autoRebidEnabled = tier == .reserve || tier == .blackcard
                    store.priorityPlacementEnabled = tier == .blackcard
                    await store.refreshPendingRefunds(storeKit: storeKit, backend: backend)
                    // Quiet server-identity ping — proves the stored session
                    // is still valid; drops it locally on 401 so we never
                    // present a phantom signed-in state after a secret rotate.
                    if auth.isSignedIn { await auth.refreshMe() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await store.refreshPendingRefunds(storeKit: storeKit, backend: backend) }
                        if auth.isSignedIn { Task { await auth.refreshMe() } }
                    }
                }
                .onChange(of: storeKit.activeTier) { _, tier in
                    store.autoRebidEnabled = tier == .reserve || tier == .blackcard
                    store.priorityPlacementEnabled = tier == .blackcard
                }
                .onChange(of: store.demoMode) { _, isDemo in
                    storeKit.demoOwnsAllStatus = isDemo
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
