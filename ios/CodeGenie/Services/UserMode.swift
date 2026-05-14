import Foundation
import SwiftUI

/// First-time vs. power-user mode.
///
/// **Why this exists.** Settings has ~12 things to think about (BYOK
/// keys, subscription, snapshot cap, per-agent routing, custom
/// agents, telemetry, Apple Developer creds, hosted credits, etc.).
/// A new user does not need any of that to watch a sample build or
/// describe their first app. We hide the entire power-user surface
/// behind one bit.
///
/// **Default.** New users land in `.justBuild`. The Describe-an-app
/// form drops to: one prompt field + one Build button. Settings
/// shows only the essentials. Power features (cost cap, snapshot
/// cap, per-agent routing, custom agents, admin, telemetry, Apple
/// Developer) are tucked behind a single "Power user" disclosure.
///
/// **Promotion.** The first time the user explicitly opts in to a
/// power feature (taps "Power user mode" in Settings, OR sets a
/// custom API key, OR pairs a Mac), we flip them to `.power` so the
/// UI stops hiding things they've already shown they want.
@MainActor
final class UserMode: ObservableObject {
    static let shared = UserMode()

    enum Tier: String, Codable {
        case justBuild
        case power
    }

    @Published private(set) var tier: Tier

    private static let storageKey = "user.mode.tier.v1"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        self.tier = Tier(rawValue: raw) ?? .justBuild
    }

    var isSimple: Bool { tier == .justBuild }
    var isPower: Bool { tier == .power }

    func setTier(_ tier: Tier) {
        self.tier = tier
        UserDefaults.standard.set(tier.rawValue, forKey: Self.storageKey)
        Haptics.selection()
    }

    /// Promote on the first explicit power action. Idempotent.
    func promoteToPower() {
        guard tier != .power else { return }
        setTier(.power)
    }
}
