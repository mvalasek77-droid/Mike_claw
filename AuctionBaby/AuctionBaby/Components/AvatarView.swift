import SwiftUI

/// A procedurally-generated portrait. The app ships no real photos — every
/// "photo" is a deterministic gradient + monogram derived from the profile's
/// `hue` seed, so the concept reads clearly while staying tasteful and SFW.
///
/// Supports a `locked` state used on the bidder side: a woman sees a man's
/// stats but his picture stays frosted until she accepts his bid.
struct AvatarView: View {
    let name: String
    let hue: Double
    var locked: Bool = false
    var copycat: Bool = false
    var corner: CGFloat = Theme.cornerL

    private var initials: String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return String(chars).uppercased()
    }

    private var base: Color { Color(hue: hue, saturation: 0.55, brightness: 0.85) }
    private var deep: Color { Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                                    saturation: 0.7, brightness: 0.45) }

    var body: some View {
        ZStack {
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

            if copycat {
                LinearGradient(colors: [Theme.copycat.opacity(0.45), .clear],
                               startPoint: .bottomLeading, endPoint: .topTrailing)
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
    var size: CGFloat = 44
    var locked: Bool = false
    var copycat: Bool = false

    var body: some View {
        AvatarView(name: name, hue: hue, locked: locked, copycat: copycat, corner: size)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }
}
