import Foundation

/// The submission journey has three honest phases, because Apple's own
/// process has three: TestFlight only needs an app record and a
/// processed build; the public App Store needs the listing, privacy
/// answers and review details; and after you press Submit there is a
/// review whose outcome you have to act on. The guide used to stop at
/// "Submitted", which is exactly where a first-timer is most alone.
enum ASCPhase: String, CaseIterable {
    case testflight = "Part 1 — Get it on your phone"
    case appStore = "Part 2 — Put it on the App Store"
    case review = "Part 3 — Through Apple's review"

    var subtitle: String {
        switch self {
        case .testflight: "The least Apple needs before you and your friends can install the real app."
        case .appStore: "Only when you want strangers to be able to find and download it."
        case .review: "What happens after you submit, and what to do with Apple's answer."
        }
    }

    /// Short label for the progress header.
    var shortLabel: String {
        switch self {
        case .testflight: "Get it testable"
        case .appStore: "Prepare the store page"
        case .review: "Apple's review"
        }
    }
}

struct ASCStep: Identifiable, Hashable {
    /// Stable across launches, unlike a fresh UUID: step identity is
    /// its position in Apple's process.
    var id: Int { number }
    let number: Int
    let phase: ASCPhase
    let title: String
    let body: String
    let action: ActionKind
    let safariRoute: String?

    enum ActionKind: Hashable {
        /// CodeGenie opens the URL in the paired Mac's Safari.
        case openSafariOnMac(String)
        /// CodeGenie actually performs the TestFlight upload itself.
        case uploadToTestFlight
        /// Tells the user exactly where to look for the install invite.
        case openTestFlightApp
        /// Explains internal vs. external testers and the public link.
        case inviteTesters
        /// CodeGenie types the listing fields into the open ASC page.
        case fillForm
        /// The user prepares an asset outside CodeGenie.
        case prepareAsset(String)
        /// Waiting on Apple to process an upload.
        case wait(String)
        /// Only the account holder can do this.
        case manual
        /// CodeGenie drafts the notes Apple's reviewer reads.
        case reviewNotes
        /// The moment of submission, gated on readiness.
        case submit
        /// Tracking Apple's review of the submitted version.
        case review(ReviewMoment)
    }

    /// The three points in a review where the user needs different help.
    enum ReviewMoment: Hashable {
        case queue, decision, release
    }

    /// Who actually performs the work. Drives the Hybrid/You/Apple badge.
    var ownership: Ownership {
        switch action {
        case .openSafariOnMac, .fillForm, .uploadToTestFlight, .reviewNotes: return .hybrid
        case .prepareAsset, .openTestFlightApp, .inviteTesters, .manual, .submit: return .you
        case .wait: return .apple
        case .review(let moment): return moment == .release ? .you : .apple
        }
    }

    enum Ownership {
        case hybrid, you, apple

        var label: String {
            switch self {
            case .hybrid: "Hybrid"
            case .you:    "You"
            case .apple:  "Apple"
            }
        }

        var explanation: String {
            switch self {
            case .hybrid: "CodeGenie does the heavy lifting. You review and confirm."
            case .you:    "You do this — CodeGenie can't tap buttons in your Apple account."
            case .apple:  "Apple does this. Nothing for you to do but wait."
            }
        }
    }
}

extension ASCStep {
    /// Step numbers are persisted with every saved submission, so the
    /// numbering is versioned. See `ASCSubmissionRecord.migrate`.
    static let schemaVersion = 2

    /// The step at which the user presses Submit in App Store Connect.
    static let submitStepNumber = 15

