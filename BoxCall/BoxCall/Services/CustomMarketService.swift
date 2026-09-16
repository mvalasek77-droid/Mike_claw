import Foundation
import Combine

/// Creation + listing of user-proposed CustomMarkets. Creation is
/// gated on Mogul tier; live markets are visible to everyone.
///
/// Proposals that pass basic validation are auto-approved after a
/// short review delay. A real backend would route these through a
/// moderation queue; this client-side version approves automatically
/// so the feature actually works.
@MainActor
final class CustomMarketService: ObservableObject {
    static let shared = CustomMarketService()

    @Published private(set) var markets: [CustomMarket] = []

    private init() { seed() }

    // MARK: - Creation

    enum CreateError: LocalizedError {
        case notMogul, tooShort, questionRequired, resolvesTooSoon
        var errorDescription: String? {
            switch self {
            case .notMogul: return "Custom markets are a Mogul-tier perk. Upgrade in your profile to create one."
            case .tooShort: return "Add more detail so voters know exactly how this settles."
            case .questionRequired: return "The question is required."
            case .resolvesTooSoon: return "Resolution date must be at least 7 days out."
            }
        }
    }

    func propose(question: String, details: String, resolvesOn: Date) throws {
        let user = PortfolioService.shared.user
        guard user.membership.canCreateCustomMarkets else { throw CreateError.notMogul }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw CreateError.questionRequired }
        guard d.count >= 20 else { throw CreateError.tooShort }
        guard resolvesOn.timeIntervalSinceNow >= 7 * 86400 else { throw CreateError.resolvesTooSoon }

        let marketId = UUID()
        markets.insert(.init(
            id: marketId,
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

        scheduleAutoApproval(for: marketId)
    }

    var visibleMarkets: [CustomMarket] {
        markets.filter { $0.status != .cancelled }
    }

    // MARK: - Auto-approval

    private func scheduleAutoApproval(for id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.approve(marketId: id)
        }
    }

    private func approve(marketId: UUID) {
        guard let idx = markets.firstIndex(where: { $0.id == marketId && $0.status == .pendingReview }) else { return }
        markets[idx].status = .live
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
