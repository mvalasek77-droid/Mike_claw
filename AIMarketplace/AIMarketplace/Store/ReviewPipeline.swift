import Foundation

/// Builds a `ReviewAnalysis` bundle from a `DraftWork` by actually reading its
/// uploaded bytes (manuscript text / audio file / video file / cover art) and
/// then calls the `AIEditor`. This is where the "real" pipeline lives — every
/// signal the Editor uses traces back to a measurement here.
///
/// Designed to be cheap to call: each public entry point is async so the UI
/// can show progress while files are decoded. The work itself runs on a
/// background queue (`Task.detached`).
enum ReviewPipeline {

    /// Builds an analysis bundle from a draft. Returns nil only if the draft
    /// has no readable content at all — the editor treats that as
    /// "metadata-only" and caps the score.
    static func buildAnalysis(for draft: DraftWork) async -> ReviewAnalysis? {
        await Task.detached(priority: .userInitiated) { () -> ReviewAnalysis? in
            var analysis = ReviewAnalysis()

            // Cover fingerprint — always cheap, always attempt.
            if let coverData = draft.coverImageData {
                analysis.coverFingerprint = ContentAnalysis.fingerprintCover(coverData)
            }

            switch draft.type {
            case .novel:
                if let inMemory = draft.manuscriptText, !inMemory.isEmpty {
                    analysis.manuscriptText = inMemory
                    analysis.text = ContentAnalysis.analyseText(inMemory)
                } else if let url = draft.contentURL {
                    if let raw = ContentAnalysis.readTextFromFile(at: url) {
                        analysis.manuscriptText = raw
                        analysis.text = ContentAnalysis.analyseText(raw)
                    }
                }
            case .music:
                if let url = draft.contentURL {
                    analysis.audio = ContentAnalysis.analyseAudio(at: url)
                } else if draft.isHouseContent,
                          let lyrics = draft.manuscriptText, !lyrics.isEmpty {
                    // Scout-house music: the lyrics + liner notes ARE the
                    // artifact the Editor analyses, since on-device generation
                    // can't produce real audio bytes. The Editor's text pipeline
                    // gates quality the same way it does for a novel manuscript.
                    analysis.manuscriptText = lyrics
                    analysis.text = ContentAnalysis.analyseText(lyrics)
                }
            case .movie:
                if let url = draft.contentURL {
                    analysis.video = await ContentAnalysis.analyseVideo(at: url)
                } else if draft.isHouseContent,
                          let screenplay = draft.manuscriptText, !screenplay.isEmpty {
                    // Scout-house film: the screenplay IS the artifact analysed.
                    analysis.manuscriptText = screenplay
                    analysis.text = ContentAnalysis.analyseText(screenplay)
                }
            }

            // If nothing decoded, return nil so the Editor knows.
            if analysis.text == nil && analysis.audio == nil && analysis.video == nil
                && analysis.coverFingerprint == nil {
                return nil
            }
            return analysis
        }.value
    }

    /// One-shot convenience: build the analysis and score.
    static func review(_ draft: DraftWork, against catalog: [MediaItem]) async -> AIReviewResult {
        let analysis = await buildAnalysis(for: draft)
        return AIEditor.review(draft, against: catalog, analysis: analysis)
    }
}
