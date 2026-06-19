import SwiftUI

/// The character bible: profiles and voice notes. Voice notes feed the AI
/// "Check Character Voice" tool, and the list auto-suggests any character
/// already cued in the script that isn't profiled yet.
struct CharacterBibleView: View {
    @Binding var screenplay: Screenplay
    @State private var editing: CharacterProfile?

    private var unprofiled: [String] {
        let profiled = Set(screenplay.characters.map { $0.name.uppercased() })
        return screenplay.characterNames.filter { !profiled.contains($0.uppercased()) }
    }

    var body: some View {
        List {
            if !unprofiled.isEmpty {
                Section("In the script, not yet profiled") {
                    ForEach(unprofiled, id: \.self) { name in
                        Button {
                            editing = CharacterProfile(name: name)
                        } label: {
                            Label(name, systemImage: "plus.circle")
                                .foregroundStyle(Palette.accent)
                        }
                    }
                }
            }

            Section("Characters") {
                if screenplay.characters.isEmpty {
                    Text("No profiles yet.").foregroundStyle(Palette.secondaryText)
                }
                ForEach(screenplay.characters) { profile in
                    Button {
                        editing = profile
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.headline).foregroundStyle(Palette.primaryText)
                            if !profile.role.isEmpty {
                                Text(profile.role).font(.caption).foregroundStyle(Palette.secondaryText)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    screenplay.characters.remove(atOffsets: offsets)
                }
            }
        }
        .navigationTitle("Character Bible")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = CharacterProfile(name: "") } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { profile in
            CharacterEditorSheet(profile: profile) { updated in
                if let idx = screenplay.characters.firstIndex(where: { $0.id == updated.id }) {
                    screenplay.characters[idx] = updated
                } else {
                    screenplay.characters.append(updated)
                }
            }
        }
    }
}

struct CharacterEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: CharacterProfile
    var onSave: (CharacterProfile) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $profile.name)
                    TextField("Role (Protagonist, Antagonist…)", text: $profile.role)
                    TextField("Age", text: $profile.age)
                }
                Section("Profile") {
                    TextField("Description", text: $profile.description, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Goal / want", text: $profile.goal, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    TextField("Vocabulary, rhythm, verbal tics…", text: $profile.voiceNotes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Voice notes")
                } footer: {
                    Text("Used by the AI to keep this character's dialogue on-voice.")
                }
            }
            .navigationTitle(profile.name.isEmpty ? "New Character" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            onSave(profile)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
