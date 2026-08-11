import SwiftUI
import UIKit

extension Font {
    /// A system font that keeps the app's hand-calibrated point size **and**
    /// scales with Dynamic Type.
    ///
    /// Auction Baby's typography is tuned at the default text size (serif
    /// display faces, custom weights, tight tracking), so we don't want to
    /// swap in semantic text styles — that would reflow the whole look. Instead
    /// we keep the exact size and route it through `UIFontMetrics`, which grows
    /// and shrinks it with the user's Dynamic Type setting.
    ///
    /// `relativeTo` selects which system text style's scaling curve to follow.
    /// Call sites pass the style nearest their size (a 42-pt display face →
    /// `.largeTitle`, an 11-pt caption → `.caption2`) so everything scales in
    /// proportion rather than all snapping to body's curve.
    ///
    /// Reactivity: `scaledValue(for:)` reads the current trait environment,
    /// which SwiftUI re-establishes on every body evaluation — and bodies
    /// re-evaluate when `\.dynamicTypeSize` changes — so text resizes live when
    /// the user moves the slider. The app root clamps the upper bound
    /// (`.accessibility3`) so the largest settings can't shatter dense layouts.
    static func dynamicScaled(_ size: CGFloat,
                              weight: Font.Weight = .regular,
                              design: Font.Design = .default,
                              relativeTo textStyle: UIFont.TextStyle = .body) -> Font {
        let scaledSize = UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size)
        return .system(size: scaledSize, weight: weight, design: design)
    }
}
