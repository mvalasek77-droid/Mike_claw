import Vision
import AVFoundation
import UIKit

/// Liveness check via blink detection.
/// Uses VNDetectFaceLandmarksRequest to track eye openness over time.
/// A natural blink (open → closed → open) within a time window proves
/// the camera input is a live person, not a photo or video replay.
final class LivenessChecker {
    private var eyeOpennessHistory: [(time: Double, ratio: Double)] = []
    private var blinkDetected = false
    private var startTime: CFTimeInterval = 0
    private let timeout: CFTimeInterval = 12  // seconds before giving up

    var onBlinkProgress: ((Double) -> Void)?  // 0..1, how close to detecting blink
    var onBlinkDetected: (() -> Void)?
    var onTimeout: (() -> Void)?

    /// Eye openness ratio: distance between upper and lower eye landmarks
    /// divided by distance between left and right eye corners.
    /// A closed eye has ratio < 0.15; open is > 0.25.
    private static let openThreshold: Double = 0.22
    private static let closedThreshold: Double = 0.15

    enum State { case waitingForEyes, eyesOpen, eyesClosed, blinkComplete }
    private var state: State = .waitingForEyes

    func reset() {
        eyeOpennessHistory.removeAll()
        blinkDetected = false
        state = .waitingForEyes
        startTime = 0
    }

    /// Process a captured frame. Returns true if liveness check is complete.
    @discardableResult
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) -> Bool {
        if startTime == 0 { startTime = timestamp }

        // Timeout check
        if timestamp - startTime > timeout {
            DispatchQueue.main.async { self.onTimeout?() }
            return true
        }

        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            guard let self else { return }
            let results = request.results as? [VNFaceObservation] ?? []
            guard let face = results.first,
                  let landmarks = face.landmarks,
                  let leftEye = landmarks.leftEye,
                  let rightEye = landmarks.rightEye else { return }

            let leftRatio = Self.eyeOpennessRatio(eye: leftEye)
            let rightRatio = Self.eyeOpennessRatio(eye: rightEye)
            let avgRatio = (leftRatio + rightRatio) / 2.0

            self.handleEyeRatio(avgRatio, time: timestamp)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([request])

        return blinkDetected
    }

    private func handleEyeRatio(_ ratio: Double, time: CFTimeInterval) {
        eyeOpennessHistory.append((time, ratio))

        switch state {
        case .waitingForEyes:
            // Wait until we see open eyes
            if ratio > Self.openThreshold {
                state = .eyesOpen
            }

        case .eyesOpen:
            // Detect eyes closing
            if ratio < Self.closedThreshold {
                state = .eyesClosed
            }

        case .eyesClosed:
            // Detect eyes opening again = blink complete
            if ratio > Self.openThreshold {
                state = .blinkComplete
                blinkDetected = true
                DispatchQueue.main.async {
                    self.onBlinkProgress?(1.0)
                    self.onBlinkDetected?()
                }
            }

        case .blinkComplete:
            break
        }

        // Report progress: 0 = just started, 0.33 = eyes detected, 0.66 = eyes closed, 1.0 = blink complete
        let progress: Double
        switch state {
        case .waitingForEyes: progress = 0.1
        case .eyesOpen: progress = 0.33
        case .eyesClosed: progress = 0.66
        case .blinkComplete: progress = 1.0
        }
        DispatchQueue.main.async { self.onBlinkProgress?(progress) }
    }

    /// Calculate eye openness ratio from VNFaceLandmarkRegion2D.
    /// Returns a normalized ratio: ~0.3+ = open, ~0.1 = closed.
    private static func eyeOpennessRatio(eye: VNFaceLandmarkRegion2D) -> Double {
        let points = eye.normalizedPoints
        guard points.count >= 6 else { return 0.3 }

        // Find the vertical extent (top vs bottom of eye)
        let ys = points.map { $0.y }
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        let verticalDist = maxY - minY

        // Find the horizontal extent (left vs right corner of eye)
        let xs = points.map { $0.x }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let horizontalDist = maxX - minX

        guard horizontalDist > 0 else { return 0.3 }
        return Double(verticalDist / horizontalDist)
    }

    var isComplete: Bool { blinkDetected }
}