import SwiftUI

/// Full-width live price chart for a single contract.
struct PriceChart: View {
    let points: [PricePoint]
    let color: Color
    var height: CGFloat = 140

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else {
                let msg = Text("Waiting for the first tick…").font(.caption).foregroundColor(.secondary)
                ctx.draw(msg, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let inset: CGFloat = 30
            let plot = CGRect(x: inset, y: 8,
                              width: size.width - inset - 8,
                              height: size.height - 26)

            let marks = points.map(\.mark)
            let minV = marks.min() ?? 0
            let maxV = marks.max() ?? 1
            let pad = max(0.05, (maxV - minV) * 0.15)
            let lo = max(0, minV - pad)
            let hi = maxV + pad
            let range = max(hi - lo, 0.01)

            let dx = plot.width / CGFloat(points.count - 1)

            // Fill area under the curve
            var area = Path()
            area.move(to: CGPoint(x: plot.minX, y: plot.maxY))
            for (i, p) in points.enumerated() {
                let x = plot.minX + CGFloat(i) * dx
                let y = plot.maxY - CGFloat((p.mark - lo) / range) * plot.height
                area.addLine(to: CGPoint(x: x, y: y))
            }
            area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: plot.minY),
                endPoint: CGPoint(x: 0, y: plot.maxY)))

            // Line
            var line = Path()
            for (i, p) in points.enumerated() {
                let x = plot.minX + CGFloat(i) * dx
                let y = plot.maxY - CGFloat((p.mark - lo) / range) * plot.height
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                else      { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Latest-value dot
            if let last = points.last {
                let x = plot.maxX
                let y = plot.maxY - CGFloat((last.mark - lo) / range) * plot.height
                let dot = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                ctx.fill(Path(ellipseIn: dot), with: .color(color))
            }

            // Y-axis labels
            ctx.draw(Text(String(format: "%.2f", hi)).font(.caption2).foregroundColor(.secondary),
                     at: CGPoint(x: plot.minX - 14, y: plot.minY + 6))
            ctx.draw(Text(String(format: "%.2f", lo)).font(.caption2).foregroundColor(.secondary),
                     at: CGPoint(x: plot.minX - 14, y: plot.maxY - 6))

            // Time labels
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            ctx.draw(Text(f.string(from: points.first!.time)).font(.caption2).foregroundColor(.tertiary),
                     at: CGPoint(x: plot.minX + 20, y: plot.maxY + 12))
            ctx.draw(Text(f.string(from: points.last!.time)).font(.caption2).foregroundColor(.tertiary),
                     at: CGPoint(x: plot.maxX - 20, y: plot.maxY + 12))
        }
        .frame(height: height)
    }
}
