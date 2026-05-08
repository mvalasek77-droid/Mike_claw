import SwiftUI
import PhotosUI

// MARK: - CompanionPhotoStore
//
// Saves and loads a user-supplied portrait photo for each companion.
// Photos are written as JPEG to Documents/hermes/photos/<companionId>.jpg
// so they survive app updates and don't bloat UserDefaults.

@MainActor
final class CompanionPhotoStore: ObservableObject {
    static let shared = CompanionPhotoStore()

    // Published so any view observing this redraws when a photo changes.
    @Published private(set) var photoVersion: Int = 0

    private var imageCache: [String: UIImage] = [:]

    private let dir: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes/photos")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private init() {}

    // MARK: - Read

    func photo(for companionId: String) -> UIImage? {
        if let cached = imageCache[companionId] {
            return cached
        }
        let url = photoURL(for: companionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let image = UIImage(data: data)
        imageCache[companionId] = image
        return image
    }

    func hasPhoto(for companionId: String) -> Bool {
        FileManager.default.fileExists(atPath: photoURL(for: companionId).path)
    }

    // MARK: - Write

    func save(_ image: UIImage, for companionId: String) {
        guard let jpeg = image.jpegData(compressionQuality: 0.88) else { return }
        try? jpeg.write(to: photoURL(for: companionId), options: .atomic)
        imageCache[companionId] = image
        photoVersion += 1
    }

    func remove(for companionId: String) {
        try? FileManager.default.removeItem(at: photoURL(for: companionId))
        imageCache[companionId] = nil
        photoVersion += 1
    }

    // MARK: - Private

    private func photoURL(for companionId: String) -> URL {
        dir.appendingPathComponent("\(companionId).jpg")
    }
}

// MARK: - CompanionPhotoPicker
//
// SwiftUI wrapper that shows a PhotosPicker button and writes the selection
// into CompanionPhotoStore. Drop this anywhere you want a "change photo" action.

struct CompanionPhotoPicker: View {
    let companionId: String
    var label: AnyView = AnyView(
        Label("Choose Photo", systemImage: "camera.fill")
    )

    @ObservedObject private var store = CompanionPhotoStore.shared
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pickerItem,
                     matching: .images,
                     photoLibrary: .shared()) {
            label
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await MainActor.run {
                    CompanionPhotoStore.shared.save(image, for: companionId)
                }
            }
        }
    }
}
