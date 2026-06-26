import SwiftUI

/// Centralised colour, gradient and geometry tokens for **Auction Baby**.
///
/// The brand is an "auction house for dating": deep gallery-black walls, warm
/// gold for *value / money* and a rose-crimson for *desire / the match*. The
/// two accents are used consistently — gold means a number with a dollar sign
/// in front of it, rose means a human connection.
enum Theme {
    // Value / money accent — auction-house gold.
    static let gold = Color(red: 0.91, green: 0.74, blue: 0.36)
    static let goldDeep = Color(red: 0.74, green: 0.54, blue: 0.18)
    static let goldSoft = Color(red: 0.97, green: 0.86, blue: 0.60)

    // Desire / match accent — rose-crimson.
    static let rose = Color(red: 0.93, green: 0.27, blue: 0.42)
    static let roseSoft = Color(red: 0.98, green: 0.52, blue: 0.62)

    // Semantic
    static let success = Color(red: 0.30, green: 0.83, blue: 0.55)
    static let warning = Color(red: 1.00, green: 0.66, blue: 0.20)
    static let danger = Color(red: 0.97, green: 0.28, blue: 0.31)
    static let verify = Color(red: 0.30, green: 0.74, blue: 0.98) // identity-verified blue
    static let copycat = Color(red: 0.60, green: 0.40, blue: 0.95) // synthetic / AI lure

    // Neutrals — warm gallery black so gold reads as lit, not cold.
    static let bg = Color(red: 0.045, green: 0.035, blue: 0.045)
    static let surface = Color(red: 0.11, green: 0.095, blue: 0.11)
    static let surfaceHigh = Color(red: 0.16, green: 0.14, blue: 0.16)
    static let ink = Color.white
    static let inkSoft = Color.white.opacity(0.66)
    static let inkFaint = Color.white.opacity(0.40)
    static let hairline = Color.white.opacity(0.12)

    static let cornerXL: CGFloat = 30
    static let cornerL: CGFloat = 22
    static let cornerM: CGFloat = 14
    static let cornerS: CGFloat = 9

    static let goldGradient = LinearGradient(
        colors: [goldSoft, gold, goldDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let roseGradient = LinearGradient(
        colors: [roseSoft, rose, Color(red: 0.72, green: 0.13, blue: 0.30)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Master-tier shimmer used for the "Masterpiece" and "Trillionaire" badges.
    static let prestigeGradient = LinearGradient(
        colors: [goldSoft, rose, gold, Color(red: 0.55, green: 0.42, blue: 0.95), goldSoft],
        startPoint: .leading, endPoint: .trailing
    )
}

/// Full-bleed gallery background — a single warm spotlight from top centre,
/// vignetted toward the edges, like a lot under auction lighting.
struct AppBackground: View {
    var glow: Color = Theme.gold
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [glow.opacity(0.20), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0, endRadius: 520
            )
            LinearGradient(
                colors: [Theme.rose.opacity(0.10), .clear],
                startPoint: .bottomTrailing, endPoint: .center
            )
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                center: .center, startRadius: 220, endRadius: 780
            )
        }
        .ignoresSafeArea()
    }
}

extension Font {
    static let displayXL = Font.system(size: 42, weight: .heavy, design: .serif)
    static let displayL = Font.system(size: 30, weight: .bold, design: .serif)
    static let titleSerif = Font.system(size: 22, weight: .bold, design: .serif)
    static let titleRounded = Font.system(size: 22, weight: .bold, design: .rounded)
}

extension View {
    /// Standard horizontal page padding.
    func screenPadding() -> some View { self.padding(.horizontal, 18) }

    /// Applies Apple's iOS 26 Liquid Glass material when the SDK/runtime
    /// supports it, and is a graceful no-op on iOS 17–25 so the app builds
    /// and looks coherent everywhere.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = Theme.cornerL) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Subtle depth: a two-layer cast shadow (tight contact + soft ambient)
    /// plus a top-light highlight stroke. Gives raised glass surfaces the
    /// fluid, lit, parallax feel of the iOS 26 design language.
    func depth(_ corner: CGFloat = Theme.cornerL, strong: Bool = false) -> some View {
        self
            .shadow(color: .black.opacity(strong ? 0.35 : 0.22), radius: strong ? 8 : 5, x: 0, y: strong ? 4 : 2)
            .shadow(color: .black.opacity(strong ? 0.45 : 0.28), radius: strong ? 30 : 18, x: 0, y: strong ? 16 : 9)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.40), .white.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8
                    )
            )
    }
}

/// Formats whole-dollar auction figures the way an auctioneer would read them:
/// `$5`, `$1,000`, `$1M`, `$100M`. Compact above six figures so a million-dollar
/// bid never blows out a layout.
enum Money {
    static func full(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: value)) ?? "\(value)")
    }

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...: return "$\(value / 1_000_000_000)B"
        case 1_000_000...:     return "$\(trim(Double(value) / 1_000_000))M"
        case 10_000...:        return "$\(value / 1_000)K"
        default:               return full(value)
        }
    }

    private static func trim(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
}

/// Formats a count of Gavels (the in-app currency) — no dollar sign, since
/// Gavels are not dollars. `1,000`, `14K`, `1.2M`.
enum Tally {
    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return "\(trim(Double(value) / 1_000_000))M"
        case 100_000...:   return "\(value / 1_000)K"
        case 10_000...:    return "\(trim(Double(value) / 1_000))K"
        default:
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: value)) ?? "\(value)"
        }
    }

    private static func trim(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }
}
