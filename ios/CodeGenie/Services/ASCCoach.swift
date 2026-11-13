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
        bundleID: String
    ) -> Walkthrough {
        switch step.number {

        // MARK: Part 1 — onto your phone

        case 1:
            return Walkthrough(
                plainTitle: "Get your project onto your Mac",
                whatThisIs: "Right now \(appName) is a folder of code stored by CodeGenie. An iPhone can't turn code into an app — only a Mac can. So the first job is simply moving that folder to your Mac. AirDrop does it in one tap.",
                doThis: [
                    .init(text: "Wake your Mac and unlock it. Keep it near this iPhone."),
                    .init(text: "Tap Send project to my Mac below. CodeGenie packs the project into one file."),
                    .init(text: "In the share sheet that appears, tap AirDrop, then tap your Mac."),
                    .init(text: "On the Mac, the file lands in your Downloads folder as a .zip. Double-click it to unpack it into a normal folder."),
                    .init(text: "Leave that folder where it is. You'll open it in the next step."),
                ],
                watchOut: "If your Mac doesn't appear under AirDrop, open Finder on the Mac, click AirDrop in the sidebar, and set \"Allow me to be discovered by\" to Everyone. No AirDrop at all? Choose Save to Files instead, put it in iCloud Drive, and open iCloud Drive on the Mac.",
                timeEstimate: "2 minutes"
            )

        case 2:
            return Walkthrough(
                plainTitle: "Open your project in Xcode",
                whatThisIs: "Xcode is Apple's own app for building iPhone apps. It's free, it only runs on a Mac, and it is big. You won't write any code in it — you'll open your project, sign in, and press a few buttons over the next steps.",
                doThis: [
                    .init(text: "On your Mac, open the App Store app, search for Xcode, and click Get. It's a large download, so this can take half an hour. Skip this if it's already installed."),
                    .init(text: "Open Xcode once. If it offers to install extra components or the iOS platform, say yes and let it finish."),
                    .init(text: "In Finder, open the folder you unpacked in step 1. Find the file whose name ends in .xcodeproj — it has a blue icon — and double-click it."),
                    .init(text: "If the Mac asks whether to trust the project, click Trust and Open."),
                    .init(text: "In the menu bar choose Xcode, then Settings, then the Accounts tab. Click the + at the bottom left, choose Apple Account, and sign in with the Apple ID that's in the Developer Program."),
                    .init(text: "You should now see a window with a list of files on the left and your app's name at the top. That's your project, open."),
                ],
                watchOut: "Double-clicking the folder itself opens nothing useful — it has to be the .xcodeproj file inside it. If Xcode says the project was made with a newer version, update Xcode from the App Store first.",
                timeEstimate: "10 minutes, plus the Xcode download"
            )

        case 3:
            return Walkthrough(
                plainTitle: "Put your name on the app",
                whatThisIs: "Every iPhone app is digitally signed by whoever made it. That signature is how Apple, and every iPhone, knows this app is yours and hasn't been tampered with. Xcode does all the cryptography — you only have to tell it who you are.",
                doThis: [
                    .init(text: "In Xcode's left sidebar, click the very top item — the blue icon with your app's name."),
                    .init(text: "In the middle of the window, under TARGETS, click your app's name."),
                    .init(text: "Click the Signing & Capabilities tab along the top."),
                    .init(text: "Tick Automatically manage signing."),
                    .init(text: "Open the Team menu and choose your name. Pick the one that does not say Personal Team."),
                    .init(text: "Check Bundle Identifier reads exactly this. It's already set; don't change it.", copyValue: bundleID),
                    .init(text: "Wait a few seconds. Any red text under Signing should clear and a line reading Xcode Managed Profile should appear."),
                ],
                watchOut: "If the only team offered says Personal Team, your Developer Program membership isn't active on this Apple ID yet — a personal team can run on your own phone but can't upload to Apple. \"Failed to register bundle identifier\" means that ID is taken: tell the coach and it will walk you through changing it safely.",
                timeEstimate: "3 minutes"
            )

        case 4:
            return Walkthrough(
                plainTitle: "See it run",
                whatThisIs: "Before sending anything to Apple, run the app on your Mac. Xcode includes the Simulator, a pretend iPhone in a window. This is the first time anyone sees \(appName) actually running, and it's the cheapest moment to notice something is wrong.",
                doThis: [
                    .init(text: "At the top of the Xcode window, in the middle, there's a bar showing your app's name and a device. Click the device part."),
                    .init(text: "Choose any recent iPhone under iOS Simulators — iPhone 16 is fine."),
                    .init(text: "Press the ▶ Run button at the top left, or press Command-R."),
                    .init(text: "The first build takes a few minutes. Watch the bar at the top: it says Building, then Running."),
                    .init(text: "A window with an iPhone appears and your app opens in it. Click around with the mouse as if it were your finger."),
                    .init(text: "Come back here and say what happened."),
                ],
                watchOut: "If the bar says Build Failed and a red ❌ appears, click it to see the errors, copy the first one, and tap It showed an error below. CodeGenie can build again with that error fixed. Don't try to edit the code yourself.",
                timeEstimate: "5 minutes"
            )

        case 5:
            return Walkthrough(
                plainTitle: "Tell Apple your app exists",
                whatThisIs: "Two short forms on two Apple websites. First you register your app's ID, which is its permanent, unique name inside Apple's systems. Then you create an empty record for the app to be uploaded into. Nothing here is public yet.",
                doThis: [
                    .init(text: "Open the Identifiers page on Apple's developer site and sign in with your developer Apple ID.", copyValue: "https://developer.apple.com/account/resources/identifiers/list"),
                    .init(text: "Look for your bundle ID in the list. Xcode usually registered it for you in step 3. If it's there, skip to the App Store Connect part below.", copyValue: bundleID),
                    .init(text: "If it isn't: click the blue +, choose App IDs, Continue, App, Continue. Paste the bundle ID as Explicit, give any description, then Continue and Register."),
                    .init(text: "Now open App Store Connect. Click Apps, then the blue + near the top-left, then New App.", copyValue: "https://appstoreconnect.apple.com/apps"),
                    .init(text: "Platforms: tick iOS. Name: the public name on the App Store, which must be unique across the whole store.", copyValue: appName),
                    .init(text: "Primary Language: whatever language your app's text is in."),
                    .init(text: "Bundle ID: pick yours from the dropdown. SKU: your own private reference — pasting the bundle ID again is fine.", copyValue: bundleID),
                    .init(text: "User Access: leave it on Full Access. Click Create."),
                ],
                watchOut: "\"You do not have permission\" on either site means this Apple ID isn't enrolled in the Developer Program yet — that's the $99 a year step, and Apple can take a day to approve it. If Apple says the app name is taken, choose a different public name; the bundle ID stays the same.",
                timeEstimate: "10 minutes"
            )

        case 6:
            return Walkthrough(
                plainTitle: "Send your app to Apple",
                whatThisIs: "An archive is the finished, sealed version of your app — the exact thing people will install. Xcode makes it, signs it with your name, and uploads it to the record you just created. You're not submitting for review yet; this only makes it available for you to install and test.",
                doThis: [
                    .init(text: "In Xcode, click the device in the bar at the top again. This time choose Any iOS Device (arm64), at the top of the list."),
                    .init(text: "In the menu bar choose Product, then Archive. If Archive is greyed out, a simulator is still selected — repeat the line above."),
                    .init(text: "Wait a few minutes. When it finishes, a window called Organizer opens with your archive selected."),
                    .init(text: "Click Distribute App on the right."),
                    .init(text: "Choose App Store Connect, then click Distribute. On older Xcode versions: choose App Store Connect, Next, Upload, then keep clicking Next and finally Upload."),
                    .init(text: "Wait for the green tick and \"Upload successful\" or \"App upload complete\"."),
                ],
                watchOut: "\"No suitable application records were found\" means the bundle ID in Xcode doesn't match the record from step 5 — compare them character by character. \"The bundle version must be higher\" means you've uploaded this build number before: in Xcode, under the General tab, raise Build by one and archive again.",
                timeEstimate: "10 to 15 minutes, mostly waiting"
            )

        case 7:
            return Walkthrough(
                plainTitle: "Wait for Apple to check it",
                whatThisIs: "Apple scans every upload before it can be installed. Your build shows as Processing until that finishes. This is Apple's queue, so nothing you do here speeds it up.",
                doThis: [
                    .init(text: "Open App Store Connect, click your app, then the TestFlight tab. Your build appears with a yellow Processing label."),
                    .init(text: "Nothing needs to stay open. Apple emails you when it's ready."),
                    .init(text: "If a yellow warning says Missing Compliance, click Manage and answer No — unless you wrote your own encryption. Using HTTPS does not count."),
                    .init(text: "When the label is gone and the build has a version number you can click, come back and mark this done."),
                ],
                watchOut: "If the build disappears instead of finishing, check your email. Apple sends the reason there and doesn't show it on the page. The usual causes are a missing app icon or a missing permission explanation — tell the coach what the email says.",
                timeEstimate: "Usually 5 to 30 minutes, occasionally a few hours"
            )

        case 8:
            return Walkthrough(
                plainTitle: "Install it on your own iPhone",
                whatThisIs: "TestFlight is Apple's free app for trying builds that aren't on the App Store yet. This is the moment your app becomes real — a genuine icon on your Home Screen.",
                doThis: [
                    .init(text: "Install TestFlight from the App Store on this iPhone if you don't have it."),
                    .init(text: "In App Store Connect, open your app, the TestFlight tab, then Internal Testing in the sidebar. Click the + to create a group — call it anything."),
                    .init(text: "In that group, click the + next to Testers and tick yourself."),
                    .init(text: "Apple emails you an invitation. Open it on this iPhone and tap View in TestFlight."),
                    .init(text: "Tap Install. Your app is now on your Home Screen."),
                ],
                watchOut: "Internal testers must be people already listed under Users and Access in App Store Connect. If you're not offered as a tester, add yourself there first. A random email address won't work here — that's what external testers are for, two steps from now.",
                timeEstimate: "5 minutes"
            )

        // MARK: Part 2 — testing

        case 9:
            return Walkthrough(
                plainTitle: "Find out whether it actually works",
                whatThisIs: "\(appName) was written by AI and nobody has properly used it yet — including you. It builds, which only proves the code is valid. Apple's most common reason for rejecting an app is that it simply didn't work when they tried it. This step is how you find that out first.",
                doThis: [
                    .init(text: "Open \(appName) on this iPhone, from the Home Screen."),
                    .init(text: "Work down the test plan below. Each test says what to do and what should happen."),
                    .init(text: "After each one, tap Works or Didn't work. Be strict — \"mostly\" is Didn't work."),
                    .init(text: "When something fails, write one line about what happened. That line goes straight into the next build."),
                    .init(text: "The required tests must all pass before the App Store steps open. The rest are strongly advised."),
                ],
                watchOut: "The temptation is to tick everything because you want to be finished. A reviewer will do these same things in their first two minutes, and a rejection costs days. A failed test here costs a rebuild of a few minutes.",
                timeEstimate: "10 to 15 minutes"
            )

        case 10:
            return Walkthrough(
                plainTitle: "Watch someone else use it",
                whatThisIs: "You built this, so you know where to tap and you avoid the broken paths without noticing. A person who has never seen it doesn't. One outsider using your app for five minutes finds most of what a reviewer or a first customer would.",
                doThis: [
                    .init(text: "Pick someone who hasn't seen the app. A friend or family member is perfect."),
                    .init(text: "In App Store Connect, open your app, TestFlight, then External Testing. Click + to create a group and add the build."),
                    .init(text: "Fill in What to Test with one sentence, add their email — or turn on Public Link and send them the link."),
                    .init(text: "Click Submit for Review. Apple does a quick check on your first external build, usually within a day. Later builds go out instantly."),
                    .init(text: "When they have it, ask them to do the app's main task. Say nothing, and don't help."),
                    .init(text: "Note every place they hesitate, tap the wrong thing, or ask a question. Each one is a real problem."),
                ],
                watchOut: "Don't explain the app before they start. If they need you to explain it, that is the finding. If they get stuck and you can't see why, ask what they expected to happen.",
                timeEstimate: "15 minutes of your time, plus up to a day for Apple's first check"
            )

        case 11:
            return Walkthrough(
                plainTitle: "Decide: ready, or rebuild?",
                whatThisIs: "A checkpoint. Everything after this is paperwork for the public store, and it takes an hour or two. Doing it for an app with known problems wastes that time, because a rebuild means uploading and testing again anyway.",
                doThis: [
                    .init(text: "Look at the test results below. Anything marked Didn't work has to be fixed."),
                    .init(text: "Add anything your tester ran into as a failed test, in a line each."),
                    .init(text: "If there are failures, tap Rebuild with these fixed. CodeGenie builds again with your notes, and you repeat the upload and the tests."),
                    .init(text: "If everything passes, tap It's ready and carry on to the store page."),
                ],
                watchOut: "\"It works on my phone\" is not the same as tested. If a required test hasn't been tried, this step stays closed.",
                timeEstimate: "2 minutes"
            )

        // MARK: Part 3 — the store page

        case 12:
            return Walkthrough(
                plainTitle: "Make your app icon",
                whatThisIs: "The App Store needs one large, perfectly square icon. Apple's rules on this are strict and automatic — a wrong file is rejected before a human ever sees it.",
                doThis: [
                    .init(text: "You need a PNG that is exactly 1024 by 1024 pixels."),
                    .init(text: "No transparency. Every pixel filled — a transparent background is an instant rejection."),
                    .init(text: "Don't round the corners yourself. Apple rounds them for you."),
                    .init(text: "In App Store Connect, open your app's version page and drag the file onto the App Icon slot if one is shown. Otherwise the icon comes from the build you uploaded."),
                ],
                watchOut: "Icons exported from screenshots or design tools often carry a hidden transparency layer. If Apple rejects it for that, re-export it flattened onto a solid background.",
                timeEstimate: "10 minutes"
            )

        case 13:
            return Walkthrough(
                plainTitle: "Take your screenshots",
                whatThisIs: "The pictures people swipe through on your App Store page. You need at least one iPhone size; Apple scales it for the others.",
                doThis: [
                    .init(text: "In Xcode, choose the largest iPhone simulator — iPhone 16 Pro Max — and press ▶ Run, as in step 4."),
                    .init(text: "Put real-looking content into the app first. An empty first screen sells nothing."),
                    .init(text: "On each screen worth showing, press Command-S in the Simulator. The picture is saved to your Mac's Desktop."),
                    .init(text: "Take three to five. Lead with the one that shows what the app is for."),
                    .init(text: "In App Store Connect, open your app's version page and drag them into Previews and Screenshots."),
                ],
                watchOut: "Screenshots showing placeholder text or made-up data are one of the most common rejection reasons, and so are screenshots of features that aren't in the build. Take them from the build you tested.",
                timeEstimate: "20 minutes"
            )

        case 14:
            return Walkthrough(
                plainTitle: "Write your store page",
                whatThisIs: "The words people read before deciding to download. CodeGenie has drafted these from your description and checked every one against Apple's length limits.",
                doThis: [
                    .init(text: "Tap Edit listing below and read what CodeGenie drafted. It was written before the app existed — make sure it's still true."),
                    .init(text: "Fix anything flagged. Those are hard limits or required fields, and the page won't save without them."),
                    .init(text: "Add a Support URL and a Privacy Policy URL. Apple requires both and opens them. A simple page with a contact email is enough for each."),
                    .init(text: "Tap Copy listing, then paste each field into your app's version page in App Store Connect."),
                    .init(text: "Press Save at the top right of App Store Connect."),
                ],
                watchOut: "Keywords is one single field capped at 100 characters including the commas — not 100 per word. And describe only what this build does: features you plan to add later don't belong here.",
                timeEstimate: "20 minutes"
            )

        case 15:
            return Walkthrough(
                plainTitle: "Answer Apple's privacy questions",
                whatThisIs: "A questionnaire about what data your app collects. Your answers become the App Privacy box on your store page. Apple audits these, and a wrong answer can pull a live app.",
                doThis: [
                    .init(text: "In App Store Connect, open App Privacy in the left sidebar and click Get Started."),
                    .init(text: "\"Do you collect data from this app?\" — if your app keeps everything on the phone and sends nothing anywhere, answer No."),
                    .init(text: "Answer Yes if the app has accounts, analytics, crash reporting, or any server that receives what users enter."),
                    .init(text: "Check the Privacy Policy URL is filled in. It's required even when you collect nothing."),
                    .init(text: "Click Publish."),
                ],
                watchOut: "Not sure whether your app sends data anywhere? Ask the coach — describe what the app does and it will tell you what counts. Guessing No is the answer that gets apps pulled later.",
                timeEstimate: "10 minutes"
            )

        case 16:
            return Walkthrough(
                plainTitle: "Tell Apple who the app is suitable for",
                whatThisIs: "Every app carries an age rating. You don't choose the number — you answer a questionnaire about what the app contains and Apple works it out.",
                doThis: [
                    .init(text: "In App Store Connect, open your app and click App Information in the left sidebar."),
                    .init(text: "Find Age Rating and click Edit or Set Up."),
                    .init(text: "Answer each question about violence, mature themes, medical content, gambling and contests. Most first apps are None for all of them."),
                    .init(text: "\"Unrestricted Web Access\": Yes only if your app lets people browse to any website they like."),
                    .init(text: "User-generated content and messaging: Yes if people can post things other people see."),
                    .init(text: "Click Done, check the rating Apple shows, then Save."),
                ],
                watchOut: "Answering None to everything when the app has chat, user posts or an in-app browser is something Apple checks after release. Understating it can get an approved app removed.",
                timeEstimate: "5 minutes"
            )

        case 17:
            return Walkthrough(
                plainTitle: "Set your price",
                whatThisIs: "What your app costs and which countries can see it. Free everywhere is the normal choice for a first app, and you can change it later without another review.",
                doThis: [
                    .init(text: "Open Pricing and Availability in the left sidebar."),
                    .init(text: "Price: choose Free unless you have a reason not to."),
                    .init(text: "Availability: leave all countries selected."),
                    .init(text: "Click Save."),
                ],
                watchOut: "Charging money means Apple also needs your bank and tax details under Business, which can take several days to clear. Free avoids all of that on a first release.",
                timeEstimate: "3 minutes"
            )

        case 18:
            return Walkthrough(
                plainTitle: "Give the reviewer what they need",
                whatThisIs: "A real person at Apple opens your app knowing nothing about it. App Review Information is the only thing you get to say to them beforehand. A clear note prevents the most common first-app rejection: the reviewer couldn't work out how to use it.",
                doThis: [
                    .init(text: "On your app's version page, scroll down to App Review Information."),
                    .init(text: "Contact Information: your real name, phone number and email. Apple writes or calls if the reviewer gets stuck."),
                    .init(text: "Sign-In Required: tick this only if your app has a login, then enter a username and password that work right now."),
                    .init(text: "Notes: use the draft below. Edit it so it's true for your app, fill in every blank, then copy and paste it in."),
                    .init(text: "Click Save."),
                ],
                watchOut: "A test account that has expired, needs a code sent to your phone, or opens to an empty screen counts as no account at all. You tested signing in with it in Part 2 — use exactly that one.",
                timeEstimate: "10 minutes"
            )

        case 19:
            return Walkthrough(
                plainTitle: "Attach your build and decide when it goes live",
                whatThisIs: "The store page and the app file are separate things until you join them here. You also answer two legal questions, and choose whether approval publishes the app immediately or waits for you.",
                doThis: [
                    .init(text: "On the version page, find the Build section and click Add Build."),
                    .init(text: "Pick the build you tested. Check its version and build number match what TestFlight shows on your phone."),
                    .init(text: "Export Compliance: answer No unless you wrote your own encryption. Using HTTPS does not count."),
                    .init(text: "Content Rights: say whether the app shows content that belongs to someone else, and that you have the right to use it."),
                    .init(text: "Version Release: choose Manually release this version to pick the moment yourself, or Automatically to go live as soon as Apple approves."),
                    .init(text: "Click Save."),
                ],
                watchOut: "If you rebuilt after testing, there may be two builds in the list. Submitting the older one is an easy mistake — compare the build number with the one on your phone.",
                timeEstimate: "5 minutes"
            )

        case 20:
            return Walkthrough(
                plainTitle: "Send it to Apple for review",
                whatThisIs: "The final button. A real person at Apple opens your app and checks it against the App Store rules. Apple requires the account holder to press this — nobody can do it for you.",
                doThis: [
                    .init(text: "Open your submission checklist below and confirm everything on it. These are the things only you can vouch for."),
                    .init(text: "On the version page in App Store Connect, click Add for Review at the top right."),
                    .init(text: "If a list of missing items appears, fix each one. Apple names the exact field."),
                    .init(text: "Click Submit for Review. The status changes to Waiting for Review."),
                    .init(text: "Come back here and tap I submitted for review. CodeGenie explains what happens next and follows the review with you."),
                ],
                watchOut: "Add for Review is not the same as submitting. Until you press Submit for Review on the next screen, nothing has been sent and the status stays at Ready for Review.",
                timeEstimate: "5 minutes"
            )

        // MARK: Part 4 — review

        case 21:
            return Walkthrough(
                plainTitle: "Wait for a reviewer",
                whatThisIs: "Your app is in a queue with everyone else's. Nothing is being judged yet. Apple reviews most submissions within a day, and there is nothing you can do to move up.",
                doThis: [
                    .init(text: "Check the status below whenever you like, or read it on your app's page in App Store Connect."),
                    .init(text: "Keep your support page, privacy policy and any server your app uses online."),
                    .init(text: "Leave the submission alone. Editing the build or cancelling sends you to the back of the queue."),
                    .init(text: "Apple emails the account holder the moment the status changes."),
                ],
                watchOut: "If the status goes back to Prepare for Submission by itself, Apple bounced the submission before review — usually a missing field. Open the version page and read the banner at the top.",
                timeEstimate: "Usually under 24 hours"
            )

        case 22:
            return Walkthrough(
                plainTitle: "Act on Apple's answer",
                whatThisIs: "Review ends one of two ways: approved, or sent back with the guideline it fell short of. Being sent back is normal — it happens to most first apps — and you can fix and resubmit as many times as you need.",
                doThis: [
                    .init(text: "Check the status below, or read it on your app's page in App Store Connect."),
                    .init(text: "Approved: you're done here. The next step releases it."),
                    .init(text: "Sent back: open App Review on your app's page and read the whole message. It names a guideline number."),
                    .init(text: "Paste that message below. CodeGenie finds the guideline, explains it, and says exactly what to change."),
                    .init(text: "Reply in the same thread to say what you changed, then resubmit."),
                ],
                watchOut: "Don't argue the rule and don't resubmit unchanged — both slow you down. If you believe the reviewer misread the app, reply politely with specifics; if that fails, there is a formal appeal under Contact Us.",
                timeEstimate: "A few minutes for a store-page fix, longer if the app needs a new build"
            )

        case 23:
            return Walkthrough(
                plainTitle: "Put it on the store",
                whatThisIs: "Approved is not quite the same as live. If you chose manual release, your app waits for you. Either way it takes a few hours to appear everywhere.",
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
