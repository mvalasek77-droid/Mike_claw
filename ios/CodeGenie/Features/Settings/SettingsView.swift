import SwiftUI

struct SettingsView: View {
    @StateObject private var creds = Credentials.shared
    @State private var anthropicDraft: String = ""
    @State private var openaiDraft: String = ""
    @State private var revealAnthropic = false
    @State private var revealOpenAI = false
    @State private var savedFlash: AIProvider?
    @State private var showPairMac = false
    @State private var showTutorial = false
    @State private var showAgentRouting = false
    @State private var showAppleDev = false
    @State private var showChangelog = false
    @State private var showCustomAgents = false
    @State private var showCrashLog = false
    @State private var showAdmin = false
    @State private var showBugReport = false
    @StateObject private var telemetry = Telemetry.shared
    @StateObject private var userMode = UserMode.shared
    @StateObject private var billing = BillingStore.shared

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    authModePicker
                    if creds.authMode == .byok { keyEntryBlock }
                    if creds.authMode == .subscription { subscriptionBlock }
                    if creds.authMode == .codegenie { hostedBlock }
                    modelComparison
                    estimatorBlock
                    modeBlock
                    if userMode.isPower {
                        costCapBlock
                        agentRoutingBlock
                        customAgentsBlock
                        appleDevBlock
                        pairMacBlock
                        adminBlock
                    }
                    tutorialBlock
                    telemetryBlock
                    supportBlock
                    aboutBlock
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showPairMac) {
            PairMacView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView(mode: .replay) { showTutorial = false }
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAgentRouting) {
            AgentRoutingView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAppleDev) {
            AppleDevSetupView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showChangelog) {
            ChangelogView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showCustomAgents) {
            CustomAgentsView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showCrashLog) {
            CrashLogView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAdmin) {
            AdminView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showBugReport) {
            BugReportView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onAppear {
            anthropicDraft = creds.anthropicKey
            openaiDraft    = creds.openaiKey
        }
        .task { await billing.refresh() }
    }

    private var pairMacBlock: some View {
        navTile(
            title: "Pair your Mac",
            subtitle: "Reach into Xcode + Safari from this app.",
            icon: "macbook.and.iphone",
            tint: LiquidGlass.accent
        ) { showPairMac = true }
    }

    private var costCapBlock: some View {
        GlassCard(title: "Build cost cap", icon: "exclamationmark.triangle.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { creds.costCapUSD != nil },
                    set: { on in
                        creds.setCostCap(on ? (creds.costCapUSD ?? 5.00) : nil)
                        Haptics.selection()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Halt the build over $X")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("Backend stops cleanly when rolling USD spend crosses the cap.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    }
                }
                .tint(LiquidGlass.warning)

                if let cap = creds.costCapUSD {
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundStyle(LiquidGlass.warning)
                        Slider(
                            value: Binding(
                                get: { cap },
                                set: { creds.setCostCap(($0 * 100).rounded() / 100) }
                            ),
                            in: 0.50...50.0,
                            step: 0.25
                        )
                        .tint(LiquidGlass.warning)
                        Text(String(format: "$%.2f", cap))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var agentRoutingBlock: some View {
        navTile(
            title: "Route per agent",
            subtitle: routingSubtitle,
            icon: "arrow.triangle.branch",
            tint: LiquidGlass.warning
        ) { showAgentRouting = true }
    }

    private var customAgentsBlock: some View {
        let count = creds.customAgents.filter(\.enabled).count
        let subtitle = count == 0
            ? "Add your own swarm member."
            : "\(count) active custom agent\(count == 1 ? "" : "s")"
        return navTile(
            title: "Custom agents",
            subtitle: subtitle,
            icon: "person.crop.circle.badge.plus",
            tint: LiquidGlass.accentSecondary
        ) { showCustomAgents = true }
    }

    private var appleDevBlock: some View {
        navTile(
            title: "Apple Developer",
            subtitle: creds.hasAppleDevCreds ? "Connected — TestFlight upload enabled" : "Connect to enable signing & TestFlight",
            icon: "applelogo",
            tint: creds.hasAppleDevCreds ? LiquidGlass.success : LiquidGlass.accent
        ) { showAppleDev = true }
    }

    private var routingSubtitle: String {
        let n = creds.agentModels.count
        if n == 0 { return "Send each agent to its best model." }
        return "\(n) of 8 agents overridden."
    }

    /// Power-user disclosure. Off by default — first-time users see
    /// a simple Settings surface. Flipping it reveals every advanced
    /// block (cost cap, per-agent routing, custom agents, Apple
    /// Developer setup, Pair-your-Mac, Admin).
    private var modeBlock: some View {
        GlassCard(title: "Power user mode", icon: "wand.and.rays", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { userMode.isPower },
                    set: { userMode.setTier($0 ? .power : .justBuild) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(userMode.isPower ? "Showing all controls" : "Simple mode")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(userMode.isPower
                             ? "Cost cap, per-agent routing, custom agents, Apple Developer setup, Pair Mac, Admin."
                             : "Just build apps. The advanced surface is one tap away when you want it.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(LiquidGlass.accent)
            }
        }
    }

    private var tutorialBlock: some View {
        navTile(
            title: "Watch the tour",
            subtitle: "The 7-step tutorial — re-runnable anytime.",
            icon: "play.rectangle.fill",
            tint: LiquidGlass.accentSecondary
        ) { showTutorial = true }
    }

    private var adminBlock: some View {
        navTile(
            title: "Admin",
            subtitle: "Storage maintenance + workspace archive.",
            icon: "wrench.and.screwdriver.fill",
            tint: LiquidGlass.warning
        ) { showAdmin = true }
    }

    private func navTile(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.selection(); action() }) {
            GlassSurface(tier: .raised, corner: 22) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CodeGenieLogo(size: 44, animate: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Pick a provider, see costs, ship.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authModePicker: some View {
        GlassCard(title: "How CodeGenie pays for builds", icon: "creditcard.fill", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Credentials.AuthMode.allCases) { mode in
                    AuthModeRow(
                        mode: mode,
                        selected: creds.authMode == mode,
                        action: { creds.setAuthMode(mode); Haptics.selection() }
                    )
                }
            }
        }
    }

    private var keyEntryBlock: some View {
        VStack(spacing: 12) {
            keyRow(provider: .anthropic, draft: $anthropicDraft, reveal: $revealAnthropic)
            keyRow(provider: .openai,    draft: $openaiDraft,    reveal: $revealOpenAI)
        }
    }

    private func keyRow(provider: AIProvider, draft: Binding<String>, reveal: Binding<Bool>) -> some View {
        let stored = (provider == .anthropic) ? creds.anthropicKey : creds.openaiKey
        return GlassCard(
            title: provider.displayName,
            icon: provider == .anthropic ? "a.circle.fill" : "o.circle.fill",
            tint: provider == .anthropic ? LiquidGlass.accentSecondary : LiquidGlass.success
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pay-per-token. Set your key once — it stays in the iOS Keychain.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))

                HStack(spacing: 10) {
                    Group {
                        if reveal.wrappedValue {
                            TextField(provider.keyEnvVar, text: draft).textInputAutocapitalization(.never)
                        } else {
                            SecureField(provider.keyEnvVar, text: draft)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))

                    Button { reveal.wrappedValue.toggle() } label: {
                        Image(systemName: reveal.wrappedValue ? "eye.slash" : "eye")
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(reveal.wrappedValue ? "Hide key" : "Show key")
                }

                HStack(spacing: 8) {
                    PrimaryButton(title: "Save", systemImage: "checkmark", style: .filled) {
                        creds.setKey(draft.wrappedValue, for: provider)
                        savedFlash = provider
                        Haptics.success()
                    }
                    .frame(maxWidth: 140)

                    if !stored.isEmpty {
                        PrimaryButton(title: "Clear", systemImage: "trash", style: .glass) {
                            creds.clearKey(for: provider); draft.wrappedValue = ""
                        }
                        .frame(maxWidth: 110)
                    }

                    Spacer()

                    Link(destination: provider.consoleURL) {
                        HStack(spacing: 4) {
                            Text("Get key").font(.system(size: 13, weight: .semibold, design: .rounded))
                            Image(systemName: "arrow.up.right.square").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(LiquidGlass.accent)
                    }
                }

                if savedFlash == provider {
                    Label("Saved to Keychain", systemImage: "lock.shield.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.success)
                        .transition(.opacity)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation { savedFlash = nil }
                        }
                }
            }
        }
    }

    private var subscriptionBlock: some View {
        GlassCard(title: "Pair a subscription", icon: "person.crop.circle.badge.checkmark", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 12) {
                Text("If you already pay for Claude Pro/Max or ChatGPT Plus/Pro, route CodeGenie through the paired Mac companion.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))

                Label(
                    creds.backendToken.isEmpty ? "Pair your Mac before starting a subscription build" : "Mac companion token saved",
                    systemImage: creds.backendToken.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(creds.backendToken.isEmpty ? LiquidGlass.warning : LiquidGlass.success)

                ForEach(AIProvider.allCases) { p in
                    HStack(spacing: 10) {
                        Image(systemName: p == .anthropic ? "a.circle.fill" : "o.circle.fill")
                            .foregroundStyle(p == .anthropic ? LiquidGlass.accentSecondary : LiquidGlass.success)
                        Text(p.subscriptionName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Spacer()
                        Link(destination: p.subscriptionURL) {
                            Text("Sign in")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(LiquidGlass.auroraGradient, in: Capsule())
                                .foregroundStyle(LiquidGlass.primaryText)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Text("The Mac companion owns browser sign-in. CodeGenie never asks for or stores your account password.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            }
        }
    }

    private var hostedBlock: some View {
        GlassCard(title: "CodeGenie hosted credits", icon: "sparkles", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hosted builds use StoreKit entitlement state plus a monthly free-build counter. If App Store Connect products are not live yet, free builds remain available and paid plans show as unavailable.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Label(billing.hostedStatusText, systemImage: billing.canStartHostedBuild ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(billing.canStartHostedBuild ? LiquidGlass.success : LiquidGlass.warning)

                ForEach(BillingPlan.allCases) { plan in
                    HostedPlanRow(plan: plan, billing: billing)
                }

                HStack(spacing: 10) {
                    PrimaryButton(title: "Restore", systemImage: "arrow.clockwise", style: .glass) {
                        Task { await billing.restorePurchases() }
                    }
                    .frame(maxWidth: 150)
                    if billing.isLoading {
                        ProgressView()
                            .tint(LiquidGlass.accent)
                    }
                    Spacer()
                }

                HStack(spacing: 14) {
                    Link("Terms of Use", destination: URL(string: "https://codegenie.app/terms")!)
                    Link("Privacy Policy", destination: URL(string: "https://codegenie.app/privacy")!)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)

                if let message = billing.lastMessage {
                    Text(message)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var supportBlock: some View {
        navTile(
            title: "Report a bug",
            subtitle: "Email logs and steps to mvalasek77@gmail.com",
            icon: "exclamationmark.bubble.fill",
            tint: LiquidGlass.warning
        ) { showBugReport = true }
    }

    private var modelComparison: some View {
        GlassCard(title: "Models & pricing", icon: "tablecells", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ModelCatalogue.all) { model in
                    ModelRow(
                        model: model,
                        selected: creds.preferredModelID == model.id,
                        onPick: { creds.setPreferredModel(model.id); Haptics.selection() }
                    )
                    if model.id != ModelCatalogue.all.last?.id {
                        Divider().background(.white.opacity(0.08))
                    }
                }
            }
        }
    }

    private var estimatorBlock: some View {
        let model = ModelCatalogue.model(id: creds.preferredModelID) ?? ModelCatalogue.all[0]
        let cost = model.estimatedBuildCostUSD()
        let buildsPer10 = max(1, Int((10.0 / cost).rounded(.down)))
        return GlassCard(title: "Cost estimator", icon: "dollarsign.circle.fill", tint: LiquidGlass.success) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "$%.3f", cost))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .contentTransition(.numericText())
                    Text("per build").font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    Spacer()
                    Text(model.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(LiquidGlass.primaryText)
                }
                Text("≈ \(buildsPer10) builds for $10. Based on a typical 120k input + 40k output tokens per app.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
            }
        }
    }

    private var telemetryBlock: some View {
        GlassCard(title: "Build telemetry", icon: "chart.bar.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { telemetry.enabled },
                    set: { telemetry.setEnabled($0); Haptics.selection() }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track build outcomes")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("On-device only. Nothing leaves your phone.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    }
                }
                .tint(LiquidGlass.accent)

                if telemetry.enabled && (telemetry.snapshot.buildsStarted > 0) {
                    Divider().background(.white.opacity(0.1))
                    let s = telemetry.snapshot
                    metricRow("Builds run",    "\(s.buildsStarted)")
                    metricRow("Success rate",  String(format: "%.0f%%", s.successRate * 100))
                    metricRow("Avg retries",   String(format: "%.1f", s.averageRetries))
                    metricRow("Avg time",      String(format: "%.0fs", s.averageSeconds))
                    Button("Reset stats") { telemetry.reset(); Haptics.tap() }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.warning)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func metricRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
            Spacer()
            Text(v).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(LiquidGlass.primaryText)
        }
    }

    private var aboutBlock: some View {
        GlassCard(title: "About CodeGenie", icon: "info.circle.fill", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 6) {
                aboutRow("Version", "0.1.0 (build 1)")
                aboutRow("Engine", "Genie Swarm — 8 agents")
                aboutRow("Theme", "iOS 26 Liquid Glass")
                aboutRow("Repo", "github.com/mvalasek77-droid/Mike_claw")
                Button {
                    showChangelog = true
                    Haptics.selection()
                } label: {
                    HStack {
                        Text("What's new")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(LiquidGlass.accent)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open changelog")
                Button {
                    showCrashLog = true
                    Haptics.selection()
                } label: {
                    HStack {
                        Text("Recent build failures")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(LiquidGlass.warning)
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open recent build failures")
            }
        }
    }

    private func aboutRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                .frame(width: 80, alignment: .leading)
            Text(v).font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Spacer()
        }
    }
}

// MARK: - Sub-views

private struct AuthModeRow: View {
    let mode: Credentials.AuthMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? LiquidGlass.accent : LiquidGlass.primaryText.opacity(0.4))
                    .font(.system(size: 22))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(mode.blurb)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct HostedPlanRow: View {
    let plan: BillingPlan
    @ObservedObject var billing: BillingStore

    var body: some View {
        GlassSurface(tier: billing.isActive(plan) ? .deep : .flat, corner: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(plan.label)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            if billing.isActive(plan) {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(LiquidGlass.success.opacity(0.18), in: Capsule())
                                    .foregroundStyle(LiquidGlass.success)
                            }
                        }
                        Text(billing.displayPrice(for: plan))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(plan == .free ? LiquidGlass.success : LiquidGlass.primaryText)
                        Text(plan.summary)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.68))
                    }
                    Spacer()
                    if plan != .free {
                        Button {
                            Task { await billing.purchase(plan) }
                        } label: {
                            Text(buttonTitle)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(buttonFill, in: Capsule())
                                .foregroundStyle(LiquidGlass.primaryText)
                        }
                        .buttonStyle(.plain)
                        .disabled(!billing.canPurchase(plan) || billing.purchaseInFlight != nil)
                        .opacity((billing.canPurchase(plan) && billing.purchaseInFlight == nil) ? 1 : 0.55)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.features, id: \.self) { feature in
                        Label(feature, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.68))
                    }
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.label) plan, \(billing.displayPrice(for: plan)), \(plan.summary)")
    }

    private var buttonTitle: String {
        if billing.isActive(plan) { return "Active" }
        if billing.purchaseInFlight == plan { return "Buying..." }
        return billing.canPurchase(plan) ? "Subscribe" : "Unavailable"
    }

    private var buttonFill: some ShapeStyle {
        billing.canPurchase(plan) ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.08))
    }
}

private struct PlanPill: View {
    let label: String, subtitle: String, price: String, highlighted: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text(price)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(highlighted ? LiquidGlass.success : LiquidGlass.primaryText)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(highlighted ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(highlighted ? LiquidGlass.success.opacity(0.5) : .white.opacity(0.1))
        )
    }
}

private struct ModelRow: View {
    let model: AIModel
    let selected: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? LiquidGlass.accent : LiquidGlass.primaryText.opacity(0.4))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        TierBadge(tier: model.tier)
                        Spacer()
                        Text(String(format: "$%.0f / $%.0f", model.inputUSDPerMTok, model.outputUSDPerMTok))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    }
                    Text(model.tagline)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    Text("Best for: \(model.bestFor)")
                        .font(.caption2)
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private struct TierBadge: View {
    let tier: AIModel.Tier
    var body: some View {
        Text(tier.label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint, in: Capsule())
            .foregroundStyle(LiquidGlass.primaryText)
    }
    private var tint: Color {
        switch tier {
        case .flagship: LiquidGlass.accent
        case .balanced: LiquidGlass.accentSecondary
        case .fast:     LiquidGlass.success
        }
    }
}
