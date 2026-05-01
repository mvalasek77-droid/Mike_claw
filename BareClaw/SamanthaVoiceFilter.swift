import Foundation

// Compatibility layer while the rest of the app still calls the old APIs.
// The old voice filter system is intentionally removed. Speech now goes
// directly through the companion's base voice profile with no love-stage
// mutation and no text post-processing.

extension VoiceCharacter {
    func withLoveFilter(gender _: CompanionGender, loveStage _: LoveStage) -> VoiceCharacter {
        self
    }
}

@MainActor
extension CompanionVoiceEngine {
    func speakFiltered(_ text: String, companion: CompanionPersonality) {
        speak(text, character: companion.voiceCharacter, context: .love)
    }

    func speakFilteredCurrent(_ text: String) {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        let companion = CompanionPersonality.find(id: id) ?? .luna
        speakFiltered(text, companion: companion)
    }
}
