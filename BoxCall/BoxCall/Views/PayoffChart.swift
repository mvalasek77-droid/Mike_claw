import SwiftUI

/// Classic hockey-stick payoff diagram. X = actual opening ($M),
/// Y = net profit per contract (payoff − premium).
struct PayoffChart: View {
    let side: ContractSide
    let strike: Double
    let premium: Double
    let multiplier: Double
    /// Range of "actual" values to plot. Defaults to strike ± 60%.
    let xRange: ClosedRange<Double>

    init(side: ContractSide,
         strike: Double,
         premium: Double,
         multiplier: Double = 1,
         xRange: ClosedRange<Double>? = nil) {
        self.side = side
        self.strike = strike
        self.premium = premium
        self.multiplier = multiplier
        if let xRange {
            self.xRange = xRange
        } else {
            let pad = max(4, strike * 0.6)
            self.xRange = max(0, strike - pad)...(strike + pad)
        }
    }

    private func payoff(at actual: Double) -> Double {
        let intrinsic = side == .call
            ? max(actual - strike, 0)
            : max(strike - actual, 0)
        return intrinsic * multiplier - premium
    }

    private var breakEven: Double {
        side == .call ? strike + premium / multiplier
                      : strike - premium / multiplier
    }

    private var yRange: ClosedRange<Double> {
        let a = payoff(at: xRange.lowerBound)
        let b = payoff(at: xRange.upperBound)
        let lo = min(a, b, -premium)
        let hi = max(a, b, premium)
        // Add a little headroom
        let pad = max(1.0, (hi - lo) * 0.15)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 30
            let plot = CGRect(x: inset, y: 12,
                              width: size.width - inset - 8,
                              height: size.height - 12 - inset)

            let xR = xRange
            let yR = yRange

            func px(_ x: Double) -> CGFloat {
                plot.minX + CGFloat((x - xR.lowerBound) / (xR.upperBound - xR.lowerBound)) * plot.width
            }
            func py(_ y: Double) -> CGFloat {
                plot.maxY - CGFloat((y - yR.lowerBound) / (yR.upperBound - yR.lowerBound)) * plot.height
            }

            // Zero P&L axis
            let zeroY = py(0)
            var axis = Path()
            axis.move(to: CGPoint(x: plot.minX, y: zeroY))
            axis.addLine(to: CGPoint(x: plot.maxX, y: zeroY))
            ctx.stroke(axis, with: .color(.secondary.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Fill profit / loss regions under the curve
            let steps = 120
            var top = Path()
            var bottom = Path()
            for i in 0...steps {
                let x = xR.lowerBound + (xR.upperBound - xR.lowerBound) * Double(i) / Double(steps)
                let y = payoff(at: x)
                let point = CGPoint(x: px(x), y: py(y))
                if i == 0 {
                    top.move(to: CGPoint(x: point.x, y: zeroY))
                    bottom.move(to: CGPoint(x: point.x, y: zeroY))
                }
                if y >= 0 {
                    top.addLine(to: point)
                } else {
                    bottom.addLine(to: point)
                }
            }
            top.addLine(to: CGPoint(x: plot.maxX, y: zeroY))
            top.closeSubpath()
            bottom.addLine(to: CGPoint(x: plot.maxX, y: zeroY))
            bottom.closeSubpath()

            ctx.fill(top, with: .color(.green.opacity(0.18)))
            ctx.fill(bottom, with: .color(.red.opacity(0.18)))

            // Main payoff line
            var line = Path()
            for i in 0...steps {
                let x = xR.lowerBound + (xR.upperBound - xR.lowerBound) * Double(i) / Double(steps)
                let point = CGPoint(x: px(x), y: py(payoff(at: x)))
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            ctx.stroke(line, with: .color(side == .call ? .green : .red),
                       style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

            // Strike marker
            var strikeLine = Path()
            strikeLine.move(to: CGPoint(x: px(strike), y: plot.minY))
            strikeLine.addLine(to: CGPoint(x: px(strike), y: plot.maxY))
            ctx.stroke(strikeLine, with: .color(.orange.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Break-even marker
            if breakEven >= xR.lowerBound && breakEven <= xR.upperBound {
                var beLine = Path()
                beLine.move(to: CGPoint(x: px(breakEven), y: plot.minY))
                beLine.addLine(to: CGPoint(x: px(breakEven), y: plot.maxY))
                ctx.stroke(beLine, with: .color(.blue.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            // Y-axis labels: 0 and premium loss
            ctx.draw(Text("0").font(.caption2).foregroundColor(.secondary),
                     at: CGPoint(x: plot.minX - 12, y: zeroY))
            ctx.draw(Text("-\(Int(premium))").font(.caption2).foregroundColor(.red),
                     at: CGPoint(x: plot.minX - 14, y: py(-premium)))

            // X-axis labels
            ctx.draw(Text("$\(Int(xR.lowerBound))M").font(.caption2).foregroundColor(.secondary),
                     at: CGPoint(x: plot.minX + 10, y: plot.maxY + 12))
            ctx.draw(Text("Strike $\(Int(strike))M").font(.caption2).foregroundColor(.orange),
                     at: CGPoint(x: px(strike), y: plot.maxY + 12))
            ctx.draw(Text("$\(Int(xR.upperBound))M").font(.caption2).foregroundColor(.secondary),
                     at: CGPoint(x: plot.maxX - 14, y: plot.maxY + 12))
        }
        .frame(height: 180)
        .clampDynamicType(.accessibility1)
        .accessibleChart("Payoff diagram for a \(side.display) at strike $\(Int(strike))M with premium \(String(format: "%.2f", premium)). Break-even at $\(String(format: "%.1f", breakEven))M.")
    }
}
