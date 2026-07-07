import StoreKit
import SwiftUI

struct PaywallView: View {
    @ObservedObject var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    private let reviewScreenshotMode: Bool

    init(store: SubscriptionStore, launchArguments: [String] = ProcessInfo.processInfo.arguments) {
        self.store = store
        self.reviewScreenshotMode = launchArguments.contains("--chaddrop-review-paywall")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        productList
                        restorePanel
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("ChadDrop Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
        .task {
            if !reviewScreenshotMode {
                await store.refreshPurchasedProducts()
                await store.loadProducts()
            }
        }
        .onChange(of: store.isSubscribed) { _, isSubscribed in
            if isSubscribed && !reviewScreenshotMode {
                dismiss()
            }
        }
    }

    private var hero: some View {
        PaywallPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Unlimited decodes", systemImage: "crown.fill")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Get unlimited text reads, suggested replies, and future premium AI features with a weekly or yearly subscription.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var productList: some View {
        if reviewScreenshotMode {
            reviewProductList
        } else if store.isLoading && store.products.isEmpty {
            PaywallPanel {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading subscriptions...")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        } else if store.products.isEmpty {
            PaywallPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Subscriptions not available yet", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.peach)

                    Text("StoreKit did not return products for this build. In App Store Connect, create these auto-renewable subscription product IDs under the same app bundle ID, finish metadata/pricing, and submit them with the app version.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.productIDs, id: \.self) { productID in
                            Text(productID)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.82))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(store.products) { product in
                    Button {
                        Task {
                            await store.purchase(product)
                        }
                    } label: {
                        ProductOptionRow(product: product)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLoading)
                }
            }
        }
    }

    private var reviewProductList: some View {
        VStack(spacing: 10) {
            ReviewProductOptionRow(
                title: "ChadDrop Pro Weekly",
                subtitle: "1 week. Unlimited decodes and suggested replies.",
                detail: "US$2.99/week"
            )
            ReviewProductOptionRow(
                title: "ChadDrop Pro Annual",
                subtitle: "1 year. Unlimited decodes and suggested replies.",
                detail: "US$29.99/year"
            )
        }
    }

    private var restorePanel: some View {
        PaywallPanel {
            VStack(alignment: .leading, spacing: 12) {
                if !reviewScreenshotMode, let statusMessage = store.statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await store.restorePurchases()
                        }
                    } label: {
                        Label("Restore", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PaywallSecondaryButtonStyle())
                    .disabled(store.isLoading)

                    Button {
                        dismiss()
                    } label: {
                        Text("Not now")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PaywallSecondaryButtonStyle())
                }

                Text("Subscriptions renew automatically and can be managed in your Apple Account.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Link(destination: ChadDropLegalLinks.termsOfUse) {
                        Label("Terms of Use", systemImage: "doc.text.fill")
                    }
                    .accessibilityIdentifier("termsOfUseLink")

                    Link(destination: ChadDropLegalLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "lock.shield.fill")
                    }
                    .accessibilityIdentifier("privacyPolicyLink")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            }
        }
    }
}

private struct ProductOptionRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Text(product.displayPrice)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(16)
        .background(AppTheme.hotGradient, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 10)
    }

    private var subtitle: String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.description
        }

        return "Auto-renews every \(period.chadDropDisplayText)"
    }
}

private struct ReviewProductOptionRow: View {
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Text(detail)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(16)
        .background(AppTheme.hotGradient, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 10)
    }
}

private struct PaywallPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
    }
}

private struct PaywallSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
    }
}
