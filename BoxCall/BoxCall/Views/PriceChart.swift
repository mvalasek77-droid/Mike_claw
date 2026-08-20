import SwiftUI

/// Full-width live price chart for a single contract, with optional
/// support / resistance overlay showing where market makers are stepping in.
struct PriceChart: View {
    let points: [PricePoint]
    let color: Color
    var sr: SRLevel? = nil
    var height: CGFloat = 160

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else {
                let msg = Text("Waiting for the first tick…").font(.caption).foregroundColor(.secondary)
                ctx.draw(msg, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let inset: CGFloat = 34
            let plot = CGRect(x: inset, y: 8,
                              width: size.width - inset - 40,
                              height: size.height - 26)

            let marks = points.map(\.mark)
            var lo = marks.min() ?? 0
            var hi = marks.max() ?? 1

            // Expand y-range to include S/R lines so they always render.
            if let sr {
                lo = min(lo, sr.support)
                hi = max(hi, sr.resistance)
            }
            let pad = max(0.05, (hi - lo) * 0.15)
            lo = max(0, lo - pad)
            hi = hi + pad
            let range = max(hi - lo, 0.01)

            func px(_ y: Double) -> CGFloat {
                plot.maxY - CGFloat((y - lo) / range) * plot.height
            }

            // MM band (shaded between support and resistance)
            if let sr {
                let bandRect = CGRect(x: plot.minX,
                                      y: px(sr.resistance),
                                      width: plot.width,
                                      height: max(1, px(sr.support) - px(sr.resistance)))
                ctx.fill(Path(bandRect), with: .color(color.opacity(0.06)))

                // Support line (green)
                var supportLine = Path()
                supportLine.move(to: CGPoint(x: plot.minX, y: px(sr.support)))
                supportLine.addLine(to: CGPoint(x: plot.maxX, y: px(sr.support)))
                ctx.stroke(supportLine, with: .color(.green.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // Resistance line (red)
                var resistanceLine = Path()
                resistanceLine.move(to: CGPoint(x: plot.minX, y: px(sr.resistance)))
                resistanceLine.addLine(to: CGPoint(x: plot.maxX, y: px(sr.resistance)))
                ctx.stroke(resistanceLine, with: .color(.red.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                // Labels to the right of the plot
                ctx.draw(Text("R \(sr.resistance, specifier: "%.2f")")
                            .font(.caption2.weight(.semibold)).foregroundColor(.red),
                         at: CGPoint(x: plot.maxX + 22, y: px(sr.resistance)))
                ctx.draw(Text("S \(sr.support, specifier: "%.2f")")
                            .font(.caption2.weight(.semibold)).foregroundColor(.green),
                         at: CGPoint(x: plot.maxX + 22, y: px(sr.support)))
            }

            // Area under the price curve
            let dx = plot.width / CGFloat(points.count - 1)
            var area = Path()
            area.move(to: CGPoint(x: plot.minX, y: plot.maxY))
            for (i, p) in points.enumerated() {
                area.addLine(to: CGPoint(x: plot.minX + CGFloat(i) * dx, y: px(p.mark)))
            }
            area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: plot.minY),
                endPoint: CGPoint(x: 0, y: plot.maxY)))

            // Price line
            var line = Path()
            for (i, p) in points.enumerated() {
                let pt = CGPoint(x: plot.minX + CGFloat(i) * dx, y: px(p.mark))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Latest-value dot
            if let last = points.last {
                let x = plot.maxX
                let y = px(last.mark)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                         with: .color(color))
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
