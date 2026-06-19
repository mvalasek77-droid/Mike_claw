import SwiftUI

struct ProjectsLibraryView: View {
    @EnvironmentObject private var store: ScreenplayStore
    @State private var showingNew = false
    @State private var searchText = ""

    private var filtered: [Screenplay] {
        guard !searchText.isEmpty else { return store.screenplays }
        return store.screenplays.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.logline.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground().ignoresSafeArea()

                ScrollView {
                    if store.screenplays.isEmpty {
                        EmptyStateView(symbol: "doc.badge.plus",
                                       title: "No projects yet",
                                       message: "Create your first screenplay to start writing.")
                        .padding(.top, 80)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filtered) { screenplay in
                                NavigationLink(value: screenplay.id) {
                                    ProjectCard(screenplay: screenplay)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        store.duplicate(screenplay)
                                    } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                                    Button(role: .destructive) {
                                        store.delete(screenplay)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search projects")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showingNew = true
                    } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ScreenplayWorkspaceView(screenplayID: id)
            }
            .sheet(isPresented: $showingNew) {
                NewProjectSheet()
            }
        }
    }
}

struct ProjectCard: View {
    let screenplay: Screenplay

    private var analytics: ScriptAnalytics { ScriptAnalytics(screenplay) }

    var body: some View {
        GlassCard(tier: .raised, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Palette.marqueeGradient)
                        .frame(height: 96)
                        .overlay(
                            Image(systemName: "film.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white.opacity(0.35))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(10)
                        )
                    Text(screenplay.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(10)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !screenplay.genre.isEmpty {
                        Pill(text: screenplay.genre)
                    }
                    HStack(spacing: 10) {
                        Label(String(format: "%.0f pg", analytics.pageCount),
                              systemImage: "doc")
                        Label(analytics.runtime, systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                }
                .padding(12)
            }
        }
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject private var store: ScreenplayStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedTemplate: StructureTemplate? = StructureLibrary.threeAct

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Untitled", text: $title)
                }
                Section("Structure template") {
                    ForEach(StructureLibrary.all) { template in
                        Button {
                            selectedTemplate = template
                            Haptics.selection()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).foregroundStyle(Palette.primaryText)
                                    Text(template.blurb)
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                }
                                Spacer()
                                if selectedTemplate?.id == template.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.accent)
                                }
                            }
                        }
                    }
                    Button {
                        selectedTemplate = nil
                        Haptics.selection()
                    } label: {
                        HStack {
                            Text("Blank — no beats").foregroundStyle(Palette.primaryText)
                            Spacer()
                            if selectedTemplate == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = title.trimmingCharacters(in: .whitespaces)
                        store.create(title: name.isEmpty ? "Untitled" : name,
                                     template: selectedTemplate)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
