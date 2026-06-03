import SwiftUI

/// First-run account registration, styled after Amazon KDP's warm "ink + amber"
/// sign-up. Manual publisher form — this is the publisher account; per-title
/// registration happens later in the Publish flow.
struct RegisterView: View {
    @EnvironmentObject private var store: MarketplaceStore

    @State private var name = ""
    @State private var email = ""
    @State private var agreed = false
    @State private var legalDoc: LegalDoc?

    private var isDemo: Bool { name.trimmed.lowercased() == "demo" }

    private var canContinue: Bool {
        if isDemo { return true }
        return !name.trimmed.isEmpty && email.contains("@") && agreed
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
                                         placeholder: "e.g. Mike Valasek", icon: "person.text.rectangle")
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
                                     + Text("Terms of Use").foregroundColor(Theme.kdp)
                                     + Text(" and ")
                                     + Text("Privacy Policy").foregroundColor(Theme.kdp)
                                     + Text(". I accept that there is no tolerance for objectionable, infringing, or hateful content — titles violating these rules will be removed and accounts may be suspended. I confirm I hold the rights to all content I publish and will accurately disclose every AI system used."))
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(Theme.inkSoft)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Required to create an account")

                            HStack(spacing: 16) {
                                Button("Terms of Use") { legalDoc = .terms }
                                Button("Privacy Policy") { legalDoc = .privacy }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.kdp)
                        }
                    }

                    PrimaryButton(title: "Create account", systemImage: "arrow.right",
                                  tint: Theme.kdp, enabled: canContinue) {
                        if isDemo {
                            agreed = true
                            email = "demo@aimarketplace.app"
                            name = "Demo User"
                        }
                        withAnimation { store.register(name: name, email: email) }
                    }

                    // App Review demo entry — one-tap path that skips form
                    // entry, accepts the terms implicitly, sets the demoMode
                    // flag, and signs in. The flag is what makes Stripe +
                    // top-up + Profile UI show their App-Review-safe
                    // simulated paths. See DEMO_MODE.md for credentials.
                    Button {
                        withAnimation { store.registerAsDemoUser() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                            Text("Continue as Demo User · for App Review")
                        }
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerS).strokeBorder(Theme.accent, lineWidth: 1.2))
                    }

                    benefitRow
                }
                .screenPadding()
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $legalDoc) { LegalSheet(doc: $0) }
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
            Text("Publish AI-made novels, music, and film. Pass the AI Editor's 85% commercial-quality bar and reach a global audience.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var benefitRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                benefit("85%", "your share*")
                benefit("85%", "quality bar")
                benefit("3", "media types")
            }
                Text("*of net proceeds, after Apple's App Store commission. See Terms.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
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
