import SwiftUI

// MARK: - Pipeline Step enum

/// Ordered steps that run after a build succeeds (.readyForTest).
/// The pipeline auto-advances through these stages.
enum PipelineStep: String, CaseIterable, Identifiable {
    case perfection   = "Perfection Mode"
    case metadata     = "Generate Metadata"
    case legalPages  = "Legal Pages"
    case screenshots  = "Take Screenshots"
    case ascSignIn   = "ASC Sign-In"
    case archive      = "Archive & Export"
    case upload       = "Upload to ASC"
    case submit       = "Submit for Review"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .perfection:  return "checkmark.shield.fill"
        case .metadata:    return "text.page.badge.plus"
        case .legalPages:  return "doc.text.fill"
        case .ascSignIn:   return "person.badge.keypad.fill"
        case .screenshots: return "photo.on.rectangle.angled"
        case .archive:     return "archivebox.fill"
        case .upload:      return "cloud.fill"
        case .submit:      return "paperplane.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .perfection:  return "Run 10,000 quality probes"
        case .metadata:    return "App Store listing text"
        case .legalPages:  return "Generate Privacy Policy & Terms"
        case .ascSignIn:   return "Sign into App Store Connect"
        case .screenshots: return "Auto-capture app screens"
        case .archive:     return "Compile into an IPA"
        case .upload:      return "Push to App Store Connect"
        case .submit:      return "Send to Apple for review"
        }
    }

    /// The jargon-free explanation shown in the help sheet.
    var jargonExplanation: String {
        switch self {
        case .perfection:
            return "A 10,000-probe quality check across nine axes — Apple Review readiness, accessibility, performance, security, polish, and more. Run it before submitting to the App Store. If it flags blockers, fix them; if it's green, you have a much better shot at getting through App Review on the first try."
        case .metadata:
            return "CodeGenie writes your App Store listing — title, subtitle, keywords, description, and privacy policy URL — all optimized for discoverability."
        case .legalPages:
            return "Generates a professional privacy policy and terms of use for your app, then publishes them to GitHub Pages so you have URLs ready for App Store Connect. Required for App Store submission."
        case .ascSignIn:
            return "Checks whether your Apple Developer account already has an app record in App Store Connect. If not, it tells you exactly which bundle ID to create an app for — this is required before you can upload builds."
        case .screenshots:
            return "Automatic screenshots are taken by running your app in the simulator and capturing each screen."
        case .archive:
            return "Your app is compiled into an IPA file — the package format Apple uses for App Store distribution."
        case .upload:
            return "The IPA is uploaded securely to App Store Connect using your Apple Developer credentials."
        case .submit:
            return "Your app is submitted to Apple for review. This is the final step — once approved, it goes live on the App Store."
        }
    }

    /// Colour tint for each step's icon background.
    var tint: Color {
        switch self {
        case .perfection:  return LiquidGlass.accent
        case .metadata:    return LiquidGlass.accentSecondary
        case .legalPages:  return Color.purple
        case .ascSignIn:   return Color.orange
        case .screenshots: return LiquidGlass.success
        case .archive:     return LiquidGlass.warning
        case .upload:      return LiquidGlass.accent
        case .submit:      return LiquidGlass.success
        }
    }
}

// MARK: - Step status

enum PipelineStepStatus: Equatable {
    case pending
    case running
    case complete
    case failed(String)

    var isPending: Bool  { self == .pending }
    var isRunning: Bool  { if case .running = self { return true } else { return false } }
    var isComplete: Bool { self == .complete }
    var isFailed: Bool   { if case .failed = self { return true } else { return false } }
}

// MARK: - Pipeline state tracker

/// Tracks the status of each pipeline step and drives auto-advance logic.
@MainActor
final class PipelineRun: ObservableObject {
    @Published private(set) var stepStatuses: [PipelineStep: PipelineStepStatus] = [:]
    @Published private(set) var currentStep: PipelineStep? = nil
    @Published private(set) var isRunning: Bool = false

    /// Results from completed steps (keyed by step).
    @Published var perfectionResult: PipelineClient.PerfectionResult?
    @Published var metadataResult: PipelineClient.MetadataResult?
    @Published var legalPagesResult: PipelineClient.LegalPagesResult?
    @Published var ascSignInResult: PipelineClient.AscSignInResult?
    @Published var screenshotsResult: PipelineClient.ScreenshotsResult?
    @Published var uploadResult: PipelineClient.UploadResult?
    @Published var submitResult: PipelineClient.SubmitResult?

    init() {
        // All steps start as pending
        for step in PipelineStep.allCases {
            stepStatuses[step] = .pending
        }
    }

    /// Mark a step as running (advances currentStep).
    func markRunning(_ step: PipelineStep) {
        stepStatuses[step] = .running
        currentStep = step
        isRunning = true
    }

    /// Mark a step as complete (with an optional result).
    func markComplete(_ step: PipelineStep) {
        stepStatuses[step] = .complete
        // Advance currentStep to the next pending step, or nil if done
        if let idx = PipelineStep.allCases.firstIndex(of: step),
           idx + 1 < PipelineStep.allCases.endIndex {
            let next = PipelineStep.allCases[idx + 1]
            if case .pending = stepStatuses[next] {
                currentStep = next  // will be picked up by auto-advance
            }
        } else {
            currentStep = nil
            isRunning = false
        }
    }

    /// Mark a step as failed.
    func markFailed(_ step: PipelineStep, error: String) {
        stepStatuses[step] = .failed(error)
        isRunning = false
    }

    /// Reset a failed step back to pending so it can be retried.
    func retry(_ step: PipelineStep) {
        stepStatuses[step] = .pending
    }

    /// Reset everything.
    func reset() {
        for step in PipelineStep.allCases {
            stepStatuses[step] = .pending
        }
        currentStep = nil
        isRunning = false
        perfectionResult = nil
        metadataResult = nil
        legalPagesResult = nil
        ascSignInResult = nil
        screenshotsResult = nil
        uploadResult = nil
        submitResult = nil
    }

    func status(for step: PipelineStep) -> PipelineStepStatus {
        stepStatuses[step] ?? .pending
    }
}