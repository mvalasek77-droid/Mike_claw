import SwiftUI

/// The single source of truth for the user's saved screenshot sets.
///
/// Projects are persisted as one JSON document; source images live alongside
/// in the workspace's image directory. Writes are debounced-free but cheap
/// (a handful of small documents), and every mutation funnels through here so
/// the UI and disk never drift apart.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ScreenshotProject] = []

    init(loadFromDisk: Bool = true) {
        if loadFromDisk { load() }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Workspace.projectsFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([ScreenshotProject].self, from: data)
            projects = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            // Don't silently drop the user's library — record it so we can see
            // exactly which document failed to decode.
            BugLog.error("ProjectStore", "Couldn't load saved sets: \(error.localizedDescription)")
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(projects)
            try data.write(to: Workspace.projectsFile, options: .atomic)
        } catch {
            BugLog.error("ProjectStore", "Couldn't save your library: \(error.localizedDescription)")
        }
    }

    // MARK: Mutations

    func project(id: UUID) -> ScreenshotProject? {
        projects.first { $0.id == id }
    }

    @discardableResult
    func create(name: String = "Untitled Set") -> ScreenshotProject {
        var project = ScreenshotProject.newProject(name: name)
        project.style.caption.text = "Built for the moment"
        // Start punchy: a clean status bar and a tasteful color "pop" are on by
        // default, since that's the look App Store screenshots want.
        if let pop = EnhancePreset.all.first(where: { $0.id == "pop" }) {
            project.style.adjustments = pop.adjustments
        }
        projects.insert(project, at: 0)
        persist()
        return project
    }

    func upsert(_ project: ScreenshotProject) {
        var updated = project
        updated.modifiedAt = Date()
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = updated
        } else {
            projects.insert(updated, at: 0)
        }
        projects.sort { $0.modifiedAt > $1.modifiedAt }
        persist()
    }

    /// Duplicate a set into an independent copy — each slide gets its own image
    /// file so editing or deleting one set never affects the other.
    @discardableResult
    func duplicate(_ project: ScreenshotProject) -> ScreenshotProject {
        var copy = project
        copy.id = UUID()
        copy.name = Self.duplicateName(for: project.name, existing: projects.map(\.name))
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        copy.slides = project.slides.map { slide in
            var s = slide
            s.id = UUID()
            if let file = ImageStore.copy(slide.imageFile) { s.imageFile = file }
            return s
        }
        // A photo backdrop is also a file — give the copy its own.
        if let bgFile = copy.style.background.imageFile, let newBg = ImageStore.copy(bgFile) {
            copy.style.background.imageFile = newBg
        }
        projects.insert(copy, at: 0)
        projects.sort { $0.modifiedAt > $1.modifiedAt }
        persist()
        return copy
    }

    private static func duplicateName(for base: String, existing: [String]) -> String {
        let candidate = "\(base) copy"
        if !existing.contains(candidate) { return candidate }
        var n = 2
        while existing.contains("\(candidate) \(n)") { n += 1 }
        return "\(candidate) \(n)"
    }

    func delete(_ project: ScreenshotProject) {
        // Clean up the project's source images so we don't leak disk.
        for slide in project.slides { ImageStore.delete(slide.imageFile) }
        if let bgFile = project.style.background.imageFile { ImageStore.delete(bgFile) }
        projects.removeAll { $0.id == project.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        // Resolve to concrete projects first: deleting mutates `projects`, so
        // the offsets would otherwise go stale and risk an out-of-bounds access.
        let targets = offsets.map { projects[$0] }
        for project in targets { delete(project) }
    }
}
