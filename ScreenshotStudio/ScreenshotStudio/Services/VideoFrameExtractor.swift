import AVFoundation
import UIKit

/// Pulls representative still frames out of an App Preview video so they can
/// flow through the same studio treatment (frame, backdrop, caption, export)
/// as imported screenshots. App Store previews and screenshots share the exact
/// device resolutions, so a chosen frame drops straight into a slide.
enum VideoFrameExtractor {
    /// Extract `count` evenly-spaced frames across the clip's duration.
    static func frames(from url: URL, count: Int = 6) async -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let seconds: Double
        if let duration = try? await asset.load(.duration) {
            seconds = CMTimeGetSeconds(duration)
        } else {
            seconds = 0
        }
        guard seconds.isFinite, seconds > 0 else {
            BugLog.warning("Video", "Picked video has no readable duration.")
            return []
        }

        let n = max(count, 1)
        var images: [UIImage] = []
        for i in 0..<n {
            let fraction = n <= 1 ? 0.0 : Double(i) / Double(n - 1)
            // Keep a hair off the final frame, which can fail to decode.
            let t = min(seconds * fraction, max(seconds - 0.05, 0))
            let time = CMTime(seconds: t, preferredTimescale: 600)
            if let cg = try? await generator.image(at: time).image {
                images.append(UIImage(cgImage: cg))
            }
        }
        if images.isEmpty {
            BugLog.warning("Video", "Couldn't extract any frames from the picked video.")
        }
        return images
    }
}
