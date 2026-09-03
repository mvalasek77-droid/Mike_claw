import Foundation

/// The AI guidance layer for App Store Connect submission.
///
/// **Why this exists.** A first-time submitter does not know that
/// Apple silently truncates a 31-character subtitle, that keywords are
/// a single 100-char comma-joined string (not a list), or that a
/// missing support URL is a hard rejection. Before this, CodeGenie
/// drafted metadata and hoped. Now the coach validates every field
/// against Apple's real limits, tells the user exactly what is wrong
/// in plain English, and refuses to advance a step that would produce
/// a rejection.
///
/// The coach is deterministic — no LLM call. Apple's limits are fixed
/// and public, so a rules engine gives a faster, cheaper, and more
/// reliable answer than a model would, and it works offline.
enum ASCCoach {

    // MARK: - Apple's real field limits
    //
    // Sourced from App Store Connect Help → "Reference → App
    // information". These are hard server-side limits: exceed them and
    // the form refuses to save (or silently truncates, which is worse
    // because the user does not notice until review).

    enum Limit {
        static let name = 30
        static let subtitle = 30
        static let promotionalText = 170
        static let description = 4000
        /// Keywords is ONE field: a comma-separated string capped at
        /// 100 characters total, including the commas. Users routinely
        /// assume it's 100 chars per keyword.
        static let keywordsTotal = 100
        static let descriptionMinimum = 10
    }

    // MARK: - Issues

    struct Issue: Identifiable, Hashable {
        let id = UUID()
        let field: Field
        let severity: Severity
        let message: String
        /// What the user should actually do about it.
        let fix: String

        enum Severity: Int, Comparable {
            case blocking = 2
            case warning = 1

            static func < (a: Severity, b: Severity) -> Bool {
                a.rawValue < b.rawValue
            }
        }

        enum Field: String, Hashable {
            case name, subtitle, keywords, description
            case promotionalText, supportURL, marketingURL
            case category, ageRating, price
        }
    }

    // MARK: - Validation

