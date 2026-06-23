import PhotosUI
import SwiftUI

/// A thin SwiftUI wrapper over `PHPickerViewController` that returns the
/// picked images as `UIImage`s. We use PHPicker (not the legacy image picker)
/// so the app never needs full photo-library access — the system handles
/// selection out-of-process, which is the privacy-forward, App-Review-safe
/// path.
struct PhotoPicker: UIViewControllerRepresentable {
    var selectionLimit: Int = 0 // 0 == unlimited
    var onComplete: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .current
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: ([UIImage]) -> Void
        init(onComplete: @escaping ([UIImage]) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { onComplete([]); return }

            let group = DispatchGroup()
            // Preserve the user's selection order.
            var images = [UIImage?](repeating: nil, count: results.count)

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage { images[index] = image }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.onComplete(images.compactMap { $0 })
            }
        }
    }
}

/// Standard share sheet for handing rendered images to AirDrop, Files, etc.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // On iPad UIKit presents this as a popover and *crashes* if no anchor
        // is set. Anchor it to its own view (centred, no arrow) so it presents
        // safely on every device.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX,
                                        y: controller.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
