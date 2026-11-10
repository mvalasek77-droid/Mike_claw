import Foundation

/// Where a submitted version stands with Apple, in terms a first-time
/// submitter can act on.
///
/// App Store Connect reports around twenty raw states. Most of them
/// mean the same thing to the person waiting, so they collapse here
/// into the handful that each call for something different.
enum ASCReviewState: String, Codable, CaseIterable, Hashable {
    /// Nothing has been submitted for this version yet.
    case notSubmitted
    /// Submitted, sitting in Apple's queue.
    case waitingForReview
    /// A reviewer has the app open.
    case inReview
    /// Sent back: the app itself fell short of a guideline.
    case rejected
    /// Sent back: only the store page needs changing. No new build.
    case metadataRejected
    /// The uploaded binary failed Apple's automated checks.
    case invalidBinary
    /// The developer withdrew the submission.
    case developerRejected
    /// Apple needs the encryption question answered before review.
    case waitingForExportCompliance
    /// Approved, waiting for the developer to press Release.
    case pendingDeveloperRelease
    /// Approved, waiting on a date or on Apple.
    case pendingAppleRelease
    /// Approved and propagating to the store. Up to a day.
    case processingForDistribution
    /// Live on the App Store.
    case live
    /// Pulled from sale after having been live.
    case removedFromSale
    /// A state this build of CodeGenie does not recognise.
    case unknown

    /// Maps Apple's `appVersionState` / `appStoreState` strings.
    ///
    /// Both vocabularies are accepted because Apple is part-way through
    /// replacing one with the other and returns either depending on
    /// the API version.
    init(apple raw: String) {
        switch raw.uppercased() {
        case "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW":
            self = .notSubmitted
        case "WAITING_FOR_REVIEW":
            self = .waitingForReview
        case "IN_REVIEW":
            self = .inReview
        case "REJECTED":
            self = .rejected
        case "METADATA_REJECTED":
            self = .metadataRejected
        case "INVALID_BINARY":
            self = .invalidBinary
        case "DEVELOPER_REJECTED":
            self = .developerRejected
        case "WAITING_FOR_EXPORT_COMPLIANCE":
            self = .waitingForExportCompliance
        case "PENDING_DEVELOPER_RELEASE", "ACCEPTED":
            self = .pendingDeveloperRelease
        case "PENDING_APPLE_RELEASE", "PENDING_CONTRACT":
            self = .pendingAppleRelease
        case "PROCESSING_FOR_APP_STORE", "PROCESSING_FOR_DISTRIBUTION":
            self = .processingForDistribution
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "PREORDER_READY_FOR_SALE":
            self = .live
        case "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE", "REPLACED_WITH_NEW_VERSION":
            self = .removedFromSale
        default:
            self = .unknown
        }
    }

    enum Tone: String { case waiting, action, problem, good }

    var tone: Tone {
        switch self {
        case .waitingForReview, .inReview, .pendingAppleRelease, .processingForDistribution:
            return .waiting
        case .notSubmitted, .waitingForExportCompliance, .pendingDeveloperRelease, .unknown:
            return .action
        case .rejected, .metadataRejected, .invalidBinary, .developerRejected, .removedFromSale:
            return .problem
        case .live:
            return .good
        }
    }

    /// What App Store Connect itself calls this, so the user can match
    /// what they read here to what they see on Apple's page.
    var appleLabel: String {
        switch self {
        case .notSubmitted: "Prepare for Submission"
        case .waitingForReview: "Waiting for Review"
        case .inReview: "In Review"
        case .rejected: "Rejected"
        case .metadataRejected: "Metadata Rejected"
        case .invalidBinary: "Invalid Binary"
        case .developerRejected: "Developer Rejected"
        case .waitingForExportCompliance: "Waiting for Export Compliance"
        case .pendingDeveloperRelease: "Pending Developer Release"
        case .pendingAppleRelease: "Pending Apple Release"
        case .processingForDistribution: "Processing for Distribution"
        case .live: "Ready for Distribution"
        case .removedFromSale: "Removed from Sale"
        case .unknown: "Something else"
        }
    }