    /// Validate a metadata draft against Apple's rules.
    /// Returns issues sorted blocking-first.
    static func validate(_ m: AppStoreMetadata) -> [Issue] {
        var issues: [Issue] = []

        // --- Name (required, ≤30) ---
        let name = m.name.trimmed
        if name.isEmpty {
            issues.append(.init(
                field: .name, severity: .blocking,
                message: "App name is empty.",
                fix: "Every app needs a name. This is what shows under the icon on the Home Screen."
            ))
        } else if name.count > Limit.name {
            issues.append(.init(
                field: .name, severity: .blocking,
                message: "App name is \(name.count) characters — Apple's limit is \(Limit.name).",
                fix: "Trim \(name.count - Limit.name) character\(name.count - Limit.name == 1 ? "" : "s"). Short names also look better on the Home Screen."
            ))
        }

        // --- Subtitle (optional but strongly recommended, ≤30) ---
        let subtitle = m.subtitle.trimmed
        if subtitle.isEmpty {
            issues.append(.init(
                field: .subtitle, severity: .warning,
                message: "No subtitle.",
                fix: "The subtitle sits under your name in search results. Apps with one get noticeably more taps."
            ))
        } else if subtitle.count > Limit.subtitle {
            issues.append(.init(
                field: .subtitle, severity: .blocking,
                message: "Subtitle is \(subtitle.count) characters — Apple's limit is \(Limit.subtitle).",
                fix: "Trim \(subtitle.count - Limit.subtitle) character\(subtitle.count - Limit.subtitle == 1 ? "" : "s")."
            ))
        }

        // --- Keywords (ONE comma-joined field, ≤100 total) ---
        let keywordString = m.keywords
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        if keywordString.isEmpty {
            issues.append(.init(
                field: .keywords, severity: .warning,
                message: "No keywords.",
                fix: "Keywords are how people find you in search. Add a few terms someone would actually type."
            ))
        } else if keywordString.count > Limit.keywordsTotal {
            issues.append(.init(
                field: .keywords, severity: .blocking,
                message: "Keywords total \(keywordString.count) characters — Apple's limit is \(Limit.keywordsTotal) for the whole comma-separated list.",
                fix: "Remove \(keywordString.count - Limit.keywordsTotal) character\(keywordString.count - Limit.keywordsTotal == 1 ? "" : "s"). Drop the weakest terms — this is one field, not one limit per word."
            ))
        }

        // --- Description (required, 10…4000) ---
        let description = m.description.trimmed
        if description.count < Limit.descriptionMinimum {
            issues.append(.init(
                field: .description, severity: .blocking,
                message: description.isEmpty ? "Description is empty." : "Description is too short.",
                fix: "Write at least a couple of sentences on what the app does and who it's for. Reviewers read this."
            ))
        } else if description.count > Limit.description {
            issues.append(.init(
                field: .description, severity: .blocking,
                message: "Description is \(description.count) characters — Apple's limit is \(Limit.description).",
                fix: "Trim \(description.count - Limit.description) characters."
            ))
        }

        // --- Promotional text (optional, ≤170) ---
        let promo = m.promotionalText.trimmed
        if promo.count > Limit.promotionalText {
            issues.append(.init(
                field: .promotionalText, severity: .blocking,
                message: "Promotional text is \(promo.count) characters — Apple's limit is \(Limit.promotionalText).",
                fix: "Trim \(promo.count - Limit.promotionalText) characters."
            ))
        }

        // --- Support URL (REQUIRED by Apple) ---
        let support = m.supportURL.trimmed
        if support.isEmpty {
            issues.append(.init(
                field: .supportURL, severity: .blocking,
                message: "Support URL is missing — Apple requires one.",
                fix: "A page where users can reach you. A GitHub repo README or a simple contact page is enough."
            ))
        } else if !isPlausibleURL(support) {
            issues.append(.init(
                field: .supportURL, severity: .blocking,
                message: "Support URL doesn't look like a valid link.",
                fix: "It must start with https:// and point at a real, reachable page."
            ))
        } else if isPlaceholderURL(support) {
            issues.append(.init(
                field: .supportURL, severity: .blocking,
                message: "Support URL is still the placeholder.",
                fix: "Replace example.com with a page you actually control — Apple checks that this loads."
            ))
        }

        // --- Marketing URL (optional) ---
        let marketing = m.marketingURL.trimmed
        if !marketing.isEmpty {
            if !isPlausibleURL(marketing) {
                issues.append(.init(
                    field: .marketingURL, severity: .warning,
                    message: "Marketing URL doesn't look like a valid link.",
                    fix: "Either fix it or clear it — this field is optional."
                ))
            } else if isPlaceholderURL(marketing) {
                issues.append(.init(
                    field: .marketingURL, severity: .warning,
                    message: "Marketing URL is still the placeholder.",
                    fix: "Clear it or point it at your real site. It's optional, so empty is better than fake."
                ))
            }
        }

        // --- Category ---
        if m.primaryCategory.trimmed.isEmpty {
            issues.append(.init(
                field: .category, severity: .blocking,
                message: "No primary category.",
                fix: "Pick the category people would browse to find an app like yours."
            ))
        }

        return issues.sorted { a, b in
            if a.severity != b.severity { return a.severity > b.severity }
            return a.field.rawValue < b.field.rawValue
        }
    }

    static func blockingIssues(_ m: AppStoreMetadata) -> [Issue] {
        validate(m).filter { $0.severity == .blocking }
    }

    static func isMetadataReady(_ m: AppStoreMetadata) -> Bool {
        blockingIssues(m).isEmpty
    }

    // MARK: - Character budget helpers (for live UI counters)

    static func remaining(_ text: String, limit: Int) -> Int {
        limit - text.trimmed.count
    }

