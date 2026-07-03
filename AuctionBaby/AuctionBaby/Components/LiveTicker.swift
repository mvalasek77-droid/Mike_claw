import SwiftUI
import UIKit

/// The heartbeat of the floor: a one-line live feed of (simulated) auction
/// activity — bids landing, lots getting watched, accepts closing — rotating
/// every few seconds with a pulsing LIVE dot. Pure ambience, zero data cost,
/// and the single biggest "this place is alive" signal in the app.
struct LiveTicker: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var index = 0
    @State private var pulse = false

    private let timer = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Fabricated-but-plausible floor activity, rebuilt from whoever is
    /// actually on the floor so names always match what the user sees.
    private var lines: [String] {
        let women = store.floor.map(\.name)
        let men = ["Julian W.", "Marcus B.", "Sam O.", "Dominic V.", "Aaron K.", "Leo M."]
        guard !women.isEmpty else { return ["The floor opens soon."] }
        var out: [String] = []
        for (i, w) in women.enumerated() {
            let m = men[i % men.count]
            let amount = 120 + (i * 173 % 900)
            switch i % 4 {
            case 0: out.append("\(m) just bid \(Money.compact(amount)) on \(w)")
            case 1: out.append("\(2 + i % 6) bidders are watching \(w)")
            case 2: out.append("\(w) accepted a \(Money.compact(amount + 150)) bid")
            default: out.append("\(m) was outbid on \(w) — rebid incoming")
            }
        }
        return out
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(Theme.danger).frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.25 : 0.8)
                    .opacity(pulse ? 1 : 0.55)
                Text("LIVE").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(Theme.danger)
            }
            Text(lines[index % max(lines.count, 1)])
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
                .id(index)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.6))
        .clipped()
        .onReceive(timer) { _ in
            guard !reduceMotion else { index += 1; return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { index += 1 }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel("Live floor activity")
    }
}
