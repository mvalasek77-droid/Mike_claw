import SwiftUI
import Foundation

@main
struct AIMarketplaceApp: App {
    @StateObject private var store = MarketplaceStore()
    @StateObject private var ledger = AICoinLedger()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(ledger)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var showSplash = true

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()

            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.4)) { showSplash = false } }
                    .transition(.opacity)
            } else if !store.isRegistered {
                RegisterView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .motion(.easeInOut(duration: 0.4), value: showSplash)
        .motion(.easeInOut(duration: 0.4), value: store.isRegistered)
    }
}

/// Brief branded splash.
struct SplashView: View {
    var onDone: () -> Void
    @State private var appear = false

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                BrandMark(size: 76)
                    .scaleEffect(appear ? 1 : 0.8)
                    .opacity(appear ? 1 : 0)
                Text("AI MARKETPLACE")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Theme.ink)
                    .opacity(appear ? 1 : 0)
                Text("Where machine-made stories go to sell out.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onDone() }
        }
    }
}

/// The marketplace mark — a play/page hybrid inside a rounded badge.
struct BrandMark: View {
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.brandGradient)
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.5), radius: size * 0.2, y: size * 0.08)
    }
}