    static func keywordString(_ keywords: [String]) -> String {
        keywords.map { $0.trimmed }.filter { !$0.isEmpty }.joined(separator: ",")
    }

    // MARK: - Scoped readiness gates
    //
    // The backend's release-readiness audit returns one flat list of
    // items, but TestFlight and full App Store submission need
    // different subsets of it — TestFlight only needs a build,
    // credentials, and the privacy manifest; the public listing,
    // screenshots, and privacy policy doc are App-Store-only. Rather
    // than teach the backend two gates, we filter client-side: it's
    // the same data, read two different ways.

    private static let testFlightUploadKeys: Set<String> = [
        "workspace", "xcode_project", "ipa", "apple_credentials",
        "testflight_upload", "privacy_manifest",
    ]

    private static let doneStatuses: Set<String> = ["automated", "assisted", "user_confirmation"]

    /// A `nil` run reads as "nothing outstanding" rather than "unknown"
    /// — callers that can't rule out a missing/failed fetch (as
    /// opposed to a genuinely absent backend job, which they should
    /// check first) should treat a `nil` readiness result as
    /// unverified, not as a pass.
    static func outstandingForTestFlightUpload(_ run: ReleaseReadinessRun?) -> [ReleaseReadinessItem] {
        guard let run else { return [] }
        return run.items.filter {
            $0.required && testFlightUploadKeys.contains($0.key) && !doneStatuses.contains($0.status)
        }
    }

    static func isReadyForTestFlightUpload(_ run: ReleaseReadinessRun?) -> Bool {
        run != nil && outstandingForTestFlightUpload(run).isEmpty
    }

    /// Full App Store submission needs everything the backend marks
    /// required — this is exactly what `releaseGate` already computes,
    /// so we just read it rather than re-deriving the same logic.
    static func isReadyForAppStoreSubmission(_ run: ReleaseReadinessRun?) -> Bool {
        run?.isReadyForTestFlight == true
    }

    static func outstandingForAppStoreSubmission(_ run: ReleaseReadinessRun?) -> [ReleaseReadinessItem] {
        guard let run else { return [] }
        return run.items.filter { $0.required && !doneStatuses.contains($0.status) }
    }

    // MARK: - URL heuristics

    private static func isPlausibleURL(_ s: String) -> Bool {
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              host.contains(".")
        else { return false }
        return true
    }

