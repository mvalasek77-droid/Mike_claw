import SwiftUI

/// Single source of truth for MetaBro's visual language.
/// No view should hard-code colors, spacing, radii, or motion — pull from here.
enum Tokens {

    // MARK: Color (semantic, light/dark adaptive, P3)
    enum Color {
        // Literal default so the system renders before an asset catalog is wired;
        // swap for `Color("Accent")` once Assets.xcassets ships.
        static let accent = SwiftUI.Color(red: 0.36, green: 0.55, blue: 1.0)

        static let upvote = SwiftUI.Color(red: 1.0, green: 0.42, blue: 0.21)
        static let downvote = SwiftUI.Color(red: 0.42, green: 0.55, blue: 0.95)
        static let respect = SwiftUI.Color(red: 0.20, green: 0.78, blue: 0.55)

        static let textPrimary = SwiftUI.Color.primary
        static let textSecondary = SwiftUI.Color.secondary
        static let separator = SwiftUI.Color.primary.opacity(0.08)
    }

    // MARK: Spacing (4pt base scale)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Corner radius
    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let pill: CGFloat = 999
    }

    // MARK: Typography — built on Dynamic Type so everything scales.
    enum Typography {
        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        static let headline = Font.system(.headline, design: .rounded)
        static let body = Font.system(.body)
        static let caption = Font.system(.caption, design: .rounded)
        static let score = Font.system(.subheadline, design: .rounded).weight(.semibold)
            .monospacedDigit()
    }

    // MARK: Motion curves — springy, interruptible. Never linear.
    enum Motion {
        static let snappy: Animation = .snappy(duration: 0.32, extraBounce: 0.12)
        static let gentle: Animation = .spring(response: 0.45, dampingFraction: 0.82)
        static let pop: Animation = .spring(response: 0.28, dampingFraction: 0.6)
    }
}
