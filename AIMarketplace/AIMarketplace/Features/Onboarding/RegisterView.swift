import SwiftUI

/// First-run account registration, styled after Amazon KDP's warm "ink + amber"
/// sign-up. This is the publisher account; per-title registration happens later
/// in the Publish flow.
struct RegisterView: View {
    @EnvironmentObject private var store: MarketplaceStore

    @State private var name = ""
    @State private var email = ""
    @State private var agreed = false
    @State private var showTerms = false

    private var canContinue: Bool {
        !name.trimmed.isEmpty && email.contains("@") && agreed
    }

    var body: some View {
        ZStack {
            // KDP-style warm backdrop.
            LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.04),
                                    Color(red: 0.05, green: 0.04, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            LinearGradient(colors: [Theme.kdp.opacity(0.28), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Create your publisher account")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)

                            LabeledField(label: "Publisher / pen name", text: $name,
                                         placeholder: "e.g. Nova Mercer", icon: "person.text.rectangle")
                            LabeledField(label: "Email", text: $email,
                                         placeholder: "you@example.com", icon: "envelope",
                                         keyboard: .emailAddress)

                            Button {
                                Haptics.selection()
                                agreed.toggle()
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(agreed ? Theme.kdp : Theme.inkFaint)
                                    (Text("I agree to the AI Marketplace ")
                                     + Text("Content & AI Disclosure Terms").foregroundColor(Theme.kdp)
                                     + Text(" and confirm I hold the rights to anything I publish."))
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(Theme.inkSoft)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)

                            Button("Read the terms") { showTerms = true }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.kdp)
                        }
                    }

                    PrimaryButton(title: "Create account", systemImage: "arrow.right",
                                  tint: Theme.kdp, enabled: canContinue) {
                        store.accountName = name.trimmed
                        store.accountEmail = email.trimmed
                        withAnimation { store.isRegistered = true }
                    }

                    benefitRow
                }
                .screenPadding()
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showTerms) { TermsSheet() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BrandMark(size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Marketplace")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Direct Publishing")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Theme.kdp)
                }
            }
            Text("Publish AI-made novels, music and film. Pass the AI Editor's 85% commercial bar and go live to millions of viewers.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var benefitRow: some View {
        HStack(spacing: 10) {
            benefit("70%", "royalties")
            benefit("85%", "quality bar")
            benefit("3", "media types")
        }
    }

    private func benefit(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.kdp)
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var icon: String? = nil
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(width: 18)
                }
                TextField(placeholder, text: $text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled(keyboard == .emailAddress)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerS).strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
        }
    }
}

struct TermsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    termsBlock("AI Disclosure", "Every title must declare which AI systems produced it. Undisclosed or misattributed AI use is grounds for removal.")
                    termsBlock("Rights & Originality", "You confirm you hold the rights to publish the work and its underlying prompts, and that it does not infringe third-party IP.")
                    termsBlock("Quality Bar", "Submissions are scored by the AI Editor. Only works reaching 85% commercial readiness are accepted for sale.")
                    termsBlock("Royalties", "Creators earn up to 70% of list price on each sale, paid to the registered publisher account.")
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Publishing Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func termsBlock(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text(body).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