    var headline: String {
        switch self {
        case .notSubmitted: "Apple hasn't received a submission yet"
        case .waitingForReview: "You're in the queue"
        case .inReview: "A reviewer has your app open"
        case .rejected: "Apple sent it back"
        case .metadataRejected: "Apple wants the store page changed"
        case .invalidBinary: "Apple couldn't accept the build"
        case .developerRejected: "The submission was withdrawn"
        case .waitingForExportCompliance: "Apple needs one answer from you"
        case .pendingDeveloperRelease: "Approved — waiting for you to release"
        case .pendingAppleRelease: "Approved — release is scheduled"
        case .processingForDistribution: "Approved — going live now"
        case .live: "Your app is on the App Store"
        case .removedFromSale: "Your app is not on sale"
        case .unknown: "CodeGenie doesn't recognise this status"
        }
    }

    var meaning: String {
        switch self {
        case .notSubmitted:
            "The version is still marked Prepare for Submission. Either Submit for Review was never pressed, or Apple bounced the submission before it reached the queue — App Store Connect shows a red banner at the top of the version page when that happens."
        case .waitingForReview:
            "Nothing is wrong and nothing is needed. Apple reviews most submissions within a day; a first app, or a week with a new iOS release, can take longer."
        case .inReview:
            "A person at Apple is using your app right now. This part usually takes from a few minutes to a few hours. Keep any server or test account your app depends on running."
        case .rejected:
            "A reviewer found something that doesn't meet a guideline. This happens to most first apps. Apple tells you the exact guideline number and what they saw, and you can fix it and resubmit as many times as it takes."
        case .metadataRejected:
            "Your app passed, but something on the store page did not — a screenshot, the description, a URL. You fix the page and resubmit the same build. No rebuilding."
        case .invalidBinary:
            "Apple's automated checks failed the uploaded file before a person saw it. The reason is in an email to the account holder. It needs a corrected build."
        case .developerRejected:
            "Someone with access to your account pulled this version out of review. Nothing was judged. You can submit it again whenever you like."
        case .waitingForExportCompliance:
            "Review won't start until the encryption question on the build is answered."
        case .pendingDeveloperRelease:
            "Apple approved it. You chose to release manually, so it stays private until you press the button."
        case .pendingAppleRelease:
            "Apple approved it. It will go live on the date you set, or as soon as Apple finishes its side."
        case .processingForDistribution:
            "Apple is copying your app to App Store servers around the world. It can take up to 24 hours to appear in search everywhere."
        case .live:
            "Anyone can download it. Search can lag a few hours behind; the direct link works immediately."
        case .removedFromSale:
            "The app is no longer downloadable by new users. People who already have it keep it."
        case .unknown:
            "Apple reported a status this version of CodeGenie has no advice for. Open App Store Connect to read it directly."
        }
    }

    /// The literal next actions, in order.
    var nextActions: [String] {
        switch self {
        case .notSubmitted:
            [
                "Open your app in App Store Connect and read any red banner at the top of the version page.",
                "Fix what it names, then press Add for Review and Submit for Review again.",
            ]
        case .waitingForReview:
            [
                "Leave it alone. Changing the build or cancelling puts you at the back of the queue.",
                "Keep your support and privacy policy pages online — the reviewer opens them.",
                "If it has been more than three working days, use Contact Us in App Store Connect to ask for a status check.",
            ]
        case .inReview:
            [
                "Keep any login, server or API your app needs running.",
                "Watch the email address on your developer account. Reviewers write there if they get stuck.",
            ]
        case .rejected:
            [
                "Open App Store Connect. The message is under App Review on your app's page.",
                "Find the guideline number in it — something like 2.1 or 4.3 — and pick it below.",
                "Fix exactly what it describes. Don't change unrelated things in the same submission.",
                "Reply in that same thread to explain what you changed, then resubmit.",
            ]
        case .metadataRejected:
            [
                "Read Apple's message under App Review to see which field or screenshot they mean.",
                "Edit it on the version page and press Save.",
                "Reply in the thread saying what you changed, then press Resubmit to App Review. The same build is reused.",
            ]
        case .invalidBinary:
            [
                "Check the developer account's email for a message with an ITMS error code.",
                "Fix that in the app, then upload a new build from step 3.",
                "Attach the new build to this version in step 14 and submit again.",
            ]
        case .developerRejected:
            [
                "Make whatever change prompted the withdrawal.",
                "Press Add for Review and Submit for Review again.",
            ]
        case .waitingForExportCompliance:
            [
                "Open your app's TestFlight tab and click the warning next to the build.",
                "Answer No unless you wrote your own encryption. Using HTTPS does not count.",
            ]
        case .pendingDeveloperRelease:
            [
                "Open the version page in App Store Connect.",
                "Press Release This Version.",
            ]
        case .pendingAppleRelease:
            ["Nothing to do. Apple releases it for you."]
        case .processingForDistribution:
            ["Nothing to do. Check back in a few hours."]
        case .live:
            [
                "Open your App Store page and check it reads the way you intended.",
                "Share the link.",
                "Turn on notifications in App Store Connect so you see reviews and crash reports.",
            ]
        case .removedFromSale:
            ["Open Pricing and Availability in App Store Connect to put it back on sale."]
        case .unknown:
            ["Open App Store Connect and read the status on your app's version page."]
        }
    }

