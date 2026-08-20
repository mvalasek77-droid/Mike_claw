import SwiftUI

struct FeaturedCritics: View {
    @EnvironmentObject var social: SocialService
    @ObservedObject var moderation = ModerationService.shared
    @State private var expanded: Review?

    var spotlight: [Review] { moderation.filter(reviews: social.spotlightedReviews()) }
    var winner: Review? { spotlight.first }
    var supporting: [Review] { Array(spotlight.dropFirst()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let winner {
                WinnerReviewCard(review: winner, rank: 1)
                    .onTapGesture { expanded = winner }
            } else {
                Text("No reviews yet — top-5 traders' reviews will appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !supporting.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(supporting.enumerated()), id: \.element.id) { i, r in
                            SupportingReviewCard(review: r, rank: i + 2)
                                .onTapGesture { expanded = r }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .sheet(item: $expanded) { review in
            ReviewDetailSheet(review: review)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.circle.fill").foregroundStyle(.orange)
            Text("Featured Critics")
                .font(.headline)
            Spacer()
            Text("This week's top traders")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Winner card (hero)

struct WinnerReviewCard: View {
    let review: Review
    let rank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                rankBadge(rank)
                Text(review.moviePosterEmoji).font(.title2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(review.movieTitle).font(.subheadline.weight(.bold))
                    HStack(spacing: 6) {
                        Text("@\(review.authorHandle)").font(.caption).foregroundStyle(.orange)
                        Text(review.authorTier.name).font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(review.authorTier.color.opacity(0.25)))
                            .foregroundStyle(review.authorTier.color)
                    }
                }
                Spacer()
                Text(review.stars).font(.caption).foregroundStyle(.yellow)
            }
            Text(review.headline)
                .font(.title3.weight(.bold))
                .lineLimit(2)
            Text(review.body)
                .font(.callout)
                .lineLimit(4)
                .foregroundStyle(.primary.opacity(0.85))
            HStack {
                Label("\(review.likes)", systemImage: "heart.fill")
                    .font(.caption).foregroundStyle(.pink)
                Spacer()
                Text("Read more →").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [.orange.opacity(0.18), .orange.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.5), lineWidth: 1.5)
        )
    }
}

// MARK: - Supporting cards (#2-5)

struct SupportingReviewCard: View {
    let review: Review
    let rank: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                rankBadge(rank)
                Spacer()
                Text(review.stars).font(.caption2).foregroundStyle(.yellow)
            }
            HStack(spacing: 6) {
                Text(review.moviePosterEmoji).font(.body)
                Text(review.movieTitle).font(.caption.weight(.bold)).lineLimit(1)
            }
            Text(review.headline)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
            Text("@\(review.authorHandle)")
                .font(.caption2)
                .foregroundStyle(review.authorTier.color)
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

@ViewBuilder
private func rankBadge(_ n: Int) -> some View {
    let (label, color): (String, Color) = {
        switch n {
        case 1: return ("#1", .orange)
        case 2: return ("#2", .yellow)
        case 3: return ("#3", .green)
        default: return ("#\(n)", .blue)
        }
    }()
    Text(label)
        .font(.caption2.weight(.heavy))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.25)))
        .foregroundStyle(color)
}

// MARK: - Detail sheet

struct ReviewDetailSheet: View {
    let review: Review
    @EnvironmentObject var social: SocialService
    @ObservedObject var moderation = ModerationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showReport = false

    var live: Review {
        social.reviews.first(where: { $0.id == review.id }) ?? review
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Text(review.moviePosterEmoji)
                            .font(.system(size: 56))
                            .frame(width: 72, height: 100)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.gray.opacity(0.2)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(review.movieTitle).font(.title3.bold())
                            Text(review.stars).font(.subheadline).foregroundStyle(.yellow)
                            HStack(spacing: 6) {
                                Text("@\(review.authorHandle)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(review.authorTier.color)
                                if review.authorTier >= .analyst {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(review.authorTier.color)
                                        .font(.caption)
                                }
                            }
                            Text(review.authorTier.name).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Text(review.headline)
                        .font(.title2.bold())
                    Text(review.body)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.9))
                    Button {
                        social.toggleReviewLike(id: review.id)
                    } label: {
                        Label("\(live.likes)", systemImage: live.isLikedByMe ? "heart.fill" : "heart")
                    }
                    .buttonStyle(.bordered)
                    .tint(.pink)
                }
                .padding()
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !review.authorIsCurrentUser {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                showReport = true
                            } label: {
                                Label("Report review", systemImage: "flag")
                            }
                            Button(role: .destructive) {
                                moderation.block(handle: review.authorHandle)
                                dismiss()
                            } label: {
                                Label("Block @\(review.authorHandle)", systemImage: "hand.raised")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showReport) {
                ReportSheet(kind: .review, targetId: review.id.uuidString,
                            authorHandle: review.authorHandle)
            }
        }
    }
}

// MARK: - Write

struct WriteReviewSheet: View {
    let movie: Movie
    @EnvironmentObject var social: SocialService
    @Environment(\.dismiss) private var dismiss
    @State private var headline: String = ""
    @State private var body: String = ""
    @State private var rating: Int = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(movie.posterEmoji).font(.title)
                        VStack(alignment: .leading) {
                            Text(movie.title).font(.headline)
                            Text(movie.studio).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Rating") {
                    Picker("Stars", selection: $rating) {
                        ForEach(0...5, id: \.self) { n in
                            Text(n == 0 ? "No rating" : String(repeating: "★", count: n)).tag(n)
                        }
                    }
                }
                Section("Headline") {
                    TextField("One-line hook", text: $headline)
                }
                Section("Review") {
                    TextField("Say something worth reading…", text: $body, axis: .vertical)
                        .lineLimit(6...12)
                }
                Section {
                    Button {
                        let h = headline.trimmingCharacters(in: .whitespacesAndNewlines)
                        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !h.isEmpty, !b.isEmpty else { return }
                        social.submitReview(movie: movie, headline: h, body: b, rating: rating)
                        dismiss()
                    } label: {
                        Text("Publish review")
                            .frame(maxWidth: .infinity).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Write review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
