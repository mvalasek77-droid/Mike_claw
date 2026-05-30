//
//  PayoutConfigView.swift
//  AI Marketplace
//
//  Lets the creator configure the Stripe Connect worker URL and shared secret
//  so the app can talk to the Cloudflare payout backend.
//

import SwiftUI

struct PayoutConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MarketplaceStore
    @State private var workerURL: String = ""
    @State private var sharedSecret: String = ""
    @State private var saved = false

    /// What stage of onboarding the creator is in — drives which CTA shows.
    private enum Stage {
        case notStarted        // no Stripe account yet
        case incompleteFlow    // account exists; creator abandoned Stripe form
        case underReview       // form submitted; Stripe still verifying
        case ready             // payouts enabled
    }
    private var stage: Stage {
        if store.payoutConnected { return .ready }
        if store.connectAccountID != nil && store.payoutDetailsSubmitted { return .underReview }
        if store.connectAccountID != nil { return .incompleteFlow }
        return .notStarted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        hero
                        configFields
                        statusCard
                        actionCard
                        if let err = store.lastPayoutError {
                            errorCard(err)
                        }
                        saveButton
                    }
                    .screenPadding()
                }
            }
            .navigationTitle("Payout Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .onAppear {
            workerURL = store.payoutBaseURL
            sharedSecret = store.payoutSharedSecret
            // Refresh live status from Stripe whenever the screen opens, so
            // the creator sees the current state (especially after returning
            // from Stripe in Safari).
            if store.connectAccountID != nil && !store.payoutBaseURL.isEmpty {
                Task { await store.refreshPayoutStatus() }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.and.bolt.horizontal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.success)
            Text("Connect Stripe")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Paste your Cloudflare Worker URL and shared secret to enable real Stripe Connect payouts.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var configFields: some View {
        GlassCard(title: "Worker Config", icon: "server.rack", tint: Theme.accent) {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Worker URL")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                    TextField("https://your-worker.workers.dev", text: $workerURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shared Secret")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                    SecureField("Paste your APP_SHARED_SECRET", text: $sharedSecret)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var statusCard: some View {
        GlassCard(title: "Status", icon: "checkmark.seal.fill", tint: store.payoutConnected ? Theme.success : Theme.inkSoft) {
            VStack(alignment: .leading, spacing: 8) {
                statusRow("Worker configured", !store.payoutBaseURL.isEmpty)
                statusRow("Secret set", !store.payoutSharedSecret.isEmpty)
                statusRow("Stripe account created", store.connectAccountID != nil)
                statusRow("Onboarding form submitted", store.payoutDetailsSubmitted)
                statusRow("Payouts enabled", store.payoutConnected)
                if let accountId = store.connectAccountID {
                    Text("Account: \(accountId)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    @ViewBuilder
    private var actionCard: some View {
        switch stage {
        case .notStarted:
            PrimaryButton(title: "Connect Stripe",
                          systemImage: "link",
                          tint: Theme.success,
                          enabled: !store.payoutBaseURL.isEmpty
                                && !store.payoutSharedSecret.isEmpty) {
                store.connectPayout()
            }
            Text("Opens Stripe's hosted onboarding in Safari. Switch back to the app when you're done — your status will refresh automatically.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        case .incompleteFlow:
            PrimaryButton(title: "Resume Stripe onboarding",
                          systemImage: "arrow.up.right.square.fill",
                          tint: Theme.warning) {
                store.resumePayoutOnboarding()
            }
            Text("You started Stripe onboarding but didn't finish. Tap to pick up where you left off — Stripe's link expires after a few minutes, so we'll fetch a fresh one.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        case .underReview:
            Label("Stripe is verifying your details. This usually takes minutes; can take up to 24 hours for some accounts. Payouts unlock once Stripe is satisfied.",
                  systemImage: "clock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.10)))
            Button("Re-check status") {
                Task { await store.refreshPayoutStatus() }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accent)
        case .ready:
            Label("Payouts ready. Your share of each sale will land in your bank automatically via Stripe.",
                  systemImage: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.success)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.success.opacity(0.10)))
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("Dismiss") { store.lastPayoutError = nil }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.10)))
    }

    private func statusRow(_ label: String, _ on: Bool) -> some View {
        HStack {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(on ? Theme.success : Theme.inkFaint)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }

    private var saveButton: some View {
        PrimaryButton(title: saved ? "Saved ✓" : "Save configuration",
                      systemImage: saved ? "checkmark" : "arrow.triangle.2.circlepath",
                      tint: Theme.success,
                      enabled: !saved) {
            store.payoutBaseURL = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            store.payoutSharedSecret = sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            withAnimation { saved = true }
            Haptics.success()
            // After 2s, dismiss the saved state
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saved = false
            }
        }
    }
}