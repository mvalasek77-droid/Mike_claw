import SwiftUI

/// The Library tab: saved Skills as glass cards, plus one-off Notes that
/// failed the Taste Test.
struct LibraryView: View {
    @EnvironmentObject private var store: SkillStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if store.skills.isEmpty && store.notes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(title: "Skills", systemImage: "sparkles")
                            ForEach(store.skills) { skill in
                                NavigationLink(value: skill.id) {
                                    SkillCardView(skill: skill)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(skill.title), used \(skill.timesUsed) times\(skill.recentlyEvolved ? ", recently evolved" : "")")
                                .accessibilityHint("Opens the Skill's details")
                            }

                            if !store.notes.isEmpty {
                                SectionHeader(title: "One-off notes", systemImage: "note.text")
                                ForEach(store.notes) { note in
                                    noteCard(note)
                                }
                            }
                        }
                        .padding()
                        .accentPulse(on: store.evolutionPulse)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: UUID.self) { skillID in
                SkillDetailView(skillID: skillID)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nothing here yet",
            systemImage: "books.vertical",
            description: Text("Run a coach session from the Coach tab — Skills that pass the Taste Test land here.")
        )
    }

    private func noteCard(_ note: OneOffNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button {
                    store.deleteNote(note)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityLabel("Delete note \(note.title)")
            }
            Text(note.body)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(3)
            Text(note.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .glassCard()
    }
}
