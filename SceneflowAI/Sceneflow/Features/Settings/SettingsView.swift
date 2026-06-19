import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var ai: AIService
    @EnvironmentObject private var entitlements: Entitlements
    @State private var showPaywall = false
    @State private var apiKeyDraft = ""

    private var footerText: String {
        let status = ai.isConfigured ? "Status: connected." : "Status: demo mode."
        switch ai.configuration.mode {
        case .onDeviceKey:
            return "Your key is stored only in this device's Keychain — encrypted, never in the app bundle or backups, and sent directly to Anthropic over TLS. It's your key and your usage. \(status)"
        case .proxy:
            return "Calls a server you host that holds the key. See backend/proxy.py for a reference. \(status)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if entitlements.isPro {
                        Label("Sceneflow Pro — active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Palette.success)
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Upgrade to Pro").font(.headline)
                                        .foregroundStyle(Palette.primaryText)
                                    Text("Unlimited AI + pro export · \(Pricing.pro.priceText)/yr")
                                        .font(.caption).foregroundStyle(Palette.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Palette.accent)
                            }
                        }
                    }
                } header: { Text("Subscription") }

                Section {
                    Picker("Connection", selection: $ai.configuration.mode) {
                        ForEach(AIConfiguration.Mode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    if ai.configuration.mode == .onDeviceKey {
                        if ai.hasAPIKey {
                            HStack {
                                Label("API key stored", systemImage: "key.fill")
                                    .foregroundStyle(Palette.success)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    ai.clearAPIKey()
                                    apiKeyDraft = ""
                                }
                            }
                        } else {
                            SecureField("sk-ant-…", text: $apiKeyDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Save key") {
                                ai.setAPIKey(apiKeyDraft)
                                apiKeyDraft = ""
                                Haptics.success()
                            }
                            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            Link("Get an API key at console.anthropic.com",
                                 destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                                .font(.caption)
                        }
                    } else {
                        TextField("https://your-server.example.com", text: $ai.configuration.proxyURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    Picker("Model", selection: $ai.configuration.model) {
                        Text("Claude Opus 4.8").tag("claude-opus-4-8")
                        Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                        Text("Claude Haiku 4.5").tag("claude-haiku-4-5")
                    }
                    Picker("Creativity", selection: $ai.configuration.creativity) {
                        ForEach(AIConfiguration.Creativity.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text(footerText)
                }

                Section("Pricing") {
                    HStack {
                        Text("Sceneflow Pro")
                        Spacer()
                        Text("\(Pricing.pro.priceText)/yr")
                            .foregroundStyle(Palette.secondaryText)
                    }
                    HStack {
                        Text("Comparable pro apps")
                        Spacer()
                        Text("≈ $\(Int(Pricing.competitorAnnualUSD))/yr")
                            .foregroundStyle(Palette.secondaryText)
                            .strikethrough()
                    }
                    Label("You save \(Pricing.savingsPercent)%", systemImage: "tag.fill")
                        .foregroundStyle(Palette.success)
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    Link("Fountain format", destination: URL(string: "https://fountain.io")!)
                }

                #if DEBUG
                Section("Developer") {
                    Toggle("Simulate Pro", isOn: Binding(
                        get: { entitlements.isPro },
                        set: { entitlements.isPro = $0 }
                    ))
                    Button("Reset free AI usage") { entitlements.monthlyAIUsage = 0 }
                }
                #endif
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}
