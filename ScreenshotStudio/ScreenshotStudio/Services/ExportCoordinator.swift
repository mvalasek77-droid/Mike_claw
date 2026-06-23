import SwiftUI

/// Drives a full export run: render every slide for every selected device
/// slot, then hand the batch to the photo library — all while publishing
/// fine-grained progress so the UI can show a satisfying, honest meter.
@MainActor
final class ExportCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case rendering(done: Int, total: Int)
        case saving
        case finished(count: Int)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// True when the last failure was Photos permission being denied, so the UI
    /// can offer a deep link to Settings.
    @Published private(set) var needsPhotoAccess = false

    var isRunning: Bool {
        switch phase {
        case .rendering, .saving: return true
        default: return false
        }
    }

    var progress: Double {
        switch phase {
        case .rendering(let done, let total):
            return total == 0 ? 0 : Double(done) / Double(total)
        case .saving: return 0.95
        case .finished: return 1
        default: return 0
        }
    }

    func reset() { phase = .idle }

    /// Render the chosen slots (and languages) and save them to Photos.
    func export(project: ScreenshotProject,
                sizes: [ASCDeviceSize],
                languages: [String] = []) async {
        needsPhotoAccess = false
        let slots = sizes.isEmpty ? [project.deviceSize] : sizes
        let langs = languages.isEmpty ? [project.activeLanguage] : languages
        let total = slots.count * langs.count * max(project.slides.count, 0)
        guard total > 0 else {
            BugLog.warning("Export", "Export attempted with nothing to render.")
            phase = .failed("Add at least one screenshot before exporting.")
            Haptics.error()
            return
        }

        phase = .rendering(done: 0, total: total)
        Haptics.ramp()

        // Encode each render to PNG data immediately and drop the decoded
        // bitmap, so peak memory stays at roughly one image instead of holding
        // every full-resolution bitmap (a full iPhone+iPad batch would
        // otherwise pin hundreds of MB and risk an out-of-memory termination).
        var pngs: [Data] = []
        pngs.reserveCapacity(total)
        var done = 0

        for slot in slots {
            let canvasSize = slot.pixelSize(for: project.orientation)
            let layout = slot.statusBarLayout
            for lang in langs {
                for slide in project.slides {
                    autoreleasepool {
                        let source = ImageStore.load(slide.imageFile)
                        if let rendered = ScreenshotRenderer.render(
                            canvasSize: canvasSize,
                            style: project.style,
                            image: source,
                            captionText: project.captionText(for: slide, language: lang),
                            statusBarLayout: layout
                        ), let data = rendered.pngData() {
                            pngs.append(data)
                        }
                    }
                    done += 1
                    phase = .rendering(done: done, total: total)
                    // Yield so the progress meter animates smoothly instead of
                    // freezing the run loop on big batches.
                    await Task.yield()
                }
            }
        }

        guard !pngs.isEmpty else {
            BugLog.error("Export", "Rendering produced no images for \(slots.count) size(s) × \(langs.count) language(s).")
            phase = .failed("The slides couldn't be rendered. Please try again.")
            Haptics.error()
            return
        }

        phase = .saving
        do {
            try await PhotoExporter.save(pngs)
            BugLog.info("Export", "Saved \(pngs.count) screenshot(s) to Photos.")
            phase = .finished(count: pngs.count)
            Haptics.success()
        } catch {
            if let exportError = error as? PhotoExporter.ExportError, case .permissionDenied = exportError {
                needsPhotoAccess = true
            }
            BugLog.error("Export", "Saving to Photos failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            Haptics.error()
        }
    }
}
