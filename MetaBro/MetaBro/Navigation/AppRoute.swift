import SwiftUI

/// Type-safe routes for deep links and navigation. Adding a destination is a
/// compile-time change, not a stringly-typed guess.
enum AppRoute: Hashable {
    case postDetail(Post)
    case community(Community)
    case profile(User)
}

/// The five primary tabs of the hybrid: feed fusion, communities, post,
/// messages, and you.
enum AppTab: Hashable, CaseIterable {
    case home, communities, create, messages, profile

    var title: String {
        switch self {
        case .home: "Home"
        case .communities: "Bro-hoods"
        case .create: "Post"
        case .messages: "Messages"
        case .profile: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .communities: "person.3.fill"
        case .create: "plus.circle.fill"
        case .messages: "bubble.left.and.bubble.right.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}
