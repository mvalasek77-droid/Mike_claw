import SwiftUI

/// A bureau-style credit report: each factor with its signed points and the
/// floor's written comment. The rows always sum to the headline score (minus
/// the 300 base), so the report reads as the score's receipt.
struct CreditReportCard: View {
    let title: String
    let factors: [CreditFactor]
    var tint: Color = Theme.gold

    var body: some View {
        GlassCard(title: title, icon: "doc.text.magnifyingglass", tint: tint) {
            VStack(spacing: 0) {
                ForEach(Array(factors.enumerated()), id: \.element.id) { i, factor in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: factor.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(pointColor(factor.points))
                                .frame(width: 22)
                            Text(factor.name)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(factor.points >= 0 ? "+\(factor.points)" : "\(factor.points)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(pointColor(factor.points))
                        }
                        Text(factor.comment)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 30)
                    }
                    .padding(.vertical, 9)
                    if i < factors.count - 1 { Divider().overlay(Theme.hairline) }
                }
                Divider().overlay(Theme.hairline)
                HStack {
                    Text("Base 300 + adjustments")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                    Spacer()
                    Text("= \(min(900, max(300, 300 + factors.reduce(0) { $0 + $1.points })))")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                .padding(.top, 9)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(factors.count) factors")
    }

    private func pointColor(_ points: Int) -> Color {
        if points > 0 { return Theme.success }
        if points < 0 { return Theme.danger }
        return Theme.inkFaint
    }
}
