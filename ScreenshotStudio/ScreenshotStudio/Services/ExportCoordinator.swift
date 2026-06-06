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

    /// Render the chosen slots and save them to Photos.
    func export(project: ScreenshotProject, sizes: [ASCDeviceSize]) async {
        let slots = sizes.isEmpty ? [project.deviceSize] : sizes
        let total = slots.count * max(project.slides.count, 0)
        guard total > 0 else {
            phase = .failed("Add at least one screenshot before exporting.")
            Haptics.error()
            return
        }

        phase = .rendering(done: 0, total: total)
        Haptics.ramp()

        var images: [UIImage] = []
        images.reserveCapacity(total)
        var done = 0

        for slot in slots {
            let canvasSize = slot.pixelSize(for: project.orientation)
            for slide in project.slides {
                let source = ImageStore.load(slide.imageFile)
                if let rendered = ScreenshotRenderer.render(
                    canvasSize: canvasSize,
                    style: project.style,
                    image: source,
                    captionText: project.captionText(for: slide)
                ) {
                    images.append(rendered)
                }
                done += 1
                phase = .rendering(done: done, total: total)
                // Yield so the progress meter animates smoothly instead of
                // freezing the run loop on big batches.
                await Task.yield()
            }
        }

        phase = .saving
        do {
            try await PhotoExporter.save(images)
            phase = .finished(count: images.count)
            Haptics.success()
        } catch {
            phase = .failed(error.localizedDescription)
            Haptics.error()
        }
    }
}
