import AVFoundation
import UIKit

/// Composites a source App Preview recording into the studio frame — the
/// background, device bezel, caption and overlays — and exports an H.264 `.mov`
/// at the device's pixel size, so a preview video gets the same treatment as a
/// screenshot.
///
/// The source video is scaled to fill the device's screen rect; everything
/// around it comes from a pre-rendered "backplate" image drawn as a Core
/// Animation layer behind the video.
enum VideoExporter {
    enum ExportError: LocalizedError {
        case noVideoTrack
        case setupFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "That file doesn't contain a video track."
            case .setupFailed: return "Couldn't set up the video export."
            case .exportFailed(let message): return message
            }
        }
    }

    /// Export the composited preview. `backplate` is the full studio frame with
    /// a blank screen area; `screenRect` is where the video goes (both in canvas
    /// pixel space).
    static func export(sourceURL: URL,
                       backplate: UIImage,
                       canvasSize: CGSize,
                       screenRect: CGRect,
                       progress: @escaping (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let duration = try await asset.load(.duration)

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.setupFailed
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                       of: sourceVideoTrack, at: .zero)

        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                            of: sourceAudio, at: .zero)
        }

        // --- Position the source video inside the screen rect ----------------
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferred = try await sourceVideoTrack.load(.preferredTransform)
        let oriented = naturalSize.applying(preferred)
        let videoSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let safeVideo = CGSize(width: max(videoSize.width, 1), height: max(videoSize.height, 1))

        let scale = max(screenRect.width / safeVideo.width, screenRect.height / safeVideo.height)
        let scaledW = safeVideo.width * scale
        let scaledH = safeVideo.height * scale
        let tx = screenRect.midX - scaledW / 2
        let ty = screenRect.midY - scaledH / 2
        let transform = preferred
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        // --- Core Animation layer tree (backplate behind the video) ----------
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: canvasSize)
        parentLayer.isGeometryFlipped = true
        let backplateLayer = CALayer()
        backplateLayer.frame = parentLayer.bounds
        backplateLayer.contents = backplate.cgImage
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(backplateLayer)
        parentLayer.addSublayer(videoLayer)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvasSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        // --- Export ----------------------------------------------------------
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppPreview-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.setupFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mov
        session.videoComposition = videoComposition

        let poll = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        poll.cancel()

        switch session.status {
        case .completed:
            progress(1)
            return outputURL
        case .cancelled:
            throw ExportError.exportFailed("Export was cancelled.")
        default:
            throw ExportError.exportFailed(session.error?.localizedDescription ?? "Video export failed.")
        }
    }

    /// A small solid-black image with a given aspect ratio, used as the source
    /// "screenshot" when rendering the backplate so the device frames the video
    /// at the right shape.
    static func blackImage(aspect: CGSize) -> UIImage {
        let w: CGFloat = 120
        let h = aspect.width > 0 ? max(w * aspect.height / aspect.width, 1) : w
        let size = CGSize(width: w, height: h)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
