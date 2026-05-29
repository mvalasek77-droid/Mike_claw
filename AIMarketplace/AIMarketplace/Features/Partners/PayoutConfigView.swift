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

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        hero
                        configFields
                        statusCard
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
                statusRow("Stripe connected", store.payoutConnected)
                if let accountId = store.connectAccountID {
                    Text("Account: \(accountId)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
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