    var typicalWait: String? {
        switch self {
        case .waitingForReview: "Usually under 24 hours"
        case .inReview: "Minutes to a few hours"
        case .processingForDistribution: "Up to 24 hours"
        default: nil
        }
    }

    /// Apple has finished deciding and said yes.
    var isApproved: Bool {
        switch self {
        case .pendingDeveloperRelease, .pendingAppleRelease, .processingForDistribution, .live:
            true
        default:
            false
        }
    }

    /// Apple, or the upload pipeline, said no and the user has to act.
    var needsFix: Bool {
        switch self {
        case .rejected, .metadataRejected, .invalidBinary:
            true
        default:
            false
        }
    }

    /// Worth asking Apple again later without the user doing anything.
    var isWaitingOnApple: Bool { tone == .waiting }

    /// A reviewer has at least picked the app up.
    var hasLeftQueue: Bool {
        switch self {
        case .notSubmitted, .waitingForReview, .waitingForExportCompliance, .developerRejected, .unknown:
            false
        default:
            true
        }
    }

    /// States offered when the user reports the status by hand, in the
    /// order they tend to happen.
    static let reportable: [ASCReviewState] = [
        .waitingForReview, .inReview, .rejected, .metadataRejected,
        .pendingDeveloperRelease, .processingForDistribution, .live,
    ]
}

// MARK: - Persisted review progress

/// What CodeGenie remembers about one version's trip through review.
struct ASCReviewProgress: Codable, Hashable {
    struct Event: Codable, Hashable {
        let state: ASCReviewState
        let at: Date
    }

    var state: ASCReviewState
    var lastCheckedAt: Date?
    /// The version string Apple reported, e.g. "1.0".
    var versionString: String?
    /// One entry per change of state, oldest first.
    var history: [Event]
    /// The guideline the user picked from Apple's rejection message.
    var rejectionGuideline: String?
    var resubmissions: Int

    init(state: ASCReviewState = .waitingForReview, at date: Date = Date()) {
        self.state = state
        self.lastCheckedAt = nil
        self.versionString = nil
        self.history = [Event(state: state, at: date)]
        self.rejectionGuideline = nil
        self.resubmissions = 0
    }

    /// Record what Apple (or the user) now says. Returns true when the
    /// state actually changed, so callers know whether to announce it.
    @discardableResult
    mutating func observe(_ new: ASCReviewState, version: String? = nil, at date: Date = Date()) -> Bool {
        lastCheckedAt = date
        if let version, !version.isEmpty { versionString = version }
        guard new != state else { return false }
        // An unrecognised status must not overwrite a known one: a
        // newer Apple vocabulary should degrade to "ask the user", not
        // erase the fact that the app was already approved.
        if new == .unknown && state != .unknown { return false }
        state = new
        history.append(Event(state: new, at: date))
        if !new.needsFix { rejectionGuideline = nil }
        return true
    }

    /// The user says they fixed the problem and sent it back.
    mutating func markResubmitted(at date: Date = Date()) {
        resubmissions += 1
        rejectionGuideline = nil
        state = .waitingForReview
        lastCheckedAt = date
        history.append(Event(state: .waitingForReview, at: date))
    }

