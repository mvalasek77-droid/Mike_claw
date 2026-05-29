import SwiftUI
import PassKit

/// Apple Pay integration for direct media purchases.
///
/// Uses a **merchant ID** configured in the entitlements file. In production,
/// the `paymentAuthorization` callback would hit a backend to process the
/// real transaction. In the demo, completing it immediately grants access.
@MainActor
final class ApplePayService: ObservableObject {
    @Published var isAvailable: Bool = false

    /// The merchant ID must match the one in the entitlements.
    private let merchantID = "merchant.com.valasek.aimarketplace"

    init() {
        isAvailable = PKPaymentAuthorizationController.canMakePayments()
    }

    /// Payment networks the marketplace supports.
    private let networks: [PKPaymentNetwork] = [.amex, .visa, .masterCard, .discover]

    /// Whether the device can make Apple Pay payments with at least one
    /// of the supported networks set up.
    var canMakePayments: Bool {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: networks)
    }

    // MARK: - Payment request builder

    /// Creates a payment request for buying a single media item.
    func request(for item: MediaItem, price: Double) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantID
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "US"
        request.currencyCode = "USD"
        request.supportedNetworks = networks

        let total = PKPaymentSummaryItem(
            label: "AI Marketplace — \(item.title)",
            amount: NSDecimalNumber(value: price),
            type: .final
        )
        request.paymentSummaryItems = [total]

        return request
    }

    /// Creates a payment request for topping up wallet credit.
    func topUpRequest(amount: Double) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantID
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "US"
        request.currencyCode = "USD"
        request.supportedNetworks = networks

        let total = PKPaymentSummaryItem(
            label: "AI Marketplace — Wallet Top Up",
            amount: NSDecimalNumber(value: amount),
            type: .final
        )
        request.paymentSummaryItems = [total]

        return request
    }
}

// MARK: - SwiftUI Apple Pay button wrapper

/// A native Apple Pay button that adapts to the system style.
struct ApplePayButton: UIViewRepresentable {
    var style: PKPaymentButtonStyle = .automatic
    var type: PKPaymentButtonType = .buy
    var action: () -> Void

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: type, paymentButtonStyle: style)
        button.addTarget(context.coordinator, action: #selector(Coordinator.onTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func onTap() { action() }
    }
}