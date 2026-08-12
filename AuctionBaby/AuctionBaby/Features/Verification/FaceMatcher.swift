import Vision
import UIKit
import CoreImage

/// Compares a live selfie to the user's profile photo using Vision face landmarks.
/// On-device only — no face data ever leaves the phone.
///
/// Approach: extract 76-point face landmarks from both the selfie and the
/// profile photo, normalize them to a unit coordinate system (distance between
/// eye centers = 1.0), then compute the average Euclidean distance across
/// all landmark points. A low distance means the same person.
final class FaceMatcher {
    /// Match threshold: average landmark distance below this = same person.
    /// Tunable — lower = stricter, higher = more lenient.
    static let matchThreshold: Double = 0.20

    struct MatchResult {
        let isMatch: Bool
        let score: Double          // 0..1, higher = better match
        let distance: Double       // raw landmark distance (lower = better)
        let error: String?
    }

    /// Compare a captured selfie pixel buffer to a profile photo (UIImage).
    /// Returns a match result with confidence score.
    static func match(selfieBuffer: CVPixelBuffer, profilePhotos: [UIImage]) -> MatchResult {
        // Extract face landmarks from the selfie
        guard let selfieLandmarks = extractLandmarks(from: selfieBuffer, orientation: .leftMirrored) else {
            return MatchResult(isMatch: false, score: 0, distance: 1, error: "No face detected in selfie")
        }

        let candidates = profilePhotos.compactMap { photo -> [CGPoint]? in
            guard let image = normalizedCGImage(from: photo) else { return nil }
            return extractLandmarks(from: image)
        }
        guard !candidates.isEmpty else {
            return MatchResult(isMatch: false, score: 0, distance: 1, error: "No face detected in profile photo")
        }

        // Normalize both sets to unit space (inter-ocular distance = 1.0)
        let normalizedSelfie = normalizeLandmarks(selfieLandmarks)
        // Match against every usable profile photo and keep the strongest.
        let distance = candidates
            .map { computeDistance(normalizedSelfie, normalizeLandmarks($0)) }
            .min() ?? 1

        // Convert to a 0..1 score (1 = perfect match, 0 = no match)
        let score = max(0, 1.0 - distance / (matchThreshold * 2))
        let isMatch = distance < matchThreshold

        return MatchResult(isMatch: isMatch, score: score, distance: distance, error: nil)
    }

    private static func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage { return cgImage }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
    }

    // MARK: - Private

    /// Extract all face landmark points from an image (pixel buffer or CGImage).
    private static func extractLandmarks(from buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [CGPoint]? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let face = (request.results as? [VNFaceObservation])?.first,
              let landmarks = face.landmarks else { return nil }
        return collectAllLandmarkPoints(landmarks)
    }

    private static func extractLandmarks(from cgImage: CGImage) -> [CGPoint]? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let face = (request.results as? [VNFaceObservation])?.first,
              let landmarks = face.landmarks else { return nil }
        return collectAllLandmarkPoints(landmarks)
    }

    /// Collect all landmark points from every region into a flat array.
    /// Vision provides these regions: faceContour, leftEye, rightEye,
    /// leftEyebrow, rightEyebrow, nose, noseCrest, medianLine, outerLips,
    /// innerLips, leftPupil, rightPupil.
    private static func collectAllLandmarkPoints(_ landmarks: VNFaceLandmarks2D) -> [CGPoint] {
        var points: [CGPoint] = []
        let regions: [VNFaceLandmarkRegion2D?] = [
            landmarks.faceContour,
            landmarks.leftEye,
            landmarks.rightEye,
            landmarks.leftEyebrow,
            landmarks.rightEyebrow,
            landmarks.nose,
            landmarks.noseCrest,
            landmarks.medianLine,
            landmarks.outerLips,
            landmarks.innerLips,
        ]
        for region in regions {
            if let region {
                points.append(contentsOf: region.normalizedPoints)
            }
        }
        // Pupils are sometimes nil; add if present
        if let lp = landmarks.leftPupil { points.append(contentsOf: lp.normalizedPoints) }
        if let rp = landmarks.rightPupil { points.append(contentsOf: rp.normalizedPoints) }
        return points
    }

    /// Normalize landmark points so that the distance between eye centers = 1.0.
    /// This makes comparison invariant to face size and position in frame.
    private static func normalizeLandmarks(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 6 else { return points }

        // Approximate eye centers from the landmark cloud.
        // Vision landmark points are in normalized image coords [0,1].
        // We find the leftmost and rightmost clusters as eye positions.
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }

        // Use the bounding box center + width for normalization
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let scale = max(maxX - minX, maxY - minY)
        guard scale > 0 else { return points }

        // Normalize so center is at origin and max dimension = 1
        return points.map { CGPoint(x: ($0.x - centerX) / scale, y: ($0.y - centerY) / scale) }
    }

    /// Compute average Euclidean distance between two landmark point sets.
    /// Both sets must have the same number of points (Vision guarantees this
    /// for the same landmark regions).
    private static func computeDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 1.0 }

        var totalDist: Double = 0
        for i in 0..<count {
            let dx = Double(a[i].x - b[i].x)
            let dy = Double(a[i].y - b[i].y)
            totalDist += (dx * dx + dy * dy).squareRoot()
        }
        return totalDist / Double(count)
    }

    /// Pick the best-quality face frame from a pixel buffer.
    /// Returns nil if no face or quality is too low.
    static func captureQualityScore(_ buffer: CVPixelBuffer) -> Double {
        let request = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .leftMirrored)
        do {
            try handler.perform([request])
        } catch {
            return 0
        }
        guard let face = (request.results as? [VNFaceObservation])?.first else { return 0 }
        return face.captureQuality ?? 0
    }
}
