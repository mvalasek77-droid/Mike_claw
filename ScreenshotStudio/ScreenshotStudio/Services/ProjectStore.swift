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
        if let decoded = try? decoder.decode([ScreenshotProject].self, from: data) {
            projects = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: Workspace.projectsFile, options: .atomic)
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

    func delete(_ project: ScreenshotProject) {
        // Clean up the project's source images so we don't leak disk.
        for slide in project.slides { ImageStore.delete(slide.imageFile) }
        projects.removeAll { $0.id == project.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets { delete(projects[index]) }
    }
}
