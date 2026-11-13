import Foundation

/// One thing to try in the installed app, and what should happen.
struct TestCase: Identifiable, Hashable {
    let id: String
    let area: Area
    let title: String
    /// Exactly what to do, for someone who has never tested software.
    let how: String
    /// What a pass looks like, so "it seemed fine" has a definition.
    let expect: String
    /// What goes wrong for real users or reviewers when this fails.
    let why: String
    /// Required tests gate submission. The rest are strongly advised.
    let required: Bool

    enum Area: String, CaseIterable, Identifiable {
        case basics = "Does it work?"
        case features = "Your app's features"
        case realWorld = "Real-world conditions"
        case polish = "Looks finished"

        var id: String { rawValue }

        var blurb: String {
            switch self {
            case .basics: "The things a reviewer checks in their first minute."
            case .features: "Each thing your app promises to do."
            case .realWorld: "Phones lose signal, get interrupted, and run out of patience."
            case .polish: "The difference between a finished app and a demo."
            }
        }
    }
}

enum TestOutcome: String, Codable, Hashable {
    case passed, failed
}

struct TestResult: Codable, Hashable {
    var outcome: TestOutcome
    /// What went wrong, in the user's words. Fed into the next build.
    var note: String?
    var at: Date

    init(outcome: TestOutcome, note: String? = nil, at: Date = Date()) {
        self.outcome = outcome
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.at = at
    }
}

/// A test plan written for one particular app.
///
/// A generated app compiles; that says nothing about whether it does
/// what was asked. Apple's most common rejection — guideline 2.1 — is
/// simply "it didn't work when we tried it". The plan turns "test your
/// app" from advice nobody follows into a short list of specific things
/// to tap, each with a stated expected result, and the guide will not
/// offer the App Store steps until the required ones pass.
enum TestPlan {

    static func make(for app: AppDescription, requiresLogin: Bool = false) -> [TestCase] {
        let name = app.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "your app" : app.title
        var cases: [TestCase] = []

        // --- Basics ---
        cases.append(TestCase(
            id: "first_launch", area: .basics,
            title: "Open it for the very first time",
            how: "Delete \(name) from your iPhone, install it again from TestFlight, and open it.",
            expect: "It opens to something you can use within a few seconds. No blank screen, no crash, no endless spinner.",
            why: "A reviewer always starts from a fresh install. An app that only works after you've set it up fails here.",
            required: true
        ))
        cases.append(TestCase(
            id: "main_task", area: .basics,
            title: "Do the one thing the app is for",
            how: "Without thinking about how it was built, use \(name) for its main purpose from start to finish.",
            expect: "You can complete it without getting stuck, and the result is what you'd expect.",
            why: "If the main purpose doesn't work end to end, nothing else about the app matters.",
            required: true
        ))
        cases.append(TestCase(
            id: "every_button", area: .basics,
            title: "Tap everything on every screen",
            how: "Go through each screen and tap every button, link, tab and menu item once.",
            expect: "Each one does something. Nothing is dead, and nothing leads to an empty or unfinished screen.",
            why: "Reviewers tap things. A button that does nothing reads as an unfinished app and is rejected as one.",
            required: true
        ))
        if requiresLogin {
            cases.append(TestCase(
                id: "login", area: .basics,
                title: "Sign in with the test account you'll give Apple",
                how: "Sign out, then sign in using exactly the username and password you plan to put in App Review Information.",
                expect: "It signs in first time, with no verification code sent to your own phone, and shows real content.",
                why: "The reviewer has only those credentials. If they don't work, the app is rejected without being looked at.",
                required: true
            ))
        }

        // --- Features ---
        let features = app.features
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(6)
        for (index, feature) in features.enumerated() {
            cases.append(TestCase(
                id: "feature_\(index + 1)", area: .features,
                title: "Try: \(feature)",
                how: "Find this in the app and use it the way a new user would.",
                expect: "It works, and it does what those words promise.",
                why: "Your store page will describe this. If the app doesn't do it, that's rejected as inaccurate.",
                required: true
            ))
        }
        cases.append(TestCase(
            id: "odd_input", area: .features,
            title: "Give it input it isn't expecting",
            how: inputAdvice(for: app.category),
            expect: "It copes: a clear message or a sensible result. No crash and no nonsense on screen.",
            why: "Real people type the wrong thing constantly. Crashes on odd input are the commonest bug in new apps.",
            required: false
        ))

        // --- Real world ---
        cases.append(TestCase(
            id: "quit_relaunch", area: .realWorld,
            title: "Close it completely and open it again",
            how: "Add or change something in the app. Swipe up from the bottom, swipe \(name) off the top to close it, then open it again.",
            expect: "What you added is still there, and the app comes back without errors.",
            why: "An app that forgets everything when closed looks broken to anyone who uses it twice.",
            required: true
        ))
        cases.append(TestCase(
            id: "no_network", area: .realWorld,
            title: "Use it with no internet",
            how: "Turn on Airplane Mode in Control Centre, then open \(name) and use it.",
            expect: "Either it works offline, or it says plainly that it needs a connection. It doesn't freeze or crash.",
            why: "Reviewers test on poor connections, and so does everyone on a train.",
            required: true
        ))
        cases.append(TestCase(
            id: "interrupted", area: .realWorld,
            title: "Interrupt it",
            how: "Halfway through doing something, switch to another app for a minute, then come back.",
            expect: "You're where you left off, and nothing you'd entered is lost.",
            why: "Phones are interrupted all day. Losing someone's work to a text message earns one-star reviews.",
            required: false
        ))
        if needsPermissions(app) {
            cases.append(TestCase(
                id: "permission_denied", area: .realWorld,
                title: "Say no when it asks for permission",
                how: "Reinstall, and when \(name) asks for access to something, choose Don't Allow.",
                expect: "The app carries on and explains what won't work. It doesn't crash or lock you out of everything.",
                why: "Apple requires apps to keep working when permission is refused, and the reviewer will refuse.",
                required: true
            ))
        }

        // --- Polish ---
        cases.append(TestCase(
            id: "no_placeholder", area: .polish,
            title: "Hunt for leftover sample content",
            how: "Read every screen for placeholder words: \"Lorem ipsum\", \"Sample\", \"Title\", \"TODO\", made-up names, example.com.",
            expect: "Everything on screen is real, or is clearly an empty state that tells you what to do.",
            why: "Visible placeholder content is rejected as an incomplete app, even when everything else is perfect.",
            required: true
        ))
        cases.append(TestCase(
            id: "dark_mode", area: .polish,
            title: "Switch to Dark Mode",
            how: "Open Control Centre, press and hold the brightness slider, and turn on Dark Mode. Look at every screen.",
            expect: "All text is readable. Nothing disappears into the background.",
            why: "Most people leave Dark Mode on in the evening. White text on white is a common miss.",
            required: false
        ))
        cases.append(TestCase(
            id: "large_text", area: .polish,
            title: "Turn the text size up",
            how: "In Settings → Accessibility → Display & Text Size → Larger Text, drag the slider most of the way right. Look at every screen.",
            expect: "Text grows, nothing is cut off mid-word, and every button can still be reached.",
            why: "About a quarter of people change their text size. Apple's design rules expect apps to follow it.",
            required: false
        ))
        return cases
    }

