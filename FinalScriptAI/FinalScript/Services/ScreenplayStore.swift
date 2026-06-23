import Foundation
import Combine

/// Owns every screenplay and persists them as JSON in the app's Documents
/// directory. One file per script so a large library doesn't rewrite
/// everything on each keystroke. Autosave is debounced by the editor.
@MainActor
final class ScreenplayStore: ObservableObject {
    @Published private(set) var screenplays: [Screenplay] = []

    private let directory: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = docs.appendingPathComponent("Screenplays", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Loading

    private func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: nil)) ?? []
        let jsonURLs = urls.filter { $0.pathExtension == "json" }
        var loaded: [Screenplay] = []
        for url in jsonURLs {
            if let data = try? Data(contentsOf: url),
               let screenplay = try? decoder.decode(Screenplay.self, from: data) {
                loaded.append(screenplay)
            }
        }
        // Only seed sample scripts when the directory is genuinely empty — if
        // files exist but failed to decode (corruption / schema change), leave
        // them in place rather than masking them with starter content.
        if loaded.isEmpty && jsonURLs.isEmpty {
            loaded = SampleData.starterLibrary()
            loaded.forEach { persist($0) }
        }
        screenplays = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - CRUD

    func screenplay(id: UUID) -> Screenplay? {
        screenplays.first { $0.id == id }
    }

    @discardableResult
    func create(title: String, template: StructureTemplate? = nil) -> Screenplay {
        var new = Screenplay(title: title)
        new.titlePage.title = title
        if let template {
            new.beats = template.makeBeats()
        }
        new.elements = [ScreenplayElement(type: .sceneHeading, text: "INT. — DAY")]
        screenplays.insert(new, at: 0)
        persist(new)
        return new
    }

    func save(_ screenplay: Screenplay) {
        var updated = screenplay
        updated.modifiedAt = .now
        if let idx = screenplays.firstIndex(where: { $0.id == updated.id }) {
            screenplays[idx] = updated
        } else {
            screenplays.insert(updated, at: 0)
        }
        screenplays.sort { $0.modifiedAt > $1.modifiedAt }
        persist(updated)
    }

    func delete(_ screenplay: Screenplay) {
        screenplays.removeAll { $0.id == screenplay.id }
        try? FileManager.default.removeItem(at: fileURL(for: screenplay.id))
    }

    func duplicate(_ screenplay: Screenplay) {
        let copy = Screenplay(title: screenplay.title + " (Copy)",
                          titlePage: screenplay.titlePage,
                          elements: screenplay.elements,
                          beats: screenplay.beats,
                          characters: screenplay.characters,
                          revisions: screenplay.revisions,
                          logline: screenplay.logline,
                          genre: screenplay.genre)
        save(copy)
    }

    // MARK: - Import

    @discardableResult
    func importFountain(_ text: String, title: String) -> Screenplay {
        let (titlePage, elements) = FountainParser.parseDocument(text)
        var new = Screenplay(title: title)
        new.titlePage.title = title
        new.elements = elements
        if var titlePage {
            if titlePage.title.isEmpty { titlePage.title = title }
            new.titlePage = titlePage
        }
        save(new)
        return new
    }

    // MARK: - Disk

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func persist(_ screenplay: Screenplay) {
        guard let data = try? encoder.encode(screenplay) else { return }
        try? data.write(to: fileURL(for: screenplay.id), options: .atomic)
    }
}
