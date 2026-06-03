import SwiftUI

/// Procedurally generated cover art so every title has a distinct, premium
/// poster without shipping image assets. Colours are seeded from the item so
/// the same title always renders the same artwork.
struct PosterArt: View {
    let item: MediaItem
    var showsTitle: Bool = true

    private var cover: UIImage? { ContentResolver.coverImage(for: item) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    GeneratedCover(item: item)
                }

                // Suppress the gradient + title overlay when the artwork
                // already has the title baked in (album covers, movie
                // posters), otherwise the title renders twice on top of
                // itself — the "bleeding / overlapping" the user flagged.
                if showsTitle && !item.coverHasTitle {
                    LinearGradient(colors: [.clear, .black.opacity(0.72)],
                                   startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 3) {
                        Spacer()
                        Text(item.categoryLabel.uppercased())
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
