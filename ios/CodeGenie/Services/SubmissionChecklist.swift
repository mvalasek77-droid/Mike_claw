import Foundation

/// The things a person has to confirm themselves before submitting.
///
/// **Why this is separate from the readiness gates.** CodeGenie already
/// checks everything a machine can check: field lengths, a signed
/// binary, credentials, the privacy manifest. Those are gates and they
/// block automatically.
///
/// This list is the other half — the things only the human knows.
/// Whether the app actually works on a real device. Whether the
/// screenshots show real content. Whether the privacy answers are
/// true. Apple rejects on these constantly and no static analysis can
/// catch any of them.
///
/// Items CodeGenie *can* verify are marked `autoKey` and tick
/// themselves from the live readiness run, so the user is never asked
/// to confirm something already proven. What is left is genuinely
/// theirs to attest.
enum SubmissionChecklist {

    struct Item: Identifiable, Hashable {
        let id: String
        let group: Group
        let title: String
        /// Why Apple cares. Without this the item is just a chore.
        let why: String
        /// When set, a readiness item with this key ticks it
        /// automatically once it passes.
        let autoKey: String?
        /// Only relevant to the full App Store release, not TestFlight.
        let appStoreOnly: Bool

        init(
            id: String,
            group: Group,
            title: String,
            why: String,
            autoKey: String? = nil,
            appStoreOnly: Bool = false
        ) {
            self.id = id
            self.group = group
            self.title = title
            self.why = why
            self.autoKey = autoKey
            self.appStoreOnly = appStoreOnly
        }
    }

    enum Group: String, CaseIterable, Identifiable {
        case works = "It actually works"
        case content = "What Apple will see"
        case legal = "Honesty and legal"
        case ready = "Before you press Submit"

        var id: String { rawValue }

        var blurb: String {
            switch self {
            case .works:   "Reviewers open your app on a real device. Most first-app rejections happen right here."
            case .content: "Your store page has to match what the app really does."
            case .legal:   "These are audited after release. A wrong answer can pull a live app."
            case .ready:   "The last look before it leaves your hands."
            }
        }
    }

