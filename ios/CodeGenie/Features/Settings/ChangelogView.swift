import SwiftUI

/// "What's new" sheet. Renders a hand-curated list of release notes
/// so users see what got better between updates.
///
/// We deliberately hand-curate rather than auto-pulling from git so
/// the user-facing copy stays terse and useful. Engineering churn
/// (refactors, dependency bumps, test additions) lives in the git log;
/// this list is reserved for things a user can feel.
struct ChangelogView: View {
    private let entries: [ChangelogEntry] = [
        .init(
            version: "0.1.0",
            date: "May 2026",
            highlights: [
                "First public branch. Liquid Glass theme, 7-step cartoon tutorial, BitDrop game, build screen with live transcript, App Store Connect walkthrough.",
                "Settings: LLM cost comparison, BYOK API keys, subscription pairing, hosted credits, per-agent model routing.",
                "Pair-your-Mac flow with Bonjour discovery + QR code scanner.",
                "Apple Developer onboarding (Team ID + ASC API key or Apple ID + app-specific password) — Keychain-stored.",
                "Submit-to-App-Store from the build's success screen now actually uploads + polls TestFlight processing status.",
                "Download workspace as a zip from any green build.",
                "On-device telemetry (opt-in) tracking success rate, average retries, average time-to-green.",
            ]
        )
    ]

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    ForEach(entries) { entry in entryCard(entry) }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                CodeGenieLogo(size: 40, animate: false)
                Text("What's new")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            Text("Notable changes between versions.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryCard(_ entry: ChangelogEntry) -> some View {
        GlassCard(title: "v\(entry.version)", icon: "sparkles", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.date)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .accessibilityHidden(true)
                ForEach(entry.highlights, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(LiquidGlass.accentSecondary.opacity(0.6))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct ChangelogEntry: Identifiable, Hashable {
    let version: String
    let date: String
    let highlights: [String]
    var id: String { version }
}

#Preview { ChangelogView() }
