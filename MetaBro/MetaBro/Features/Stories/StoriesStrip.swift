import SwiftUI

/// Palette for story gradients, indexed by `Story.accentIndex`.
enum StoryPalette {
    static let gradients: [[Color]] = [
        [Tokens.Color.accent, Tokens.Color.respect],
        [Tokens.Color.upvote, .pink],
        [.purple, Tokens.Color.accent],
        [.teal, .green],
    ]
    static func gradient(_ index: Int) -> [Color] {
        gradients[((index % gradients.count) + gradients.count) % gradients.count]
    }
}

/// Facebook-style story rail: tall rounded cards, "Create story" first, then
/// bros' stories with their avatar ringed in blue until seen.
struct StoriesStrip: View {
    let stories: [Story]
    let onOpen: (Int) -> Void   // opens the viewer at the given index

    private let cardSize = CGSize(width: 108, height: 180)

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.sm) {
                createCard
                ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                    Button { onOpen(index) } label: { card(for: story) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.md)
        }
    }

    private var createCard: some View {
        VStack(spacing: 0) {
            Tokens.Color.inputBackground
                .overlay { UserAvatar(user: Session.me, size: 64) }
            ZStack(alignment: .top) {
                Tokens.Color.cardBackground
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Tokens.Color.accent, in: Circle())
                    .overlay(Circle().stroke(Tokens.Color.cardBackground, lineWidth: 3))
                    .offset(y: -17)
                Text("Create story")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .padding(.top, 24)
            }
            .frame(height: 64)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
            .stroke(Tokens.Color.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Create story")
    }

    private func card(for story: Story) -> some View {
        ZStack {
            LinearGradient(colors: StoryPalette.gradient(story.accentIndex),
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(story.caption)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, Tokens.Spacing.sm)
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
        }
        .overlay(alignment: .topLeading) {
            UserAvatar(user: story.author, size: 34)
                .padding(3)
                .overlay(Circle().stroke(story.seen ? Color.white.opacity(0.5) : Tokens.Color.accent,
                                         lineWidth: 3))
                .padding(Tokens.Spacing.sm)
        }
        .overlay(alignment: .bottomLeading) {
            Text(story.author.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(Tokens.Spacing.sm)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .opacity(story.seen ? 0.75 : 1)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(story.author.displayName)'s story\(story.seen ? ", seen" : "")")
    }
}
