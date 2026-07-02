import Foundation
import Combine

/// On-device library. Everything persists as Codable JSON in the app's
/// Documents directory — no account, no server.
@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var skills: [Skill] = []
    @Published private(set) var notes: [OneOffNote] = []
    /// Increments whenever a Skill evolves; views observe it to pulse the accent.
    @Published private(set) var evolutionPulse: Int = 0

    private let skillsURL: URL
    private let notesURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        skillsURL = documents.appendingPathComponent("skills.json")
        notesURL = documents.appendingPathComponent("notes.json")
        load()
        if skills.isEmpty {
            skills = Self.starterSkills()
            persistSkills()
        }
    }

    // MARK: - Mutations

    func add(_ skill: Skill) {
        skills.insert(skill, at: 0)
        persistSkills()
        Haptics.success()
    }

    func add(_ note: OneOffNote) {
        notes.insert(note, at: 0)
        persistNotes()
        Haptics.success()
    }

    func recordUse(of skillID: UUID) {
        guard let index = skills.firstIndex(where: { $0.id == skillID }) else { return }
        skills[index].timesUsed += 1
        persistSkills()
    }

    /// Appends new rules to a Skill with a visible changelog entry.
    /// Skills are never modified silently.
    func evolve(skillID: UUID, newRules: [String], changeSummary: String) {
        guard let index = skills.firstIndex(where: { $0.id == skillID }) else { return }
        let cleaned = newRules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        skills[index].instructions.append(contentsOf: cleaned)
        skills[index].updateDates.append(.now)
        skills[index].lastEvolvedAt = .now
        skills[index].changelog.append(ChangelogEntry(summary: changeSummary))
        persistSkills()
        evolutionPulse += 1
        Haptics.success()
    }

    func deleteNote(_ note: OneOffNote) {
        notes.removeAll { $0.id == note.id }
        persistNotes()
    }

    func skill(withID id: UUID) -> Skill? {
        skills.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        skills = Self.decode([Skill].self, from: skillsURL) ?? []
        notes = Self.decode([OneOffNote].self, from: notesURL) ?? []
    }

    private func persistSkills() { Self.encode(skills, to: skillsURL) }
    private func persistNotes() { Self.encode(notes, to: notesURL) }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence is best-effort; the in-memory library stays authoritative.
        }
    }

    // MARK: - Starter library

    static func starterSkills() -> [Skill] {
        [
            Skill(
                title: "Draft Email",
                summary: "Turns bullet points into a send-ready email in your voice.",
                instructions: [
                    "Ask for the recipient, the relationship, and the single outcome the email should produce.",
                    "Ask for 3-5 bullet points of raw content before writing anything.",
                    "Draft at three lengths: two sentences, one paragraph, full email.",
                    "Match register to the relationship — never more formal than the last email received.",
                    "End with exactly one clear call to action."
                ],
                tools: ["Reference file: past sent emails for tone"],
                isStarter: true
            ),
            Skill(
                title: "Debug This Code",
                summary: "A disciplined debugging loop: reproduce, isolate, fix, verify.",
                instructions: [
                    "Ask for the exact error output and the smallest snippet that reproduces it.",
                    "State a single hypothesis before proposing any change.",
                    "Propose the minimal fix, not a rewrite.",
                    "List what to run to confirm the fix, and what would disprove it.",
                    "Flag any change that could affect behaviour outside the reported bug."
                ],
                tools: ["Script: failing test runner", "Reference file: stack trace"],
                isStarter: true
            ),
            Skill(
                title: "Write PR Description",
                summary: "Summarises a diff into a reviewable pull-request description.",
                instructions: [
                    "Ask for the diff or a list of changed files with one line each.",
                    "Lead with the why: one paragraph on the problem being solved.",
                    "List user-visible changes separately from internal refactors.",
                    "Call out risky areas and what was and wasn't tested.",
                    "Keep the whole description under 200 words."
                ],
                tools: ["Script: git diff --stat"],
                isStarter: true
            ),
            Skill(
                title: "Interview Me",
                summary: "Flips the script: the model asks you questions before answering.",
                instructions: [
                    "Do not produce a deliverable yet.",
                    "Ask 3-5 targeted questions covering goal, audience, acceptance test, and edge cases.",
                    "Ask one question at a time and wait for the answer.",
                    "After the last answer, restate the brief in three sentences and ask for confirmation.",
                    "Only then produce the deliverable."
                ],
                isStarter: true
            ),
            Skill(
                title: "Build A Skill From Our Chat",
                summary: "Distils the current conversation into a reusable Skill.",
                instructions: [
                    "Review the conversation and identify the repeatable task inside it.",
                    "Write a one-line description of when to reach for this Skill.",
                    "Extract the steps that worked into numbered instructions.",
                    "Record the mistakes made along the way as explicit rules to avoid.",
                    "Suggest one tool, script, or reference file that would make it stronger."
                ],
                isStarter: true
            )
        ]
    }
}
