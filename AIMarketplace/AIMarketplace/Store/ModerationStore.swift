import Foundation
import SwiftUI

/// Per-device moderation state — which titles the user has reported, which
/// creators they have blocked. Sending a report goes through the same
/// Cloudflare Worker that handles payouts (POST /moderation/report); the
/// Worker emails the operator inbox.
///
/// Persisted locally via UserDefaults — reports and blocks survive app launches
/// without needing the encrypted creator archive (this is buyer-side state).
@MainActor
final class ModerationStore: ObservableObject {
    /// Titles this device has reported (used to grey-out the Report button after submission).
    @Published private(set) var reportedItemIDs: Set<UUID> = []
    /// Creators (by display name) this device has blocked.
    @Published private(set) var blockedCreators: Set<String> = []

    private let defaultsKey = "aimkt.moderation.v1"

    init() { load() }

    // MARK: - Blocks

    func block(_ creator: String) {
        let name = creator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        blockedCreators.insert(name)
        persist()
    }

    func unblock(_ creator: String) {
        blockedCreators.remove(creator)
        persist()
    }

    func isBlocked(_ creator: String) -> Bool { blockedCreators.contains(creator) }

    // MARK: - Reports

    /// Submit a report to the operator. The report is recorded locally first so
    /// the UI can acknowledge immediately even if the network call fails; the
    /// operator inbox is the authoritative log for App Review.
    func submitReport(
        itemID: UUID,
        itemTitle: String,
        creatorName: String,
        reason: String,
        details: String,
        reporterEmail: String?,
        baseURL: String?,
        sharedSecret: String?
    ) async -> Bool {
        reportedItemIDs.insert(itemID); persist()

        let trimmedURL = (baseURL ?? "").trimmingCharacters(in: .whitespaces)
        let secret = (sharedSecret ?? "").trimmingCharacters(in: .whitespaces)
        guard !trimmedURL.isEmpty, !secret.isEmpty,
              let base = URL(string: trimmedURL) else { return false }

        var req = URLRequest(url: base.appendingPathComponent("moderation/report"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "item_id": itemID.uuidString,
            "item_title": itemTitle,
            "creator_name": creatorName,
            "reason": reason,
            "details": details,
            "reporter_email": reporterEmail ?? "",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch {
            return false
        }
    }

    func hasReported(_ itemID: UUID) -> Bool { reportedItemIDs.contains(itemID) }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var reported: [UUID]
        var blocked: [String]
    }

    private func persist() {
        let snap = Snapshot(reported: Array(reportedItemIDs), blocked: Array(blockedCreators))
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        reportedItemIDs = Set(snap.reported)
        blockedCreators = Set(snap.blocked)
    }
}