    static let all: [ASCStep] = [
        // ---- Phase 1: Get it testable ----
        .init(number: 1, phase: .testflight,
              title: "Sign in to App Store Connect",
              body: "CodeGenie opens appstoreconnect.apple.com in your Mac's Safari. You sign in there — your password and 2-factor codes never touch CodeGenie.",
              action: .openSafariOnMac("https://appstoreconnect.apple.com"),
              safariRoute: "https://appstoreconnect.apple.com"),

        .init(number: 2, phase: .testflight,
              title: "Create the app record",
              body: "Click + → New App. Platform iOS, and the bundle ID must match your Xcode target exactly or the upload in the next step fails.",
              action: .openSafariOnMac("https://appstoreconnect.apple.com/apps"),
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 3, phase: .testflight,
              title: "Upload your build",
              body: "CodeGenie runs Apple's validate-then-upload flow itself. No listing, no screenshots, no pricing needed yet — just the app record from step 2 and a signed build.",
              action: .uploadToTestFlight,
              safariRoute: nil),

        .init(number: 4, phase: .testflight,
              title: "Wait for Apple to process it",
              body: "Usually 5–30 minutes. CodeGenie keeps checking with Apple while this screen is open.",
              action: .wait("Apple is processing your build"),
              safariRoute: nil),

        .init(number: 5, phase: .testflight,
              title: "Open TestFlight on your iPhone",
              body: "Apple emails the account holder an invite once the build finishes processing. Accept it, then TestFlight installs your real app.",
              action: .openTestFlightApp,
              safariRoute: nil),

        .init(number: 6, phase: .testflight,
              title: "Invite testers",
              body: "Internal testers (your ASC team, up to 100) get it instantly. External testers (up to 10,000, via a public link or email) need one Apple review the first time — usually under a day.",
              action: .inviteTesters,
              safariRoute: nil),

        // ---- Phase 2: Prepare the store page ----
        .init(number: 7, phase: .appStore,
              title: "Prepare your 1024×1024 icon",
              body: "Exactly 1024×1024, PNG, no alpha channel, no pre-rounded corners. Apple rejects anything else without review.",
              action: .prepareAsset("icon-1024.png"),
              safariRoute: nil),

        .init(number: 8, phase: .appStore,
              title: "Prepare screenshots",
              body: "At least one iPhone display size. Screenshots showing placeholder or lorem-ipsum content are a common rejection reason.",
              action: .prepareAsset("screenshots"),
              safariRoute: nil),

        .init(number: 9, phase: .appStore,
              title: "Fill in the listing",
              body: "Name, subtitle, keywords, description, copyright and URLs. CodeGenie checks every field against Apple's limits before you paste anything.",
              action: .fillForm,
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 10, phase: .appStore,
              title: "Answer the privacy questions",
              body: "Apple asks what data you collect. Answer honestly — this is audited, and a wrong answer here pulls a live app.",
              action: .manual,
              safariRoute: nil),

        .init(number: 11, phase: .appStore,
              title: "Set the age rating",
              body: "A short questionnaire about violence, mature themes, gambling and unrestricted web access. Apple works out the rating from your answers.",
              action: .manual,
              safariRoute: nil),

        .init(number: 12, phase: .appStore,
              title: "Set pricing and availability",
              body: "Free in all territories is the safe default. Price can change later without a new review.",
              action: .manual,
              safariRoute: nil),

        .init(number: 13, phase: .appStore,
              title: "Tell the reviewer how to use your app",
              body: "App Review Information: who to contact, a working test login if your app has one, and notes explaining anything a stranger would not work out alone.",
              action: .reviewNotes,
              safariRoute: nil),

        .init(number: 14, phase: .appStore,
              title: "Pick the build and choose when it goes live",
              body: "Attach the processed build to this version, answer the export-compliance and content-rights questions, and choose manual or automatic release.",
              action: .manual,
              safariRoute: nil),

        .init(number: 15, phase: .appStore,
              title: "Submit for review",
              body: "Press Add for Review, then Submit. Apple requires the account holder to do this.",
              action: .submit,
              safariRoute: nil),

        // ---- Phase 3: Through review ----
        .init(number: 16, phase: .review,
              title: "Wait in Apple's queue",
              body: "Your app shows as Waiting for Review until a reviewer picks it up. Most apps are picked up within a day.",
              action: .review(.queue),
              safariRoute: nil),

        .init(number: 17, phase: .review,
              title: "Read Apple's decision",
              body: "Approved, or sent back with the exact guideline it fell short of. A rejection is common on a first app and almost always fixable.",
              action: .review(.decision),
              safariRoute: nil),

        .init(number: 18, phase: .review,
              title: "Release it",
              body: "Once approved, your app goes live automatically or when you press Release — whichever you chose in step 14.",
              action: .review(.release),
              safariRoute: nil)
    ]

    static func steps(in phase: ASCPhase) -> [ASCStep] { all.filter { $0.phase == phase } }

    static func step(_ number: Int) -> ASCStep? { all.first { $0.number == number } }
}
