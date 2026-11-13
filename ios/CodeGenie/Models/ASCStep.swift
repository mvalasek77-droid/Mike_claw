import Foundation

/// The trip from a finished build to a live app, in the four parts it
/// really has.
///
/// 1. Getting the app onto a real iPhone, which means doing the Mac
///    part in Xcode by hand. There is no helper app on the Mac: the
///    guide teaches the half-dozen things to click, once.
/// 2. Testing it. A build that compiles is not an app that works, and
///    the people who find that out should be the developer and a
///    friend, not Apple's reviewer or a stranger.
/// 3. Preparing the public store page.
/// 4. Apple's review, and acting on its outcome.
enum ASCPhase: String, CaseIterable {
    case testflight = "Part 1 — Get it on your phone"
    case testing = "Part 2 — Test it properly"
    case appStore = "Part 3 — Put it on the App Store"
    case review = "Part 4 — Through Apple's review"

    var subtitle: String {
        switch self {
        case .testflight: "Open the project in Xcode on your Mac and send it to Apple, so the real app installs on your iPhone."
        case .testing: "Use it like a stranger would, and have someone else do the same. This is where rejections are prevented."
        case .appStore: "Only when you want strangers to be able to find and download it."
        case .review: "What happens after you submit, and what to do with Apple's answer."
        }
    }

    /// Short label for the progress header.
    var shortLabel: String {
        switch self {
        case .testflight: "Get it on your phone"
        case .testing: "Test it"
        case .appStore: "Prepare the store page"
        case .review: "Apple's review"
        }
    }

    /// What finishing this part means, said as an achievement.
    var doneLabel: String {
        switch self {
        case .testflight: "Installed"
        case .testing: "Tested"
        case .appStore: "Submitted"
        case .review: "Live"
        }
    }
}

struct ASCStep: Identifiable, Hashable {
    /// Stable across launches: a step's identity is its position in
    /// the process.
    var id: Int { number }
    let number: Int
    let phase: ASCPhase
    let title: String
    let body: String
    let action: ActionKind
    /// Where this step happens, so the user knows which device to pick up.
    let place: Place

    enum Place: String, Hashable {
        case phone = "On this iPhone"
        case xcode = "In Xcode on your Mac"
        case web = "On Apple's website"
        case apple = "Apple does this"
    }

    enum ActionKind: Hashable {
        /// Send the project from the phone to the Mac.
        case transferProject
        /// Something the user does in Xcode, following the walkthrough.
        case xcode
        /// A page on one of Apple's websites.
        case website(String)
        /// Waiting on Apple to process an upload.
        case wait(String)
        /// Tells the user exactly where to look for the install invite.
        case openTestFlightApp
        /// Working through the test plan in the installed app.
        case testPlan
        /// Explains internal vs. external testers and the public link.
        case inviteTesters
        /// Decide whether testing passed, or go back and rebuild.
        case testVerdict
        /// The user prepares an asset outside CodeGenie.
        case prepareAsset(String)
        /// The listing form, drafted and validated here.
        case fillForm
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

    /// Who does the work. Drives the badge on each step.
    var ownership: Ownership {
        switch action {
        case .wait: return .apple
        case .review(let moment): return moment == .release ? .you : .apple
        case .fillForm, .reviewNotes, .testPlan, .transferProject: return .together
        default: return .you
        }
    }

    enum Ownership {
        case together, you, apple

        var label: String {
            switch self {
            case .together: "Together"
            case .you:      "You"
            case .apple:    "Apple"
            }
        }

        var explanation: String {
            switch self {
            case .together: "CodeGenie prepares it. You check it and carry it out."
            case .you:      "You do this, following the instructions. Ask the coach if anything looks different."
            case .apple:    "Apple does this. Nothing for you to do but wait."
            }
        }
    }
}

extension ASCStep {
    /// Step numbers are persisted with every saved submission, so the
    /// numbering is versioned. See `ASCSubmissionRecord.migrate`.
    static let schemaVersion = 3

    static let uploadStepNumber = 6
    static let processingStepNumber = 7
    static let testPlanStepNumber = 9
    static let testVerdictStepNumber = 11
    static let buildSelectionStepNumber = 19
    /// The step at which the user presses Submit in App Store Connect.
    static let submitStepNumber = 20
    static let queueStepNumber = 21
    static let decisionStepNumber = 22
    static let releaseStepNumber = 23

