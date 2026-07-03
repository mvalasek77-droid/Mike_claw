import SwiftUI

/// A 270° gauge used for the man's "Auction Credit" (a 300–900 credit-score
/// analogue) and other headline scores. Animates its sweep on appear.
struct ScoreGauge: View {
    let value: Int
    let range: ClosedRange<Int>
    var label: String
    var tint: Color = Theme.gold
    var size: CGFloat = 150

    @State private var animated = false

    private var fraction: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        return min(1, max(0, Double(value - range.lowerBound) / span))
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Theme.hairline, style: .init(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: 0.75 * (animated ? fraction : 0))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.6), tint, Theme.goldSoft],
                                    center: .center),
                    style: .init(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(0.5), radius: 6)

            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .onAppear { Motion.run(.easeOut(duration: 0.9)) { animated = true } }
        .accessibilityElement()
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Horizontal 0–100 / 0–5 stat bar with a trailing readout.
struct StatBar: View {
    let label: String
    let value: Double
    var max: Double = 5
    var tint: Color = Theme.rose
    var readout: String? = nil

    @State private var animated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(readout ?? String(format: "%.1f", value))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (animated ? min(1, value / max) : 0))
                }
            }
            .frame(height: 8)
        }
        .onAppear { Motion.run(.easeOut(duration: 0.7)) { animated = true } }
        .accessibilityElement()
        .accessibilityLabel("\(label): \(readout ?? String(format: "%.1f out of %.0f", value, max))")
    }
}

/// Read-only 1–5 star row.
struct StarRow: View {
    let value: Double
    var size: CGFloat = 13
    var tint: Color = Theme.gold

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: starName(for: i))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(format: "%.1f out of 5 stars", value))
    }

    private func starName(for i: Int) -> String {
        let pos = Double(i) + 1
        if value >= pos { return "star.fill" }
        if value >= pos - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Interactive star picker used in the review sheets.
struct StarPicker: View {
    @Binding var value: Int
    var tint: Color = Theme.gold

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= value ? "star.fill" : "star")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(i <= value ? tint : Theme.inkFaint)
                    .scaleEffect(i == value ? 1.12 : 1)
                    .onTapGesture {
                        Haptics.selection()
                        Motion.run(Motion.snap) { value = i }
                    }
                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
            }
        }
    }
}
