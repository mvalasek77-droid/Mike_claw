import Testing
import Foundation
@testable import MetaBro

struct OnboardingDraftTests {

    @Test func validDraftPassesValidation() {
        let draft = OnboardingDraft(handle: "bro_dawg42", displayName: "Bro Dawg")
        #expect(draft.isValid)
    }

    @Test func handleTooShortFailsValidation() {
        let draft = OnboardingDraft(handle: "ab", displayName: "Bro")
        #expect(!draft.isValid)
    }

    @Test func handleTooLongFailsValidation() {
        let draft = OnboardingDraft(handle: String(repeating: "a", count: 21), displayName: "Bro")
        #expect(!draft.isValid)
    }

    @Test func handleStartingWithDigitFailsValidation() {
        let draft = OnboardingDraft(handle: "1bro", displayName: "Bro")
        #expect(!draft.isValid)
    }

    @Test func handleWithUppercaseFailsValidation() {
        let draft = OnboardingDraft(handle: "BroDawg", displayName: "Bro")
        #expect(!draft.isValid)
    }

    @Test func handleWithInvalidCharactersFailsValidation() {
        let draft = OnboardingDraft(handle: "bro-dawg", displayName: "Bro")
        #expect(!draft.isValid)
    }

    @Test func emptyDisplayNameFailsValidation() {
        let draft = OnboardingDraft(handle: "brodawg", displayName: "   ")
        #expect(!draft.isValid)
    }

    @Test func whitespaceIsTrimmedBeforeValidating() {
        let draft = OnboardingDraft(handle: "  brodawg  ", displayName: "  Bro Dawg  ")
        #expect(draft.isValid)
    }
}

struct MockAuthServiceTests {

    private func freshDefaults() -> UserDefaults {
        let suiteName = "metabro.tests.auth.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func restoreSessionReturnsNilWhenNothingPersisted() async {
        let service = MockAuthService(defaults: freshDefaults())
        let user = await service.restoreSession()
        #expect(user == nil)
    }

    @Test func completeOnboardingWithValidDraftPersistsAndReturnsUser() async throws {
        let service = MockAuthService(defaults: freshDefaults())
        let draft = OnboardingDraft(handle: "newbro", displayName: "New Bro")
        let user = try await service.completeOnboarding(draft)
        #expect(user.handle == "@newbro")
        #expect(user.displayName == "New Bro")
        #expect(user.broCred == 0)
    }

    @Test func completeOnboardingWithInvalidDraftThrows() async throws {
        let service = MockAuthService(defaults: freshDefaults())
        let draft = OnboardingDraft(handle: "x", displayName: "Bro")
        await #expect(throws: AuthError.invalidHandle) {
            try await service.completeOnboarding(draft)
        }
    }

    @Test func restoreSessionAfterOnboardingReturnsSameUser() async throws {
        let service = MockAuthService(defaults: freshDefaults())
        let draft = OnboardingDraft(handle: "persistentbro", displayName: "Persistent Bro")
        let created = try await service.completeOnboarding(draft)
        let restored = await service.restoreSession()
        #expect(restored?.id == created.id)
        #expect(restored?.handle == created.handle)
        #expect(restored?.displayName == created.displayName)
    }

    @Test func signOutClearsPersistedState() async throws {
        let service = MockAuthService(defaults: freshDefaults())
        let draft = OnboardingDraft(handle: "leavingbro", displayName: "Leaving Bro")
        _ = try await service.completeOnboarding(draft)
        await service.signOut()
        let restored = await service.restoreSession()
        #expect(restored == nil)
    }
}

struct SessionTests {

    @Test func freshSessionStartsAsGuest() {
        let session = Session()
        #expect(session.current.id == Session.guest.id)
        #expect(!session.isSignedIn)
    }

    @Test func signInUpdatesCurrentUserAndSignedInState() {
        let session = Session()
        let user = User(id: UUID(), handle: "@bro", displayName: "Bro", avatarURL: nil, broCred: 10)
        session.signIn(as: user)
        #expect(session.current.id == user.id)
        #expect(session.isSignedIn)
    }

    @Test func signOutRevertsToGuest() {
        let session = Session()
        let user = User(id: UUID(), handle: "@bro", displayName: "Bro", avatarURL: nil, broCred: 10)
        session.signIn(as: user)
        session.signOut()
        #expect(session.current.id == Session.guest.id)
        #expect(!session.isSignedIn)
    }
}