    static let all: [ASCStep] = [
        // ---- Part 1: Get it on your phone ----
        .init(number: 1, phase: .testflight,
              title: "Send the project to your Mac",
              body: "Your app exists as a folder of code. It has to be on a Mac to become something an iPhone can run.",
              action: .transferProject, place: .phone),

        .init(number: 2, phase: .testflight,
              title: "Open it in Xcode",
              body: "Xcode is Apple's free app for building apps. You'll open your project in it and sign in with your Apple ID.",
              action: .xcode, place: .xcode),

        .init(number: 3, phase: .testflight,
              title: "Tell Xcode who you are",
              body: "Signing is how Apple knows an app came from you. One checkbox and one menu, and Xcode handles the rest.",
              action: .xcode, place: .xcode),

        .init(number: 4, phase: .testflight,
              title: "Run it on your Mac first",
              body: "Press one button and your app opens in a simulated iPhone on your Mac. This is your first look at it actually running.",
              action: .xcode, place: .xcode),

        .init(number: 5, phase: .testflight,
              title: "Create the app's record at Apple",
              body: "Apple needs an empty record with your app's name and ID before it will accept an upload.",
              action: .website("https://appstoreconnect.apple.com/apps"), place: .web),

        .init(number: 6, phase: .testflight,
              title: "Archive and upload from Xcode",
              body: "Xcode packages the finished app and sends it to Apple. Two menu items and a few clicks of Next.",
              action: .xcode, place: .xcode),

        .init(number: 7, phase: .testflight,
              title: "Wait for Apple to process it",
              body: "Usually 5–30 minutes. Apple emails you when it's done.",
              action: .wait("Apple is processing your build"), place: .apple),

        .init(number: 8, phase: .testflight,
              title: "Install it with TestFlight",
              body: "TestFlight is Apple's free app for trying builds before they're public. This puts the real app on your Home Screen.",
              action: .openTestFlightApp, place: .phone),

        // ---- Part 2: Test it properly ----
        .init(number: 9, phase: .testing,
              title: "Test it yourself",
              body: "Work through a short test plan made for your app. Each test takes a minute and catches something reviewers reject for.",
              action: .testPlan, place: .phone),

        .init(number: 10, phase: .testing,
              title: "Have someone else test it",
              body: "You know where not to tap. Nobody else does. One other person using it finds most of what a reviewer would.",
              action: .inviteTesters, place: .web),

        .init(number: 11, phase: .testing,
              title: "Decide if it's ready",
              body: "If testing found problems, fix them now with a rebuild. Going on with known bugs costs days, not minutes.",
              action: .testVerdict, place: .phone),

        // ---- Part 3: Prepare the store page ----
        .init(number: 12, phase: .appStore,
              title: "Prepare your 1024×1024 icon",
              body: "Exactly 1024×1024, PNG, no transparency, no pre-rounded corners. Apple rejects anything else automatically.",
              action: .prepareAsset("icon-1024.png"), place: .phone),

        .init(number: 13, phase: .appStore,
              title: "Take your screenshots",
              body: "At least one iPhone size, showing the real app with real content.",
              action: .prepareAsset("screenshots"), place: .xcode),

        .init(number: 14, phase: .appStore,
              title: "Fill in the listing",
              body: "Name, subtitle, keywords, description, copyright and URLs. CodeGenie drafts them and checks every one against Apple's limits.",
              action: .fillForm, place: .web),

        .init(number: 15, phase: .appStore,
              title: "Answer the privacy questions",
              body: "Apple asks what data you collect. Answer honestly — this is audited, and a wrong answer can pull a live app.",
              action: .website("https://appstoreconnect.apple.com/apps"), place: .web),

        .init(number: 16, phase: .appStore,
              title: "Set the age rating",
              body: "A short questionnaire about what the app contains. Apple works out the rating from your answers.",
              action: .website("https://appstoreconnect.apple.com/apps"), place: .web),

        .init(number: 17, phase: .appStore,
              title: "Set pricing and availability",
              body: "Free in all countries is the safe default. Price can change later without a new review.",
              action: .website("https://appstoreconnect.apple.com/apps"), place: .web),

        .init(number: 18, phase: .appStore,
              title: "Tell the reviewer how to use your app",
              body: "Who to contact, a working test login if your app has one, and notes explaining anything a stranger wouldn't work out alone.",
              action: .reviewNotes, place: .web),

        .init(number: 19, phase: .appStore,
              title: "Pick the build and choose when it goes live",
              body: "Attach the build you tested to this version, answer two legal questions, and choose manual or automatic release.",
              action: .website("https://appstoreconnect.apple.com/apps"), place: .web),

        .init(number: 20, phase: .appStore,
              title: "Submit for review",
              body: "Press Add for Review, then Submit. Apple requires the account holder to do this.",
              action: .submit, place: .web),

        // ---- Part 4: Through review ----
        .init(number: 21, phase: .review,
              title: "Wait in Apple's queue",
              body: "Your app shows as Waiting for Review until a reviewer picks it up. Most apps are picked up within a day.",
              action: .review(.queue), place: .apple),

        .init(number: 22, phase: .review,
              title: "Read Apple's decision",
              body: "Approved, or sent back with the exact guideline it fell short of. A rejection is common on a first app and almost always fixable.",
              action: .review(.decision), place: .apple),

        .init(number: 23, phase: .review,
              title: "Release it",
              body: "Once approved, your app goes live automatically or when you press Release — whichever you chose.",
              action: .review(.release), place: .web)
    ]

    static func steps(in phase: ASCPhase) -> [ASCStep] { all.filter { $0.phase == phase } }

    static func step(_ number: Int) -> ASCStep? { all.first { $0.number == number } }
}
