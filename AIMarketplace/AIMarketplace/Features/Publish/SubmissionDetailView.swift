import SwiftUI

/// Read-only view of a title already on the bookshelf, with the AI Editor's
/// recorded verdict and a publish action if it was accepted.
struct SubmissionDetailView: View {
    let submissionID: UUID
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var revising = false
    @State private var editingDetails = false

    private var submission: Submission? {
        store.submissions.first { $0.id == submissionID }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if let sub = submission {
                    content(sub)
                } else {
                    Text("Submission not found.").foregroundStyle(Theme.inkSoft).padding(40)
                }
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle(submission?.title ?? "Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fullScreenCover(isPresented: $revising) {
                if let sub = submission {
                    SubmitWorkView(reviseFrom: sub)
                }
            }
            .sheet(isPresented: $editingDetails) {
                if let sub = submission {
                    EditLiveTitleSheet(submission: sub)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ sub: Submission) -> some View {
        VStack(spacing: 18) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: sub.draft.type.icon)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(sub.draft.type.accent)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(sub.draft.type.accent.opacity(0.18)))
                Text(sub.title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Chip(text: sub.status.rawValue,
                     systemImage: statusIcon(sub.status),
                     color: statusColor(sub.status), filled: true)
            }
            .padding(.top, 16)

            if let review = sub.review {
                VStack(spacing: 14) {
                    ScoreRing(score: review.overall, size: 140)
                    Text(review.summary)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .screenPadding()

                    GlassCard(title: "Score breakdown", icon: "list.bullet.rectangle", tint: Theme.kdp) {
                        VStack(spacing: 12) {
                            ForEach(review.criteria) { c in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(c.name).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text("\(c.score)").font(.system(size: 13, weight: .heavy, design: .rounded))
                                            .foregroundStyle(c.score >= AIReviewResult.threshold ? Theme.success : Theme.warning)
                                    }
                                    ScoreBar(score: c.score)
                                }
                            }
                        }
                    }
                    .screenPadding()

                    if !review.improvements.isEmpty {
                        GlassCard(title: "To reach the bar", icon: "wrench.and.screwdriver.fill", tint: Theme.warning) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(review.improvements, id: \.self) { note in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.warning).padding(.top, 2)
                                        Text(note).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink.opacity(0.9))
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                        .screenPadding()
                    }

                    actionArea(sub, review: review)
                }
            } else {
                // No verdict yet — either still in flight or interrupted.
                // The "still being reviewed" copy without any action used
                // to be a dead-end. Now: explicit "Re-run review" button
                // that re-fires the analysis against the same submission.
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.accent)
                        Text("Review not finished yet.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Text("If you closed the app while the editor was working, the review didn't complete. Tap below to re-run it.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Re-run the review", systemImage: "arrow.clockwise") {
                        Task { _ = await store.runReviewAsync(for: sub.id) }
                    }
                }
                .padding(24)
            }
        }
        .padding(.bottom, 40)
    }

    @ViewBuilder
    private func actionArea(_ sub: Submission, review: AIReviewResult) -> some View {
        VStack(spacing: 10) {
            if review.passed {
                if sub.publishedItemID != nil {
                    Chip(text: "Published to marketplace", systemImage: "checkmark.seal.fill", color: Theme.success, filled: true)
                    PrimaryButton(title: "Edit details", systemImage: "slider.horizontal.3", style: .ghost) {
                        editingDetails = true
                    }
                    Text("Price, genre and synopsis go live immediately. Content changes need a new submission so the AI Editor can re-vet the file.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                        .multilineTextAlignment(.center)
                } else {
                    PrimaryButton(title: "Publish to Marketplace", systemImage: "tray.and.arrow.up.fill", tint: Theme.success) {
                        store.publish(submissionID: sub.id)
                    }
                    PrimaryButton(title: "Revise & resubmit", systemImage: "pencil", style: .ghost) {
                        revising = true
                    }
                }
            } else {
                PrimaryButton(title: "Revise & resubmit", systemImage: "pencil", tint: Theme.kdp) {
                    revising = true
                }
                Text("The wizard reopens pre-filled with this draft — fix what the Editor flagged and run the review again.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.center)
            }
        }
        .screenPadding()
    }

    private func statusIcon(_ s: SubmissionStatus) -> String {
        switch s {
        case .accepted: return "checkmark.seal.fill"
        case .rejected: return "exclamationmark.triangle.fill"
        case .reviewing: return "hourglass"
        case .draft: return "doc"
        }
    }

    private func statusColor(_ s: SubmissionStatus) -> Color {
        switch s {
        case .accepted: return Theme.success
        case .rejected: return Theme.warning
        case .reviewing: return Theme.accent
        case .draft: return Theme.inkFaint
        }
    }
}

/// Creator-side metadata editor for a LIVE title. Price, genre and synopsis
/// mirror straight into the storefront; content changes go through
/// Revise & resubmit so the AI Editor re-vets the file.
private struct EditLiveTitleSheet: View {
    let submission: Submission
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var price: Double
    @State private var genre: String
    @State private var synopsis: String

    init(submission: Submission) {
        self.submission = submission
        _price = State(initialValue: submission.draft.price)
        _genre = State(initialValue: submission.draft.genre)
        _synopsis = State(initialValue: submission.draft.synopsis)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Changes go live in the store immediately. Buyers who already own this title keep it at the price they paid.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("List price")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                            Spacer()
                            Text(String(format: "$%.2f", price))
                                .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        }
                        Slider(value: $price, in: 0.99...19.99, step: 0.50).tint(Theme.kdp)
                            .accessibilityLabel("List price")
                            .accessibilityValue(String(format: "$%.2f", price))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Genre").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        TextField("e.g. Sci-Fi, Lo-Fi, Thriller", text: $genre)
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Synopsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        TextEditor(text: $synopsis)
                            .frame(minHeight: 110).padding(8).scrollContentBackground(.hidden)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                            .foregroundStyle(Theme.ink).font(.system(size: 14))
                            .accessibilityLabel("Synopsis")
                    }

                    PrimaryButton(title: "Save changes", systemImage: "checkmark", tint: Theme.kdp) {
                        store.updateLiveTitle(submissionID: submission.id,
                                              price: price, synopsis: synopsis, genre: genre)
                        Haptics.success()
                        dismiss()
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.kdp).ignoresSafeArea())
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
