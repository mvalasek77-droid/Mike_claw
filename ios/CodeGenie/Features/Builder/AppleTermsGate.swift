import SwiftUI

/// Human gate for Apple Terms acceptance.
/// The user MUST manually accept Apple's App Store Connect Terms of Service
/// and Paid Applications Agreement. CodeGenie cannot automate this.
struct AppleTermsGate: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(Color.red)

                        Text("Accept Apple's Terms")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)

                        Text("Apple requires that you manually agree to their terms in App Store Connect. CodeGenie cannot do this on your behalf.")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    // Steps
                    GlassSurface(tier: .deep) {
                        VStack(alignment: .leading, spacing: 16) {
                            stepRow(number: 1, title: "Open App Store Connect", detail: "Go to appstoreconnect.apple.com and sign in with your Apple ID")
                            stepRow(number: 2, title: "Accept Terms of Service", detail: "If you see a banner asking you to agree to the App Store Connect Terms of Service, click Agree")
                            stepRow(number: 3, title: "Accept Paid Applications Agreement", detail: "Go to Agreements, Tax, and Banking. Accept the Paid Applications Agreement if prompted")
                            stepRow(number: 4, title: "Create Your App Record", detail: "Go to My Apps → + → New App. Enter the bundle ID shown in the ASC Sign-In step above")
                        }
                        .padding()
                    }

                    // Link
                    Link(destination: URL(string: "https://appstoreconnect.apple.com")!) {
                        HStack {
                            Image(systemName: "safari.fill")
                            Text("Open App Store Connect")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LiquidGlass.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Legal pages notice
                    GlassSurface(tier: .raised) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Privacy Policy & Terms of Use", systemImage: "doc.text.fill")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)

                            Text("Your privacy policy and terms of use are hosted on GitHub Pages. These URLs are required by Apple for App Store submission. You can edit them on GitHub anytime.")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        }
                        .padding()
                    }

                    // Warning
                    GlassSurface(tier: .raised) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Declining cancels the pipeline")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText)
                                Text("Only confirm once you've accepted the terms in ASC. Declining will stop the pipeline.")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                            }
                        }
                        .padding()
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Apple Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Decline", role: .destructive) {
                        Haptics.warning()
                        onDecline()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.success()
                        onAccept()
                    } label: {
                        Text("I've Accepted")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.success)
                    }
                }
            }
        }
    }

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(LiquidGlass.accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(detail)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
            }
        }
    }
}