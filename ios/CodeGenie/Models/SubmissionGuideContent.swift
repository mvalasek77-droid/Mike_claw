import Foundation

/// The tutorial shown before the first step, and the explanation shown
/// after the last one the user controls.
///
/// Fixed text, kept with the rules rather than in the views, so that
/// what the app promises about the process can be checked against the
/// steps it actually contains.
enum SubmissionTutorial {

    struct Page: Identifiable, Hashable {
        let id: String
        let symbol: String
        let title: String
        let body: String
        let points: [String]
    }

    static func pages(appName: String) -> [Page] {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "your app" : appName
        return [
            Page(
                id: "overview",
                symbol: "map.fill",
                title: "Here's the whole trip",
                body: "Getting \(name) from here to the App Store has four parts. You can stop after any of them and pick up later — your place is saved.",
                points: ASCPhase.allCases.map { phase in
                    "\(phase.shortLabel): \(ASCStep.steps(in: phase).count) steps"
                }
            ),
            Page(
                id: "needs",
                symbol: "checklist",
                title: "What you'll need",
                body: "Nothing here is optional, and it's better to know now than at step 3.",
                points: [
                    "A Mac. Apple only allows iPhone apps to be packaged on one. Any Mac from the last few years works.",
                    "Xcode, Apple's free app for building apps. It's a large download from the Mac App Store, so start it early.",
                    "Apple's Developer Program: $99 a year, paid to Apple. Approval can take a day or two.",
                    "About two hours spread over a few days. Most of the waiting is Apple's.",
                ]
            ),
            Page(
                id: "xcode",
                symbol: "hammer.fill",
                title: "You'll use Xcode yourself — briefly",
                body: "Xcode looks intimidating and you need about six buttons in it. Each step tells you exactly which one, in order, and what you should see afterwards.",
                points: [
                    "CodeGenie sends the project to your Mac. You open it.",
                    "You pick your name from one menu so Apple knows the app is yours.",
                    "You press Run to see it, then Archive to send it to Apple.",
                    "If Xcode shows an error, copy it and ask the coach. It has seen most of them.",
                ]
            ),
            Page(
                id: "testing",
                symbol: "checkmark.shield.fill",
                title: "Testing is not optional",
                body: "The app was written by AI. It builds, which proves only that the code is valid — not that it does what you asked. The most common reason Apple rejects an app is simply that it didn't work when they tried it.",
                points: [
                    "You'll get a short test plan written for your app, with what to tap and what should happen.",
                    "Anything that fails goes straight into a rebuild, in your own words.",
                    "The App Store steps unlock when the required tests pass.",
                    "Ten minutes of testing saves a rejection and several days.",
                ]
            ),
            Page(
                id: "help",
                symbol: "bubble.left.and.text.bubble.right.fill",
                title: "You're not doing this alone",
                body: "Every step has a coach that knows which step you're on, what your app is called, and what's still outstanding.",
                points: [
                    "One step on screen at a time, with the literal clicks.",
                    "\"Where people get stuck\" on each step, before you get stuck there.",
                    "Tap Ask on any step to describe what you're seeing, or paste an error.",
                    "After you submit, CodeGenie follows Apple's review with you until the app is live.",
                ]
            ),
        ]
    }
}

/// What the user is told the moment they have submitted.
///
/// Pressing Submit is where a first-timer's instructions run out and
/// the anxiety starts: nothing visibly happens for a day. This says
/// what is going on, what they should and shouldn't do, and what each
/// possible outcome will mean.
enum AfterSubmission {

    struct Section: Identifiable, Hashable {
        let id: String
        let symbol: String
        let title: String
        let body: String
    }

    static let headline = "Submitted. Here's what happens now."

    static let sections: [Section] = [
        Section(
            id: "queue",
            symbol: "hourglass",
            title: "First, it waits in a queue",
            body: "The status reads Waiting for Review. Nothing is being judged yet. Most apps are picked up within a day; a first app, or the week of a new iOS release, can take a little longer."
        ),
        Section(
            id: "review",
            symbol: "person.fill.viewfinder",
            title: "Then a person at Apple uses your app",
            body: "The status changes to In Review. A reviewer installs your app on a real iPhone, taps through it, reads your store page and opens your links. This usually takes from a few minutes to a few hours."
        ),
        Section(
            id: "meanwhile",
            symbol: "hand.raised.fill",
            title: "While you wait",
            body: "Leave the submission alone — editing it or cancelling sends you to the back of the queue. Keep your support page, your privacy policy and any server your app uses online. Watch the email address on your developer account; reviewers write there if they get stuck."
        ),
        Section(
            id: "approved",
            symbol: "checkmark.seal.fill",
            title: "If it's approved",
            body: "Apple emails you. The app goes live by itself, or waits for you to press Release if you chose manual release. It can take a few hours to show up in search; the direct link works straight away."
        ),
        Section(
            id: "rejected",
            symbol: "arrow.uturn.backward.circle.fill",
            title: "If it's sent back",
            body: "This is normal — it happens to most first apps and it is not a mark against your account. Apple names the exact guideline and describes what they saw. CodeGenie explains what that guideline means, what to change, and gives you a reply to adapt. You can resubmit as many times as it takes."
        ),
        Section(
            id: "tracking",
            symbol: "bell.badge.fill",
            title: "How you'll know",
            body: "Apple emails the account holder at every change. Open this guide any time and CodeGenie shows where the app stands and what, if anything, you need to do."
        ),
    ]
}
