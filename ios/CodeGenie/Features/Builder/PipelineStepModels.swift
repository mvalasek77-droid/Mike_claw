import SwiftUI

// MARK: - Pipeline Step enum

/// Ordered steps that run after a build succeeds (.readyForTest).
/// The pipeline auto-advances through these stages.
/// Steps after `.metadata` require explicit user approval ("review gates").
enum PipelineStep: String, CaseIterable, Identifiable {
    case perfection       = "Perfection Mode"
    case metadata         = "Generate Metadata"
    case reviewMetadata   = "Review Metadata"      // ⛔ HUMAN GATE — must approve
    case legalPages       = "Legal Pages"
    case ascSignIn        = "ASC Sign-In"
    case acceptAppleTerms = "Accept Apple Terms"    // ⛔ HUMAN GATE — must accept
    case appIcon          = "Verify App Icon"       // Auto-included with build upload
    case screenshots      = "Upload Screenshots"
    case archive          = "Archive & Export"
    case upload           = "Upload to ASC"
    case whatsNew         = "What's New"
    case betaReview       = "Submit for Beta Review"
    case testers          = "Manage Testers"
    case submit           = "Submit for Review"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .perfection:       return "checkmark.shield.fill"
        case .metadata:         return "text.page.badge.plus"
        case .reviewMetadata:   return "person.badge.checkmark"
        case .legalPages:       return "doc.text.fill"
        case .ascSignIn:        return "person.badge.keypad.fill"
        case .acceptAppleTerms: return "hand.raised.fill"
        case .appIcon:          return "app.badge.fill"
        case .screenshots:      return "photo.on.rectangle.angled"
        case .archive:          return "archivebox.fill"
        case .upload:           return "cloud.fill"
        case .whatsNew:         return "text.bubble.fill"
        case .betaReview:       return "checkmark.globe.fill"
        case .testers:          return "person.3.fill"
        case .submit:           return "paperplane.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .perfection:       return "Run 10,000 quality probes"
        case .metadata:         return "App Store listing text"
        case .reviewMetadata:   return "You must review & approve"
        case .legalPages:       return "Generate Privacy Policy & Terms"
        case .ascSignIn:        return "Sign into App Store Connect"
        case .acceptAppleTerms: return "You must accept Apple's terms"
        case .appIcon:          return "Icon auto-included with build"
        case .screenshots:      return "Auto-capture app screens"
        case .archive:          return "Compile into an IPA"
        case .upload:           return "Push to App Store Connect"
        case .whatsNew:         return "Release notes for this version"
        case .betaReview:       return "Submit build for TestFlight review"
        case .testers:          return "Assign testers to the build"
        case .submit:           return "Send to Apple for review"
        }
    }

    /// The jargon-free explanation shown in the help sheet.
    var jargonExplanation: String {
        switch self {
        case .perfection:
            return "A 10,000-probe quality check across nine axes — Apple Review readiness, accessibility, performance, security, polish, and more. Run it before submitting to the App Store. If it flags blockers, fix them; if it's green, you have a much better shot at getting through App Review on the first try."
        case .metadata:
            return "CodeGenie writes your App Store listing — title, subtitle, keywords, description, and privacy policy URL — all optimized for discoverability."
        case .reviewMetadata:
            return "Apple requires accurate metadata. You must review what CodeGenie generated — name, subtitle, keywords, description, category — and explicitly approve it before the pipeline can continue. If anything looks wrong, reject and the pipeline will be canceled so you can fix it."
        case .legalPages:
            return "Generates a professional privacy policy and terms of use for your app, then publishes them to GitHub Pages so you have URLs ready for App Store Connect. Required for App Store submission."
        case .ascSignIn:
            return "Checks whether your Apple Developer account already has an app record in App Store Connect. If not, it tells you exactly which bundle ID to create an app for — this is required before you can upload builds."
        case .acceptAppleTerms:
            return "Apple requires that you manually accept the App Store Connect Terms of Service and Paid Applications Agreement. CodeGenie cannot do this on your behalf — you must sign into App Store Connect and agree. This step pauses the pipeline until you confirm acceptance."
        case .appIcon:
            return "Apple requires a 1024×1024 app icon uploaded to App Store Connect. The ASC REST API does not support icon uploads, so you must open Safari, sign into App Store Connect, and upload the icon manually. This step checks whether the icon is already uploaded and pauses the pipeline until you confirm it's done."
        case .screenshots:
            return "Automatic screenshots are taken by running your app in the simulator and capturing each screen. They are uploaded directly to App Store Connect via the API."
        case .archive:
            return "Your app is compiled into an IPA file — the package format Apple uses for App Store distribution."
        case .upload:
            return "The IPA is uploaded securely to App Store Connect using your Apple Developer credentials."
        case .whatsNew:
            return "Apple requires release notes (What's New) for every version. CodeGenie generates these automatically based on your app's changes, then sets them in App Store Connect. This step only works after a build has been uploaded."
        case .betaReview:
            return "Before testers can access your build on TestFlight, Apple must review it for compliance. This step submits the build for beta review — once approved, testers will be able to install it."
        case .testers:
            return "This step lists your beta testers and assigns them to the current build so they can install it via TestFlight. The build must have been submitted for beta review first — if it hasn't, this step will fail and tell you to wait for approval."
        case .submit:
            return "Your app is submitted to Apple for review. This is the final step — once approved, it goes live on the App Store."
        }
    }

    /// Whether this step requires explicit user action before continuing.
    var isHumanGate: Bool {
        switch self {
        case .reviewMetadata, .acceptAppleTerms: return true
        default: return false
        }
    }

    /// Colour tint for each step's icon background.
    var tint: Color {
        switch self {
        case .perfection:       return LiquidGlass.accent
        case .metadata:         return LiquidGlass.accentSecondary
        case .reviewMetadata:   return Color.yellow
        case .legalPages:       return Color.purple
        case .ascSignIn:       return Color.orange
        case .acceptAppleTerms: return Color.red
        case .appIcon:          return Color.blue
        case .screenshots:     return LiquidGlass.success
        case .archive:         return LiquidGlass.warning
        case .upload:          return LiquidGlass.accent
        case .whatsNew:        return Color.cyan
        case .betaReview:      return Color.mint
        case .testers:         return Color.teal
        case .submit:          return LiquidGlass.success
        }
    }

    /// Whether this step can be auto-recovered by AI steering on failure.
    var isAISteered: Bool {
        switch self {
        case .metadata, .ascSignIn, .archive, .upload, .whatsNew, .betaReview, .testers, .submit:
            return true
        default:
            return false
        }
    }

    /// Whether this step is fully automated (no human or AI interaction needed).
    var isAutomated: Bool {
        switch self {
        case .perfection, .legalPages, .screenshots:
            return true
        default:
            return false
        }
    }
}

