import SwiftUI
import UIKit
import Vision
import AVFoundation

/// Verify the account with a real face-to-photo match.
///
/// Flow:
///   1. Camera opens with front camera, face detection overlay
///   2. Liveness check — user blinks to prove they're real
///   3. Face match — selfie landmarks compared to profile photo landmarks
///   4. Result submitted to server (or local blue check for demo mode)
///
/// Demo / local-only path: if no server session, the real camera flow still
/// runs (liveness + face match), but the blue check is awarded locally.
struct VerificationSheet: View {
    /// Callback used only by the local/demo path. On the server path the flag
    /// arrives via the auth-refresh loop, not this closure.
    var onVerified: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var verification: VerificationService
    @EnvironmentObject private var store: AuctionStore

    private enum Phase {
        case idle           // "Verify me" button
        case camera         // Camera open, waiting for face
        case liveness       // Face detected, blink challenge
        case matching       // Capturing selfie, comparing to profile
        case submitting     // Sending result to server
        case pending        // Server says "under review"
        case done           // Verified!
        case failed         // Something went wrong
        case noCamera       // Camera permission denied
    }

    @State private var phase: Phase = .idle
    @State private var sweep = false
    @State private var vendorNote: String?
    @State private var isCapturing = false
    @State private var faceBox: CGRect? = nil  // face bounding box in screen coords
    @State private var livenessProgress: Double = 0
    @State private var matchScore: Double = 0
    @State private var selfieQualityScore: Double = 0
    @State private var livenessChecker = LivenessChecker()
    @State private var cameraPermissionGranted: Bool? = nil

    private var useServerPath: Bool { verification.isEnabled }

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(Theme.hairline).frame(width: 38, height: 5).padding(.top, 10)

            // Camera or icon area
            phaseVisual
                .frame(height: 220)

            VStack(spacing: 6) {
                Text(title).font(.dynamicScaled(20, weight: .heavy, design: .serif, relativeTo: .title3)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.dynamicScaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                if let vendorNote {
                    Text(vendorNote)
                        .font(.dynamicScaled(11, weight: .semibold, relativeTo: .caption2))
                        .foregroundStyle(Theme.inkFaint)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)

            // Liveness progress bar
            if phase == .liveness {
                livenessProgressBar
            }

            // Match score indicator
            if phase == .matching || phase == .done {
                if matchScore > 0 {
                    Text("Match score: \(Int(matchScore * 100))%")
                        .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                        .foregroundStyle(matchScore > 0.5 ? Theme.verify : Theme.warning)
                }
            }

            Spacer()

            actionButton
                .screenPadding()

            Text(footerNote)
                .font(.dynamicScaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
        }
        .background(AppBackground().opacity(0.5))
        .task { await checkCameraPermission() }
    }

    // MARK: - Visual area (camera or icon)

    @ViewBuilder
    private var phaseVisual: some View {
        switch phase {
        case .camera, .liveness, .matching:
            cameraView
        case .idle:
            iconView(systemName: "faceid", tint: Theme.verify)
        case .done:
            iconView(systemName: "checkmark.seal.fill", tint: Theme.verify, scale: 1.1)
        case .pending:
            iconView(systemName: "hourglass", tint: Theme.verify)
        case .failed:
            iconView(systemName: "exclamationmark.triangle.fill", tint: Theme.danger)
        case .submitting:
            iconView(systemName: "faceid", tint: Theme.verify)
        case .noCamera:
            iconView(systemName: "camera.slash.fill", tint: Theme.warning)
        }
    }

    private func iconView(systemName: String, tint: Color, scale: CGFloat = 1.0) -> some View {
        ZStack {
            Circle().fill(tint.opacity(0.14)).frame(width: 150, height: 150)
            Image(systemName: systemName)
                .font(.dynamicScaled(66, weight: .bold, relativeTo: .largeTitle))
                .foregroundStyle(tint)
                .scaleEffect(scale)
        }
    }

    private var cameraView: some View {
        ZStack {
            // Camera preview
            CameraCaptureView(
                onFaceDetected: { face, buffer in handleFaceDetected(face, buffer) },
                onNoFace: { handleNoFace() },
                onCameraError: { message in
                    phase = .noCamera
                    vendorNote = message
                },
                isCapturing: $isCapturing
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerL))

            // Face bounding box overlay
            if let faceBox {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(phase == .liveness ? Theme.verify : Theme.gold, lineWidth: 2)
                    .frame(width: faceBox.width, height: faceBox.height)
                    .position(x: faceBox.midX, y: faceBox.midY)
            }

            // Overlay instructions for liveness
            if phase == .liveness {
                VStack {
                    Spacer()
                    Text("Blink once")
                        .font(.dynamicScaled(18, weight: .heavy, design: .serif, relativeTo: .title3))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .padding(.bottom, 12)
                }
            }

            // Scanning sweep line for matching phase
            if phase == .matching {
                RoundedRectangle(cornerRadius: 2).fill(
                    LinearGradient(colors: [.clear, Theme.verify, .clear],
                                   startPoint: .leading, endPoint: .trailing))
                    .frame(height: 3)
                    .offset(y: sweep ? 100 : -100)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerL))
        .padding(.horizontal, 20)
    }

