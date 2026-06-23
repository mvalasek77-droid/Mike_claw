import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Picks a single video from the photo library (out-of-process, no full
/// library access) and hands back a stable file URL we own. The system-
/// provided URL is temporary, so we copy it into our temp directory before the
/// representation is reclaimed.
struct VideoPicker: UIViewControllerRepresentable {
    var onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: (URL?) -> Void
        init(onComplete: @escaping (URL?) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                onComplete(nil)
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else {
                    DispatchQueue.main.async { self.onComplete(nil) }
                    return
                }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ascpreview-\(UUID().uuidString).mov")
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: url, to: dest)
                    DispatchQueue.main.async { self.onComplete(dest) }
                } catch {
                    DispatchQueue.main.async { self.onComplete(nil) }
                }
            }
        }
    }
}
