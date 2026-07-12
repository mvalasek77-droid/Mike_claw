import SwiftUI

enum ChadDropLegalDoc: String, Identifiable {
    case privacy, terms
    var id: String { rawValue }
    var title: String { self == .privacy ? "Privacy Policy" : "Terms of Use" }
}

struct ChadDropLegalSheet: View {
    let doc: ChadDropLegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Effective June 9, 2026")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    switch doc {
                    case .privacy: ChadDropPrivacyBody()
                    case .terms: ChadDropTermsBody()
                    }
                }
                .padding(20)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
    }
}

private struct Clause: View {
    let title: String
    let text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChadDropPrivacyBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Clause("Summary", "ChadDrop is privacy-first. Your text stays yours. We do not collect, store, or transmit your personal information.")
            Clause("Information we collect", "We do not collect personal data. No names, emails, device identifiers, location data, usage statistics, or crash logs.")
            Clause("Third-party services", "ChadDrop does not integrate with third-party analytics, advertising networks, tracking frameworks, or social sharing services.")
            Clause("AI processing", "Text may be processed on-device or through a secure, ephemeral API call. Analyzed text is not stored by our servers or AI providers beyond returning the result, and is never used to train models.")
            Clause("Data retention", "Because we collect no personal data, there is nothing to retain. Any text you input remains on your device.")
            Clause("Children's privacy", "ChadDrop does not knowingly collect personal information from anyone, including children under 13.")
            Clause("Changes to this policy", "If we ever change how ChadDrop handles data, we will update this policy. We will never silently begin collecting data.")
            Clause("Contact", "Questions about privacy: mvalasek77@gmail.com")
        }
    }
}

private struct ChadDropTermsBody: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Clause("Summary", "ChadDrop is an AI-powered text analysis companion for entertainment and reflection. It is not therapy, legal advice, or a safety service.")
            Clause("Acceptance of terms", "By using ChadDrop, you confirm that you have read, understood, and agree to these Terms. If you do not agree, please do not use the app.")
            Clause("Eligibility", "You must be at least 13 years old to use ChadDrop. If you are under 18, your parent or legal guardian must agree to these terms on your behalf.")
            Clause("User conduct", "Use ChadDrop only for lawful purposes. Do not use it to harass, threaten, or harm others, or to analyze text you do not have the right to analyze.")
            Clause("Intellectual property", "ChadDrop and all of its content are the exclusive property of Alpha Elite Holdings Inc. You are granted a limited, non-exclusive, non-transferable, revocable license for personal, non-commercial use.")
            Clause("AI-generated content", "AI analysis is probabilistic, not definitive. The app is not a lie detector or psychological assessment tool. Results are for informational and entertainment purposes only.")
            Clause("Disclaimers", "The app is provided \"as is\" without warranties of any kind. We are not liable for decisions made based on the app's analysis.")
            Clause("Governing law", "These terms are governed by the laws of the United States and the state in which Alpha Elite Holdings Inc. is organized.")
            Clause("Contact", "Questions about these terms: mvalasek77@gmail.com")
        }
    }
}
