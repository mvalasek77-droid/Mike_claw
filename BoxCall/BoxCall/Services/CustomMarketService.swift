import Foundation
import Combine

/// Creation + listing of user-proposed CustomMarkets. Creation is
/// gated on Mogul tier; live markets are visible to everyone.
///
/// Server-side moderation is required before a new market goes live
/// (kept simple here: proposals from Mogul users go straight to
/// pendingReview; a real backend has an admin queue).
@MainActor
final class CustomMarketService: ObservableObject {
    static let shared = CustomMarketService()

    @Published private(set) var markets: [CustomMarket] = []

    private init() { seed() }

    // MARK: - Creation

    enum CreateError: LocalizedError {
        case notMogul, tooShort, questionRequired
        var errorDescription: String? {
            switch self {
            case .notMogul: return "Custom markets are a Mogul-tier perk. Upgrade in your profile to create one."
            case .tooShort: return "Add more detail so voters know exactly how this settles."
            case .questionRequired: return "The question is required."
            }
        }
    }

    func propose(question: String, details: String, resolvesOn: Date) throws {
        let user = PortfolioService.shared.user
        guard user.membership == .mogul else { throw CreateError.notMogul }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw CreateError.questionRequired }
        guard d.count >= 20 else { throw CreateError.tooShort }

        markets.insert(.init(
            id: UUID(),
            question: q,
            details: d,
            creatorHandle: user.handle,
            creatorTier: user.tier,
            createdAt: Date(),
            resolvesOn: resolvesOn,
            yesVolume: 0,
            noVolume: 0,
            status: .pendingReview
        ), at: 0)
    }

    var visibleMarkets: [CustomMarket] {
        markets.filter { $0.status != .cancelled }
    }

    private func seed() {
        markets = [
            .init(id: UUID(),
                  question: "Villeneuve's Rendezvous opens above $50M.",
                  details: "Domestic three-day opening weekend, per Box Office Mojo. Settles the Monday after release.",
                  creatorHandle: "popcornshark", creatorTier: .studioHead,
                  createdAt: Date().addingTimeInterval(-3 * 86400),
                  resolvesOn: Date().addingTimeInterval(60 * 86400),
                  yesVolume: 128, noVolume: 42, status: .live),
            .init(id: UUID(),
                  question: "First 2027 Marvel misses tracking by 20%+.",
                  details: "'Tracking' = final NRG estimate on Wednesday of opening week per Deadline. Settles Monday.",
                  creatorHandle: "indieyoda", creatorTier: .producer,
                  createdAt: Date().addingTimeInterval(-6 * 86400),
                  resolvesOn: Date().addingTimeInterval(180 * 86400),
                  yesVolume: 71, noVolume: 205, status: .live)
        ]
    }
}
