import SwiftUI
import UIKit

/// The pill that advertises a man's purchased ``Archetype``. Trillionaire gets
/// the animated prestige shimmer; everyone else gets a flat tinted capsule.
struct ArchetypeBadge: View {
    let archetype: Archetype
    var compact: Bool = false

    @State private var shimmer = false

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
                Image(systemName: archetype.systemImage)
                Text(archetype.title)
            }
            .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
            .foregroundStyle(archetype.usesPrestigeStyle ? .black : archetype.tint)
            .padding(.horizontal, compact ? 8 : 11).padding(.vertical, compact ? 4 : 6)
            .background(
                Group {
                    if archetype.usesPrestigeStyle {
                        Capsule().fill(Theme.prestigeGradient)
                            .hueRotation(.degrees(shimmer ? 18 : -18))
                    } else {
                        Capsule().fill(archetype.tint.opacity(0.18))
                    }
                }
            )
            .overlay(Capsule().strokeBorder(archetype.tint.opacity(0.6), lineWidth: 0.8))
            .shadow(color: archetype.tint.opacity(archetype.usesPrestigeStyle ? 0.6 : 0), radius: 8)
            .onAppear {
                guard archetype.usesPrestigeStyle, !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { shimmer = true }
            }
        }
    }
}

/// The rarest object on the floor: a woman's "Masterpiece" — only mintable by a
/// Trillionaire who actually pays $1,000,000 for a date.
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

/// "Copycat" warning flag — an AI-generated lure profile.
struct CopycatTag: View {
    var compact: Bool = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
            Text(compact ? "AI" : "Copycat · AI")
        }
        .font(.system(size: compact ? 10 : 12, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 3 : 5)
        .background(Capsule().fill(Theme.copycat.opacity(0.9)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.6))
        .accessibilityLabel("Copycat, AI-generated profile")
    }
}
