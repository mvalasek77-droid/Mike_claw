import SwiftUI

/// Renders search state: communities first (Reddit ranks community matches
/// above posts), then matching posts. Tapping a post opens its thread.
struct SearchResultsView: View {
    let state: SearchViewModel.State
    let onOpenPost: (Post) -> Void
    let safetyService: SafetyService

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty(let query):
            ContentUnavailableView.search(text: query)
        case .error(let message):
            ContentUnavailableView("Search failed",
                                   systemImage: "exclamationmark.magnifyingglass",
                                   description: Text(message))
        case .results(let results):
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                    if !results.communities.isEmpty {
                        section("Bro-hoods") {
                            ForEach(results.communities) { c in
                                communityRow(c)
                            }
                        }
                    }
                    if !results.posts.isEmpty {
                        section("Posts") {
                            ForEach(results.posts) { post in
                                PostCardView(post: post, onVote: { _ in },
                                             onOpen: { onOpenPost(post) },
                                             safetyService: safetyService)
                            }
                        }
                    }
                }
                .padding(Tokens.Spacing.lg)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            Text(title).font(Tokens.Typography.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func communityRow(_ c: Community) -> some View {
        HStack(spacing: Tokens.Spacing.md) {
            RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
                .fill(Tokens.Color.accent.opacity(0.25))
                .frame(width: 40, height: 40)
                .overlay(Text(String(c.name.prefix(1))).font(.headline.bold()))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(Tokens.Typography.headline)
                Text("\(c.memberCount.abbreviated) bros · b/\(c.slug)")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Spacer()
            if c.isJoined {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Tokens.Color.accent)
                    .accessibilityLabel("Joined")
            }
        }
        .padding(Tokens.Spacing.md)
        .liquidGlass()
    }
}
