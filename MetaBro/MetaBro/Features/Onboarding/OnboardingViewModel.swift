import SwiftUI

/// Drives the three-step onboarding flow: welcome → claim an identity →
/// agree to the Code of Conduct. Identity-based onboarding is a Phase 0
/// foundation requirement — the app shouldn't boot straight into the tabs.
@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable, Equatable { case welcome, identity, codeOfConduct }

    enum Phase: Equatable {
        case editing
        case submitting
        case failed(String)
    }

    private(set) var step: Step = .welcome
    var handle: String = ""
    var displayName: String = ""
    var agreedToCodeOfConduct = false
    private(set) var phase: Phase = .editing

    private let service: AuthService
    private let session: Session

    /// `session` defaults to the app-wide singleton; tests inject a private
    /// instance so they don't mutate global state shared with other suites.
    init(service: AuthService, session: Session = .shared) {
        self.service = service
        self.session = session
    }

    var draft: OnboardingDraft {
        OnboardingDraft(handle: handle, displayName: displayName)
    }

    var canContinueFromIdentity: Bool { draft.isValid }
    var canFinish: Bool { agreedToCodeOfConduct && draft.isValid && phase != .submitting }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        HapticsEngine.shared.play(.selectionChanged)
        step = next
    }

    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    /// Completes onboarding. Returns whether it succeeded so the view can
    /// hand off to the rest of the app.
    func finish() async -> Bool {
        guard canFinish else { return false }
        phase = .submitting
        do {
            let user = try await service.completeOnboarding(draft)
            session.signIn(as: user)
            HapticsEngine.shared.play(.refreshDone)
            phase = .editing
            return true
        } catch {
            BroLog.error(error, category: "onboarding")
            phase = .failed("Couldn't set up your account. Check your connection and try again.")
            HapticsEngine.shared.play(.error)
            return false
        }
    }
}
