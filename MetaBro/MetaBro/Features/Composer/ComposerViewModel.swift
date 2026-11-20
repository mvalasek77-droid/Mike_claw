import PhotosUI
import SwiftUI
import UIKit

/// Drives the post composer. Loads the Bro-hoods you can post to (your joined
/// communities, plus "Your feed" for a social post) and submits the draft.
@MainActor
@Observable
final class ComposerViewModel {
    enum Phase: Equatable {
        case editing
        case submitting
        case posted
        case failed(String)
    }

    var title: String = ""
    var body: String = ""
    /// nil target = a social post to your own feed.
    var target: Community?
    private(set) var targets: [Community] = []
    private(set) var phase: Phase = .editing

    /// Selection from the system photo picker; loading it fills `photo`.
    var photoSelection: PhotosPickerItem?
    private(set) var photo: UIImage?
    private(set) var isLoadingPhoto = false
    private var photoData: Data?

    private let feedService: FeedService
    private let communityService: CommunityService

    init(feedService: FeedService, communityService: CommunityService) {
        self.feedService = feedService
        self.communityService = communityService
    }

    var canSubmit: Bool {
        phase != .submitting && !isLoadingPhoto &&
        (!body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoData != nil)
    }

    func loadTargets() async {
        targets = (try? await communityService.discover().filter(\.isJoined)) ?? []
    }

    func removePhoto() {
        photoSelection = nil
        photo = nil
        photoData = nil
    }

    func loadPhoto() async {
        guard let item = photoSelection else { return }
        if case .failed = phase { phase = .editing }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            let resized = Self.downscaled(image, maxDimension: 1600)
            photo = resized
            photoData = resized.jpegData(compressionQuality: 0.85)
        } catch {
            BroLog.error(error, category: "composer")
            phase = .failed("Couldn't load that photo. Try another one.")
        }
    }

    /// Caps the longest side so feed photos stay light in memory and on disk.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func submit() async {
        guard canSubmit else { return }
        phase = .submitting
        let draft = PostDraft(title: title, body: body, community: target, imageData: photoData)
        do {
            _ = try await feedService.createPost(draft)
            phase = .posted
            HapticsEngine.shared.play(.award)
        } catch {
            BroLog.error(error, category: "composer")
            phase = .failed("Couldn't post. Check your connection and try again.")
            HapticsEngine.shared.play(.error)
        }
    }

    /// Reset for another post after a successful submission.
    func reset() {
        title = ""
        body = ""
        target = nil
        removePhoto()
        phase = .editing
    }
}
