import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var children: [Child] = []
    @Published var alertsByChild: [Int: [SafetyAlert]] = [:]
    @Published var resources: [SafetyResource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    #if DEBUG
    var isDemoMode: Bool { UserDefaults.standard.bool(forKey: "demoMode") }
    #else
    var isDemoMode: Bool { false }
    #endif

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        if isDemoMode {
            loadDemoData()
            return
        }
        #endif

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

    func linkChild(username: String, parentName: String) async -> Bool {
        #if DEBUG
        if isDemoMode {
            return linkDemoChild(username: username, parentName: parentName)
        }
        #endif

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
        #if DEBUG
        if isDemoMode {
            children.removeAll { $0.id == child.id }
            alertsByChild[child.id] = nil
            return
        }
        #endif

        do {
            try await api.unlinkChild(id: child.id)
            children.removeAll { $0.id == child.id }
            alertsByChild[child.id] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh(_ child: Child) async {
        #if DEBUG
        if isDemoMode { return }
        #endif

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
        #if DEBUG
        if isDemoMode {
            alertsByChild[child.id]?.removeAll { $0.id == alert.id }
            return
        }
        #endif

        do {
            try await api.acknowledge(alertId: alert.id)
            alertsByChild[child.id]?.removeAll { $0.id == alert.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Demo Data

    #if DEBUG
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
                lastPollStatus: "ok"
            )
            children = [demoChild]
            alertsByChild[demoChild.id] = Self.demoAlerts
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
            lastPollStatus: "ok"
        )
        children.append(demoChild)
        alertsByChild[demoChild.id] = Self.demoAlerts
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
    #endif
}