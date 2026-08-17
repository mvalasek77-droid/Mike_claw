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

/// Horizontal rail of story rings at the top of the feed. The first ring is
/// "Your story"; the rest are bros, unseen ones highlighted with a colored ring.
struct StoriesStrip: View {
    let stories: [Story]
    let onOpen: (Int) -> Void   // opens the viewer at the given index

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.md) {
                yourStory
                ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                    Button { onOpen(index) } label: { ring(for: story) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, Tokens.Spacing.sm)
        }
    }

    private var yourStory: some View {
        VStack(spacing: Tokens.Spacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 64, height: 64)
                    .overlay(Text("Y").font(.title3.bold()))
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Tokens.Color.accent)
                    .background(Circle().fill(.background))
            }
            Text("Your story").font(.caption2).foregroundStyle(Tokens.Color.textSecondary)
        }
        .accessibilityLabel("Add to your story")
    }

    private func ring(for story: Story) -> some View {
        VStack(spacing: Tokens.Spacing.xs) {
            Circle()
                .strokeBorder(
                    story.seen
                        ? AnyShapeStyle(Tokens.Color.separator)
                        : AnyShapeStyle(LinearGradient(colors: StoryPalette.gradient(story.accentIndex),
                                                       startPoint: .top, endPoint: .bottom)),
                    lineWidth: story.seen ? 2 : 3
                )
                .frame(width: 64, height: 64)
                .overlay { UserAvatar(user: story.author, size: 54) }
            Text(story.author.displayName)
                .font(.caption2)
                .foregroundStyle(Tokens.Color.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 64)
        }
        .accessibilityLabel("\(story.author.displayName)'s story\(story.seen ? ", seen" : "")")
    }
}
