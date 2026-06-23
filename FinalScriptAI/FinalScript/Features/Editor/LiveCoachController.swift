import SwiftUI

/// Drives the editor's live coach: as the writer pauses, it sends the scene
/// they're working on to the canon-grounded model and surfaces a few craft
/// notes. Debounced and de-duplicated so it doesn't fire on every keystroke or
/// re-ask about a scene that hasn't changed; advisory, so transient errors are
/// swallowed rather than interrupting the writer.
@MainActor
final class LiveCoachController: ObservableObject {
    @Published var enabled = false
    @Published private(set) var suggestions: [LiveSuggestion] = []
    @Published private(set) var isThinking = false
    /// True when the coach is on but there's no API key to actually call.
    @Published private(set) var needsKey = false

    private var task: Task<Void, Never>?
    private var lastSignature = ""

    /// Minimum scene length (characters) before a note is worth asking for, and
    /// the pause after typing before we call — tuned so the coach feels like it
    /// waits for you to finish a thought.
    private static let minSceneLength = 40
    private static let debounce: UInt64 = 2_200_000_000 // 2.2s

    func analyze(scene: [ScreenplayElement], screenplay: Screenplay,
                 ai: AIService, entitlements: Entitlements) {
        guard enabled, entitlements.isPro else { return }
        guard ai.isConfigured else { needsKey = true; return }
        needsKey = false

        let sceneText = FountainParser.serialize(scene)
        guard sceneText.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minSceneLength else { return }
        let signature = String(sceneText.hashValue)
        guard signature != lastSignature else { return }

        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounce)
            guard !Task.isCancelled, enabled else { return }
            lastSignature = signature
            isThinking = true
            defer { isThinking = false }
            do {
                let result = try await ai.liveCoach(scene: sceneText, screenplay: screenplay)
                guard !Task.isCancelled, enabled else { return }
                suggestions = result
            } catch {
                // Advisory feature — stay quiet on a failed live call.
                guard !Task.isCancelled else { return }
                suggestions = []
            }
        }
    }

    func turnOff() {
        task?.cancel()
        enabled = false
        suggestions = []
        isThinking = false
        needsKey = false
        lastSignature = ""
    }
}
