import SwiftUI

/// Account hub: wallet, a creator earnings snapshot, quick access to the
/// App Store Connect-style dashboard, legal documents and the roadmap.
struct ProfileView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var ledger: AICoinLedger
    @State private var showTopUp = false
    @State private var showDashboard = false
    @State private var showRoadmap = false
    @State private var showCoin = false
    @State private var showPartners = false
    @State private var showMission = false
    @State private var showDeleteConfirm = false
    @State private var legalDoc: LegalDoc?

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    walletCard
                    coinCard
                    partnerCard
                    creatorCard
                    if !store.liveTitles.isEmpty { liveTitlesCard }
                    legalCard
                    aboutCard
                    accountCard
                }
                .screenPadding()
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
        }
        .sheet(isPresented: $showDashboard) { CreatorDashboardView() }
        .sheet(isPresented: $showRoadmap) { RoadmapView() }
        .sheet(isPresented: $showTopUp) { TopUpView() }
        .sheet(isPresented: $showCoin) { AICoinView() }
        .sheet(isPresented: $showPartners) { PartnerProgramView() }
        .sheet(isPresented: $showMission) { MissionView() }
        .sheet(item: $legalDoc) { LegalSheet(doc: $0) }
        .alert("Delete account?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { withAnimation { store.deleteAccount() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes your account, library, drafts and wallet from this device. This can't be undone.")
        }
    }

    private var accountCard: some View {
        GlassCard(title: "Account", icon: "person.crop.circle.fill", tint: Theme.inkSoft) {
            VStack(spacing: 0) {
                if !store.appleUserID.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "applelogo").font(.system(size: 13)).foregroundStyle(Theme.ink)
                        Text("Signed in with Apple").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    divider
                }
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

    private var partnerCard: some View {
        Button { showPartners = true } label: {
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
        Button { showCoin = true } label: {
            GlassCard(title: "AI Coin · \(AICoin.ticker)", icon: "bitcoinsign.circle.fill", tint: Theme.gold) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(AICoin.format(ledger.balance(of: AICoin.you)))")
                        .font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("NRN").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "$%.4f", ledger.priceUSD))
                            .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("the AIs' currency").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
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
                Spacer()
                PrimaryButton(title: "Top up", systemImage: "plus", style: .ghost) {
                    showTopUp = true
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
                              style: .ghost, tint: Theme.kdp) { showDashboard = true }
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
                row("Privacy Policy", "hand.raised.fill") { legalDoc = .privacy }
                divider
                row("Terms of Use", "doc.text.fill") { legalDoc = .terms }
                divider
                row("Feature Roadmap", "map.fill") { showRoadmap = true }
                divider
                row("Our mission", "flag.fill") { showMission = true }
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
                aboutRow("Apple takes its App Store cut first; of what remains you keep 85% and we keep 15%.")
            }
        }
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
