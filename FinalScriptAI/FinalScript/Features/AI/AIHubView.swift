import SwiftUI

/// The "AI Room" tab — a home for AI work across projects. Pick a script to
/// open its full AI toolset, or use the quick logline brainstormer.
struct AIHubView: View {
    @EnvironmentObject private var store: ScreenplayStore
    @EnvironmentObject private var ai: AIService

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GlassCard(tier: .raised) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("AI Room", systemImage: "sparkles")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(Palette.primaryText)
                                Text("Co-write scenes, get coverage, brainstorm beats, and keep every character on-voice — powered by Claude.")
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }

                        SectionHeader("Open a project's AI tools")
                        if store.screenplays.isEmpty {
                            Text("Create a project first.")
                                .font(.subheadline).foregroundStyle(Palette.secondaryText)
                        } else {
                            ForEach(store.screenplays) { screenplay in
                                NavigationLink(value: screenplay.id) {
                                    HStack {
                                        Image(systemName: "film.fill").foregroundStyle(Palette.accent)
                                        Text(screenplay.title).foregroundStyle(Palette.primaryText)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(Palette.secondaryText)
                                    }
                                    .padding(.vertical, 12)
                                }
                                Divider().overlay(Palette.secondaryText.opacity(0.15))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("AI Room")
            .navigationDestination(for: UUID.self) { id in
                ProjectAILoader(screenplayID: id)
            }
        }
    }
}

/// Loads a screenplay into a binding and hands it to the AI panel, persisting
/// edits (e.g. inserted scenes) back to the store.
struct ProjectAILoader: View {
    let screenplayID: UUID
    @EnvironmentObject private var store: ScreenplayStore
    @State private var screenplay: Screenplay?

    var body: some View {
        Group {
            if screenplay != nil {
                AIAssistantView(screenplay: Binding(
                    get: { screenplay ?? Screenplay(title: "") },
                    set: { screenplay = $0; store.save($0) }
                ))
            } else {
                ProgressView()
            }
        }
        .onAppear { screenplay = store.screenplay(id: screenplayID) }
    }
}
