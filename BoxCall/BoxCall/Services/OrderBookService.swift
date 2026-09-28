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

    @Published private(set) var openOrders: [LimitOrder] = [] {
        didSet { if openOrders != oldValue { persist() } }
    }
    @Published private(set) var filledOrders: [LimitOrder] = []

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("open_orders.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([LimitOrder].self, from: data) {
            openOrders = saved
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(openOrders) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func cancelAll() {
        for order in openOrders { cancel(orderId: order.id) }
    }

    /// Drops every order without refunding — used when the whole account is erased.
    func eraseAllData() {
        openOrders = []
        filledOrders = []
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    enum PlaceError: LocalizedError {
        case insufficientFunds, invalidLimit, orderLimitReached, tradingLocked
        var errorDescription: String? {
            switch self {
            case .tradingLocked:     return "Trading on this movie locked when it opened. It settles Monday."
            case .insufficientFunds: return "Not enough Reel Coins to reserve for this limit."
            case .invalidLimit:      return "Limit price must be greater than 0."
            case .orderLimitReached: return "You've hit your limit-order cap. Cancel an existing order or upgrade your membership for more."
            }
        }
    }

    /// Reserves the total cost up front, then rests the order. A user
    /// can cancel to get the reservation back.
    @discardableResult
    func placeBuyLimit(contract: Contract, quantity: Int,
                       limitPrice: Double) throws -> UUID {
        guard limitPrice > 0 else { throw PlaceError.invalidLimit }
        guard MarketService.shared.movie(id: contract.movieId)?.isTradingOpen ?? false else {
            throw PlaceError.tradingLocked
        }
        let membership = PortfolioService.shared.user.membership
        guard openOrders.count < membership.maxLimitOrders else {
            throw PlaceError.orderLimitReached
        }
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
    /// whose limit is at or above the current ask, and cancels orders
    /// on movies that have already settled.
    func tickMatch() {
        guard !openOrders.isEmpty else { return }
        var stillOpen: [LimitOrder] = []
        for order in openOrders {
            if let movie = MarketService.shared.movie(id: order.movieId), !movie.isTradingOpen {
                let reserved = order.limitPrice * Double(order.quantity)
                PortfolioService.shared.mutateUser { $0.reelCoins += reserved }
                var expired = order
                expired.status = .cancelled
                filledOrders.append(expired)
                continue
            }
            let ask = MarketService.shared.ask(contractId: order.contractId)
            guard ask > 0 else {
                stillOpen.append(order); continue
            }
            if ask <= order.limitPrice {
                let fillPrice = min(ask, order.limitPrice)
                let paid = fillPrice * Double(order.quantity)
                let reserved = order.limitPrice * Double(order.quantity)
                let refund = max(0, reserved - paid)
                PortfolioService.shared.mutateUser { $0.reelCoins += refund }

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
                RewardsService.shared.celebrate("Limit order filled",
                                                subtitle: "\(order.quantity) \(order.side.display) at \(String(format: "%.2f", fillPrice))",
                                                emoji: "✅")

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
