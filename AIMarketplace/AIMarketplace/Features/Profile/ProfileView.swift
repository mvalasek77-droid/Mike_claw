import SwiftUI

/// Account + creator dashboard: wallet, royalties, published titles and a
/// snapshot of the publishing pipeline.
struct ProfileView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var showTopUp = false

    private var liveTitles: [MediaItem] {
        store.submissions.compactMap { sub in
            sub.publishedItemID.flatMap { id in store.catalog.first { $0.id == id } }
        }
    }

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    walletCard
                    creatorCard
                    if !liveTitles.isEmpty { liveTitlesCard }
                    aboutCard
                }
                .screenPadding()
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
        }
        .alert("Wallet topped up", isPresented: $showTopUp) {
            Button("Nice", role: .cancel) { }
        } message: { Text("$25.00 added to your demo balance.") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.brandGradient).frame(width: 64, height: 64)
                Text(initials)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.accountName.isEmpty ? "Creator" : store.accountName)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(store.accountEmail.isEmpty ? "Publisher account" : store.accountEmail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var walletCard: some View {
        GlassCard(title: "Wallet", icon: "creditcard.fill", tint: Theme.accent) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "$%.2f", store.walletBalance))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                PrimaryButton(title: "Top up", systemImage: "plus", style: .ghost) {
                    store.walletBalance += 25
                    showTopUp = true
                }
                .frame(width: 130)
            }
        }
    }

    private var creatorCard: some View {
        GlassCard(title: "Creator earnings", icon: "chart.line.uptrend.xyaxis", tint: Theme.kdp) {
            HStack(spacing: 12) {
                stat(String(format: "$%.2f", store.creatorEarnings), "Royalties")
                stat("\(liveTitles.count)", "Live titles")
                stat("\(store.submissions.count)", "Submissions")
            }
        }
    }

    private var liveTitlesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your published titles")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(liveTitles) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            PosterArt(item: item).frame(width: 96, height: 142)
                            Text("\(item.purchases) sold")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .frame(width: 96)
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        GlassCard(title: "About AI Marketplace", icon: "info.circle.fill", tint: Theme.inkSoft) {
            VStack(alignment: .leading, spacing: 8) {
                aboutRow("Every title discloses the AI that made it.")
                aboutRow("The AI Editor only passes work at 85%+ commercial quality.")
                aboutRow("Creators earn up to 70% royalties on each sale.")
            }
        }
    }

    private func aboutRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.success)
            Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 19, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
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
