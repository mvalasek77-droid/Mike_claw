import Photos
import UIKit

/// Saves rendered screenshots to the user's photo library, into a dedicated
/// "Screenshot Studio" album so exports are easy to find and AirDrop to a Mac
/// for upload to App Store Connect.
enum PhotoExporter {
    enum ExportError: LocalizedError {
        case permissionDenied
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screenshot Studio needs permission to save to Photos. Enable it in Settings › Privacy › Photos."
            case .writeFailed:
                return "The export couldn't be saved. Please try again."
            }
        }
    }

    private static let albumName = "Screenshot Studio"

    /// Save a batch of images to the dedicated album. Throws on the first
    /// failure so the caller can surface a single, clear error.
    static func save(_ images: [UIImage]) async throws {
        guard !images.isEmpty else { return }
        try await ensureAuthorized()
        let album = try await fetchOrCreateAlbum()

        try await PHPhotoLibrary.shared().performChanges {
            for image in images {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                if let placeholder = request.placeholderForCreatedAsset,
                   let albumChange = PHAssetCollectionChangeRequest(for: album) {
                    albumChange.addAssets([placeholder] as NSArray)
                }
            }
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

    // MARK: - Album

    private static func fetchOrCreateAlbum() async throws -> PHAssetCollection {
        if let existing = existingAlbum() { return existing }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
        }

        guard let created = existingAlbum() else { throw ExportError.writeFailed }
        return created
    }

    private static func existingAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumName)
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: options
        )
        return collections.firstObject
    }
}
