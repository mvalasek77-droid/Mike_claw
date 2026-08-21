import Foundation
import Combine

/// Resting buy-limit orders. Each MarketService tick, the book scans
/// every open order and fills any whose limit is at or above the
/// current mark — the Reel Coins were already withheld at order
/// placement, so the fill just spawns a Position and marks the order
/// filled.
@MainActor
final class OrderBookService: ObservableObject {
    static let shared = OrderBookService()

    @Published private(set) var openOrders: [LimitOrder] = []
    @Published private(set) var filledOrders: [LimitOrder] = []

    private init() {}

    enum PlaceError: LocalizedError {
        case insufficientFunds, invalidLimit
        var errorDescription: String? {
            switch self {
            case .insufficientFunds: return "Not enough Reel Coins to reserve for this limit."
            case .invalidLimit:      return "Limit price must be greater than 0."
            }
        }
    }

    /// Reserves the total cost up front, then rests the order. A user
    /// can cancel to get the reservation back.
    @discardableResult
    func placeBuyLimit(contract: Contract, quantity: Int,
                       limitPrice: Double) throws -> UUID {
        guard limitPrice > 0 else { throw PlaceError.invalidLimit }
        let reservation = limitPrice * Double(quantity)
        guard PortfolioService.shared.user.reelCoins >= reservation else {
            throw PlaceError.insufficientFunds
        }
        PortfolioService.shared.mutateUser { $0.reelCoins -= reservation }
        let id = UUID()
        openOrders.append(.init(
            id: id, contractId: contract.id, movieId: contract.movieId,
            side: contract.side, strikeMillions: contract.strikeMillions,
            multiplier: contract.multiplier, quantity: quantity,
            limitPrice: limitPrice, placedAt: Date(), status: .working
        ))
        AnalyticsService.shared.track(.tradePlaced(
            movieId: contract.movieId, side: contract.side.rawValue,
            strike: contract.strikeMillions, qty: quantity, cost: reservation))
        return id
    }

    func cancel(orderId: UUID) {
        guard let idx = openOrders.firstIndex(where: { $0.id == orderId }) else { return }
        let o = openOrders[idx]
        // Refund the reservation.
        PortfolioService.shared.mutateUser {
            $0.reelCoins += o.limitPrice * Double(o.quantity)
        }
        var cancelled = o
        cancelled.status = .cancelled
        openOrders.remove(at: idx)
        filledOrders.append(cancelled)
    }

    /// Called by MarketService on every tick — matches any buy-limit
    /// whose limit is at or above the current mark.
    func tickMatch() {
        guard !openOrders.isEmpty else { return }
        let chainsById: [String: [Contract]] = MarketService.shared.chains
        var stillOpen: [LimitOrder] = []
        for order in openOrders {
            let mark = chainsById[order.movieId]?
                .first(where: { $0.id == order.contractId })?.premium
            guard let mark else {
                stillOpen.append(order); continue
            }
            if mark <= order.limitPrice {
                // Fill at the mark (better than limit possibly) — refund
                // the price difference so users always get a good-or-
                // better price.
                let fillPrice = min(mark, order.limitPrice)
                let paid = fillPrice * Double(order.quantity)
                let reserved = order.limitPrice * Double(order.quantity)
                let refund = max(0, reserved - paid)
                PortfolioService.shared.mutateUser { $0.reelCoins += refund }

                // Spawn a position without going through buy() (which
                // would try to charge again).
                let position = Position(
                    id: UUID(),
                    contractId: order.contractId, movieId: order.movieId,
                    side: order.side, strikeMillions: order.strikeMillions,
                    multiplier: order.multiplier, quantity: order.quantity,
                    entryPremium: fillPrice, openedAt: Date(),
                    settledPayout: nil, actualOWMillions: nil
                )
                PortfolioService.shared.appendPosition(position)
                MarketService.shared.recordBuy(contractId: order.contractId,
                                               quantity: order.quantity)

                var filled = order
                filled.status = .filled
                filledOrders.append(filled)
            } else {
                stillOpen.append(order)
            }
        }
        openOrders = stillOpen
    }
}
