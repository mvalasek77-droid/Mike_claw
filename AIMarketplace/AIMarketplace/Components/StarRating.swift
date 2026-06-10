import SwiftUI

/// Read-only star display supporting half stars.
struct StarRow: View {
    let rating: Double
    var size: CGFloat = 12
    var color: Color = Theme.gold

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: symbol(for: i))
                    .font(.system(size: size))
                    .foregroundStyle(color)
            }
        }
        // VoiceOver: read the rating once, not five star glyphs.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating.formatted()) out of 5 stars")
    }

    private func symbol(for index: Int) -> String {
        let position = Double(index) + 1
        if rating >= position { return "star.fill" }
        if rating >= position - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Interactive 1–5 star picker.
struct StarPicker: View {
    @Binding var rating: Int
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(value <= rating ? Theme.gold : Theme.inkFaint)
                    .onTapGesture { Haptics.selection(); rating = value }
                    .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
            }
        }
    }
}
