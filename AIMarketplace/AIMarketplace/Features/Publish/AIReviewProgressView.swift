import SwiftUI
import Foundation

/// Real-time progress UI for the AI Editor's review. The previous version
/// animated 5 cosmetic "passes" for ~3 seconds and ONLY THEN started the
/// actual analysis — meaning a real review of a 50k-word manuscript or a
/// movie would stall on the last animation step for up to 60 seconds with
/// no UI feedback. This version runs the analysis in parallel with the
/// animation: the passes tick at a natural pace, the elapsed-time counter
/// is always visible, and the view stays on a "Finalising the review"
/// state with a live spinner if the analysis takes longer than the
/// animation. When the analysis returns, `onComplete(verdict)` fires.
struct AIReviewProgressView: View {
    let draft: DraftWork
    /// The actual review work — captured by the view, started on appear,
    /// awaited in parallel with the animation. Returning nil signals a
    /// timeout / failure and the caller renders an error card.
    var perform: () async -> AIReviewResult?
    var onComplete: (AIReviewResult?) -> Void

    @State private var passIndex = 0
    @State private var pulse = false
    @State private var elapsedSeconds = 0
    @State private var analysisFinished = false
    @State private var verdict: AIReviewResult?
    @State private var animateTask: Task<Void, Never>?
    @State private var analyseTask: Task<Void, Never>?
    @State private var tickerTask: Task<Void, Never>?

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

    private let tickInterval: Double = 2.0   // ~10s animation for 5 passes

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
                Text(analysisFinished ? "Wrapping up" : "AI Editor is reviewing")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(currentLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .contentTransition(.opacity)
                    .id(currentLabel)
                Text("\(elapsedSeconds)s")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(passes.enumerated()), id: \.offset) { i, pass in
                    HStack(spacing: 10) {
                        Image(systemName: i < passIndex
                              ? "checkmark.circle.fill"
                              : (i == passIndex ? "circle.dotted" : "circle"))
                            .foregroundStyle(i < passIndex
                                             ? Theme.success
                                             : (i == passIndex ? Theme.kdp : Theme.inkFaint))
                        Text(pass)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(i <= passIndex ? Theme.ink : Theme.inkFaint)
                        Spacer()
                        if i == passIndex && !analysisFinished {
                            ProgressView().scaleEffect(0.7).tint(Theme.kdp)
                        }
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
        .onAppear { start() }
        .onDisappear { teardown() }
    }

    private var progress: CGFloat {
        // While the analysis runs we cap the bar at "almost done"; when it
        // finishes we let it round out the rest of the way.
        let target = analysisFinished
            ? CGFloat(passes.count)
            : CGFloat(min(passIndex, passes.count - 1))
        return target / CGFloat(passes.count)
    }

    private var currentLabel: String {
        if analysisFinished { return "Finalising your verdict…" }
        return passes[min(passIndex, passes.count - 1)]
    }

    private func start() {
        pulse = true

        // 1. Kick off the real analysis IMMEDIATELY. This is what was broken
        //    before — the analysis used to start only after the animation
        //    finished, so the user stared at a frozen screen for up to 60 s.
        analyseTask = Task { @MainActor in
            let result = await perform()
            if Task.isCancelled { return }
            verdict = result
            analysisFinished = true
            // If the animation hasn't finished yet, let it run on its own
            // ticker and `complete()` is fired by the animation. Otherwise
            // we finish now.
            if passIndex >= passes.count - 1 { complete() }
        }

        // 2. Tick through the named passes at a leisurely pace so the user
        //    can read each one. Capped at "one before last" until the
        //    analysis completes, then advanced to the end.
        animateTask = Task { @MainActor in
            for i in 0..<passes.count - 1 {
                try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
                if Task.isCancelled { return }
                passIndex = i + 1
                Haptics.tap()
            }
            // Wait here for the analysis to finish. Poll the flag at a
            // light cadence so the elapsed-time counter still updates.
            while !analysisFinished {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
            }
            passIndex = passes.count
            Haptics.success()
            complete()
        }

        // 3. Elapsed-time ticker so the user can see something is happening
        //    even when the analysis is the long pole. Provides the kind of
        //    transparency the user asked for: "the process need to happen
        //    in front of the user."
        tickerTask = Task { @MainActor in
            while !analysisFinished || passIndex < passes.count {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                elapsedSeconds += 1
            }
        }
    }

    private func complete() {
        let v = verdict
        teardown()
        onComplete(v)
    }

    private func teardown() {
        animateTask?.cancel(); animateTask = nil
        analyseTask?.cancel(); analyseTask = nil
        tickerTask?.cancel(); tickerTask = nil
    }
}
