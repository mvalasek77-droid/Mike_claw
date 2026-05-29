import SwiftUI

/// The AI Editor's verdict: overall score against the 85% bar, the per-criterion
/// breakdown, strengths, required improvements, and the path forward (publish if
/// accepted, revise if not).
struct ReviewVerdictView: View {
    let draft: DraftWork
    let result: AIReviewResult
    let submissionID: UUID
    var autoPublished: Bool = false
    var onReviseAgain: () -> Void
    var onClose: () -> Void

    @EnvironmentObject private var store: MarketplaceStore
    @State private var published = false

    private var isLive: Bool { published || autoPublished }

    var body: some View {
        ZStack {
            AppBackground(glow: result.passed ? Theme.success : Theme.warning).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    verdictHeader
                    autonomyCard
                    if isLive {
                        publishedBanner
                    }
                    contentSignals
                    breakdown
                    if !result.strengths.isEmpty { strengthsCard }
                    if !result.improvements.isEmpty { improvementsCard }
                    actions
                }
                .padding(.top, 30)
                .padding(.bottom, 40)
                .screenPadding()
            }
        }
    }

    private var verdictHeader: some View {
        VStack(spacing: 14) {
            ScoreRing(score: result.overall, size: 158)
            Text(result.passed ? "Accepted" : "Below the bar")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(result.passed ? Theme.success : Theme.warning)
            Chip(text: result.passed ? "Clears 85% commercial bar" : "85% commercial bar not met",
                 systemImage: result.passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                 color: result.passed ? Theme.success : Theme.warning)
            Text(result.summary)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    private var publishedBanner: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(autoPublished ? "Published by AI Autopilot" : "Live on the marketplace")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("\(draft.title) is now available to buy and \(draft.type.verb.lowercased()).")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
        }
        .transition(.scale.combined(with: .opacity))
    }

    /// The AI Editor's own confidence and its autonomous publish decision.
    @ViewBuilder private var autonomyCard: some View {
        let confident = result.aiChoosesToPublish
        GlassCard(title: "AI Editor decision", icon: "sparkles", tint: confident ? Theme.success : Theme.kdp) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Self-confidence")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Text("\(result.confidence)%")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(confident ? Theme.success : Theme.kdp)
                }
                ScoreBar(score: result.confidence, threshold: AIReviewResult.autoPublishConfidence)
                Text(result.autonomousRationale)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink.opacity(0.9))
                if result.passed, !autoPublished, confident, !store.aiAutopilotEnabled {
                    Text("Turn on AI Autopilot in the Review step to let it publish titles like this without you.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
    }

    /// Three honest sub-scores the Editor publishes alongside the overall:
    /// Content (read from real bytes), Originality (vs catalogue) and
    /// Copyright risk (famous-IP names, lorem-ipsum, missing attestation).
    private var contentSignals: some View {
        GlassCard(title: "What the Editor measured", icon: "waveform.path", tint: Theme.kdp) {
            VStack(alignment: .leading, spacing: 12) {
                signalRow(label: "Content quality",
                          value: "\(result.contentQuality)/100",
                          subtitle: "From actual file bytes (text, audio or video).",
                          score: result.contentQuality,
                          ok: result.contentQuality >= AIReviewResult.autoPublishContentFloor)
                signalRow(label: "Catalogue similarity",
                          value: "\(Int((result.copycatSimilarity * 100).rounded()))%",
                          subtitle: result.copycatNeighbour.isEmpty
                              ? "Distinct from everything published."
                              : "Closest: “\(result.copycatNeighbour)”.",
                          score: 100 - Int((result.copycatSimilarity * 100).rounded()),
                          ok: result.copycatSimilarity <= AIReviewResult.autoPublishCopycatCeiling)
                signalRow(label: "Copyright risk",
                          value: "\(result.copyrightRisk)/100",
                          subtitle: result.copyrightRisk == 0
                              ? "Clean — no flagged terms."
                              : "Higher = more risk; combines IP names, filler text and attestation.",
                          score: 100 - result.copyrightRisk,
                          ok: result.copyrightRisk <= AIReviewResult.autoPublishCopyrightCeiling)
            }
        }
    }

    private func signalRow(label: String, value: String, subtitle: String, score: Int, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(ok ? Theme.success : Theme.warning)
            }
            ScoreBar(score: max(0, min(100, score)))
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
        }
    }

    private var breakdown: some View {
        GlassCard(title: "Score breakdown", icon: "list.bullet.rectangle", tint: Theme.kdp) {
            VStack(spacing: 12) {
                ForEach(result.criteria) { c in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(c.name).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(c.score)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(c.score >= AIReviewResult.threshold ? Theme.success : Theme.warning)
                        }
                        ScoreBar(score: c.score)
                    }
                }
            }
        }
    }

    private var strengthsCard: some View {
        GlassCard(title: "Strengths", icon: "hand.thumbsup.fill", tint: Theme.success) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(result.strengths, id: \.self) { bulletRow($0, color: Theme.success, icon: "checkmark") }
            }
        }
    }

    private var improvementsCard: some View {
        GlassCard(title: "To reach the bar", icon: "wrench.and.screwdriver.fill", tint: Theme.warning) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(result.improvements, id: \.self) { bulletRow($0, color: Theme.warning, icon: "arrow.up.right") }
            }
        }
    }

    private func bulletRow(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color).padding(.top, 2)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink.opacity(0.9))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if result.passed {
                if isLive {
                    PrimaryButton(title: "Done", systemImage: "checkmark", style: .light) { onClose() }
                } else {
                    PrimaryButton(title: "Publish to Marketplace", systemImage: "tray.and.arrow.up.fill",
                                  tint: Theme.success) {
                        store.publish(submissionID: submissionID)
                        Motion.run(.spring(response: 0.4)) { published = true }
                    }
                    PrimaryButton(title: "Save to bookshelf", style: .ghost) { onClose() }
                }
            } else {
                PrimaryButton(title: "Revise & resubmit", systemImage: "arrow.uturn.left",
                              tint: Theme.kdp) { onReviseAgain() }
                PrimaryButton(title: "Save to bookshelf", style: .ghost) { onClose() }
            }
        }
    }
}

struct ScoreBar: View {
    let score: Int
    var threshold: Int = AIReviewResult.threshold

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10)).frame(height: 7)
                Capsule()
                    .fill(score >= threshold ? Theme.success : Theme.warning)
                    .frame(width: max(0, geo.size.width * CGFloat(score) / 100), height: 7)
                // 85% bar marker
                Rectangle().fill(.white.opacity(0.7))
                    .frame(width: 1.5, height: 12)
                    .offset(x: geo.size.width * CGFloat(threshold) / 100)
            }
        }
        .frame(height: 12)
    }
}
