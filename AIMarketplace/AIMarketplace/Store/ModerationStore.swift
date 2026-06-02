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

    /// Normalised match key so "Mike Valasek" and "mike valasek" + leading
    /// whitespace all collapse to the same block entry. Real rename
    /// resilience (creator changes display name → block keeps working)
    /// needs a stable creator id, which the current data model doesn't
    /// surface (users register once and don't edit their name; AI creators
    /// are model strings that don't change).
    private func key(_ creator: String) -> String {
        creator.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func block(_ creator: String) {
        let k = key(creator)
        guard !k.isEmpty else { return }
        blockedCreators.insert(k)
        persist()
    }

    func unblock(_ creator: String) {
        blockedCreators.remove(key(creator))
        persist()
    }

    func isBlocked(_ creator: String) -> Bool { blockedCreators.contains(key(creator)) }

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
        notifyOnResolve: Bool = false,
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
            "notify_on_resolve": notifyOnResolve,
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

    /// App Review 5.1.1(v): on account deletion every on-device store must be
    /// wiped. ModerationStore's state lives in its own UserDefaults key — the
    /// encrypted-archive delete in MarketplaceStore misses it — so this is the
    /// hook MarketplaceStore.deleteAccount() calls.
    func wipe() {
        reportedItemIDs.removeAll()
        blockedCreators.removeAll()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Admin queue (Worker-backed)

    /// One row in the admin moderation queue. Mirrors the Worker's KV record.
    struct QueueEntry: Identifiable, Hashable, Codable {
        var id: String
        var ts: String
        var status: String        // "pending" | "resolved"
        var item_id: String
        var item_title: String
        var creator_name: String
        var reason: String
        var details: String
        var reporter_email: String
        var disposition: String   // "" | "removed" | "warned" | "dismissed"
        var resolved_at: String
        var resolution_note: String
    }

    enum QueueStatus: String { case pending, resolved }
    enum Disposition: String { case removed, warned, dismissed }

    /// Result type so the caller can distinguish "queue is empty" from "we
    /// couldn't reach it" or "the Worker has no KV bound." The previous
    /// `-> [QueueEntry]` ate every failure mode and silently showed "Nothing
    /// pending" — a real false-reassurance footgun for the operator.
    enum QueueFetch {
        case ok([QueueEntry])
        case notConfigured(String)   // Worker reachable but reports unsupported
        case failed(String)          // Network / auth / decode error
    }

    func fetchQueue(status: QueueStatus, baseURL: String, sharedSecret: String) async -> QueueFetch {
        guard let base = URL(string: baseURL.trimmingCharacters(in: .whitespaces)),
              !sharedSecret.isEmpty else {
            return .failed("Worker URL or shared secret missing.")
        }
        var url = base.appendingPathComponent("moderation/reports")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "status", value: status.rawValue)]
        url = comps?.url ?? url
        var req = URLRequest(url: url)
        req.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
        struct Payload: Decodable { let reports: [QueueEntry]; let note: String? }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .failed("No response from the server.")
            }
            if http.statusCode == 401 { return .failed("Unauthorized — Worker secret rejected.") }
            if !(200..<300).contains(http.statusCode) {
                return .failed("Server returned \(http.statusCode).")
            }
            guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
                return .failed("Couldn't parse the queue response.")
            }
            if let note = payload.note, !note.isEmpty, payload.reports.isEmpty {
                return .notConfigured(note)
            }
            return .ok(payload.reports)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func resolve(reportID: String, disposition: Disposition, note: String,
                 baseURL: String, sharedSecret: String) async -> Bool {
        guard let base = URL(string: baseURL.trimmingCharacters(in: .whitespaces)),
              !sharedSecret.isEmpty else { return false }
        var req = URLRequest(url: base.appendingPathComponent("moderation/reports/\(reportID)/resolve"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "disposition": disposition.rawValue,
            "note": note,
        ])
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        } catch { return false }
    }

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
