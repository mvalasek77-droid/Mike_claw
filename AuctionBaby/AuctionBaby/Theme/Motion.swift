import SwiftUI
import UIKit

/// Animation curves and a light haptics layer, all Reduce-Motion aware via
/// ``Motion/run(_:_:)`` so the app honours accessibility settings everywhere.
enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snap   = Animation.spring(response: 0.26, dampingFraction: 0.86)
    static let bouncy = Animation.spring(response: 0.50, dampingFraction: 0.62)
    static let smooth = Animation.easeInOut(duration: 0.45)
    /// Fluid, slightly over-damped — the iOS 26 Liquid Glass feel.
    static let liquid = Animation.spring(response: 0.52, dampingFraction: 0.68)

    static func run(_ animation: Animation, _ body: () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t, body)
        } else {
            withAnimation(animation, body)
        }
    }
}

/// Adaptive haptics. Centralised so every tap/commit/win uses a consistent,
/// tasteful feedback vocabulary — and so we can mute it in one place.
enum Haptics {
    static func tap() { impact(.light) }
    static func commit() { impact(.medium) }
    static func heavy() { impact(.heavy) }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    static func selection() {
        let g = UISelectionFeedbackGenerator()
        g.prepare(); g.selectionChanged()
    }

    /// Two-beat haptic for the highest-stakes action in the app: sending a bid.
    /// Heavy tap signals "it's live", soft follow-up tap settles the feeling.
    static func bidPlaced() {
        impact(.heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { impact(.light) }
    }
    /// Accepting a bid — a moment of genuine human connection.
    static func accept() { notify(.success) }
    /// Declining or passing — soft so it doesn't feel punitive.
    static func decline() { impact(.light) }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare(); g.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let g = UINotificationFeedbackGenerator()
        g.prepare(); g.notificationOccurred(type)
    }
}

/// Press-scale `ButtonStyle` for NavigationLink-wrapped cards. Gives every
/// tappable card a physical "push" feel without fighting `.buttonStyle(.plain)`.
struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(
                UIAccessibility.isReduceMotionEnabled ? nil : Motion.snap,
                value: configuration.isPressed
            )
    }
}

extension View {
    @ViewBuilder
    func motion(_ animation: Animation, value: some Equatable) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self
        } else {
            self.animation(animation, value: value)
        }
    }

    /// Entrance: content rises and fades in on first appearance. Staggering
    /// the `delay` per row gives lists a lively, orchestrated arrival.
    func riseIn(_ delay: Double = 0) -> some View { modifier(RiseIn(delay: delay)) }

    /// Sweeping highlight shimmer — shown while async content is loading.
    /// Automatically suppressed when Reduce Motion is on.
    func shimmer(_ active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

struct RiseIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .onAppear {
                guard !shown else { return }
                Motion.run(Motion.spring.delay(delay)) { shown = true }
            }
    }
}

/// Left-to-right sweep shimmer for loading placeholders (avatar photos,
/// skeleton cards). Uses a diagonal gradient so it reads as light, not glitch.
struct ShimmerModifier: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content.overlay(alignment: .center) {
            if active, !UIAccessibility.isReduceMotionEnabled {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.20), location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 2.5)
                    .offset(x: -geo.size.width + phase * geo.size.width * 2.5)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
                .clipped()
                .onAppear {
                    phase = 0
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
        }
    }
}
