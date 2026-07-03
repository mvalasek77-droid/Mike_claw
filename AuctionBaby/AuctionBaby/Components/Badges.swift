import SwiftUI
import UIKit

/// The pill that advertises a man's purchased ``Archetype``. A *verified*
/// Trillionaire gets the animated prestige shimmer; a Trillionaire still
/// awaiting his confirmed $9,999 date reads as muted "Pending"; everyone else
/// gets a flat tinted capsule.
struct ArchetypeBadge: View {
    let archetype: Archetype
    var compact: Bool = false
    /// True when the man bought Trillionaire but hasn't been confirmed yet.
    var pending: Bool = false

    @State private var shimmer = false

    /// Prestige shimmer only for a *verified* Trillionaire.
    private var showsPrestige: Bool { archetype.usesPrestigeStyle && !pending }

    var body: some View {
        if archetype == .none {
            HStack(spacing: 5) {
                Image(systemName: archetype.systemImage)
                Text(compact ? "Unrated" : "No Rating")
            }
            .font(.system(size: compact ? 10 : 12, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, compact ? 8 : 11).padding(.vertical, compact ? 4 : 6)
            .background(Capsule().fill(.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.6))
        } else {
            HStack(spacing: 5) {
                Image(systemName: pending && archetype.usesPrestigeStyle ? "hourglass" : archetype.systemImage)
                Text(label)
                if showsPrestige { Image(systemName: "checkmark.seal.fill").font(.system(size: compact ? 8 : 10)) }
            }
            .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
            .foregroundStyle(showsPrestige ? .black : (pending && archetype.usesPrestigeStyle ? Theme.warning : archetype.tint))
            .padding(.horizontal, compact ? 8 : 11).padding(.vertical, compact ? 4 : 6)
            .background(
                Group {
                    if showsPrestige {
                        Capsule().fill(Theme.prestigeGradient)
                            .hueRotation(.degrees(shimmer ? 18 : -18))
                    } else if pending && archetype.usesPrestigeStyle {
                        Capsule().fill(Theme.warning.opacity(0.15))
                    } else {
                        Capsule().fill(archetype.tint.opacity(0.18))
                    }
                }
            )
            .overlay(Capsule().strokeBorder((pending && archetype.usesPrestigeStyle ? Theme.warning : archetype.tint).opacity(0.6),
                                            lineWidth: 0.8))
            .shadow(color: archetype.tint.opacity(showsPrestige ? 0.6 : 0), radius: 8)
            .onAppear {
                guard showsPrestige, !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { shimmer = true }
            }
        }
    }

    private var label: String {
        if pending && archetype.usesPrestigeStyle { return compact ? "Pending" : "Trillionaire · Pending" }
        return archetype.title
    }
}

/// The rarest object on the floor: a woman's "Masterpiece" — only mintable by a
/// Trillionaire who pays the full $1,000,000 on a date that she then confirms.
struct MasterpieceBadge: View {
    var compact: Bool = false
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "rosette")
            Text(compact ? "Masterpiece" : "Masterpiece")
        }
        .font(.system(size: compact ? 10 : 13, weight: .heavy, design: .serif))
        .foregroundStyle(.black)
        .padding(.horizontal, compact ? 9 : 13).padding(.vertical, compact ? 4 : 7)
        .background(Capsule().fill(Theme.prestigeGradient).hueRotation(.degrees(shimmer ? 22 : -22)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: Theme.gold.opacity(0.6), radius: 10)
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { shimmer = true }
        }
        .accessibilityLabel("Masterpiece rating")
    }
}

/// The lot's honors-ladder chip — her artwork tier, from Fresh Canvas up to
/// Exhibition Star. (The Masterpiece keeps its own prestige badge.)
struct ArtTierBadge: View {
    let tier: ArtTier
    var compact: Bool = false

    var body: some View {
        if tier == .masterpiece {
            MasterpieceBadge(compact: compact)
        } else {
            HStack(spacing: 5) {
                Image(systemName: tier.systemImage)
                Text(tier.title)
            }
            .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .serif))
            .foregroundStyle(tier.tint)
            .padding(.horizontal, compact ? 8 : 11).padding(.vertical, compact ? 4 : 6)
            .background(Capsule().fill(tier.tint.opacity(0.15)))
            .overlay(Capsule().strokeBorder(tier.tint.opacity(0.5), lineWidth: 0.7))
            .accessibilityLabel("Honors tier: \(tier.title)")
        }
    }
}

/// Compact "deadbeat" indicator — did this bidder actually pay what he bid?
/// High = reliable spender; low = bid big, paid small.
struct DeadbeatTag: View {
    let score: Int   // 0–100, 100 = always pays in full
    var compact: Bool = false

    private var tint: Color {
        switch score {
        case 80...: return Theme.success
        case 50..<80: return Theme.warning
        default: return Theme.danger
        }
    }
    private var word: String {
        switch score {
        case 90...: return "Pays in Full"
        case 70..<90: return "Reliable"
        case 40..<70: return "Flaky"
        default: return "Deadbeat"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: score >= 70 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            Text(compact ? "\(score)" : "\(word) · \(score)")
        }
        .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 3 : 5)
        .background(Capsule().fill(tint.opacity(0.16)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 0.6))
        .accessibilityLabel("Deadbeat score \(score) out of 100, \(word)")
    }
}

/// The identity-verified check seal. The premium trust signal — a verified
/// human, never a copycat.
struct VerifiedBadge: View {
    var size: CGFloat = 15
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Theme.verify)
            .shadow(color: Theme.verify.opacity(0.5), radius: 3)
            .accessibilityLabel("Verified")
    }
}

/// "Copycat" warning flag — an AI-generated lure profile. Gently pulses to read
/// as "synthetic / live", and holds still under Reduce Motion.
struct CopycatTag: View {
    var compact: Bool = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .opacity(pulse ? 1 : 0.55)
                .scaleEffect(pulse ? 1.0 : 0.86)
            Text(compact ? "AI" : "Copycat · AI")
        }
        .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 3 : 5)
        .background(Capsule().fill(Theme.copycat.opacity(0.9)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.6))
        .shadow(color: Theme.copycat.opacity(pulse ? 0.6 : 0.2), radius: pulse ? 8 : 3)
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else { pulse = true; return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel("Copycat, AI-generated profile")
    }
}
