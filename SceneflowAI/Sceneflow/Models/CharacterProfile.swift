import Foundation

/// A character "bible" entry. Beyond a name it captures the voice notes the AI
/// uses to keep dialogue consistent and a writer uses to stay in character.
struct CharacterProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var role: String          // Protagonist, Antagonist, Supporting…
    var description: String
    /// Free-form voice guidance: vocabulary, rhythm, verbal tics. Fed to the
    /// AI voice-consistency tool.
    var voiceNotes: String
    var age: String
    var goal: String

    init(id: UUID = UUID(),
         name: String,
         role: String = "",
         description: String = "",
         voiceNotes: String = "",
         age: String = "",
         goal: String = "") {
        self.id = id
        self.name = name
        self.role = role
        self.description = description
        self.voiceNotes = voiceNotes
        self.age = age
        self.goal = goal
    }
}
