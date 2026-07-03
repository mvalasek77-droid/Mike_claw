import SwiftUI
import UIKit

/// A profile portrait. When the profile carries a `photoName` that exists in
/// the asset catalog, the real photo renders (drop licensed images into
/// Resources/Assets.xcassets). Otherwise a deterministic gradient + monogram
/// stands in, so the app works with zero bundled photography.
///
/// Supports a `locked` state used on the bidder side: a woman sees a man's
/// stats but his picture stays frosted until she accepts his bid.
struct AvatarView: View {
    let name: String
    let hue: Double
    var photoName: String? = nil
    var locked: Bool = false
    var copycat: Bool = false
    var copycatStyle: CopycatStyle = .glam
    var corner: CGFloat = Theme.cornerL

    private var initials: String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased()
    }

    private var base: Color { Color(hue: hue, saturation: 0.55, brightness: 0.85) }
    private var deep: Color { Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                                    saturation: 0.7, brightness: 0.45) }

    /// The real photo, only if the asset actually exists in the bundle.
    private var photo: UIImage? {
        guard let photoName else { return nil }
        return UIImage(named: photoName)
    }

    var body: some View {
        if copycat && !locked {
            if photo != nil {
                // Real (licensed) imagery for the lure — the quiet AI watermark
                // stays baked into the picture so the disclosure travels with it.
                standardBody.overlay(alignment: .bottomTrailing) { aiWatermark }
            } else {
                CopycatPortrait(name: name, hue: hue, style: copycatStyle, corner: corner)
            }
        } else {
            standardBody
        }
    }

    /// Minimal, always-present AI disclosure for photo-backed copycats.
    private var aiWatermark: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles").font(.system(size: 8, weight: .black))
            Text("AI").font(.system(size: 9, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        .padding(6)
        .allowsHitTesting(false)
    }

    private var standardBody: some View {
        ZStack {
            if let photo, !locked {
                // Real photo path — fills the frame, cropped from the center.
                Color.clear
                    .overlay(
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipped()
                // Legibility scrim for text drawn over the photo by parents.
                LinearGradient(colors: [.clear, .black.opacity(0.25)],
                               startPoint: .center, endPoint: .bottom)
            } else {
                LinearGradient(colors: [base, deep], startPoint: .topLeading, endPoint: .bottomTrailing)

                // Soft studio highlight.
                RadialGradient(colors: [.white.opacity(0.35), .clear],
                               center: .init(x: 0.3, y: 0.22), startRadius: 0, endRadius: 180)

                if !locked {
                    Image(systemName: "person.fill")
                        .resizable().scaledToFit()
                        .foregroundStyle(.white.opacity(0.16))
                        .padding(.top, 26)
                        .scaleEffect(1.7)
                        .offset(y: 18)

                    Text(initials)
                        .font(.system(size: 34, weight: .heavy, design: .serif))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                }
            }

            if locked {
                Rectangle().fill(.ultraThinMaterial)
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    Text("Photo unlocks\nwhen you accept")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        )
        .accessibilityElement()
        .accessibilityLabel(locked ? "Hidden photo, unlocks when you accept the bid"
                                   : "\(name)\(copycat ? ", AI-generated profile" : "")")
    }
}

/// Circular avatar variant for chat rows and headers.
struct AvatarCircle: View {
    let name: String
    let hue: Double
    var photoName: String? = nil
    var size: CGFloat = 44
    var locked: Bool = false
    var copycat: Bool = false
    var copycatStyle: CopycatStyle = .glam

    var body: some View {
        AvatarView(name: name, hue: hue, photoName: photoName, locked: locked, copycat: copycat,
                   copycatStyle: copycatStyle, corner: size)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }
}
