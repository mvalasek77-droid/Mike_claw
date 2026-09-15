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
            if let winner {
                WinnerReviewCard(review: winner, rank: 1) {
                    expanded = winner
                }
            } else {
                Text("No reviews yet — top-5 traders' reviews will appear here.")
                    .font(.caption)
                    .foregroundStyle(Theme.cream.opacity(0.6))
            }
            if !supporting.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(supporting.enumerated()), id: \.element.id) { i, r in
                            SupportingReviewCard(review: r, rank: i + 2) {
                                expanded = r
                            }
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
}

// MARK: - Winner card (hero)

struct WinnerReviewCard: View {
    let review: Review
    let rank: Int
    let onRead: () -> Void
    @EnvironmentObject var market: MarketService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                rankBadge(rank)
                movieLink
                Spacer()
                Text(review.stars)
                    .font(.caption)
                    .foregroundStyle(Theme.marqueeGold)
            }
            Text(review.headline)
                .font(Theme.Typography.marqueeH2)
                .foregroundStyle(Theme.cream)
                .lineLimit(2)
            Text(review.body)
                .font(.callout)
                .lineLimit(4)
                .foregroundStyle(Theme.cream.opacity(0.78))
            HStack {
                Label("\(review.likes)", systemImage: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.marqueeGold)
                Spacer()
                Button(action: onRead) {
                    Text("Read review  →")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.marqueeGold)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Theme.velvetRed.opacity(0.72),
                                               Color(red: 0.07, green: 0.055, blue: 0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.marqueeGold.opacity(0.52), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var movieLink: some View {
        if let movie = market.movie(id: review.movieId) {
            NavigationLink(value: movie) {
                movieIdentity
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(movie.title)")
        } else {
            movieIdentity
        }
    }

    private var movieIdentity: some View {
        HStack(spacing: 8) {
            MarqueeMovieMark(title: review.movieTitle, width: 34, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(review.movieTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.marqueeGold)
                }
                HStack(spacing: 6) {
                    Text("@\(review.authorHandle)")
                        .font(.caption)
                        .foregroundStyle(Theme.marqueeGold)
                    Text(review.authorTier.name.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(Theme.cream.opacity(0.55))
                    }
                }
        }
    }
}

// MARK: - Supporting cards (#2-5)

struct SupportingReviewCard: View {
    let review: Review
    let rank: Int
    let onRead: () -> Void
    @EnvironmentObject var market: MarketService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                rankBadge(rank)
                Spacer()
                Text(review.stars).font(.caption2).foregroundStyle(Theme.marqueeGold)
            }
            movieLink
            Text(review.headline)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.cream)
                .lineLimit(2)
            HStack {
                Text("@\(review.authorHandle)")
                    .font(.caption2)
                    .foregroundStyle(Theme.marqueeGold)
                Spacer()
                Button("Review", action: onRead)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(red: 0.075, green: 0.06, blue: 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.marqueeGold.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private var movieLink: some View {
        if let movie = market.movie(id: review.movieId) {
            NavigationLink(value: movie) { movieIdentity }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(movie.title)")
        } else {
            movieIdentity
        }
    }

    private var movieIdentity: some View {
        HStack(spacing: 6) {
            MarqueeMovieMark(title: review.movieTitle, width: 26, height: 32)
            Text(review.movieTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.cream)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.marqueeGold)
        }
    }
}

@ViewBuilder
private func rankBadge(_ n: Int) -> some View {
    Text("#\(n)")
        .font(.caption2.weight(.heavy))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.marqueeGold.opacity(0.18)))
        .foregroundStyle(Theme.marqueeGold)
}

// MARK: - Detail sheet

struct ReviewDetailSheet: View {
    let review: Review
    @EnvironmentObject var social: SocialService
    @EnvironmentObject var market: MarketService
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
                    if let movie = market.movie(id: review.movieId) {
                        NavigationLink(value: movie) {
                            reviewHeader(movie: movie)
                        }
                        .buttonStyle(.plain)
                    } else {
                        reviewHeader(movie: nil)
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
                    .tint(Theme.marqueeGold)
                }
                .padding()
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie)
            }
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
                            Image(systemName: "ellipsis")
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

    private func reviewHeader(movie: Movie?) -> some View {
        HStack(spacing: 12) {
            MarqueeMovieMark(title: movie?.title ?? review.movieTitle, width: 72, height: 100)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(review.movieTitle).font(.title3.bold())
                    if movie != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.marqueeGold)
                    }
                }
                Text(review.stars).font(.subheadline).foregroundStyle(Theme.marqueeGold)
                HStack(spacing: 6) {
                    Text("@\(review.authorHandle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.marqueeGold)
                    if review.authorTier >= .analyst {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.marqueeGold)
                            .font(.caption)
                    }
                }
                Text(review.authorTier.name).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Write

struct WriteReviewSheet: View {
    let movie: Movie
    @EnvironmentObject var social: SocialService
    @Environment(\.dismiss) private var dismiss
    @State private var headline: String = ""
    @State private var reviewBody: String = ""
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
                    TextField("Say something worth reading…", text: $reviewBody, axis: .vertical)
                        .lineLimit(6...12)
                }
                Section {
                    Button {
                        let h = headline.trimmingCharacters(in: .whitespacesAndNewlines)
                        let b = reviewBody.trimmingCharacters(in: .whitespacesAndNewlines)
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
                              reviewBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