    /// When the current state began.
    var stateSince: Date? { history.last?.at }

    var wasEverRejected: Bool { history.contains { $0.state.needsFix } }
}

// MARK: - Reading Apple's response

enum ASCReviewParser {
    struct Version: Equatable {
        let state: ASCReviewState
        let rawState: String
        let versionString: String?
    }

    /// Reads the version that matters out of an `appStoreVersions`
    /// response: the one still moving through Apple's pipeline if
    /// there is one, otherwise the first listed.
    ///
    /// An app with an update in review has two versions — the live one
    /// and the pending one — and Apple does not promise their order,
    /// so taking the first row could report "live" while the update
    /// sits rejected.
    ///
    /// Returns nil when the app has no versions at all, which is what a
    /// record that only ever had TestFlight builds looks like.
    static func currentVersion(in body: [String: Any]) -> Version? {
        guard let rows = body["data"] as? [[String: Any]], !rows.isEmpty else {
            return nil
        }
        let versions = rows.map(version(from:))
        let settled: Set<ASCReviewState> = [.live, .removedFromSale]
        return versions.first { !settled.contains($0.state) } ?? versions.first
    }

    private static func version(from row: [String: Any]) -> Version {
        let attributes = row["attributes"] as? [String: Any] ?? [:]
        let raw = (attributes["appVersionState"] as? String)
            ?? (attributes["appStoreState"] as? String)
            ?? ""
        return Version(
            state: ASCReviewState(apple: raw),
            rawState: raw,
            versionString: attributes["versionString"] as? String
        )
    }
}

// MARK: - Rejection guidance

/// Plain-English help for the guidelines first apps are most often
/// rejected under.
///
/// Deliberately a fixed table, not a model call: the guideline numbers
/// are Apple's and do not move, and a person holding a rejection email
/// needs an answer that is right, not one that is fluent.
struct ASCRejectionGuide: Identifiable, Hashable {
    /// Apple's guideline number, e.g. "2.1".
    let id: String
    let title: String
    /// What Apple means, without the legal phrasing.
    let meaning: String
    /// What usually triggers it on a first app.
    let usualCause: String
    let fixes: [String]
    /// Whether fixing it means uploading a new build.
    let needsNewBuild: NeedsBuild
    /// A reply the user can adapt for the App Review thread.
    let replyTemplate: String

    enum NeedsBuild: String {
        case no, usually, yes

        var label: String {
            switch self {
            case .no: "No new build needed"
            case .usually: "Usually needs a new build"
            case .yes: "Needs a new build"
            }
        }
    }

    static func guide(for guideline: String) -> ASCRejectionGuide? {
        let wanted = normalise(guideline)
        if let exact = all.first(where: { $0.id == wanted }) { return exact }
        // "2.3.3" falls back to the "2.3" family, "5.1.1(v)" to "5.1.1".
        var parts = wanted.split(separator: ".").map(String.init)
        while parts.count > 1 {
            parts.removeLast()
            let parent = parts.joined(separator: ".")
            if let match = all.first(where: { $0.id == parent }) { return match }
        }
        return nil
    }

