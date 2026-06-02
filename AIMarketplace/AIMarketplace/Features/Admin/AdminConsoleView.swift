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
    @State private var filmBudgetText = ""
    @State private var deletingTitle: MediaItem?

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
                    filmProductionCard
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
        .confirmationDialog(
            "Delete this title?",
            isPresented: Binding(
                get: { deletingTitle != nil },
                set: { if !$0 { deletingTitle = nil } }
            ),
            presenting: deletingTitle
        ) { item in
            Button("Delete \"\(item.title)\"", role: .destructive) {
                store.adminDelete(item.id)
                deletingTitle = nil
            }
            Button("Cancel", role: .cancel) { deletingTitle = nil }
        } message: { item in
            Text("Removes \"\(item.title)\" from the catalogue, every buyer's library, and every watchlist. This can't be undone from the app — the title is gone.")
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

    /// Scout film production controls. Toggles the movie pipeline on/off,
    /// holds the monthly external-provider budget, and runs the feasibility
    /// check so the admin sees *before* spending whether the budget can buy
    /// a full 30-min film today.
    private var filmProductionCard: some View {
        let feasibility = store.filmFeasibility(budget: parsedBudget)
        return GlassCard(title: "Scout film production", icon: "film.stack", tint: Theme.kdp) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $store.scoutFilmCreationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable film creation").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("When on, Scout proposes a film each cycle and grows it scene-by-scene. Off → novels and music only.")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .tint(Theme.accent)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Monthly video-gen budget (USD)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 8) {
                        Image(systemName: "dollarsign.circle.fill").foregroundStyle(Theme.success)
                        TextField("0", text: $filmBudgetText)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Theme.ink)
                            .onChange(of: filmBudgetText) { _, _ in
                                store.scoutFilmBudgetUSD = parsedBudget
                            }
                        Button("Apply") { store.scoutFilmBudgetUSD = parsedBudget; Haptics.success() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
                    Text("Set $0 to keep Scout on-device — films ship as screenplay editions. Raise this to wire in Runway / Luma / Pika / Sora / Veo etc.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }

                feasibilityBlock(feasibility)
                providerList
            }
        }
        .onAppear {
            if filmBudgetText.isEmpty {
                filmBudgetText = store.scoutFilmBudgetUSD > 0
                    ? String(format: "%.2f", store.scoutFilmBudgetUSD)
                    : ""
            }
        }
    }

    private var parsedBudget: Double {
        Double(filmBudgetText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func feasibilityBlock(_ f: FilmFeasibility) -> some View {
        let (icon, color): (String, Color) = {
            switch f.verdict {
            case .feasible: return ("checkmark.seal.fill", Theme.success)
            case .partial: return ("exclamationmark.triangle.fill", Theme.warning)
            case .insufficient: return ("xmark.octagon.fill", Theme.warning)
            case .onDeviceOnly: return ("doc.text.fill", Theme.inkSoft)
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color)
                Text("Scout says").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Spacer()
            }
            Text(f.summary)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(f.detail)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerS).strokeBorder(color.opacity(0.35), lineWidth: 0.6))
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Video providers Scout can route to")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            ForEach(VideoProvider.catalog) { p in
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 11)).foregroundStyle(Theme.kdp)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.displayName).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                        Text(p.strengths.joined(separator: " · "))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                    Text(String(format: "$%.2f/scene", p.costPerSceneUSD))
                        .font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                }
                .padding(.vertical, 4)
            }
            Text("Per-scene = full 2–5 min Scout scene, stitched from clips at provider's standard quality. Real prices drift; revisit before raising the budget.")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
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
            Button { deletingTitle = item } label: {
                Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.warning)
                    .frame(width: 34, height: 34).background(Circle().fill(Theme.warning.opacity(0.15)))
            }.buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
    }
}
