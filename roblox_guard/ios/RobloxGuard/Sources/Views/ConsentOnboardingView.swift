import SwiftUI

/// Onboarding doubles as the verifiable-parental-consent flow (App Store
/// guideline 5.1.4 / COPPA). The parent must read and affirm each statement
/// before the app will link a child's account.
struct ConsentOnboardingView: View {
    var onComplete: () -> Void

    @State private var isParent = false
    @State private var understandsScope = false
    @State private var understandsData = false
    @State private var understandsLimits = false

    private var canContinue: Bool {
        isParent && understandsScope && understandsData && understandsLimits
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("RobloxGuard")
                            .font(.largeTitle.bold())
                        Text("An early-warning companion for parents. RobloxGuard watches the public footprint of your child's Roblox account and helps you start the right conversations.")
                            .foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("What this app does", systemImage: "checkmark.circle")
                                .font(.headline)
                            bullet("Watches public information: friend list changes, profile bios of new friends, online status, and current experience.")
                            bullet("Flags patterns worth your attention, like a new friend whose bio advertises Discord or Snapchat handles.")
                            bullet("Gives you conversation guides and direct links to Roblox's reporting tools and the NCMEC CyberTipline.")
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("What this app can't do", systemImage: "xmark.circle")
                                .font(.headline)
                            bullet("It cannot read your child's chats. No app can — private Roblox chats are only visible to Roblox's own moderators.")
                            bullet("It never asks for your child's password, and it can't control their account.")
                            bullet("It doesn't accuse anyone. It shows you facts and lets you decide, with reporting channels one tap away.")
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Understand the limits", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            bullet("Alerts can be wrong in both directions: some will flag something innocent (false positives), and the app can miss real problems it has no way to see (false negatives) — it never reads chats.")
                            bullet("This app is one tool, not a complete safety strategy. Use it alongside ongoing conversations with your child, Roblox's own parental controls, and your own judgment — not instead of them.")
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: $isParent) {
                            Text("I am the parent or legal guardian of the child whose account I will link.")
                        }
                        Toggle(isOn: $understandsScope) {
                            Text("I understand this app only sees public account information, not private chats.")
                        }
                        Toggle(isOn: $understandsData) {
                            Text("I consent to this app storing my child's Roblox username and derived safety alerts. Unlinking the account deletes all of it.")
                        }
                        Toggle(isOn: $understandsLimits) {
                            Text("I understand alerts can be false positives or miss real issues, and that this app supplements — not replaces — my own supervision and judgment.")
                        }
                    }
                    .toggleStyle(.switch)
                    .font(.subheadline)

                    Button {
                        onComplete()
                    } label: {
                        Text("Agree & Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canContinue)
                }
                .padding()
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.subheadline)
    }
}
