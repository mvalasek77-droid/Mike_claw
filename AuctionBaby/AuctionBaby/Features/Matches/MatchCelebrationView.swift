import SwiftUI
import UIKit

/// Payload for the full-screen match celebration.
struct MatchCelebration: Identifiable, Equatable {
    let id = UUID()
    var otherName: String
    var otherHue: Double
    var otherPhoto: String? = nil
    var otherCopycat: Bool
    var otherCopycatStyle: CopycatStyle
    var otherVerified: Bool
    var meName: String
    var meHue: Double
    var mePhoto: String? = nil
    var amount: Int
    var masterpiece: Bool
}

/// The dopamine moment: when a bid is accepted, the gavel slams, "SOLD!" lands,
/// gold confetti rains, and the two faces meet. The auction-house answer to the
/// Tinder match screen — fully Reduce-Motion aware.
struct MatchCelebrationView: View {
    let celebration: MatchCelebration
    var onDismiss: () -> Void

    @State private var appear = false
    @State private var slam = false
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    private var headline: String {
        if celebration.otherCopycat { return "BAITED" }
        return celebration.masterpiece ? "MASTERPIECE" : "SOLD!"
    }
    private var accent: LinearGradient {
        celebration.otherCopycat ? LinearGradient(colors: [Theme.copycat, Theme.copycat],
                                                  startPoint: .top, endPoint: .bottom)
            : (celebration.masterpiece ? Theme.prestigeGradient : Theme.goldGradient)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
                .onTapGesture { dismiss() }

            if !celebration.otherCopycat && !reduceMotion {
                ConfettiView()
            }

            VStack(spacing: 20) {
                BrandMark(size: 96)
                    .rotationEffect(.degrees(slam ? 0 : -42), anchor: .bottomTrailing)
                    .scaleEffect(appear ? 1 : 0.5)
                    .opacity(appear ? 1 : 0)

                Text(headline)
                    .font(.system(size: 50, weight: .heavy, design: .serif))
                    .foregroundStyle(accent)
                    .scaleEffect(appear ? 1 : 0.4)
                    .shadow(color: Theme.gold.opacity(0.5), radius: 16)

                if celebration.otherCopycat {
                    VStack(spacing: 8) {
                        Text("\(celebration.otherName) is an AI Copycat.")
                            .font(.system(size: 16, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("You just bid on a fake — it's on your record and your Auction Credit took the hit. No Gavels were spent. Study the floor closer next time.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 26)
                } else {
                    pairing
                    amountChip
                }

                Button { dismiss() } label: {
                    Text(celebration.otherCopycat ? "Got it" : "Say hello")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 40).padding(.vertical, 15)
                        .background(Capsule().fill(celebration.otherCopycat
                                                   ? AnyShapeStyle(Color.white)
                                                   : AnyShapeStyle(Theme.goldGradient)))
                        .depth(40, strong: true)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Text("Tap anywhere to continue")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
            }
            .opacity(appear ? 1 : 0)
            .screenPadding()
        }
        .onAppear { runEntrance() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(celebration.otherCopycat
            ? "Matched with an AI copycat"
            : "Sold. Matched with \(celebration.otherName) for \(Money.compact(celebration.amount)).")
    }

    private var pairing: some View {
        HStack(spacing: -14) {
            AvatarCircle(name: celebration.meName, hue: celebration.meHue,
                         photoName: celebration.mePhoto, size: 72)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.seal.fill").opacity(0) // keep layout parity
                }
            ZStack {
                Circle().fill(Theme.roseGradient).frame(width: 38, height: 38)
                Image(systemName: "heart.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            }
            .zIndex(1)
            .scaleEffect(appear ? 1 : 0)
            AvatarCircle(name: celebration.otherName, hue: celebration.otherHue,
                         photoName: celebration.otherPhoto, size: 72,
                         copycat: celebration.otherCopycat, revealed: true,
                         copycatStyle: celebration.otherCopycatStyle)
                .overlay(alignment: .bottomTrailing) {
                    if celebration.otherVerified { VerifiedBadge(size: 18).padding(2) }
                }
        }
    }

    private var amountChip: some View {
        VStack(spacing: 3) {
            Text(celebration.masterpiece ? "MASTERPIECE BID" : "WINNING BID")
                .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.5)
                .foregroundStyle(Theme.inkFaint)
            HStack(spacing: 8) {
                Text(celebration.meName).foregroundStyle(Theme.ink)
                Text("×").foregroundStyle(Theme.inkFaint)
                Text(celebration.otherName).foregroundStyle(Theme.ink)
            }
            .font(.system(size: 15, weight: .bold, design: .serif))
            Text(Money.full(celebration.amount))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.gold)
        }
    }

    private func runEntrance() {
        if reduceMotion {
            appear = true; slam = true
            return
        }
        Motion.run(.spring(response: 0.5, dampingFraction: 0.7)) { appear = true }
        Haptics.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Motion.run(.spring(response: 0.32, dampingFraction: 0.5)) { slam = true }
            Haptics.heavy()
        }
    }

    private func dismiss() {
        Haptics.tap()
        Motion.run(.easeInOut(duration: 0.25)) { onDismiss() }
    }
}

// MARK: - Confetti

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: Double, size: Double, delay: Double, rotation: Double, duration: Double
    let color: Color
}

private struct ConfettiView: View {
    @State private var dropped = false

    private let pieces: [ConfettiPiece] = {
        let palette: [Color] = [Theme.gold, Theme.goldSoft, Theme.rose, Theme.roseSoft, Theme.verify, .white]
        return (0..<46).map { _ in
            ConfettiPiece(x: Double.random(in: 0...1),
                          size: Double.random(in: 6...12),
                          delay: Double.random(in: 0...0.5),
                          rotation: Double.random(in: -180...180),
                          duration: Double.random(in: 1.4...2.6),
                          color: palette.randomElement()!)
        }
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 1.6)
                        .rotationEffect(.degrees(dropped ? p.rotation + 420 : p.rotation))
                        .position(x: p.x * geo.size.width,
                                  y: dropped ? geo.size.height * 1.1 : -50)
                        .opacity(dropped ? 0 : 1)
                        .animation(.easeIn(duration: p.duration).delay(p.delay), value: dropped)
                }
            }
        }
        .onAppear { dropped = true }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
