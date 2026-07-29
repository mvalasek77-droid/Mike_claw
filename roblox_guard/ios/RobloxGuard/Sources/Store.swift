import CryptoKit
import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var children: [Child] = []
    @Published var alertsByChild: [Int: [SafetyAlert]] = [:]
    @Published var resources: [SafetyResource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private var demoEvidenceByChild: [Int: [EvidenceItem]] = [:]

    let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    var isDemoMode: Bool { UserDefaults.standard.bool(forKey: "demoMode") }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        if isDemoMode {
            loadDemoData()
            return
        }

        do {
            children = try await api.listChildren()
            for child in children {
                alertsByChild[child.id] = try await api.alerts(childId: child.id)
            }
            if resources.isEmpty {
                resources = try await api.resources()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDemoMode(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "demoMode")
        children = []
        alertsByChild = [:]
        resources = []
        demoEvidenceByChild = [:]
        errorMessage = nil
        await loadAll()
    }

    func linkChild(username: String, parentName: String) async -> Bool {
        if isDemoMode {
            return linkDemoChild(username: username, parentName: parentName)
        }

        do {
            let child = try await api.linkChild(username: username, parentName: parentName)
            children.append(child)
            try await api.refresh(childId: child.id)
            alertsByChild[child.id] = try await api.alerts(childId: child.id)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func unlinkChild(_ child: Child) async {
        if isDemoMode {
            children.removeAll { $0.id == child.id }
            alertsByChild[child.id] = nil
            demoEvidenceByChild[child.id] = nil
            return
        }

        do {
            try await api.unlinkChild(id: child.id)
            children.removeAll { $0.id == child.id }
            alertsByChild[child.id] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(_ child: Child) async {
        if isDemoMode { return }

        do {
            try await api.refresh(childId: child.id)
            let previous = Set((alertsByChild[child.id] ?? []).map(\.id))
            let updated = try await api.alerts(childId: child.id)
            alertsByChild[child.id] = updated
            let fresh = updated.filter { !previous.contains($0.id) }
            if let worst = fresh.max(by: { severityRank($0.severity) < severityRank($1.severity) }) {
                Haptics.alert(worst.severity)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func severityRank(_ severity: AlertSeverity) -> Int {
        switch severity {
        case .info: return 0
        case .watch: return 1
        case .elevated: return 2
        }
    }

    func acknowledge(_ alert: SafetyAlert, for child: Child) async {
        if isDemoMode {
            alertsByChild[child.id]?.removeAll { $0.id == alert.id }
            return
        }

        do {
            try await api.acknowledge(alertId: alert.id)
            alertsByChild[child.id]?.removeAll { $0.id == alert.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendFeedback(alertId: Int, verdict: String) async {
        if isDemoMode { return }
        try? await api.sendFeedback(alertId: alertId, verdict: verdict)
    }

    func education() async throws -> EducationContent {
        if isDemoMode { return Self.demoEducation }
        return try await api.education()
    }

    func demoEvidence(for child: Child) -> [EvidenceItem] {
        demoEvidenceByChild[child.id] ?? []
    }

    func addDemoEvidence(imageData: Data, note: String, for child: Child) {
        guard isDemoMode else { return }
        let digest = SHA256.hash(data: imageData)
            .map { String(format: "%02x", $0) }
            .joined()
        let nextID = (demoEvidenceByChild.values.flatMap { $0 }.map(\.id).max() ?? 200000) + 1
        let item = EvidenceItem(
            id: nextID,
            kind: "parent_upload",
            sha256: digest,
            note: note.isEmpty ? "Sample evidence added during App Review demo." : note,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            filename: "demo_screenshot.png"
        )
        demoEvidenceByChild[child.id, default: []].append(item)
    }

    // MARK: - Demo Data

    /// Populates the store with a demo child and sample alerts so Apple
    /// reviewers can test every UI flow without a backend or real Roblox
    /// account. Uses builderman (Roblox's official test account).
    private func loadDemoData() {
        if children.isEmpty {
            let demoChild = Child(
                id: 99999,
                robloxUserId: 156,
                robloxUsername: "builderman",
                displayName: "builderman",
                lastPollAt: ISO8601DateFormatter().string(from: Date()),
                lastPollStatus: "ok",
                reportAccessToken: "demo"
            )
            children = [demoChild]
            alertsByChild[demoChild.id] = Self.demoAlerts
            demoEvidenceByChild[demoChild.id] = Self.demoEvidence
        }
        if resources.isEmpty {
            resources = Self.demoResources
        }
        errorMessage = nil
    }

    private func linkDemoChild(username: String, parentName: String) -> Bool {
        let demoChild = Child(
            id: 99998,
            robloxUserId: 156,
            robloxUsername: username,
            displayName: username,
            lastPollAt: ISO8601DateFormatter().string(from: Date()),
            lastPollStatus: "ok",
            reportAccessToken: "demo"
        )
        children.append(demoChild)
        alertsByChild[demoChild.id] = Self.demoAlerts
        demoEvidenceByChild[demoChild.id] = Self.demoEvidence
        errorMessage = nil
        return true
    }

    static let demoAlerts: [SafetyAlert] = [
        SafetyAlert(
            id: 100001,
            type: "grooming_precursor",
            severity: .elevated,
            title: "New friend's bio contains gaming-adjacent contact handle",
            facts: [
                "A new friend added yesterday has 'add my Snap' in their profile bio.",
                "This friend has 3 mutual games with your child.",
                "The bio also contains a Discord tag.",
            ],
            guidance: "Ask your child how they know this person. Check if they've chatted outside Roblox. Consider reviewing your child's friends list together and removing anyone they can't name in real life.",
            subjectUsername: "UnknownPlayer42",
            observedAt: ISO8601DateFormatter().string(from: Date()),
            acknowledged: false,
            explainers: [
                TermExplainer(term: "Discord", definition: "A chat app popular with gamers. Discord lets users send direct messages, share images, and join group chats — it's not part of Roblox and is not filtered by Roblox's chat safety systems."),
                TermExplainer(term: "Snap", definition: "Short for Snapchat, a messaging app where messages and photos disappear after viewing. Its disappearing nature makes it a common platform for adults contacting minors."),
                TermExplainer(term: "Bio", definition: "The text on a Roblox profile page. Anyone can see it — it's public. Roblox filters some words, but contact handles like Discord tags can still get through."),
            ]
        ),
        SafetyAlert(
            id: 100002,
            type: "off_platform_contact",
            severity: .watch,
            title: "New friend list spike: 8 new friends in 24 hours",
            facts: [
                "Your child added 8 new friends in the last day — well above their usual rate.",
                "3 of these new friends have accounts less than a week old.",
                "2 of the new friends have no mutual games with your child.",
            ],
            guidance: "This is worth a conversation, not an alarm. Ask who these new friends are. New accounts with no mutual games can be a sign of someone creating alternate identities.",
            subjectUsername: nil,
            observedAt: ISO8601DateFormatter().string(from: Date()),
            acknowledged: false,
            explainers: [
                TermExplainer(term: "Mutual games", definition: "Roblox games (called 'experiences') that both your child and the new friend have played. No mutual games means they met somewhere else on Roblox — like a chat in a different game, or a friend recommendation."),
            ]
        ),
        SafetyAlert(
            id: 100003,
            type: "age_disparity_signal",
            severity: .watch,
            title: "Friend with adult-themed bio added",
            facts: [
                "A new friend's bio contains text suggesting the account belongs to an adult.",
                "The bio includes '19F' (a common shorthand for 19-year-old female).",
                "This friend plays primarily social/roleplay experiences.",
            ],
            guidance: "Ask your child if they know this person's age. An adult befriending a child on a kids' platform is a pattern to take seriously. If the conversation feels off, use Roblox's report function and consider removing the friend.",
            subjectUsername: "SocialGamer_19",
            observedAt: ISO8601DateFormatter().string(from: Date()),
            acknowledged: false,
            explainers: [
                TermExplainer(term: "Roleplay experiences", definition: "A genre of Roblox games where players act out scenarios — like 'Brookhaven' or 'MeepCity'. These are very social and involve lots of chat, making them common places where strangers meet."),
            ]
        ),
    ]

    static let demoResources: [SafetyResource] = [
        SafetyResource(id: "ncmec", title: "NCMEC CyberTipline", url: "https://report.cybertip.org", description: "Report child exploitation to the National Center for Missing & Exploited Children."),
        SafetyResource(id: "roblox-report", title: "Report to Roblox", url: "https://en.help.roblox.com/hc/en-us/articles/203312410", description: "Roblox's official reporting tool for inappropriate behavior."),
        SafetyResource(id: "roblox-parents", title: "Roblox Parents Guide", url: "https://en.help.roblox.com/hc/en-us/articles/115004647846", description: "Official guide to Roblox parental controls and account restrictions."),
    ]

    static let demoEvidence: [EvidenceItem] = [
        EvidenceItem(
            id: 200001,
            kind: "profile_screenshot",
            sha256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
            note: "Sample profile captured when the elevated alert fired.",
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            filename: "demo_profile.png"
        ),
        EvidenceItem(
            id: 200002,
            kind: "parent_upload",
            sha256: "f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5",
            note: "Sample chat screenshot showing a request to move to Discord.",
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            filename: "demo_chat.png"
        ),
    ]

    static let demoEducation = EducationContent(
        robloxBasics: [
            BasicsEntry(
                id: "experience",
                question: "What is a Roblox experience?",
                answer: "Roblox calls each game or social world an experience. Players can move between experiences and meet different people in each one."
            ),
            BasicsEntry(
                id: "friends",
                question: "What does adding a friend allow?",
                answer: "Friends can more easily find one another, join the same experiences, and communicate through the features Roblox makes available to their accounts."
            ),
        ],
        dangers: [
            DangerEntry(
                id: "off-platform",
                title: "Moving a conversation off Roblox",
                summary: "A stranger may ask a child to continue on an app with fewer safeguards or disappearing messages.",
                progression: [
                    "The person builds trust through a shared game.",
                    "They ask for a Discord, Snapchat, or other contact handle.",
                    "They pressure the child to keep the conversation secret.",
                ]
            ),
        ],
        behavioralSigns: [
            "Becoming unusually secretive about online friends.",
            "Receiving gifts or digital currency from someone you do not know.",
        ],
        immediateRedFlags: [
            "An adult asks for private photos, a meeting, or secrecy.",
            "Someone threatens or blackmails your child.",
        ],
        responsePlaybook: [
            "Stay calm and tell your child they did the right thing by telling you.",
            "Preserve safe evidence without saving sexual imagery of a minor.",
            "Block and report the account in Roblox; contact NCMEC or local police when appropriate.",
        ],
        glossary: [
            TermExplainer(term: "Discord", definition: "A separate chat service often used by gaming communities; it is not moderated by Roblox."),
            TermExplainer(term: "Robux", definition: "Roblox's virtual currency, used for avatar items and in-experience purchases."),
        ]
    )
}
