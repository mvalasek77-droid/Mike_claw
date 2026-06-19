import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var ai: AIService
    @EnvironmentObject private var entitlements: Entitlements
    @State private var showPaywall = false

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
                    TextField("https://your-proxy.example.com", text: $ai.configuration.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
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
                    Text("AI Backend")
                } footer: {
                    Text("For security, your Anthropic API key lives on your own proxy server, never in the app. See backend/proxy.py in the project for a reference. \(ai.configuration.isConfigured ? "Status: connected." : "Status: demo mode.")")
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
