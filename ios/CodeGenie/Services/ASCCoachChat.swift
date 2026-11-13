import Foundation
import SwiftUI

/// Conversation state for the App Store Connect coach.
///
/// `ASCCoach` (the rules engine) and this are deliberately separate
/// things. The rules engine is deterministic and always right about
/// Apple's fixed limits, so it drives the gates and the step
/// walkthroughs. This is the part you can talk to when you fall off
/// the happy path — a rejection email, a build that never appeared, a
/// word nobody defined.
///
/// The coach never gates anything. If the backend is unreachable the
/// submission still works exactly as before; the user just loses the
/// ability to ask questions, and is told so plainly.
@MainActor
final class ASCCoachChat: ObservableObject {

    struct Turn: Identifiable, Equatable {
        enum Role: String { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
    }

    @Published private(set) var turns: [Turn] = []
    @Published private(set) var isThinking = false
    @Published private(set) var lastError: String?
    @Published private(set) var suggestions: [String] = []

    private let client: SwarmClient

    init(client: SwarmClient = SwarmClient()) {
        self.client = client
    }

    /// Seed the suggestion chips for a step. A blank chat box is
    /// intimidating, and a first-timer does not know what they are
    /// even allowed to ask.
    func prepare(for step: ASCStep?) {
        suggestions = Self.localSuggestions(for: step?.number)
    }

    func ask(
        _ question: String,
        step: ASCStep?,
        appName: String,
        bundleID: String,
        completed: Set<Int>,
        blockingIssues: [String],
        outstandingItems: [String]
    ) async {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isThinking else { return }

        turns.append(Turn(role: .user, text: clean))
        isThinking = true
        lastError = nil
        defer { isThinking = false }

        // Only completed turns go back as history; the in-flight
        // question is sent separately so a retry can't double it.
        let history = turns.dropLast().map {
            ["role": $0.role.rawValue, "content": $0.text]
        }

        var body: [String: Any] = [
            "question": clean,
            "history": Array(history),
            "app_name": appName,
            "bundle_id": bundleID,
            "completed_steps": completed.sorted(),
            "blocking_issues": blockingIssues,
            "outstanding_items": outstandingItems,
        ]
        if let step {
            body["step_number"] = step.number
            body["step_title"] = step.title
        }

        do {
            let response = try await client.ascCoach(body: body)
            let text = (response["answer"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                lastError = "The coach didn't have an answer for that. Try rewording it."
                Haptics.warning()
            } else {
                turns.append(Turn(role: .assistant, text: text))
                Haptics.success()
            }
            if let fresh = response["suggested"] as? [String], !fresh.isEmpty {
                suggestions = fresh
            }
        } catch {
            lastError = "Couldn't reach the coach. Your submission is unaffected — every step still works without it."
            Haptics.error()
        }
    }

    func clear() {
        turns.removeAll()
        lastError = nil
    }

    // MARK: - Offline suggestions
    //
    // Mirrors the server's list so the chips are populated the instant
    // the sheet opens, before any network round-trip. The server's
    // list wins once a real answer comes back.

    private static func localSuggestions(for step: Int?) -> [String] {
        let general = "What's the difference between TestFlight and the App Store?"
        guard let step else {
            return [general, "How much does this cost?", "How long will the whole thing take?"]
        }
        let perStep: [Int: [String]] = [
            1:  ["My Mac doesn't show up in AirDrop", "Can I use iCloud Drive instead?", "Do I really need a Mac?"],
            2:  ["Which file do I open in Xcode?", "Xcode is asking to install components", "How do I sign in to Xcode?"],
            3:  ["It only shows Personal Team", "What is a bundle identifier?", "Xcode says failed to register bundle identifier"],
            4:  ["Xcode says Build Failed", "The simulator is taking forever", "How do I use the simulator?"],
            5:  ["My bundle ID isn't in the dropdown", "What should I put for SKU?", "It says I don't have permission"],
            6:  ["Archive is greyed out", "No suitable application records were found", "It says the bundle version must be higher"],
            7:  ["How long does processing take?", "My build never showed up", "What is Missing Compliance?"],
            8:  ["How do I get the app on my phone?", "I never got the invite email"],
            9:  ["Why do I have to test it?", "A test failed — what now?", "What counts as it working?"],
            10: ["Internal vs external testers?", "How do I share a public link?", "What should I ask my tester to do?"],
            11: ["Is my app ready to submit?", "What happens when I rebuild?"],
            12: ["What are Apple's icon rules?", "My icon was rejected for transparency"],
            13: ["What screenshots do I need?", "How do I take a screenshot in the simulator?"],
            14: ["How do keywords work?", "What should I write in the description?", "What can I use as a support URL?"],
            15: ["Do I collect data if everything stays on the phone?", "Do I need a privacy policy?"],
            16: ["How do I answer the age rating questions?", "What counts as unrestricted web access?"],
            17: ["Should my app be free?", "Can I change the price later?"],
            18: ["What should I write in the review notes?", "Do I need to give Apple a test account?"],
            19: ["My build isn't in the list", "What is export compliance?", "Manual or automatic release?"],
            20: ["What happens after I submit?", "What does Add for Review do?"],
            21: ["How long does review take?", "Can I speed up the review?", "Can I change something while I wait?"],
            22: ["What does this rejection mean?", "Do I need to upload a new build?", "How do I reply to App Review?", "Can I appeal?"],
            23: ["Why can't I find my app in search?", "How do I ship an update?"],
        ]
        return (perStep[step] ?? []) + [general]
    }
}
