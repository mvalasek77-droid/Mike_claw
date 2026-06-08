import Photos
import UIKit

/// Saves rendered screenshots to the user's photo library. When the app has
/// read access we collect them into a dedicated "Screenshot Studio" album so
/// they're easy to find and AirDrop to a Mac for upload to App Store Connect;
/// under strict add-only access (where albums can't be enumerated) we fall back
/// to saving straight to the library so the export still succeeds.
enum PhotoExporter {
    enum ExportError: LocalizedError {
        case permissionDenied
        case nothingToSave
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screenshot Studio needs permission to save to Photos. Enable it in Settings › Privacy › Photos."
            case .nothingToSave:
                return "Those slides couldn't be rendered into images. Please try again."
            case .writeFailed:
                return "The export couldn't be saved. Please try again."
            }
        }
    }

    private static let albumName = "Screenshot Studio"
    /// Local identifier of the album we created, persisted so we can re-use it
    /// across launches even under add-only access (where title search fails).
    private static let albumIDKey = "ScreenshotStudio.albumLocalIdentifier"

    /// Save a batch of images. Throws a clear, catchable error on failure —
    /// never an uncatchable Objective-C exception.
    static func save(_ images: [UIImage]) async throws {
        // Photos raises an *uncatchable* NSException if asked to create an asset
        // from a UIImage with no backing CGImage, so filter those out up front.
        let valid = images.filter { $0.cgImage != nil }
        guard !valid.isEmpty else { throw ExportError.nothingToSave }

        try await ensureAuthorized()

        // The dedicated album is a nicety, not a requirement: if we can't get
        // one (e.g. strict add-only access can't enumerate collections), we
        // still save the images straight to the library.
        let album = await albumForAdding()

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for image in valid {
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                    if let album,
                       let placeholder = request.placeholderForCreatedAsset,
                       let albumChange = PHAssetCollectionChangeRequest(for: album) {
                        albumChange.addAssets([placeholder] as NSArray)
                    }
                }
            }
        } catch {
            throw ExportError.writeFailed
        }
    }

    // MARK: - Authorization

    private static func ensureAuthorized() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else { throw ExportError.permissionDenied }
        default:
            throw ExportError.permissionDenied
        }
    }

    // MARK: - Album (best-effort)

    /// Returns the album to add to, or `nil` if one can't be obtained — in which
    /// case the caller simply saves to the library. Never throws.
    private static func albumForAdding() async -> PHAssetCollection? {
        if let existing = storedAlbum() ?? albumByTitle() { return existing }

        var createdID: String?
        try? await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            createdID = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        if let createdID {
            UserDefaults.standard.set(createdID, forKey: albumIDKey)
        }
        return storedAlbum() ?? albumByTitle()
    }

    /// Look the album up by the local identifier we saved when we created it.
    private static func storedAlbum() -> PHAssetCollection? {
        guard let id = UserDefaults.standard.string(forKey: albumIDKey) else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Look the album up by title — only works when the app has read access.
    private static func albumByTitle() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: options
        ).firstObject
    }
}