    // MARK: - Reading results

    struct Summary: Equatable {
        let total: Int
        let passed: Int
        let failed: Int
        /// Required tests with no result yet.
        let requiredRemaining: Int
        /// Advised tests with no result yet.
        let optionalRemaining: Int

        /// Every required test has been tried.
        var isComplete: Bool { requiredRemaining == 0 }
        /// Tried, and nothing — required or not — is failing.
        var isPassing: Bool { isComplete && failed == 0 }
        var done: Int { passed + failed }

        var headline: String {
            if failed > 0 { return "\(failed) test\(failed == 1 ? "" : "s") failed" }
            if !isComplete { return "\(requiredRemaining) required test\(requiredRemaining == 1 ? "" : "s") to go" }
            if optionalRemaining > 0 { return "Required tests passed" }
            return "Every test passed"
        }
    }

    static func summary(of cases: [TestCase], results: [String: TestResult]) -> Summary {
        var passed = 0, failed = 0, requiredLeft = 0, optionalLeft = 0
        for test in cases {
            switch results[test.id]?.outcome {
            case .passed: passed += 1
            case .failed: failed += 1
            case nil:
                if test.required { requiredLeft += 1 } else { optionalLeft += 1 }
            }
        }
        return Summary(
            total: cases.count, passed: passed, failed: failed,
            requiredRemaining: requiredLeft, optionalRemaining: optionalLeft
        )
    }

    static func failures(in cases: [TestCase], results: [String: TestResult]) -> [(test: TestCase, note: String?)] {
        cases.compactMap { test in
            guard let result = results[test.id], result.outcome == .failed else { return nil }
            return (test, result.note)
        }
    }

    /// What to tell the next build, built from what testing found.
    /// Nil when nothing failed.
    static func fixBrief(for cases: [TestCase], results: [String: TestResult]) -> String? {
        let failed = failures(in: cases, results: results)
        guard !failed.isEmpty else { return nil }
        let lines = failed.map { item -> String in
            var line = "- \(item.test.title). Expected: \(item.test.expect)"
            if let note = item.note { line += " What happened instead: \(note)" }
            return line
        }
        return "Testing the previous build on a real iPhone found these problems. Fix every one:\n"
            + lines.joined(separator: "\n")
    }

    /// The first test still needing attention, required ones first.
    static func next(in cases: [TestCase], results: [String: TestResult]) -> TestCase? {
        cases.first { $0.required && results[$0.id] == nil }
            ?? cases.first { results[$0.id] == nil }
    }

    // MARK: - Internals

    private static func inputAdvice(for category: AppDescription.Category) -> String {
        switch category {
        case .finance:
            "Wherever it takes a number, try zero, a negative number, and an absurdly large one. Leave a required field empty and continue."
        case .games:
            "Tap fast and in the wrong order. Pause mid-game, lock the phone, and come back."
        case .social:
            "Post something empty, then something very long with emoji. Try a name with an apostrophe."
        case .photo:
            "Pick a very large photo, a screenshot, and then cancel out of the picker without choosing anything."
        default:
            "Leave fields empty and continue. Then paste in a very long piece of text with emoji."
        }
    }

    private static func needsPermissions(_ app: AppDescription) -> Bool {
        if [.photo, .health, .social].contains(app.category) { return true }
        let text = (app.prompt + " " + app.features.joined(separator: " ")).lowercased()
        return ["camera", "photo", "location", "gps", "map", "notification", "remind",
                "microphone", "contacts", "calendar", "health", "bluetooth"]
            .contains { text.contains($0) }
    }
}