    private var livenessProgressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: livenessProgress)
                .tint(Theme.verify)
                .frame(width: 200)
            Text(livenessProgress < 0.33 ? "Looking for your eyes…" :
                 livenessProgress < 0.66 ? "Now blink…" :
                 livenessProgress < 1.0 ? "Almost there…" : "Blink detected!")
                .font(.dynamicScaled(11, weight: .semibold, relativeTo: .caption2))
                .foregroundStyle(Theme.inkFaint)
        }
    }

    // MARK: - Copy per phase

    private var title: String {
        switch phase {
        case .idle:        return "Verify your identity"
        case .camera:      return "Center your face"
        case .liveness:    return "Prove you're real"
        case .matching:    return "Matching your face…"
        case .submitting:  return "Submitting…"
        case .pending:     return "Verification submitted"
        case .done:        return "You're verified!"
        case .failed:      return "That didn't go through"
        case .noCamera:    return "Camera unavailable"
        }
    }

    private var subtitle: String {
        switch phase {
        case .idle:
            return "Match your face to your photos to earn a blue check the whole floor can trust."
        case .camera:
            return "Position your face inside the frame. We'll detect it automatically."
        case .liveness:
            return "Blink once naturally so we know you're a real person, not a photo."
        case .matching:
            return "Comparing your selfie to your profile photo…"
        case .submitting:
            return "Sending your verification result for review."
        case .pending:
            return "We'll review your submission and let you know as soon as it's done. You'll get a notification the moment your blue check goes live."
        case .done:
            return "Your blue check is now live across Auction Baby."
        case .failed:
            return "Try again in a moment, or reach out to support if this keeps happening."
        case .noCamera:
            return "Camera access is required for verification. Enable it in Settings to continue."
        }
    }

    private var footerNote: String {
        useServerPath
            ? "Auction Baby never stores your selfie. Verification only compares your live face to your existing profile photos on-device."
            : "Your selfie is processed on-device and never stored. No camera data leaves your phone."
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .done, .pending:
            PrimaryButton(title: "Done", systemImage: "checkmark",
                          gradient: Theme.goldGradient) { dismiss() }
        case .failed:
            PrimaryButton(title: "Try again", systemImage: "arrow.clockwise",
                          gradient: Theme.goldGradient) { start() }
        case .noCamera:
            PrimaryButton(title: "Open Settings", systemImage: "gear",
                          gradient: Theme.goldGradient) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        case .submitting:
            PrimaryButton(title: "Submitting…", systemImage: "faceid",
                          gradient: verifyGradient, enabled: false) { }
        case .matching:
            PrimaryButton(title: "Matching…", systemImage: "faceid",
                          gradient: verifyGradient, enabled: false) { }
        case .camera, .liveness:
            PrimaryButton(title: "Cancel", systemImage: "xmark",
                          gradient: Theme.goldGradient) { phase = .idle; faceBox = nil }
        case .idle:
            PrimaryButton(title: useServerPath ? "Verify me" : "Scan my face",
                          systemImage: "faceid",
                          gradient: verifyGradient) { start() }
        }
    }

    private var verifyGradient: LinearGradient {
        LinearGradient(colors: [Theme.verify, Color(red: 0.18, green: 0.5, blue: 0.85)],
                       startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Flow

    private func checkCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraPermissionGranted = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraPermissionGranted = granted
        default:
            cameraPermissionGranted = false
        }
    }

    private func start() {
        vendorNote = nil
        matchScore = 0
        selfieQualityScore = 0
        livenessProgress = 0
        faceBox = nil
        livenessChecker.reset()

        guard cameraPermissionGranted == true else {
            phase = .noCamera
            return
        }

        phase = .camera
    }

    // MARK: - Face detection callbacks

    private func handleFaceDetected(_ face: VNFaceObservation, _ buffer: CVPixelBuffer) {
        // Convert Vision bounding box (normalized, origin bottom-left) to screen coords
        let cameraHeight: CGFloat = 220
        let cameraWidth: CGFloat = UIScreen.main.bounds.width - 40
        let bbox = face.boundingBox
        faceBox = CGRect(
            x: bbox.origin.x * cameraWidth + 20,
            y: (1 - bbox.origin.y - bbox.height) * cameraHeight,
            width: bbox.width * cameraWidth,
            height: bbox.height * cameraHeight
        )

        if phase == .camera {
            // Face detected — start liveness check
            phase = .liveness
            livenessChecker.reset()
            runLivenessCheck(buffer: buffer)
        } else if phase == .liveness {
            // Continue liveness check with this frame
            runLivenessCheck(buffer: buffer)
        }
    }

    private func handleNoFace() {
        faceBox = nil
        if phase == .liveness || phase == .camera {
            // Go back to camera phase if we lose the face
            if phase == .liveness {
                phase = .camera
                livenessChecker.reset()
                livenessProgress = 0
            }
        }
    }

    // MARK: - Liveness (blink detection)

    private func runLivenessCheck(buffer: CVPixelBuffer) {
        let timestamp = CACurrentMediaTime()

        livenessChecker.onBlinkProgress = { progress in
            withAnimation(.easeInOut(duration: 0.3)) {
                livenessProgress = progress
            }
        }

        livenessChecker.onBlinkDetected = { [self] in
            // Liveness passed — capture selfie for face matching
            captureAndMatch(buffer: buffer)
        }

        livenessChecker.onTimeout = { [self] in
            phase = .failed
            vendorNote = "We didn't detect a blink. Try again in good lighting."
        }

        _ = livenessChecker.processFrame(buffer, timestamp: timestamp)
    }

    // MARK: - Face matching

    private func captureAndMatch(buffer: CVPixelBuffer) {
        phase = .matching
        if !Motion.prefersReducedMotion {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { sweep = true }
        }

        // Get the user's profile photo
        let profilePhotos = ([store.me.photoData].compactMap { $0 } + store.me.photoGallery)
            .compactMap(UIImage.init(data:))

        guard !profilePhotos.isEmpty else {
            withAnimation { sweep = false }
            phase = .failed
            vendorNote = "Add a profile photo first, then try verification again."
            return
        }

        // Run face matching on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let quality = FaceMatcher.captureQualityScore(buffer)
            let result = FaceMatcher.match(selfieBuffer: buffer, profilePhotos: profilePhotos)

            DispatchQueue.main.async {
                withAnimation { sweep = false }
                selfieQualityScore = quality
                matchScore = result.score

                if result.isMatch {
                    // Face matches profile photo — verification passed
                    Haptics.success()
                    finishVerification()
                } else {
                    // Face doesn't match
                    Haptics.warning()
                    phase = .failed
                    vendorNote = result.error ?? "Your selfie didn't match your profile photo. Make sure your profile photo shows your face clearly."
                }
            }
        }
    }

    // MARK: - Submit result

    private func finishVerification() {
        if useServerPath {
            phase = .submitting
            Task {
                let result = await verification.submitVerificationResult(
                    selfieScore: selfieQualityScore,
                    livenessPassed: true,
                    faceMatchScore: matchScore
                )
                switch result {
                case .success(let response):
                    switch response.status {
                    case "passed":
                        Haptics.success()
                        phase = .done
                        _ = await auth.refreshMe()
                    case "pending":
                        Haptics.tap()
                        phase = .pending
                        vendorNote = response.message
                    default:
                        Haptics.warning()
                        phase = .failed
                        vendorNote = response.message ?? "Verification didn't pass. Please try again."
                    }
                case .failure(let message):
                    Haptics.warning()
                    phase = .failed
                    vendorNote = message
                }
            }
        } else {
            // Local/demo path: award blue check locally
            Motion.run(Motion.bouncy) {
                phase = .done
                onVerified()
            }
        }
    }
}
