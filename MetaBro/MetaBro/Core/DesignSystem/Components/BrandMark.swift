import SwiftUI

/// The MetaBro monogram drawn in code (the "M" whose center is an upvote
/// chevron), so the brand renders without bundling the asset everywhere.
struct BrandMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(
                    colors: [Tokens.Color.accent, Color(red: 0.23, green: 0.25, blue: 0.78)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            MShape()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.10,
                                                   lineCap: .round, lineJoin: .round))
                .padding(size * 0.24)
            ChevronShape()
                .stroke(Tokens.Color.respect, style: StrokeStyle(lineWidth: size * 0.045,
                                                                 lineCap: .round, lineJoin: .round))
                .padding(size * 0.24)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct MShape: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.06, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.06, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            return p
        }
    }

    private struct ChevronShape: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX + r.width * 0.28, y: r.midY + r.height * 0.02))
            p.addLine(to: CGPoint(x: r.midX, y: r.midY - r.height * 0.16))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.28, y: r.midY + r.height * 0.02))
            return p
        }
    }
}

/// Wordmark + slogan, used on the loading screen and as a footer.
struct SloganView: View {
    var showsMark = true

    var body: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            if showsMark { BrandMark(size: 64) }
            Text(Brand.name)
                .font(Tokens.Typography.title)
                .foregroundStyle(Tokens.Color.textPrimary)
            Text(Brand.slogan)
                .font(Tokens.Typography.caption.weight(.semibold))
                .foregroundStyle(Tokens.Color.respect)
                .textCase(.uppercase)
                .kerning(1.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Brand.name). \(Brand.slogan)")
    }
}
