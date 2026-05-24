import SwiftUI

/// Procedurally generated cover art so every title has a distinct, premium
/// poster without shipping image assets. Colours are seeded from the item so
/// the same title always renders the same artwork.
struct PosterArt: View {
    let item: MediaItem
    var showsTitle: Bool = true

    private var palette: (top: Color, bottom: Color) {
        let hue = Double(item.seed % 360) / 360.0
        let hueB = (hue + 0.11).truncatingRemainder(dividingBy: 1.0)
        return (
            Color(hue: hue, saturation: 0.66, brightness: 0.52),
            Color(hue: hueB, saturation: 0.82, brightness: 0.22)
        )
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                // Soft seeded orbs for depth.
                Circle()
                    .fill(item.type.accent.opacity(0.55))
                    .frame(width: w * 0.9)
                    .blur(radius: 42)
                    .offset(x: CGFloat((item.seed % 60)) - 30, y: -h * 0.28)
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: w * 0.6)
                    .blur(radius: 30)
                    .offset(x: w * 0.28, y: h * 0.30)

                // Giant faint category glyph.
                Image(systemName: item.type.icon)
                    .font(.system(size: min(w, h) * 0.5, weight: .black))
                    .foregroundStyle(.white.opacity(0.14))
                    .rotationEffect(.degrees(-8))

                if showsTitle {
                    LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                   startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 3) {
                        Spacer()
                        Text(item.type.title.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(item.type.accent)
                        Text(item.title)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerM, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}