// MARK: - Recovery types

/// The type of recovery action the AI proposes.
enum RecoveryAction: String, Codable, CaseIterable {
    /// Retry the step after applying a fix (e.g., bump build number).
    case retryWithFix
    /// The step requires manual human action (e.g., sign into ASC in Safari).
    case manualIntervention
    /// Skip this step — it's not critical for the pipeline to continue.
    case skip
    /// Abort the pipeline — the error is unrecoverable.
    case abort

    var displayName: String {
        switch self {
        case .retryWithFix:       return "Retry with Fix"
        case .manualIntervention: return "Manual Intervention"
        case .skip:                return "Skip Step"
        case .abort:               return "Abort Pipeline"
        }
    }
}

/// A specific, diagnosed failure mode that the AI has identified.
enum FailureMode: String, Codable {
    case ascSignInRequired           // 403 on app creation / ASC API access
    case provisioningProfileNotFound  // xcodebuild profile error
    case iconAlphaChannel             // ASC rejects IPA for alpha channel in icon
    case keychainAccessRequired       // Keychain unlock prompt blocking archive
    case distributionCertMissing     // No distribution certificate found
    case buildNumberConflict          // Build number already exists in ASC
    case unknown                      // Unrecognised error
}

/// A recovery proposal returned by the AI steering engine.
/// Matches the Rust server's `RecoveryProposal` type.
struct RecoveryProposal: Codable, Identifiable, Equatable {
    let id: String
    let jobID: String
    let step: String
    let failureMode: FailureMode
    let action: RecoveryAction
    let diagnosis: String        // Human-readable explanation of what went wrong
    let fixDescription: String   // What the fix will do
    let fixParams: [String: String] // Parameters for the fix (e.g., new build number)
    let confidence: Double       // 0.0–1.0 — how confident the AI is
    let requiresHumanAction: Bool   // Whether the user must do something outside the app
    let humanActionDescription: String? // e.g., "Sign into ASC at …"
    let autoFix: Bool            // Whether the fix can be applied automatically without user editing

