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
            case privacyPolicyURL, copyright, reviewNotes
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

        // --- Privacy policy URL (REQUIRED by Apple for every app) ---
        let policy = (m.privacyPolicyURL ?? "").trimmed
        if policy.isEmpty {
            issues.append(.init(
                field: .privacyPolicyURL, severity: .blocking,
                message: "Privacy policy URL is missing — Apple requires one for every app.",
                fix: "Even an app that collects nothing needs a page saying so. A short page on your own site or a public GitHub file is enough."
            ))
        } else if !isPlausibleURL(policy) {
            issues.append(.init(
                field: .privacyPolicyURL, severity: .blocking,
                message: "Privacy policy URL doesn't look like a valid link.",
                fix: "It must start with https:// and point at a real, reachable page."
            ))
        } else if isPlaceholderURL(policy) {
            issues.append(.init(
                field: .privacyPolicyURL, severity: .blocking,
                message: "Privacy policy URL is still a placeholder.",
                fix: "Point it at a page you control. The reviewer opens it."
            ))
        }

        // --- Copyright (required on the version page) ---
        let copyright = (m.copyright ?? "").trimmed
        if !copyright.contains(where: \.isLetter) {
            issues.append(.init(
                field: .copyright, severity: .blocking,
                message: copyright.isEmpty ? "Copyright line is empty." : "Copyright line has no owner name.",
                fix: "The year and whoever owns the app, e.g. \"2026 Jane Appleseed\". Don't type the © symbol — Apple adds it."
            ))
        } else if copyright.contains("©") || copyright.lowercased().contains("(c)") {
            issues.append(.init(
                field: .copyright, severity: .warning,
                message: "Copyright line includes a © symbol.",
                fix: "Apple adds the symbol itself, so yours would show twice. Use just the year and the name."
            ))
        }

        // --- Review notes (login without credentials is a rejection) ---
        if m.requiresLogin == true {
            let notes = (m.reviewNotes ?? "").trimmed.lowercased()
            let mentionsAccess = ["password", "login", "log in", "sign in", "account"]
                .contains { notes.contains($0) }
            if !mentionsAccess {
                issues.append(.init(
                    field: .reviewNotes, severity: .blocking,
                    message: "Your app has a sign-in, but the reviewer has no way in.",
                    fix: "Add a working test username and password in App Review Information. Without one the app is rejected unopened."
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

    /// Deliberately excludes `ipa`.
    ///
    /// The upload action now packages the app itself — archiving and
    /// signing on the Mac is the first thing it does. Requiring a
    /// finished `.ipa` before letting that action run is a deadlock:
    /// the only thing that produces one sits behind the gate demanding
    /// it, so a fresh build could never be uploaded at all.
    ///
    /// Nothing is lost by dropping it. If packaging fails, it fails
    /// with the specific reason — a lapsed membership, a bundle ID
    /// owned by another team, a compile error — which is far more
    /// use than "no .ipa was found".
    ///
    /// Also excludes `privacy_manifest`. Apple checks that at App Store
    /// review, not at TestFlight upload, so blocking a TestFlight build
    /// on it stopped people from testing their own app over a rule that
    /// does not apply yet. It stays required for the final submit.
    private static let testFlightUploadKeys: Set<String> = [
        "workspace", "xcode_project", "apple_credentials",
        "testflight_upload",
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
                whatThisIs: "Two short forms on two Apple websites. First you register your app's ID, which is its permanent, unique name inside Apple's systems. Then you create an empty record for the app to be uploaded into. Nothing here is public yet.",
                doThis: [
                    .init(text: "Open the Identifiers page on Apple's developer site and click the blue + button.", copyValue: "https://developer.apple.com/account/resources/identifiers/add/bundleId"),
                    .init(text: "Choose App IDs, Continue, then App, Continue."),
                    .init(text: "Description: your app's name is fine. Bundle ID: leave it on Explicit and paste this exact value.", copyValue: bundleID),
                    .init(text: "Scroll down, click Continue, then Register. That's the ID done."),
                    .init(text: "Now go to App Store Connect. Click Apps, then the blue + button near the top-left, then New App."),
                    .init(text: "Platforms: tick iOS. Name: the public name on the App Store, which must be unique across the whole store.", copyValue: appName),
                    .init(text: "Primary Language: whatever language your app's text is in."),
                    .init(text: "Bundle ID: pick the one you just registered from the dropdown. SKU: your own private reference — reusing the bundle ID is fine.", copyValue: bundleID),
                    .init(text: "User Access: leave it on Full Access. Click Create."),
                ],
                watchOut: "If the bundle ID isn't in the dropdown, the registration in the first four steps didn't finish, or the page was open before you registered it — reload it. If Apple says the name is taken, another app already uses it: pick a different public name. The bundle ID stays the same.",
                timeEstimate: "10 minutes"
            )

        case 3:
            return Walkthrough(
                plainTitle: "Send your app to Apple",
                whatThisIs: "This is the actual upload. What gets sent is a signed .ipa — one finished, sealed file containing your whole app. Apple only accepts that format, and building it needs a Mac with Xcode. CodeGenie does all of it for you. You don't need a listing, screenshots, or pricing yet.",
                doThis: [
                    .init(text: "Make sure step 2 is finished and the app record exists."),
                    .init(text: "Connect your Mac if you haven't — packaging and signing genuinely cannot happen on the phone alone."),
                    .init(text: "Tap Upload to TestFlight below."),
                    .init(text: "Your Mac fetches the app's files, builds and signs it, then sends it to Apple. Your signing key goes straight from this phone to your Mac and never touches CodeGenie's servers."),
                    .init(text: "It'll show you what it's doing at each stage. Leave the app open — the whole thing usually takes five to fifteen minutes."),
                ],
                watchOut: "\"No profiles were found\" or \"no valid signing identity\" means your Apple Developer details in Settings are incomplete, or your membership has lapsed — not that your app is broken. If the bundle ID doesn't match the app record you made in step 2, Apple refuses the upload: check the ID shown in step 2 against the one in App Store Connect.",
                timeEstimate: "5 to 15 minutes, mostly building"
            )

        case 4:
            return Walkthrough(
                plainTitle: "Wait for Apple to check it",
                whatThisIs: "Apple scans every upload before it can be installed. Your build shows as \"Processing\" until that finishes. This is Apple's queue, so nothing you do here speeds it up.",
                doThis: [
                    .init(text: "Tap Check with Apple below. CodeGenie asks App Store Connect directly and tells you what state your build is in."),
                    .init(text: "You can also see it in App Store Connect under your app's TestFlight tab, where it appears with a yellow Processing label."),
                    .init(text: "Nothing needs to stay open. Apple emails you when it's done."),
                    .init(text: "If Apple asks about export compliance, answer No unless you added your own custom encryption. Using HTTPS does not count as encryption here."),
                ],
                watchOut: "If the build disappears instead of turning green, check your email. Apple sends the rejection reason there and never shows it in the TestFlight tab. If Check with Apple says it can't find an app with your ID, the app record in step 2 was created with a different bundle ID.",
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
                plainTitle: "Tell Apple who the app is suitable for",
                whatThisIs: "Every app carries an age rating. You don't choose the number — you answer a questionnaire about what the app contains and Apple works it out. It decides which countries and which children's accounts can see your app.",
                doThis: [
                    .init(text: "In App Store Connect, open your app and click App Information in the left sidebar."),
                    .init(text: "Find Age Rating and click Edit (or Set Up)."),
                    .init(text: "Answer each question about violence, mature themes, medical content, gambling and contests. Most first apps are None for all of them."),
                    .init(text: "\"Unrestricted Web Access\": answer Yes only if your app lets people browse to any website they like."),
                    .init(text: "\"User-generated content\" and messaging: answer Yes if people can post things other people see."),
                    .init(text: "Click Done and check the rating Apple shows. Then Save."),
                ],
                watchOut: "Answering None to everything when the app has chat, user posts or an in-app browser is one of the things Apple checks after release. Understating it can get an approved app pulled.",
                timeEstimate: "5 minutes"
            )

        case 12:
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

        case 13:
            return Walkthrough(
                plainTitle: "Give the reviewer what they need",
                whatThisIs: "A real person at Apple opens your app knowing nothing about it. App Review Information is the only thing you get to say to them beforehand. A clear note here prevents the most common first-app rejection: the reviewer couldn't work out how to use it.",
                doThis: [
                    .init(text: "On your app's version page, scroll down to App Review Information."),
                    .init(text: "Contact Information: your real name, phone number and email. Apple calls or writes if the reviewer gets stuck."),
                    .init(text: "Sign-In Required: tick this only if your app has a login, then enter a username and password that work right now."),
                    .init(text: "Notes: tap Draft my review notes below, edit it so it's true for your app, then paste it in."),
                    .init(text: "Attach a short screen recording if anything needs special hardware, a location, or a paid account to see."),
                    .init(text: "Click Save."),
                ],
                watchOut: "A test account that has expired, needs a code sent to your phone, or opens to an empty screen counts as no account at all. Sign in with it yourself on a clean device before you submit.",
                timeEstimate: "10 minutes"
            )

        case 14:
            return Walkthrough(
                plainTitle: "Attach your build and decide when it goes live",
                whatThisIs: "The store page and the app file are separate things until you join them here. You also answer two legal questions about the build, and choose whether approval publishes the app immediately or waits for you.",
                doThis: [
                    .init(text: "On the version page, find the Build section and click Add Build (the + button)."),
                    .init(text: "Pick the build that finished processing in step 4. Check the version and build number match the one you tested."),
                    .init(text: "Export Compliance: answer No unless you wrote your own encryption. Using HTTPS does not count."),
                    .init(text: "Content Rights: say whether the app shows content that belongs to someone else, and that you have the right to use it."),
                    .init(text: "Version Release: choose Manually release this version if you want to pick the moment, or Automatically to go live as soon as Apple approves."),
                    .init(text: "Click Save."),
                ],
                watchOut: "If no build appears in the list, it is still processing or was rejected by email — go back to step 4 and check. And it is easy to attach yesterday's build: compare the build number.",
                timeEstimate: "5 minutes"
            )

        case 15:
            return Walkthrough(
                plainTitle: "Send it to Apple for review",
                whatThisIs: "The final button. A real person at Apple opens your app and checks it against the App Store rules. This is the one step CodeGenie cannot do for you — Apple requires the account holder to press it.",
                doThis: [
                    .init(text: "Open your submission checklist below and confirm everything on it. These are the things Apple rejects for."),
                    .init(text: "On the version page in App Store Connect, click Add for Review at the top right."),
                    .init(text: "If a list of missing items appears, fix each one — Apple names the exact field."),
                    .init(text: "Click Submit for Review. The status changes to Waiting for Review."),
                    .init(text: "Come back here and tap I submitted for review. CodeGenie then follows the review with you."),
                ],
                watchOut: "Add for Review is not the same as submitting. Until you press Submit for Review on the next screen, nothing has been sent and the status stays at Ready for Review.",
                timeEstimate: "5 minutes to submit"
            )

        case 16:
            return Walkthrough(
                plainTitle: "Wait for a reviewer",
                whatThisIs: "Your app is in a queue with everyone else's. Nothing is being judged yet. Apple reviews most submissions within a day, and there is nothing you can do to move up.",
                doThis: [
                    .init(text: "Tap Check with Apple below whenever you like. CodeGenie asks App Store Connect for the current status."),
                    .init(text: "Keep your support page, privacy policy and any server your app uses online."),
                    .init(text: "Leave the submission alone. Editing the build or cancelling sends you to the back of the queue."),
                    .init(text: "Apple emails the account holder the moment the status changes."),
                ],
                watchOut: "If the status goes back to Prepare for Submission by itself, Apple bounced the submission before review — usually a missing field. Open the version page and read the banner at the top.",
                timeEstimate: "Usually under 24 hours"
            )

        case 17:
            return Walkthrough(
                plainTitle: "Act on Apple's answer",
                whatThisIs: "Review ends one of two ways: approved, or sent back with the guideline it fell short of. Being sent back is normal — it happens to most first apps — and you can fix and resubmit as many times as you need.",
                doThis: [
                    .init(text: "Tap Check with Apple below, or read the status on your app's page in App Store Connect."),
                    .init(text: "Approved: you're done here. The next step releases it."),
                    .init(text: "Sent back: open App Review on your app's page and read the whole message. It names a guideline number."),
                    .init(text: "Pick that guideline below. CodeGenie explains what it means and exactly what to change."),
                    .init(text: "Reply in the same thread to say what you changed, then resubmit."),
                ],
                watchOut: "Don't argue the rule and don't resubmit unchanged — both slow you down. If you believe the reviewer misread the app, reply politely with specifics; if that fails, there is a formal appeal under Contact Us.",
                timeEstimate: "A few minutes for a store-page fix, longer if the app needs a new build"
            )

        case 18:
            return Walkthrough(
                plainTitle: "Put it on the store",
                whatThisIs: "Approved is not quite the same as live. If you chose manual release in step 14, your app waits for you. Either way it takes a few hours to appear everywhere.",
                doThis: [
                    .init(text: "If the status is Pending Developer Release, open the version page and click Release This Version."),
                    .init(text: "Wait for the status to become Ready for Distribution."),
                    .init(text: "Open your App Store page from the link in App Store Connect and read it as a stranger would."),
                    .init(text: "Share the link. Search results can lag several hours behind the direct link."),
                ],
                watchOut: "Don't panic if a search for your app's name finds nothing on day one. Indexing takes time. The direct link from App Store Connect works straight away.",
                timeEstimate: "Up to 24 hours to appear everywhere"
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

// MARK: - Reviewer notes

extension ASCCoach {

    /// A first draft of the Notes field in App Review Information.
    ///
    /// Written for a stranger with ten minutes: what the app is for,
    /// where to tap first, and how to get past any sign-in. The user
    /// is expected to edit it — the bracketed parts cannot be known
    /// from here, and saying so is better than inventing them.
    static func reviewNotesDraft(
        appName: String,
        summary: String,
        features: [String],
        requiresLogin: Bool
    ) -> String {
        let name = appName.trimmed.isEmpty ? "This app" : appName.trimmed
        let oneLine = summary.trimmed
            .split(whereSeparator: \.isNewline).first.map(String.init)?.trimmed ?? ""

        var lines: [String] = []
        lines.append("Thank you for reviewing \(name).")
        lines.append("")
        if oneLine.isEmpty {
            lines.append("What it does: [one sentence describing the app]")
        } else {
            lines.append("What it does: \(oneLine)")
        }
        lines.append("")
        lines.append("How to try the main feature:")
        let listed = features.map { $0.trimmed }.filter { !$0.isEmpty }.prefix(4)
        if listed.isEmpty {
            lines.append("1. Open the app. [Describe the first thing to tap.]")
            lines.append("2. [Describe what happens next.]")
        } else {
            lines.append("1. Open the app. The first screen is ready to use with no setup.")
            for (index, feature) in listed.enumerated() {
                lines.append("\(index + 2). \(feature)")
            }
        }
        lines.append("")
        if requiresLogin {
            lines.append("Sign-in: a working test account is entered in the Sign-In Required fields above.")
            lines.append("Username: [test username]")
            lines.append("Password: [test password]")
            lines.append("This account does not expire and needs no verification code.")
        } else {
            lines.append("Sign-in: none. The app does not require an account.")
        }
        lines.append("")
        lines.append("The app does not need special hardware, a particular location, or a purchase to review.")
        lines.append("")
        lines.append("Contact: [your name], [your email], [your phone]")
        return lines.joined(separator: "\n")
    }

    /// Bracketed blanks the draft leaves for the user to fill in.
    static func unfilledPlaceholders(in text: String) -> [String] {
        var out: [String] = []
        var current: String?
        for character in text {
            if character == "[" {
                current = ""
            } else if character == "]" {
                if let found = current, !found.trimmed.isEmpty { out.append(found) }
                current = nil
            } else if current != nil {
                current?.append(character)
            }
        }
        return out
    }
}
