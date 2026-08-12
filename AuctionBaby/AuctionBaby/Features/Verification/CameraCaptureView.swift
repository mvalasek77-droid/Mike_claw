import SwiftUI
import AVFoundation
import Vision

/// Real-time front camera capture with face detection overlay.
/// Uses AVCaptureSession + VNDetectFaceRectanglesRequest to track
/// the user's face and capture a selfie when the face is centered.
struct CameraCaptureView: UIViewRepresentable {
    var onFaceDetected: (VNFaceObservation, CVPixelBuffer) -> Void
    var onNoFace: () -> Void
    var onCameraError: (String) -> Void
    @Binding var isCapturing: Bool

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.session = context.coordinator.session
        context.coordinator.start()
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.isCapturing = isCapturing
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    // MARK: - Preview View

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var session: AVCaptureSession? {
            get { (layer as? AVCaptureVideoPreviewLayer)?.session }
            set { (layer as? AVCaptureVideoPreviewLayer)?.session = newValue }
        }
        override init(frame: CGRect) {
            super.init(frame: frame)
            (layer as? AVCaptureVideoPreviewLayer)?.videoGravity = .resizeAspectFill
        }
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            (layer as? AVCaptureVideoPreviewLayer)?.videoGravity = .resizeAspectFill
        }
    }

    // MARK: - Coordinator ( AVCaptureVideoDataOutputSampleBufferDelegate )

    final class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let parent: CameraCaptureView
        let session = AVCaptureSession()
        private let videoOutput = AVCaptureVideoDataOutput()
        private let sessionQueue = DispatchQueue(label: "com.valasek.auctionbaby.verify.camera")
        private let visionQueue = DispatchQueue(label: "com.valasek.auctionbaby.verify.vision")
        private var lastFaceTime: CFTimeInterval = 0
        var isCapturing = false

        init(parent: CameraCaptureView) { self.parent = parent }

        func start() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.configureSession()
                self.session.startRunning()
            }
        }

        func stop() {
            sessionQueue.async { [weak self] in
                self?.session.stopRunning()
            }
        }

        private func configureSession() {
            session.beginConfiguration()
            session.sessionPreset = .high

            // Front camera
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.parent.onCameraError("A front camera is required for verification.") }
                return
            }
            guard let input = try? AVCaptureDeviceInput(device: device) else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.parent.onCameraError("Auction Baby couldn't start the front camera.") }
                return
            }
            if session.canAddInput(input) { session.addInput(input) }

            // Video data output for Vision processing
            videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

            // Mirror the preview so the user sees themselves naturally
            if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }

            session.commitConfiguration()
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

            let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
                guard let self else { return }
                let results = request.results as? [VNFaceObservation] ?? []
                if let face = results.first {
                    // Throttle callbacks to ~10/sec to avoid flooding SwiftUI
                    if currentTime - self.lastFaceTime > 0.1 {
                        self.lastFaceTime = currentTime
                        // The capture output owns this buffer only for the duration of
                        // this callback. Copy it before handing it across queues.
                        guard let copiedBuffer = Self.copyPixelBuffer(pixelBuffer) else { return }
                        DispatchQueue.main.async {
                            self.parent.onFaceDetected(face, copiedBuffer)
                        }
                    }
                } else {
                    // Only fire no-face if we haven't seen one recently
                    if currentTime - self.lastFaceTime > 0.5 {
                        DispatchQueue.main.async {
                            self.parent.onNoFace()
                        }
                    }
                }
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
            try? handler.perform([request])
        }

        private static func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
            var destination: CVPixelBuffer?
            let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
            guard CVPixelBufferCreate(kCFAllocatorDefault,
                                      CVPixelBufferGetWidth(source),
                                      CVPixelBufferGetHeight(source),
                                      CVPixelBufferGetPixelFormatType(source),
                                      attributes,
                                      &destination) == kCVReturnSuccess,
                  let destination else { return nil }
            CVPixelBufferLockBaseAddress(source, .readOnly)
            CVPixelBufferLockBaseAddress(destination, [])
            defer {
                CVPixelBufferUnlockBaseAddress(destination, [])
                CVPixelBufferUnlockBaseAddress(source, .readOnly)
            }
            guard let sourceBase = CVPixelBufferGetBaseAddress(source),
                  let destinationBase = CVPixelBufferGetBaseAddress(destination) else { return nil }
            let rows = CVPixelBufferGetHeight(source)
            let sourceBytes = CVPixelBufferGetBytesPerRow(source)
            let destinationBytes = CVPixelBufferGetBytesPerRow(destination)
            for row in 0..<rows {
                memcpy(destinationBase.advanced(by: row * destinationBytes),
                       sourceBase.advanced(by: row * sourceBytes),
                       min(sourceBytes, destinationBytes))
            }
            return destination
        }
    }
}
