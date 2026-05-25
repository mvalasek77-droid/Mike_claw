import SwiftUI
import PassKit

/// Thin Apple Pay wrapper. Presents a `PKPaymentAuthorizationController` for a
/// single title and reports success/failure back to the caller. Falls back
/// gracefully: callers should only show the Apple Pay button when
/// `PaymentService.canUseApplePay` is true, and offer the in-app wallet
/// otherwise.
final class PaymentService: NSObject, PKPaymentAuthorizationControllerDelegate {
    static let shared = PaymentService()

    /// Replace with your real Apple merchant identifier before shipping.
    static let merchantID = "merchant.com.aimarketplace.app"
    static let supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]

    static var canUseApplePay: Bool {
        PKPaymentAuthorizationController.canMakePayments()
    }

    private var completion: ((Bool) -> Void)?
    private var didAuthorize = false
    /// Held for the lifetime of the presentation so it isn't deallocated early.
    private var controller: PKPaymentAuthorizationController?

    func pay(for item: MediaItem, completion: @escaping (Bool) -> Void) {
        guard PaymentService.canUseApplePay else { completion(false); return }
        self.completion = completion
        self.didAuthorize = false

        let request = PKPaymentRequest()
        request.merchantIdentifier = PaymentService.merchantID
        request.supportedNetworks = PaymentService.supportedNetworks
        request.merchantCapabilities = .threeDSecure
        request.countryCode = "US"
        request.currencyCode = "USD"
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: item.title, amount: NSDecimalNumber(value: item.price)),
            PKPaymentSummaryItem(label: "AI Marketplace", amount: NSDecimalNumber(value: item.price))
        ]

        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        self.controller = controller
        controller.present { presented in
            if !presented {
                DispatchQueue.main.async { self.finish(false) }
            }
        }
    }

    private func finish(_ success: Bool) {
        let handler = completion
        completion = nil
        controller = nil
        handler?(success)
    }

    // MARK: PKPaymentAuthorizationControllerDelegate

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        // A production app validates `payment.token` server-side here.
        didAuthorize = true
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        let authorized = didAuthorize
        controller.dismiss {
            DispatchQueue.main.async { self.finish(authorized) }
        }
    }
}

/// SwiftUI wrapper around the native `PKPaymentButton`.
struct ApplePayButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .white)
        button.cornerRadius = 14
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
