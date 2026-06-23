import SwiftUI

/// Circular user avatar. Loads the daily-generated image from `AvatarCatalog`
/// (or the user's own `avatarURL` if set), falling back to a tinted monogram
/// while loading or offline — so it always renders, including in tests/previews.
struct UserAvatar: View {
    let user: User
    var size: CGFloat = 40

    private var url: URL { user.avatarURL ?? AvatarCatalog.user(handle: user.handle) }

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        Circle()
            .fill(Tokens.Color.accent.opacity(0.25))
            .overlay(Text(initial(user.displayName))
                .font(.system(size: size * 0.42, weight: .bold)))
    }
}

/// Rounded-square Bro-hood icon, same loading strategy as `UserAvatar`.
struct CommunityAvatar: View {
    let community: Community
    var size: CGFloat = 44

    private var url: URL { community.iconURL ?? AvatarCatalog.community(slug: community.slug) }

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Tokens.Color.accent.opacity(0.25))
            .overlay(Text(initial(community.name))
                .font(.system(size: size * 0.4, weight: .bold)))
    }
}

private func initial(_ s: String) -> String {
    String(s.replacingOccurrences(of: "@", with: "").prefix(1)).uppercased()
}
