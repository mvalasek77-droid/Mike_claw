import SwiftUI

/// Tiny inline price chart for options-chain rows.
struct Sparkline: View {
    let points: [PricePoint]
    let color: Color
    var height: CGFloat = 24

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            let marks = points.map(\.mark)
            let minV = marks.min() ?? 0
            let maxV = marks.max() ?? 1
            let range = max(maxV - minV, 0.01)

            let dx = size.width / CGFloat(points.count - 1)
            var line = Path()
            for (i, p) in points.enumerated() {
                let x = CGFloat(i) * dx
                let y = size.height - CGFloat((p.mark - minV) / range) * size.height
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                else      { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: height)
        .accessibleChart(a11ySummary)
    }

    private var a11ySummary: String {
        guard let first = points.first?.mark, let last = points.last?.mark else {
            return "Empty sparkline"
        }
        let dir = last >= first ? "up" : "down"
        return "Sparkline \(dir) from \(String(format: "%.2f", first)) to \(String(format: "%.2f", last))"
    }
}
