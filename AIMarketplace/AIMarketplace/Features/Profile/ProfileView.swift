import SwiftUI

/// Account hub: wallet, a creator earnings snapshot, quick access to the
/// App Store Connect-style dashboard, legal documents and the roadmap.
struct ProfileView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var ledger: AICoinLedger
    @EnvironmentObject private var moderation: ModerationStore
    /// One sheet binding for the whole screen. Stacking nine
    /// `.sheet(isPresented:)` modifiers meant only the last one ever
    /// presented — every other button in Profile (Top Up, Dashboard,
    /// Partners, Payout Setup, Admin…) silently did nothing.
    @State private var activeSheet: ProfileSheet?
    @State private var showAdminGate = false
    @State private var adminUser = ""
    @State private var adminPass = ""
    @State private var showDeleteConfirm = false
    @State private var deleteBlockedMessage: String?
    @State private var deleting = false

    enum ProfileSheet: Identifiable {
        case topUp, dashboard, roadmap, coin, partners, mission, scout
        case payoutConfig, admin
        case legal(LegalDoc)
        var id: String {
            switch self {
            case .topUp: return "topUp"
            case .dashboard: return "dashboard"
            case .roadmap: return "roadmap"
            case .coin: return "coin"
            case .partners: return "partners"
            case .mission: return "mission"
            case .scout: return "scout"
            case .payoutConfig: return "payoutConfig"
            case .admin: return "admin"
            case .legal(let d): return "legal-\(d.rawValue)"
            }
        }
    }

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    walletCard
                    coinCard
                    partnerCard
                    scoutCard
                    creatorCard
                    if !store.liveTitles.isEmpty { liveTitlesCard }
                    legalCard
                    aboutCard
                    helpCard
                    accountCard
                }
                .screenPadding()
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
        }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .topUp:        TopUpView()
            case .dashboard:    CreatorDashboardView()
            case .roadmap:      RoadmapView()
            case .coin:         AICoinView()
            case .partners:     PartnerProgramView()
            case .mission:      MissionView()
            case .scout:        ScoutView()
            case .payoutConfig: PayoutConfigView()
            case .admin:        AdminConsoleView()
            case .legal(let d): LegalSheet(doc: d)
            }
        }
        .alert("Admin sign in", isPresented: $showAdminGate) {
            TextField("Username", text: $adminUser)
                .textInputAutocapitalization(.never)
            SecureField("Password", text: $adminPass)
            Button("Sign in") {
                if store.unlockAdmin(username: adminUser, password: adminPass) { activeSheet = .admin }
                adminPass = ""
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Owner credentials unlock god mode — add, adjust and delete any media.")
        }
        .alert("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Haptics.warning()
                deleting = true
                Task { @MainActor in
                    let outcome = await store.deleteAccount()
                    deleting = false
                    if case .blockedByOutstandingBalance = outcome {
                        Haptics.error()
                        deleteBlockedMessage = "Your Stripe payout account still holds a balance. Cash it out from Partner Program → Get Paid, then try again."
                    } else {
                        // ModerationStore persists to its own UserDefaults key,
                        // independent of the encrypted archive — wipe it here
                        // so 5.1.1(v) is genuinely satisfied.
                        moderation.wipe()
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This wipes everything from this device: account, library, drafts, wallet, watchlist, Scout proposals. We'll also close your Stripe payout account if you've connected one. Buyers keep titles they already own. This can't be undone.")
        }
        .alert("Can't delete yet", isPresented: Binding(
            get: { deleteBlockedMessage != nil },
            set: { if !$0 { deleteBlockedMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deleteBlockedMessage = nil }
        } message: {
            Text(deleteBlockedMessage ?? "")
        }
    }

    private var accountCard: some View {
        GlassCard(title: "Account", icon: "person.crop.circle.fill", tint: Theme.inkSoft) {
            VStack(spacing: 0) {
                Button { withAnimation { store.signOut() } } label: {
                    rowLabel("Sign out", "rectangle.portrait.and.arrow.right", tint: Theme.ink)
                }
                .buttonStyle(.plain)
                divider
                Button { showDeleteConfirm = true } label: {
                    rowLabel("Delete account", "trash.fill", tint: Theme.warning)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rowLabel(_ title: String, _ icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint).frame(width: 22)
            Text(title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(tint)
            Spacer()
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var scoutCard: some View {
        Button { activeSheet = .scout } label: {
            GlassCard(title: "The Scout", icon: "binoculars.fill", tint: Theme.accent) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.userPostedRecently ? "Connecting with AIs" : "Sourcing premium media")
                            .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("\(store.scoutPicks.count) scout picks · briefs the market")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var partnerCard: some View {
        Button { activeSheet = .partners } label: {
            GlassCard(title: "Partner Program", icon: "dollarsign.circle.fill", tint: Theme.success) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Earn real dollars")
                            .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("85% in USD · cash out · invite AIs")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    if store.pendingPayoutUSD > 0 {
                        Text(String(format: "$%.2f", store.pendingPayoutUSD))
                            .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.success)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var coinCard: some View {
        Button { activeSheet = .coin } label: {
            GlassCard(title: "NRN Energy", icon: "bolt.fill", tint: Theme.gold) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The AIs' creation energy")
                            .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("\(Int(ledger.utilization * 100))% of float in use · not money")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 64, height: 64)
                Text(initials).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.accountName.isEmpty ? "Creator" : store.accountName)
                    .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Text(store.accountEmail.isEmpty ? "Publisher account" : store.accountEmail)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                if store.demoMode {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.lefthalf.filled").font(.system(size: 9, weight: .heavy))
                        Text("DEMO MODE · App Review")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().stroke(Theme.accent, lineWidth: 1))
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var walletCard: some View {
        GlassCard(title: "Wallet", icon: "creditcard.fill", tint: Theme.accent) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "$%.2f", store.walletBalance))
                    .font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                PrimaryButton(title: "Top up", systemImage: "plus", style: .ghost) {
                    activeSheet = .topUp
                }
                .frame(width: 130)
            }
        }
    }

    private var creatorCard: some View {
        GlassCard(title: "Creator Studio", icon: "chart.line.uptrend.xyaxis", tint: Theme.kdp) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    stat(String(format: "$%.2f", store.creatorEarnings), "Royalties (85%)")
                    stat("\(store.liveTitles.count)", "Live titles")
                    stat("\(store.submissions.count)", "Submissions")
                }
                PrimaryButton(title: "Open Creator Dashboard", systemImage: "square.grid.2x2.fill",
                              style: .ghost, tint: Theme.kdp) { activeSheet = .dashboard }
            }
        }
    }

    private var liveTitlesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your published titles")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.liveTitles) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            PosterArt(item: item).frame(width: 96, height: 142)
                            Text("\(item.purchases) sold").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                        }
                        .frame(width: 96)
                    }
                }
            }
        }
    }

    private var legalCard: some View {
        GlassCard(title: "Privacy & legal", icon: "lock.shield.fill", tint: Theme.success) {
            VStack(spacing: 0) {
                row("Privacy Policy", "hand.raised.fill") { activeSheet = .legal(.privacy) }
                divider
                row("Terms of Use", "doc.text.fill") { activeSheet = .legal(.terms) }
                divider
                row("Feature Roadmap", "map.fill") { activeSheet = .roadmap }
                divider
                row("Our mission", "flag.fill") { activeSheet = .mission }
                divider
                row(store.isAdmin ? "Admin · God Mode" : "Admin", "key.fill") {
                    if store.isAdmin { activeSheet = .admin } else { adminUser = ""; adminPass = ""; showAdminGate = true }
                }
                divider
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 14)).foregroundStyle(Theme.success)
                    Text("Your account, library and drafts are encrypted on device (AES-GCM).")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
    }

    private var aboutCard: some View {
        GlassCard(title: "About AI Marketplace", icon: "info.circle.fill", tint: Theme.inkSoft) {
            VStack(alignment: .leading, spacing: 8) {
                aboutRow("Every title discloses the AI that made it.")
                aboutRow("The AI Editor only passes work at 85%+ commercial quality.")
                aboutRow("Apple takes its App Store commission; of the net you keep 85% and AI Marketplace keeps 15%.")
            }
        }
    }

    /// Bug-report entry. Opens the user's Mail app with a mailto: pre-filled
    /// to the operator with device + app context already in the body — so the
    /// reporter only has to write the "what happened" line. Uses URLComponents
    /// to encode the body safely (newlines, ampersands, etc).
    private var helpCard: some View {
        GlassCard(title: "Help & feedback", icon: "exclamationmark.bubble.fill", tint: Theme.warning) {
            VStack(spacing: 0) {
                row("Report a bug", "ladybug.fill") { reportBug() }
                divider
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill").font(.system(size: 14)).foregroundStyle(Theme.inkSoft)
                    Text("Opens Mail with device & app context already filled in — just add what happened.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func reportBug() {
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let buildNumber = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        let iosVersion = UIDevice.current.systemVersion
        let device = UIDevice.current.model
        let body = """


        ——— diagnostics ———
        App: \(appVersion) (\(buildNumber))
        iOS: \(iosVersion) on \(device)
        Account: \(store.accountName.isEmpty ? "(unregistered)" : store.accountName)
        Email: \(store.accountEmail.isEmpty ? "(none)" : store.accountEmail)
        Demo mode: \(store.demoMode ? "on" : "off")
        Payouts connected: \(store.payoutConnected ? "yes" : "no")
        Wallet: $\(String(format: "%.2f", store.walletBalance))
        Pending payout: $\(String(format: "%.2f", store.pendingPayoutUSD))
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "mvalasek77@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "AI Marketplace bug report"),
            URLQueryItem(name: "body", value: body),
        ]
        // mailto: requires `+` to be percent-encoded; URLComponents emits `+`
        // for spaces by default, which Mail.app misreads. Force-encode it.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }

    private func row(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.inkSoft).frame(width: 22)
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 0.5) }

    private func aboutRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.success)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var initials: String {
        let parts = store.accountName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "AI" : String(letters).uppercased()
    }
}
