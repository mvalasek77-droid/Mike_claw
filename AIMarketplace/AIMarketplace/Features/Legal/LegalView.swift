import SwiftUI

/// Long-form legal documents, presentable as sheets and reachable from
/// registration and the profile. Plain-language summaries up top, full clauses
/// below — written to satisfy App Store Review guideline 5.1 (privacy) and
/// 3.1.1 (payments / commerce disclosure).
enum LegalDoc: String, Identifiable {
    case privacy, terms
    var id: String { rawValue }
    var title: String { self == .privacy ? "Privacy Policy" : "Terms of Use" }
}

struct LegalSheet: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Last updated 25 May 2026")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                    switch doc {
                    case .privacy: PrivacyBody()
                    case .terms: TermsBody()
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct Clause: View {
    let title: String
    let text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text(text).font(.system(size: 14, weight: .regular)).foregroundStyle(Theme.inkSoft).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PrivacyBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Clause("Summary", "We collect only what we need to run your account, process purchases, and show creators how their titles perform. Your data is encrypted on device, and we never sell it.")
            Clause("What we collect", "Account details you provide (publisher name, email); your purchases and library; titles you submit and their AI-disclosure metadata; and basic, aggregated usage needed to power the Top 10 and Trending charts.")
            Clause("AI disclosure data", "For every title you publish you tell us which AI systems produced it. This disclosure is shown publicly on the title page so buyers know what they are getting.")
            Clause("How data is protected", "Sensitive data stored on your device — your identity, entitlements and drafts — is encrypted at rest using AES-GCM. The encryption key is generated on first launch and held in the device Keychain; it is never bundled with the app or sent to us.")
            Clause("Payments", "Purchases are processed through Apple. We receive confirmation of a completed transaction, not your card number. We retain a record of which titles you own so you can re-download them.")
            Clause("Your choices", "You can review your library and creator data in-app at any time, and request account deletion by contacting support. Deleting the app removes the on-device encrypted store.")
            Clause("Children", "AI Marketplace is not directed to children under 13. Titles carry a maturity rating set by the creator.")
            Clause("Contact", "Questions about privacy: privacy@aimarketplace.app")
        }
    }
}

private struct TermsBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Clause("Summary", "Publish AI-made novels, music and film. Disclose the AI you used. Pass the AI Editor's 85% commercial-quality bar to go live. You keep 85% of every sale; AI Marketplace keeps a 15% service fee.")
            Clause("Eligibility & rights", "You confirm you hold the rights to everything you publish — including the work, its cover art, and the prompts behind it — and that it does not infringe anyone else's intellectual property.")
            Clause("Mandatory AI disclosure", "Every title must accurately declare which AI systems produced it. Undisclosed, misattributed, or fraudulent AI claims are grounds for removal and account suspension.")
            Clause("Quality review", "Submissions are evaluated by the AI Editor against a transparent rubric. Only works scoring 85% or higher are accepted for sale. Scores and notes are advisory and may change as the rubric evolves.")
            Clause("AI Autopilot", "If you enable AI Autopilot, you authorise the AI Editor to publish a submission on your behalf when it both clears the 85% bar and is sufficiently confident. You remain the publisher of record and are responsible for everything it posts; you can disable Autopilot at any time.")
            Clause("Pricing, fees & royalties", "You set your list price within the allowed range. On each sale, AI Marketplace retains a 15% service fee and pays you the remaining 85%. Fees and payout timing may change with notice.")
            Clause("Purchases & content access", "Buying a title grants you a personal, non-transferable licence to read, listen to, or watch it within the app. You may not redistribute purchased content.")
            Clause("Acceptable use", "No illegal, hateful, infringing, or deceptive content. We may remove titles and suspend accounts that violate these terms.")
            Clause("Disclaimers", "Titles are provided by independent creators. AI Marketplace is the storefront and review service, not the author. Content is provided “as is”.")
            Clause("Contact", "Questions about these terms: legal@aimarketplace.app")
        }
    }
}
