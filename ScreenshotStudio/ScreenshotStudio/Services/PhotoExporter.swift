import Photos
import UIKit

/// Saves rendered screenshots to the user's photo library, collecting them into
/// a dedicated "Screenshot Studio" album so they're easy to find and AirDrop to
/// a Mac for upload to App Store Connect. Creating/reusing that album needs
/// read-write Photos access; if the album can't be made we still save straight
/// to the library so the export succeeds. Every step is recorded to the
/// on-device diagnostics log so a failed save can be diagnosed without a
/// debugger.
enum PhotoExporter {
    enum ExportError: LocalizedError {
        case permissionDenied
        case nothingToSave
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Screenshot Studio needs permission to save to Photos. Please enable it in Settings."
            case .nothingToSave:
                return "The slides couldn't be rendered into images. Please try again."
            case .writeFailed:
                return "The export couldn't be saved. Please try again."
            }
        }
    }

    private static let albumName = "Screenshot Studio"
    /// Local identifier of the album we created, persisted so we can re-use it
    /// across launches.
    private static let albumIDKey = "ScreenshotStudio.albumLocalIdentifier"

    /// Save a batch of already-encoded PNGs. Throws a clear, catchable error on
    /// failure — never an uncatchable Objective-C exception. Taking `Data`
    /// (rather than `UIImage`) keeps peak memory bounded on large exports and
    /// sidesteps the `NSException` Photos raises for a CGImage-less image.
    static func save(_ pngs: [Data]) async throws {
        guard !pngs.isEmpty else {
            BugLog.warning("Photos", "Save called with no images.")
            throw ExportError.nothingToSave
        }

        try await ensureAuthorized()

        // The dedicated album is a nicety, not a requirement: if we can't get
        // one, we still save the images straight to the library.
        let album = await albumForAdding()
        BugLog.info("Photos", album == nil
                    ? "Saving \(pngs.count) image(s) to the library."
                    : "Saving \(pngs.count) image(s) to the “\(albumName)” album.")

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for data in pngs {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                    if let album,
                       let placeholder = request.placeholderForCreatedAsset,
                       let albumChange = PHAssetCollectionChangeRequest(for: album) {
                        albumChange.addAssets([placeholder] as NSArray)
                    }
                }
            }
            BugLog.info("Photos", "Save committed successfully.")
        } catch {
            BugLog.error("Photos", "Save failed: \(error.localizedDescription)")
            throw ExportError.writeFailed
        }
    }

    // MARK: - Authorization

    @discardableResult
    private static func ensureAuthorized() async throws -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            BugLog.info("Photos", "Access already granted (\(label(status))).")
            return status
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            BugLog.info("Photos", "Access prompt result: \(label(granted)).")
            guard granted == .authorized || granted == .limited else {
                throw ExportError.permissionDenied
            }
            return granted
        default:
            BugLog.error("Photos", "Access denied (\(label(status))). Enable it in Settings.")
            throw ExportError.permissionDenied
        }
    }

    private static func label(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .limited: return "limited"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Album (best-effort)

    /// Returns the album to add to, or `nil` if one can't be obtained — in which
    /// case the caller simply saves to the library. Never throws.
    private static func albumForAdding() async -> PHAssetCollection? {
        if let existing = storedAlbum() ?? albumByTitle() { return existing }

        var createdID: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                createdID = request.placeholderForCreatedAssetCollection.localIdentifier
            }
        } catch {
            BugLog.warning("Photos", "Couldn't create the album (saving to library instead): \(error.localizedDescription)")
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
