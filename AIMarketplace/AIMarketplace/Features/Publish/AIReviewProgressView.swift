import SwiftUI
import Foundation

/// Progress UI for the AI Editor's review. The labels here describe the
/// real on-device passes that `ReviewPipeline` runs — text via
/// `NaturalLanguage`, audio via `AVAudioFile` PCM reads, video via `AVAsset`
/// track loads, cover art via perceptual hashing. We do NOT claim to be doing
/// passes the pipeline doesn't actually perform.
struct AIReviewProgressView: View {
    let draft: DraftWork
    var onComplete: () -> Void

    @State private var passIndex = 0
    @State private var pulse = false

    private var passes: [String] {
        switch draft.type {
        case .novel: return [
            "Reading manuscript bytes",
            "Measuring lexical diversity & sentence variance",
            "Detecting language and filler patterns",
            "Embedding against the catalogue for originality",
            "Fingerprinting cover art"
        ]
        case .music: return [
            "Decoding audio file",
            "Sampling PCM peaks / RMS / dynamic range",
            "Checking for silence and clipping",
            "Comparing covers against the catalogue",
            "Scoring against the 85% commercial floor"
        ]
        case .movie: return [
            "Loading video tracks",
            "Reading resolution, frame rate and bitrate",
            "Confirming the asset is playable",
            "Fingerprinting poster art",
            "Scoring against the 85% commercial floor"
        ]
        }
    }

    private let tickInterval: Double = 0.62

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
                    .animation(.easeInOut(duration: tickInterval), value: passIndex)
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
            Text("Running on device — your file never leaves your phone.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 30)
        }
        .onAppear {
            pulse = true
            advanceAsync()
        }
        .onDisappear {
            reviewTask?.cancel()
        }
    }

    private var progress: CGFloat {
        CGFloat(min(passIndex, passes.count)) / CGFloat(passes.count)
    }

    /// Cancels automatically when the view disappears;
    /// no risk of firing after dismissal.
    @State private var reviewTask: Task<Void, Never>?

    private func advanceAsync() {
        reviewTask = Task { @MainActor in
            for i in 0..<passes.count {
                try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                passIndex = i + 1
                Haptics.tap()
            }
            Haptics.success()
            onComplete()
        }
    }
}
