import SwiftUI

/// The BoxCall design system — an old-school movie house on the phone.
///
/// Palette borrows from vintage cinema: **marquee gold** for accents,
/// **velvet red** for headline surfaces, **cream** for readable text on
/// dark, and a warm-tinted **stage black** for the backdrop. Type mixes
/// a display serif for headlines with the system sans for chrome, the
/// way a real ticket stub does. On iOS 26 the surfaces use Liquid Glass;
/// on 17–25 they fall back to `ultraThinMaterial` with a matching tint.
enum Theme {

    // MARK: - Palette
    static let marqueeGold  = Color(red: 0.80, green: 0.66, blue: 0.19)  // #C9A930
    static let bulbGlow     = Color(red: 0.97, green: 0.83, blue: 0.42)  // #F7D46A
    static let velvetRed    = Color(red: 0.47, green: 0.05, blue: 0.11)  // #7A0C1C
    static let cream        = Color(red: 0.96, green: 0.91, blue: 0.83)  // #F5E9D3
    static let stageBlack   = Color(red: 0.04, green: 0.03, blue: 0.02)  // #0A0806

    /// Legacy alias so older call sites don't break during the rename.
    static let accent      = marqueeGold
    static let accentSoft  = bulbGlow

    // Semantic (kept green/red because charts trump theme for legibility)
    static let bull        = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let bear        = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let neutral     = Color(white: 0.55)

    // Tier colors (unchanged — mirrored in Tier.color)
    static let tierRookie      = Color.gray
    static let tierAnalyst     = Color.blue
    static let tierInsider     = marqueeGold
    static let tierProducer    = Color.purple
    static let tierStudioHead  = Color.pink
    static let tierOracle      = marqueeGold

    // MARK: - Radii (continuous curves — no sharp corners in a movie palace)
    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    // MARK: - Spacing (4-pt grid)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Type ramps
    enum Type {
        /// Serif display for headlines — evokes a repertory theater program.
        static let marqueeTitle  = Font.system(.largeTitle, design: .serif).weight(.bold)
        static let marqueeH1     = Font.system(.title,      design: .serif).weight(.bold)
        static let marqueeH2     = Font.system(.title2,     design: .serif).weight(.semibold)
        /// Body + labels stay sans for legibility.
        static let bodySans      = Font.system(.body)
        static let labelSans     = Font.system(.caption).weight(.semibold)
    }

    // MARK: - Motion
    enum Motion {
        static let snap:    Animation = .spring(response: 0.28, dampingFraction: 0.85)
        static let smooth:  Animation = .spring(response: 0.45, dampingFraction: 0.86)
        static let breathe: Animation = .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
        static let toast:   Animation = .spring(response: 0.36, dampingFraction: 0.75)
    }
}

// MARK: - Glass surface (Liquid Glass on iOS 26, material fallback)

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.md
    var tint: Color? = nil
    var stroke: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(background)
            .overlay(strokeShape)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            shape.glassEffect(.regular.tint(tint ?? .clear.opacity(0.001)))
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(tint?.opacity(0.10) ?? .clear))
        }
        #else
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(tint?.opacity(0.10) ?? .clear))
        #endif
    }

    @ViewBuilder
    private var strokeShape: some View {
        if let stroke {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        }
    }
}

extension View {
    func glassSurface(radius: CGFloat = Theme.Radius.md,
                      tint: Color? = nil,
                      stroke: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: radius, tint: tint, stroke: stroke))
    }
}

// MARK: - Cinema marquee

/// A row of glowing marquee bulbs. Used above key surfaces (hero cards,
/// season header) as a signature theatrical accent.
struct MarqueeBulbs: View {
    var count: Int = 12
    @State private var flicker = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Theme.bulbGlow)
                    .frame(width: 6, height: 6)
                    .shadow(color: Theme.bulbGlow.opacity(0.7), radius: flicker ? 3 : 5)
                    .opacity(flicker ? 0.75 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.07),
                        value: flicker
                    )
            }
        }
        .onAppear { flicker.toggle() }
    }
}

/// A ticket-stub divider — a horizontal line with a scalloped/perforated
/// midpoint. Used between sections on the Movie Detail hero.
struct TicketStubDivider: View {
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.marqueeGold.opacity(0.35)).frame(height: 1)
            ForEach(0..<12, id: \.self) { _ in
                Circle().fill(Theme.marqueeGold.opacity(0.35))
                    .frame(width: 3, height: 3)
                    .padding(.horizontal, 3)
            }
            Rectangle().fill(Theme.marqueeGold.opacity(0.35)).frame(height: 1)
        }
        .frame(height: 6)
    }
}

// MARK: - Depth pressable button style

struct DepthButtonStyle: ButtonStyle {
    var tint: Color = Theme.marqueeGold

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.85 : 1))
            )
            .foregroundStyle(tint == .clear ? .primary : Color.black.opacity(0.85))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.10 : 0.25),
                    radius: configuration.isPressed ? 4 : 10,
                    y: configuration.isPressed ? 2 : 6)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}
