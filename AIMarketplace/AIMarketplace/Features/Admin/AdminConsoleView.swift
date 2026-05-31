import SwiftUI

/// God-mode console: full administrative control over the catalogue — add,
/// adjust, or delete any title, force The Scout, and review automation status.
struct AdminConsoleView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: MediaItem?
    @State private var creatingNew = false
    @State private var query = ""
    @State private var confirmReset = false
    @State private var showPayouts = false

    private var items: [MediaItem] {
        let base = store.catalog.sorted { $0.addedAt > $1.addedAt }
        guard !query.trimmed.isEmpty else { return base }
        let q = query.lowercased()
        return base.filter { $0.title.lowercased().contains(q) || $0.creator.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    automationCard
                    payoutsCard
                    addBar
                    searchField
                    Text("\(items.count) titles")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in row(item) }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.warning).ignoresSafeArea())
            .navigationTitle("Admin · God Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) { Button("Lock") { store.lockAdmin(); dismiss() } }
            }
        }
        .sheet(item: $editing) { AdminEditView(original: $0) }
        .sheet(isPresented: $creatingNew) { AdminEditView(original: nil) }
        .sheet(isPresented: $showPayouts) { AdminPayoutsView() }
        .alert("Reset catalogue?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.adminResetCatalog() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes all admin edits, Editor Originals and Scout picks, and rebuilds from the base catalogue plus your published titles. Your account, wallet and library are untouched.")
        }
    }

    private var automationCard: some View {
        GlassCard(title: "Automation", icon: "gearshape.2.fill", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.userPostedRecently
                     ? "The Scout is in outreach mode (you're posting)."
                     : "The Scout is auto-sourcing a premium daily slate (you're not posting).")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                PrimaryButton(title: "Force The Scout to run now", systemImage: "binoculars.fill",
                              style: .ghost, tint: Theme.accent) {
                    store.runScout(); Haptics.success()
                }
                PrimaryButton(title: "Reset catalogue to defaults", systemImage: "arrow.counterclockwise",
                              style: .ghost, tint: Theme.warning) { confirmReset = true }
            }
        }
    }

    /// Quick access to the owed-creators queue. After an NSF or any other
    /// failed transfer the creator is owed but unpaid — this is where you
    /// fund them manually once the platform float is restored.
    private var payoutsCard: some View {
        GlassCard(title: "Creator payouts", icon: "banknote.fill", tint: Theme.warning) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pay any creator whose transfer failed (e.g. NSF when the float was short). Open this after you top up Stripe.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                PrimaryButton(title: "Owed creators · pay manually", systemImage: "banknote.fill",
                              style: .ghost, tint: Theme.warning) {
                    showPayouts = true
                }
            }
        }
    }

    private var addBar: some View {
        PrimaryButton(title: "Add a title", systemImage: "plus", tint: Theme.success) { creatingNew = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft)
            TextField("Filter titles", text: $query).foregroundStyle(Theme.ink).autocorrectionDisabled()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
    }

    private func row(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            PosterArt(item: item, showsTitle: false).frame(width: 42, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(item.type.title) · \(item.creator) · \(item.commercialScore)% · \(item.priceLabel)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer()
            Button { editing = item } label: {
                Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34).background(Circle().fill(Theme.accent.opacity(0.15)))
            }.buttonStyle(.plain)
            Button { store.adminDelete(item.id) } label: {
                Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.warning)
                    .frame(width: 34, height: 34).background(Circle().fill(Theme.warning.opacity(0.15)))
            }.buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
    }
}
