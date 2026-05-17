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
            version: "0.2.0",
            date: "May 2026",
            highlights: [
                "First-timer walkthroughs for Xcode, Apple Developer ($99/yr explained), App Store Connect, GitHub, and the TestFlight vs App Store choice — no prior knowledge assumed.",
                "Terms & Privacy gate after onboarding with a plain-English costs card up front (CodeGenie tiers, Apple $99/yr, App Store cut, GitHub free).",
                "Onboarding now has a dedicated pricing slide (Step 7 of 8) so you see costs before the legal gate.",
                "Live cost meter strip in the build screen — running USD spend vs cap, tone shifts green/amber/red.",
                "Build cost cap defaults to $5 on first launch — no more surprise bills.",
                "Pre-build confirmation sheet shows estimated cost, model, and current cap before the build starts.",
                "80%-of-cap warning fires before the build halts, so you can lift the cap deliberately.",
                "Build failure overlay with last 5 log lines, Try again, and Resume from checkpoint.",
                "Submit flow now opens a TestFlight vs App Store explainer once per device.",
                "Back up to GitHub button on the success screen — pushes to your default repo with the Keychain-stored PAT.",
                "Ship readiness card on Home tracks your four setup gates (Xcode / Mac / Apple / GitHub) and auto-hides at 4/4.",
                "Bug report sheet now submits privately to the backend (with diagnostics), with the email path kept as a fallback.",
                "PairMacView prereq card with a clear Companion download link.",
                "App Store Connect guide steps each tagged Auto / Hybrid / You so you know who's actually doing the work.",
                "Jargon explainer sheets for Pipeline / BitDrop / Perfection Mode — tap What's this? on any card.",
                "Accessibility: section headers flagged for VoiceOver, all CTAs have hints, decorative icons hidden, cards become contain-children elements.",
                "Backend: bug-report endpoint with persistence + 3 tests, github sync, release readiness audit (13 ship gates), bounded SSE queues.",
                "QA: docs/AGENT_QA_PROTOCOL.md + docs/qa/PAGE_PROCESS_MATRIX.md baseline (99 rows) so every release ships with evidence.",
            ]
        ),
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
                    .foregroundStyle(LiquidGlass.primaryText)
                Spacer()
            }
            Text("Notable changes between versions.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryCard(_ entry: ChangelogEntry) -> some View {
        GlassCard(title: "v\(entry.version)", icon: "sparkles", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.date)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
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
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
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
