import SwiftUI
import Foundation

/// Theatrical "AI Editor is reading your work" animation shown while the
/// verdict is computed. Cycles through the evaluation passes, then signals
/// completion to the parent.
struct AIReviewProgressView: View {
    let draft: DraftWork
    var onComplete: () -> Void

    @State private var passIndex = 0
    @State private var pulse = false

    private var passes: [String] {
        switch draft.type {
        case .novel: return ["Ingesting manuscript", "Assessing narrative craft", "Checking originality", "Scoring prose & polish", "Weighing market fit"]
        case .music: return ["Decoding master", "Analysing production", "Assessing composition", "Checking originality", "Scoring replay value"]
        case .movie: return ["Ingesting film", "Reviewing cinematography", "Assessing story & pacing", "Checking sound design", "Weighing market fit"]
        }
    }

    private let tickEvery = 0.62

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Theme.kdp.opacity(0.18), lineWidth: 10)
                    .frame(width: 150, height: 150)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.kdp, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: tickEvery), value: passIndex)
                Image(systemName: "sparkles")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Theme.kdp)
                    .scaleEffect(pulse ? 1.12 : 0.92)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            }

            VStack(spacing: 6) {
                Text("AI Editor is reviewing")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(passes[min(passIndex, passes.count - 1)])
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .contentTransition(.opacity)
                    .id(passIndex)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(passes.enumerated()), id: \.offset) { i, pass in
                    HStack(spacing: 10) {
                        Image(systemName: i < passIndex ? "checkmark.circle.fill" : (i == passIndex ? "circle.dotted" : "circle"))
                            .foregroundStyle(i < passIndex ? Theme.success : (i == passIndex ? Theme.kdp : Theme.inkFaint))
                        Text(pass)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(i <= passIndex ? Theme.ink : Theme.inkFaint)
                        Spacer()
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: Theme.cornerL).fill(.white.opacity(0.05)))
            .screenPadding()

            Spacer()
            Text("The trained AI Editor is scoring against the 85% commercial bar…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 30)
        }
        .onAppear {
            pulse = true
            advance()
        }
    }

    private var progress: CGFloat {
        CGFloat(min(passIndex, passes.count)) / CGFloat(passes.count)
    }

    private func advance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + tickEvery) {
            if passIndex < passes.count {
                Motion.run(.easeInOut(duration: 0.3)) { passIndex += 1 }
                Haptics.tap()
                advance()
            } else {
                Haptics.success()
                onComplete()
            }
        }
    }
}
