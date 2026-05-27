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

    @EnvironmentObject private var ledger: AICoinLedger

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
        .onAppear { store.attachEnergy(ledger) }
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

/// The marketplace mark — a play symbol on a silicon chip (media × AI).
struct BrandMark: View {
    var size: CGFloat = 56

    private var body_: CGFloat { size * 0.70 }
    private var corner: CGFloat { size * 0.22 }

    var body: some View {
        ZStack {
            chipPins
            // Chip body
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.07)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: body_, height: body_)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.65), lineWidth: max(1, size * 0.012))
                )
            // Inner die outline (circuit feel)
            RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                .frame(width: body_ * 0.66, height: body_ * 0.66)
            // Play symbol
            PlayTriangle()
                .fill(Theme.brandGradient)
                .frame(width: size * 0.26, height: size * 0.30)
                .offset(x: size * 0.03)
                .shadow(color: Theme.accent.opacity(0.6), radius: size * 0.06)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: size * 0.12, y: size * 0.06)
    }

    private var chipPins: some View {
        let len = size * 0.11
        let thick = size * 0.05
        let step = size * 0.18
        let half = body_ / 2
        return ZStack {
            ForEach([-1, 0, 1], id: \.self) { i in
                let o = CGFloat(i) * step
                Capsule().fill(Theme.accent).frame(width: len, height: thick).offset(x: -half, y: o)
                Capsule().fill(Theme.accent).frame(width: len, height: thick).offset(x: half, y: o)
                Capsule().fill(Theme.accent).frame(width: thick, height: len).offset(x: o, y: -half)
                Capsule().fill(Theme.accent).frame(width: thick, height: len).offset(x: o, y: half)
            }
        }
    }
}

/// A right-pointing play triangle.
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