    private static func isPlaceholderURL(_ s: String) -> Bool {
        let lowered = s.lowercased()
        return ["example.com", "example.org", "yoursite", "your-site",
                "changeme", "placeholder", "todo"].contains { lowered.contains($0) }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Step walkthroughs
//
// The guide used to show each step as one sentence ("Click + → New
// App"). That assumes the reader already knows what App Store Connect
// looks like. A first-time submitter does not: they do not know where
// the + is, what a bundle ID is, what an SKU is, or which of the
// fifteen fields on the screen actually matter.
//
// A `Walkthrough` is the literal set of clicks for one step, plus the
// single mistake that most often trips people up on it. It stays a
// deterministic lookup rather than an LLM call — Apple's console is a
// fixed target, so canned instructions are faster, free, work offline,
// and cannot hallucinate a button that does not exist.

extension ASCCoach {

    struct Walkthrough {
        /// The step restated the way a person would say it out loud.
        let plainTitle: String
        /// What this step actually is, for someone who has never seen it.
        let whatThisIs: String
        /// The literal clicks, in order.
        let doThis: [Instruction]
        /// The one thing that most commonly goes wrong here.
        let watchOut: String?
        /// Sets expectations so a 20-minute wait doesn't read as a hang.
        let timeEstimate: String

        struct Instruction: Identifiable, Hashable {
            let id = UUID()
            let text: String
            /// A literal value the user should paste, surfaced with a
            /// copy button so they never retype it and never typo it.
            var copyValue: String? = nil
        }
    }

    static func walkthrough(
        for step: ASCStep,
        appName: String,
        bundleID: String,
        macPaired: Bool
    ) -> Walkthrough {
        switch step.number {

        case 1:
            return Walkthrough(
                plainTitle: "Sign in to Apple's website",
                whatThisIs: "App Store Connect is the Apple website where you manage your apps. It is separate from your iPhone and from Xcode. Everything about publishing happens here.",
                doThis: [
                    .init(text: macPaired
                          ? "Tap the button below. CodeGenie opens the site in Safari on your Mac."
                          : "Open appstoreconnect.apple.com in your browser.",
                          copyValue: macPaired ? nil : "https://appstoreconnect.apple.com"),
                    .init(text: "Sign in with the Apple ID that is enrolled in the Apple Developer Program. This is often not the Apple ID you use for shopping."),
                    .init(text: "Enter the 6-digit code Apple sends to your devices."),
                    .init(text: "You should land on a page with a row of icons: Apps, TestFlight, Users and Access. That means you're in."),
                ],
                watchOut: "If you see \"You do not have permission to access this page\", your Apple ID is signed in but not enrolled in the Developer Program yet. That's the $99/year step, and it can take Apple a day to approve.",
                timeEstimate: "2 minutes"
            )

        case 2:
            return Walkthrough(
                plainTitle: "Tell Apple your app exists",
                whatThisIs: "Before you can upload anything, Apple needs an empty record to attach it to. You are just reserving the name and the ID here — no screenshots, no description, nothing public.",
                doThis: [
                    .init(text: "Click Apps in the top row, then the blue + button near the top-left, then New App."),
                    .init(text: "Platforms: tick iOS."),
                    .init(text: "Name: this is the public name on the App Store. It must be unique across the whole store.", copyValue: appName),
                    .init(text: "Primary Language: whatever language your app's text is in."),
                    .init(text: "Bundle ID: pick this exact one from the dropdown. It has to match what CodeGenie built, or the upload in the next step is rejected.", copyValue: bundleID),
                    .init(text: "SKU: your own private reference code. Nobody ever sees it. Reusing the bundle ID is fine.", copyValue: bundleID),
                    .init(text: "User Access: leave it on Full Access."),
                    .init(text: "Click Create."),
                ],
                watchOut: "If your bundle ID isn't in the dropdown, it hasn't been registered yet. Go to developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → + and register it first, then come back and reload this page.",
                timeEstimate: "5 minutes"
            )

        case 3:
            return Walkthrough(
                plainTitle: "Send your app to Apple",
                whatThisIs: "This is the actual upload. CodeGenie signs the build, runs Apple's validation, and pushes it to your app record. You don't need a listing, screenshots, or pricing for this — only the record you just made.",
                doThis: [
                    .init(text: "Make sure step 2 is finished and the app record exists."),
                    .init(text: "Tap Upload to TestFlight below."),
                    .init(text: "CodeGenie checks your Apple credentials and the build first. If something's missing it tells you exactly what, instead of failing halfway through."),
                    .init(text: "Leave the app open while the progress strip is moving."),
                ],
                watchOut: "An upload rejected for \"no valid signing identity\" almost always means your Apple Developer credentials in Settings are incomplete. Fix them there and tap upload again — you don't need to rebuild.",
                timeEstimate: "3 to 10 minutes depending on your connection"
            )

        case 4:
            return Walkthrough(
                plainTitle: "Wait for Apple to check it",
                whatThisIs: "Apple scans every upload before it can be installed. Your build shows as \"Processing\" until that finishes. This is Apple's queue, so nothing you do here speeds it up.",
                doThis: [
                    .init(text: "In App Store Connect, open your app and click the TestFlight tab."),
                    .init(text: "Your build appears with a yellow Processing label."),
                    .init(text: "Close the app and go do something else. Apple emails you when it's done."),
                    .init(text: "If Apple asks about export compliance, answer No unless you added your own custom encryption. Using HTTPS does not count as encryption here."),
                ],
                watchOut: "If the build disappears instead of turning green, check your email. Apple sends the rejection reason there and never shows it in the TestFlight tab.",
                timeEstimate: "Usually 5 to 30 minutes, occasionally a few hours"
            )

        case 5:
            return Walkthrough(
                plainTitle: "Install it on your own iPhone",
                whatThisIs: "TestFlight is Apple's free app for trying builds that aren't on the App Store yet. This is the moment your app becomes real — a genuine icon on your Home Screen.",
                doThis: [
                    .init(text: "Install TestFlight from the App Store on this iPhone if you don't have it."),
                    .init(text: "In App Store Connect, go to Users and Access and confirm your own Apple ID is listed. Add it if it isn't."),
                    .init(text: "Open your app → TestFlight tab → Internal Testing, click the + next to Testers, and tick yourself."),
                    .init(text: "Apple emails you an invite. Open it on this iPhone and tap View in TestFlight."),
                    .init(text: "Tap Install. Your app is now on your Home Screen."),
                ],
                watchOut: "Internal testers must be people already listed under Users and Access. Adding a random email address there won't work — that's what External testers in the next step are for.",
                timeEstimate: "5 minutes once the build is green"
            )

        case 6:
            return Walkthrough(
                plainTitle: "Let other people try it",
                whatThisIs: "Optional, but this is how you catch problems before the public does. Internal testers are your own team and get builds instantly. External testers are anyone else.",
                doThis: [
                    .init(text: "Internal: TestFlight tab → Internal Testing → + → tick the people you want. Up to 100, instant, no review."),
                    .init(text: "External: TestFlight tab → External Testing → + to create a group, e.g. \"Friends\"."),
                    .init(text: "Add the build to that group, then add tester emails — or turn on Public Link to get a URL you can share anywhere."),
                    .init(text: "Click Submit for Review. Apple does a light automated check on your first external build only."),
                ],
                watchOut: "External testing needs a filled-in \"What to Test\" note and a working contact email, or Apple bounces the review. Every build after the first one goes out instantly.",
                timeEstimate: "10 minutes, plus up to a day for the first external review"
            )

        case 7:
            return Walkthrough(
                plainTitle: "Make your app icon",
                whatThisIs: "The App Store needs one large, perfectly square icon. Apple's rules on this are strict and automatic — a wrong file is rejected before a human ever sees it.",
                doThis: [
                    .init(text: "Export a PNG that is exactly 1024 by 1024 pixels."),
                    .init(text: "No transparency. Fill every pixel — a transparent background is an instant rejection."),
                    .init(text: "Don't round the corners yourself. Apple rounds them for you; pre-rounded corners look wrong."),
                    .init(text: "In App Store Connect, open your app, and drag the file onto the App Icon slot."),
                    .init(text: "CodeGenie's Icon Forge can generate a compliant one if you don't have a designer."),
                ],
                watchOut: "Icons exported from screenshots or from a Figma frame often carry a hidden alpha channel. If Apple rejects it for transparency, re-export it flattened onto a solid background.",
                timeEstimate: "10 minutes"
            )

        case 8:
            return Walkthrough(
                plainTitle: "Take your screenshots",
                whatThisIs: "The pictures people swipe through on your App Store page. You need at least one iPhone size; Apple scales it to the others for you.",
                doThis: [
                    .init(text: "Run your app in the iPhone simulator, or on the phone you just installed it on."),
                    .init(text: "Capture the screens that show what your app actually does — not the empty first-launch state."),
                    .init(text: "Use a 6.9-inch iPhone size (1320 × 2868) so Apple can scale down from it."),
                    .init(text: "Upload them in App Store Connect under Previews and Screenshots."),
                ],
                watchOut: "Screenshots showing placeholder text, lorem ipsum, or fake data are one of the most common rejection reasons. Put real-looking content on screen before you capture.",
                timeEstimate: "20 minutes"
            )

        case 9:
            return Walkthrough(
                plainTitle: "Write your store page",
                whatThisIs: "The words people read before deciding to download. CodeGenie has drafted these and checked every one against Apple's length limits, so nothing here will be silently cut off.",
                doThis: [
                    .init(text: "Tap Edit listing below and read through what CodeGenie drafted."),
                    .init(text: "Fix anything flagged in red — those are hard limits that stop the form saving."),
                    .init(text: "Set a Support URL. Apple requires one and actually loads it. A GitHub README or a simple contact page is enough."),
                    .init(text: macPaired
                         ? "Tap \"Type listing into my Mac\" and CodeGenie fills each field for you. Your Mac asks permission for every single field."
                         : "Tap \"Copy listing\", then paste each field into App Store Connect."),
                    .init(text: "Press Save at the top-right of App Store Connect when you're done."),
                ],
                watchOut: "Keywords is one single field capped at 100 characters including the commas — not 100 characters per word. CodeGenie counts it correctly for you.",
                timeEstimate: "20 minutes"
            )

        case 10:
            return Walkthrough(
                plainTitle: "Answer Apple's privacy questions",
                whatThisIs: "A questionnaire about what data your app collects. Your answers become the \"App Privacy\" box on your store page. Apple audits these, and a wrong answer can pull a live app.",
                doThis: [
                    .init(text: "In App Store Connect, open App Privacy in the left sidebar and click Get Started."),
                    .init(text: "\"Do you collect data from this app?\" — if your app keeps everything on the phone and sends nothing anywhere, answer No."),
                    .init(text: "Answer Yes if you added analytics, crash reporting, accounts, or any server that receives user data."),
                    .init(text: "Add a Privacy Policy URL. This is required even when you collect nothing at all."),
                    .init(text: "Click Publish."),
                ],
                watchOut: "Answer honestly rather than optimistically. This is one of the few things Apple checks after your app is already live, and getting it wrong pulls the app down.",
                timeEstimate: "10 minutes"
            )

        case 11:
            return Walkthrough(
                plainTitle: "Set your price",
                whatThisIs: "What your app costs and which countries can see it. Free everywhere is the normal choice for a first app, and you can change it later without another review.",
                doThis: [
                    .init(text: "Open Pricing and Availability in the left sidebar."),
                    .init(text: "Price: choose Free unless you have a reason not to."),
                    .init(text: "Availability: leave all countries selected."),
                    .init(text: "Click Save."),
                ],
                watchOut: "Charging money means Apple also needs your bank and tax details filled in under Business, which can take several days to clear. Free avoids all of that on a first release.",
                timeEstimate: "3 minutes"
            )

        case 12:
            return Walkthrough(
                plainTitle: "Send it to Apple for review",
                whatThisIs: "The final button. A real person at Apple opens your app and checks it against the App Store rules. This is the only step CodeGenie cannot do for you — Apple requires the account holder.",
                doThis: [
                    .init(text: "Open your app's main App Store page in App Store Connect."),
                    .init(text: "Under Build, click + and pick the build that finished processing in step 4."),
                    .init(text: "Export Compliance: answer No unless you wrote your own encryption."),
                    .init(text: "Content Rights: answer whether your app shows content you don't own."),
                    .init(text: "Advertising Identifier: answer No unless you added an ad network."),
                    .init(text: "Click Add for Review, then Submit for Review."),
                    .init(text: "Come back here and tap \"I submitted for review\" so CodeGenie can track it."),
                ],
                watchOut: "If review rejects you, it is normal and it is not personal. Apple tells you the exact guideline number in Resolution Center. Most first-app rejections are a missing demo account or a broken support link, and both are quick fixes with no rebuild needed.",
                timeEstimate: "10 minutes to submit, then 24 to 48 hours for Apple's answer"
            )

        default:
            return Walkthrough(
                plainTitle: step.title,
                whatThisIs: step.body,
                doThis: [],
                watchOut: nil,
                timeEstimate: ""
            )
        }
    }
}