    /// Pulls every guideline number out of pasted rejection text, in
    /// the order Apple listed them.
    static func guidelines(mentionedIn text: String) -> [String] {
        var found: [String] = []
        var current = ""
        func flush() {
            let trimmed = current.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            current = ""
            let parts = trimmed.split(separator: ".")
            guard parts.count >= 2, parts.count <= 3,
                  let section = Int(parts[0]), (1...5).contains(section),
                  parts.allSatisfy({ $0.count <= 2 })
            else { return }
            if !found.contains(trimmed) { found.append(trimmed) }
        }
        for character in text {
            if character.isNumber || character == "." {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return found
    }

    private static func normalise(_ raw: String) -> String {
        var out = ""
        for character in raw {
            if character.isNumber || character == "." { out.append(character) } else if !out.isEmpty { break }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static let all: [ASCRejectionGuide] = [
        .init(
            id: "2.1",
            title: "App Completeness",
            meaning: "The reviewer hit a crash, a dead end, a placeholder, or could not get into the app at all.",
            usualCause: "No working test login was supplied, a screen still shows sample text, or the app needs a server that was down during review.",
            fixes: [
                "Read the message for the exact screen and device they were on, and reproduce it there.",
                "If the app has sign-in, put a working username and password in App Review Information (step 13).",
                "Remove every placeholder: sample names, lorem ipsum, buttons that do nothing.",
                "If a server is involved, keep it running through the whole review.",
            ],
            needsNewBuild: .usually,
            replyTemplate: "Thank you for the review. We reproduced the issue you described on [device / iOS version] and fixed it in build [number]. [One sentence on what was wrong.] A working demo account is now in App Review Information."
        ),
        .init(
            id: "2.3",
            title: "Accurate Metadata",
            meaning: "The store page promises something the app does not do, or shows something that is not in the app.",
            usualCause: "Screenshots from an earlier design, a description written before the app was finished, or keywords naming other apps.",
            fixes: [
                "Retake screenshots from the build you submitted so they match exactly.",
                "Delete any feature from the description that isn't in this version.",
                "Remove other companies' names and unrelated terms from the name, subtitle and keywords.",
                "Resubmit the same build once the page is corrected.",
            ],
            needsNewBuild: .no,
            replyTemplate: "Thank you. We have updated the [screenshots / description / keywords] so they reflect the current build exactly. No changes were made to the binary."
        ),
        .init(
            id: "4.0",
            title: "Design",
            meaning: "Something in the interface breaks Apple's design rules — text cut off, controls too small to tap, or a layout that fails on one screen size.",
            usualCause: "The app was only tried on one iPhone size, or doesn't adapt to larger text.",
            fixes: [
                "Run it on the smallest and largest iPhone in the simulator and fix anything clipped or overlapping.",
                "Turn on Larger Text in Accessibility settings and check every screen still works.",
                "Make every tappable control at least 44 points tall.",
            ],
            needsNewBuild: .yes,
            replyTemplate: "Thank you. We corrected the layout issue on [screen] and verified the app on [smallest device] and [largest device], including with larger text sizes, in build [number]."
        ),
        .init(
            id: "4.2",
            title: "Minimum Functionality",
            meaning: "Apple thinks the app does too little to justify being an app — it reads as a web page, a single static screen, or a demo.",
            usualCause: "A very small first version, or an app that only wraps a website.",
            fixes: [
                "Add something that genuinely needs to be an app: saving data on the device, notifications, widgets, offline use.",
                "Make sure the main feature works end to end with real content, not a sample.",
                "In your reply, describe concretely what a person can do in the app and why it is useful to them.",
            ],
            needsNewBuild: .yes,
            replyTemplate: "Thank you for the feedback. Build [number] adds [specific native features]. The app lets people [concrete task], which they can now do [offline / with reminders / across launches]. We'd welcome a further look."
        ),
        .init(
            id: "4.3",
            title: "Spam",
            meaning: "Apple thinks this app is too similar to others already on the store, or to a template many people have submitted.",
            usualCause: "The app's idea, layout or wording closely matches many existing apps. Reviewers apply this more strictly to apps that look generated from a common starting point.",
            fixes: [
                "Be honest about what is different. If the answer is nothing, a reply will not change the outcome — the app needs a real point of difference first.",
                "Change what makes it yours: its content, its audience, a feature the look-alikes don't have. Renaming and recolouring is not enough.",
                "Rewrite the name, subtitle and description in your own words around that difference.",
                "Don't submit several near-identical apps. Put the variations inside one.",
            ],
            needsNewBuild: .yes,
            replyTemplate: "Thank you. We understand the concern. This app is built for [specific audience] and differs from existing apps in [concrete, checkable ways]. Build [number] makes that clearer by [changes]. We are the sole developer and this is our only app in this category."
        ),
        .init(
            id: "4.8",
            title: "Login Services",
            meaning: "The app offers sign-in through another company's account, so it must also offer an equivalent privacy-focused option.",
            usualCause: "Google or Facebook sign-in was added without Sign in with Apple alongside it.",
            fixes: [
                "Add Sign in with Apple as an option wherever third-party sign-in appears.",
                "Or remove third-party sign-in and use your own email accounts only.",
            ],
            needsNewBuild: .yes,
            replyTemplate: "Thank you. Build [number] adds Sign in with Apple alongside the existing sign-in options on [screen]."
        ),
        .init(
            id: "5.1.1",
            title: "Data Collection and Storage",
            meaning: "Something about how the app asks for, explains or handles personal data doesn't meet Apple's privacy rules.",
            usualCause: "A missing or unreachable privacy policy, a permission prompt that doesn't say why, an account you can create but not delete, or a sign-up wall in front of features that don't need one.",
            fixes: [
                "Make sure the privacy policy URL loads and actually describes this app.",
                "Rewrite each permission prompt to say what the data is used for, in a full sentence.",
                "If people can create an account in the app, they must be able to delete it in the app too.",
                "Let people use anything that doesn't need an account without signing in.",
            ],
            needsNewBuild: .usually,
            replyTemplate: "Thank you. We have [updated the privacy policy at URL / reworded the permission prompt for X to explain its purpose / added account deletion under Settings]. These changes are in build [number]."
        ),
        .init(
            id: "5.1.2",
            title: "Data Use and Sharing",
            meaning: "The app shares or tracks data in a way the user wasn't asked about, or the App Privacy answers don't match what the app does.",
            usualCause: "An analytics or advertising SDK is present but the privacy answers say nothing is collected.",
            fixes: [
                "List every third-party SDK in the app and what each one sends.",
                "Update the App Privacy answers (step 10) to match.",
                "If anything tracks people across apps, ask permission with the tracking prompt first — or remove it.",
            ],
            needsNewBuild: .usually,
            replyTemplate: "Thank you. We reviewed every SDK in the app and updated our App Privacy responses to match. [We removed X / we now request tracking permission before Y] in build [number]."
        ),
        .init(
            id: "3.1.1",
            title: "In-App Purchase",
            meaning: "The app sells digital content or features without using Apple's purchase system.",
            usualCause: "A link to pay on a website, or a mention of cheaper prices elsewhere, for something used inside the app.",
            fixes: [
                "Sell digital features and subscriptions through In-App Purchase.",
                "Remove buttons and text that send people to pay outside the app, unless your region's rules specifically allow it.",
                "Physical goods and real-world services are exempt and can use other payment methods.",
            ],
            needsNewBuild: .yes,
            replyTemplate: "Thank you. Build [number] offers [feature] through In-App Purchase and removes the external payment link on [screen]."
        ),
        .init(
            id: "1.2",
            title: "User-Generated Content",
            meaning: "People can post things other people see, and the app lacks the tools Apple requires to keep that safe.",
            usualCause: "Comments, profiles or uploads were added without a way to report or block.",
            fixes: [
                "Add a way to report offensive content and a way to block abusive users.",
                "Filter objectionable material before it is shown.",
                "Publish contact details so people can reach you about content.",
                "Say in your reply how quickly reports are acted on.",
            ],
            needsNewBuild: .yes,
            replyTemplate: "Thank you. Build [number] adds reporting and blocking on [screens], filters objectionable content before display, and we act on reports within 24 hours. Contact details are at [URL]."
        ),
        .init(
            id: "1.5",
            title: "Developer Information",
            meaning: "Apple couldn't reach you, or the support link on your page doesn't lead anywhere useful.",
            usualCause: "The support URL returns an error, or points at a page with no way to make contact.",
            fixes: [
                "Open the support URL in a private browser window and confirm it loads.",
                "Make sure the page shows a way to contact you — an email address is enough.",
                "Check the contact details in App Review Information are current.",
            ],
            needsNewBuild: .no,
            replyTemplate: "Thank you. The support URL now loads and includes contact details. We have also confirmed the contact information in App Review Information."
        ),
        .init(
            id: "5.2",
            title: "Intellectual Property",
            meaning: "The app uses a name, logo, image or content that belongs to someone else.",
            usualCause: "A brand name in the app's title or keywords, or artwork and data taken from another service without permission.",
            fixes: [
                "Remove other companies' names and logos from the app and its store page.",
                "Replace any content you don't own or hold a licence for.",
                "If you do have permission, attach the written proof in your reply.",
            ],
            needsNewBuild: .usually,
            replyTemplate: "Thank you. We removed [the third-party name / artwork] from the app and its metadata in build [number]. [Or: we hold a licence for X, attached.]"
        ),
    ]
}
