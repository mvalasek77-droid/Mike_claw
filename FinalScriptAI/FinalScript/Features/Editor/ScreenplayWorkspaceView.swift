import SwiftUI

/// Container for one open screenplay. Owns the working copy, drives autosave,
/// and switches between the editor, board, outline, stats and revisions.
struct ScreenplayWorkspaceView: View {
    let screenplayID: UUID
    @EnvironmentObject private var store: ScreenplayStore

    @State private var screenplay: Screenplay?
    @State private var tab: WorkspaceTab = .editor
    @State private var saveTask: Task<Void, Never>?
    @State private var showExport = false

    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case editor = "Script"
        case board = "Board"
        case outline = "Outline"
        case doctor = "Doctor"
        case stats = "Stats"
        case revisions = "Revisions"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .editor: return "doc.plaintext"
            case .board: return "rectangle.grid.2x2"
            case .outline: return "list.bullet.indent"
            case .doctor: return "stethoscope"
            case .stats: return "chart.bar.xaxis"
            case .revisions: return "paintpalette"
            }
        }
    }

    var body: some View {
        Group {
            if let binding = screenplayBinding {
                content(binding)
            } else {
                EmptyStateView(symbol: "exclamationmark.triangle",
                               title: "Project unavailable",
                               message: "This screenplay could not be loaded.")
            }
        }
        .onAppear { if screenplay == nil { screenplay = store.screenplay(id: screenplayID) } }
    }

    private var screenplayBinding: Binding<Screenplay>? {
        guard screenplay != nil else { return nil }
        return Binding(
            get: { screenplay ?? Screenplay(title: "") },
            set: { newValue in
                screenplay = newValue
                scheduleSave(newValue)
            }
        )
    }

    @ViewBuilder
    private func content(_ binding: Binding<Screenplay>) -> some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(WorkspaceTab.allCases) { t in
                    Label(t.rawValue, systemImage: t.symbol).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            switch tab {
            case .editor: ScreenplayEditorView(screenplay: binding)
            case .board: BeatBoardView(screenplay: binding)
            case .outline: OutlineView(screenplay: binding)
            case .doctor: ScriptDoctorView(screenplay: binding.wrappedValue)
            case .stats: StatisticsView(screenplay: binding.wrappedValue)
            case .revisions: RevisionsView(screenplay: binding)
            }
        }
        .background(AmbientBackground().ignoresSafeArea())
        .navigationTitle(binding.wrappedValue.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink {
                        AIAssistantView(screenplay: binding)
                    } label: { Label("AI tools", systemImage: "sparkles") }
                    Button {
                        showExport = true
                    } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    NavigationLink {
                        TitlePageEditor(screenplay: binding)
                    } label: { Label("Title page", systemImage: "doc.richtext") }
                    NavigationLink {
                        CharacterBibleView(screenplay: binding)
                    } label: { Label("Character bible", systemImage: "person.2") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportSheet(screenplay: binding.wrappedValue)
        }
    }

    private func scheduleSave(_ value: Screenplay) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000) // debounce 0.6s
            guard !Task.isCancelled else { return }
            store.save(value)
        }
    }
}