    /// Coding keys matching the Rust server's snake_case JSON fields.
    enum CodingKeys: String, CodingKey {
        case id
        case jobID = "job_id"
        case step
        case failureMode = "failure_mode"
        case action
        case diagnosis
        case fixDescription = "fix_description"
        case fixParams = "fix_params"
        case confidence
        case requiresHumanAction = "requires_human_action"
        case humanActionDescription = "human_action_description"
        case autoFix = "auto_fix"
    }
}

/// Request body sent to the `/recover` endpoint after the user approves a proposal.
struct RecoveryRequest: Codable {
    let jobID: String
    let step: String
    let proposalID: String
    let action: RecoveryAction
    let fixParams: [String: String] // May differ from proposal if user modified

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case step
        case proposalID = "proposal_id"
        case action
        case fixParams = "fix_params"
    }
}

/// Response from the `/recover` endpoint.
struct RecoveryResult: Codable {
    let ok: Bool
    let stepRetrying: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case ok
        case stepRetrying = "step_retrying"
        case message
    }
}

// MARK: - Step status

enum PipelineStepStatus: Equatable {
    case pending
    case running
    case complete
    case failed(String)
    case recovering(RecoveryProposal)  // AI has proposed a fix, awaiting user decision

    var isPending: Bool  { self == .pending }
    var isRunning: Bool  { if case .running = self { return true } else { return false } }
    var isComplete: Bool { self == .complete }
    var isFailed: Bool   { if case .failed = self { return true } else { return false } }
    var isRecovering: Bool { if case .recovering = self { return true } else { return false } }
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

    /// The ASC build ID from the upload step, used for beta review and tester assignment.
    var buildId: String? {
        uploadResult?.uploadID
    }

    /// Human gate approvals
    @Published var metadataApproved: Bool = false
    @Published var appleTermsAccepted: Bool = false

    /// The current AI recovery proposal, if a step has failed and AI has diagnosed it.
    @Published var aiRecoveryProposal: RecoveryProposal?

    /// The step currently awaiting AI recovery approval.
    @Published var recoveringStep: PipelineStep?

    /// Retry history for each step (to detect infinite loops and auto-steer).
    @Published var retryCountByStep: [PipelineStep: Int] = [:]

    /// Maximum retries before giving up on auto-recovery.
    static let maxRetries = 3

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
    /// If the step is AI-steered, this does NOT auto-trigger steer —
    /// the caller (BuildScreen) is responsible for calling
    /// `requestRecovery(step:jobID:errorMessage:)` which will
    /// show the RecoveryGate sheet after the steer call completes.
    func markFailed(_ step: PipelineStep, error: String) {
        stepStatuses[step] = .failed(error)
        isRunning = false
    }

    /// Mark a step as recovering (AI has proposed a fix, awaiting user decision).
    /// Pauses the pipeline until the user approves or rejects.
    func markRecovering(_ step: PipelineStep, proposal: RecoveryProposal) {
        stepStatuses[step] = .recovering(proposal)
        aiRecoveryProposal = proposal
        recoveringStep = step
        isRunning = false  // Pause the pipeline until user decides
    }

    /// Apply an approved recovery — reset the step to pending so the
    /// pipeline's auto-advance can pick it up and retry it.
    func approveRecovery(for step: PipelineStep) {
        stepStatuses[step] = .pending
        aiRecoveryProposal = nil
        recoveringStep = nil
        retryCountByStep[step, default: 0] += 1
    }

    /// Reject the recovery and leave the step in a failed state.
    func rejectRecovery(for step: PipelineStep) {
        // Extract the original error from the .recovering status if possible,
        // otherwise mark with a generic message
        if case .recovering(let proposal) = stepStatuses[step] {
            stepStatuses[step] = .failed("Recovery rejected: \(proposal.fixDescription)")
        }
        aiRecoveryProposal = nil
        recoveringStep = nil
        // Pipeline stays stopped — isRunning stays false
    }

    /// Whether the step has exceeded maximum retries.
    func hasExceededMaxRetries(for step: PipelineStep) -> Bool {
        (retryCountByStep[step] ?? 0) >= Self.maxRetries
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
        aiRecoveryProposal = nil
        recoveringStep = nil
        retryCountByStep = [:]
    }

    func status(for step: PipelineStep) -> PipelineStepStatus {
        stepStatuses[step] ?? .pending
    }
}