    static let all: [Item] = [
        // --- It actually works ---
        .init(
            id: "runs_on_device",
            group: .works,
            title: "I opened the app on a real iPhone and it works",
            why: "Guideline 2.1 is the most common rejection there is. A reviewer will open your app on real hardware — if it crashes on launch or a main feature is dead, it comes straight back.",
            autoKey: nil
        ),
        .init(
            id: "no_placeholder",
            group: .works,
            title: "No placeholder text, lorem ipsum, or fake data anywhere",
            why: "Apple treats visible placeholder content as an unfinished app and rejects it, even when everything else is perfect.",
            autoKey: nil
        ),
        .init(
            id: "no_broken_links",
            group: .works,
            title: "Every button and link in the app does something",
            why: "Dead buttons and links to nowhere read as incomplete. A reviewer will tap them.",
            autoKey: nil
        ),
        .init(
            id: "demo_account",
            group: .works,
            title: "If the app has a login, I've given Apple a working test account",
            why: "Reviewers cannot sign up for your service. Without working credentials in App Review Information they cannot see your app at all, and it is rejected unopened.",
            autoKey: nil
        ),

        // --- What Apple will see ---
        .init(
            id: "icon_ready",
            group: .content,
            title: "App icon is 1024×1024, no transparency, corners not pre-rounded",
            why: "Apple rejects a wrong icon automatically, before a human sees anything. Icons exported from design tools often carry a hidden alpha channel.",
            autoKey: "app_icon",
            appStoreOnly: true
        ),
        .init(
            id: "screenshots_real",
            group: .content,
            title: "Screenshots show the real app with real content",
            why: "Guideline 2.3. Screenshots that don't match what the app does, or show placeholder data, are a frequent rejection.",
            autoKey: "screenshots",
            appStoreOnly: true
        ),
        .init(
            id: "description_true",
            group: .content,
            title: "The description matches what the app actually does",
            why: "Describing features that aren't there is rejected as inaccurate metadata, and it is easy to do by accident when the description was drafted early.",
            autoKey: nil,
            appStoreOnly: true
        ),
        .init(
            id: "support_url_live",
            group: .content,
            title: "My support URL loads in a browser right now",
            why: "Apple actually opens it. A 404 or a parked domain is a rejection, and this is one of the most common misses.",
            autoKey: nil
        ),

        // --- Honesty and legal ---
        .init(
            id: "privacy_answers",
            group: .legal,
            title: "My App Privacy answers are true",
            why: "Apple audits these after release. Saying you collect nothing while an analytics SDK phones home can get a live app pulled.",
            autoKey: nil,
            appStoreOnly: true
        ),
        .init(
            id: "privacy_policy_live",
            group: .legal,
            title: "My privacy policy URL loads and covers this app",
            why: "Required for every app, even one that collects nothing at all.",
            autoKey: "privacy_policy",
            appStoreOnly: true
        ),
        .init(
            id: "own_the_content",
            group: .legal,
            title: "I own or have permission for everything in the app",
            why: "Images, fonts, music, trademarks, and API data all count. Using someone else's brand or content without rights is rejected and can escalate.",
            autoKey: nil
        ),
        .init(
            id: "export_compliance",
            group: .legal,
            title: "I understand the encryption question",
            why: "If you didn't add your own encryption, the answer is No. Using HTTPS does not count as adding encryption. Answering wrong holds the build.",
            autoKey: nil
        ),

        // --- Before you press Submit ---
        .init(
            id: "tested_by_someone",
            group: .ready,
            title: "Someone other than me has installed and used it",
            why: "You know where not to tap. Nobody else does. A single TestFlight tester catches most of what a reviewer would find.",
            autoKey: nil
        ),
        .init(
            id: "right_build",
            group: .ready,
            title: "I picked the build that finished processing",
            why: "It is easy to submit yesterday's build. Check the version and build number against the one you just uploaded.",
            autoKey: nil,
            appStoreOnly: true
        ),
        .init(
            id: "accept_wait",
            group: .ready,
            title: "I know review takes 24–48 hours and a rejection isn't the end",
            why: "Most first apps get rejected once. Apple tells you the exact guideline in Resolution Center, and the usual fixes are metadata changes with no rebuild.",
            autoKey: nil
        ),
    ]

    // MARK: - Scoping

    /// TestFlight needs far less than a public release. Asking someone
    /// to attest to screenshots before they have even installed their
    /// own app is how a checklist turns into noise people tick blindly.
    static func items(forAppStore: Bool) -> [Item] {
        forAppStore ? all : all.filter { !$0.appStoreOnly }
    }

    static func items(in group: Group, forAppStore: Bool) -> [Item] {
        items(forAppStore: forAppStore).filter { $0.group == group }
    }

    // MARK: - Auto-satisfaction

    /// Readiness keys that have genuinely passed, so the matching items
    /// can tick themselves and stop asking.
    static func autoSatisfied(from run: ReleaseReadinessRun?) -> Set<String> {
        guard let run else { return [] }
        let passing = Set(
            run.items
                .filter { ["automated", "assisted", "user_confirmation"].contains($0.status) }
                .map(\.key)
        )
        return Set(all.compactMap { item in
            guard let key = item.autoKey, passing.contains(key) else { return nil }
            return item.id
        })
    }

    /// Everything still needing the user's own confirmation.
    static func outstanding(
        checked: Set<String>,
        autoSatisfied: Set<String>,
        forAppStore: Bool
    ) -> [Item] {
        let settled = checked.union(autoSatisfied)
        return items(forAppStore: forAppStore).filter { !settled.contains($0.id) }
    }

    static func isComplete(
        checked: Set<String>,
        autoSatisfied: Set<String>,
        forAppStore: Bool
    ) -> Bool {
        outstanding(checked: checked, autoSatisfied: autoSatisfied, forAppStore: forAppStore).isEmpty
    }
}
