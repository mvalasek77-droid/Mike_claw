import SwiftUI

/// God-mode console: full administrative control over the catalogue — add,
/// adjust, or delete any title, force The Scout, and review automation status.
struct AdminConsoleView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var moderation: ModerationStore
    @EnvironmentObject private var storeKit: StoreKitService
    @EnvironmentObject private var scoutFeed: ScoutFeedService
    @ObservedObject private var errorMonitor = ErrorMonitor.shared
    @State private var confirmUnblockAll = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmReset = false
    @State private var filmBudgetText = ""
    /// Single sheet binding — four stacked sheet modifiers meant only the
    /// last (moderation queue) presented; Add-a-title, Edit, and Payouts
    /// silently did nothing.
    @State private var activeSheet: AdminSheet?

    enum AdminSheet: Identifiable {
        case edit(MediaItem), createNew, payouts, moderation, ledger
        var id: String {
            switch self {
            case .edit(let i): return "edit-\(i.id)"
            case .createNew: return "createNew"
            case .payouts: return "payouts"
            case .moderation: return "moderation"
            case .ledger: return "ledger"
            }
        }
    }
    @State private var deletingTitle: MediaItem?
    @State private var showReleaseEmail = false
    @State private var releaseEmail: String = ""
    @State private var releaseMessage: String?

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
                    errorMonitorCard
                    floatStatusCard
                    automationCard
                    filmProductionCard
                    moderationCard
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
        .task { await store.refreshFloatStatus() }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .edit(let item): AdminEditView(original: item)
            case .createNew:      AdminEditView(original: nil)
            case .payouts:        AdminPayoutsView()
            case .moderation:     AdminModerationQueueView()
            case .ledger:         AdminLedgerView()
            }
        }
        .alert("Release Stripe email", isPresented: $showReleaseEmail) {
            TextField("creator@example.com", text: $releaseEmail)
                .textInputAutocapitalization(.never)
            Button("Release", role: .destructive) {
                Task {
                    let err = await store.releaseStripeEmail(releaseEmail)
                    releaseMessage = err ?? "Released. The creator's next Connect attempt will create a fresh account."
                }
            }
            Button("Cancel", role: .cancel) { releaseEmail = "" }
        } message: {
            Text("Frees up the email so the next /payouts/connect creates a NEW Stripe account instead of returning the rejected one. Close the existing Stripe account FIRST via the buyer-side Delete account flow, or the creator ends up with two Stripe accounts on the same email.")
        }
        .alert("Release result", isPresented: Binding(
            get: { releaseMessage != nil },
            set: { if !$0 { releaseMessage = nil } }
        )) {
            Button("OK", role: .cancel) { releaseMessage = nil; releaseEmail = "" }
        } message: {
            Text(releaseMessage ?? "")
        }
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
        .alert("Unblock everyone?", isPresented: $confirmUnblockAll) {
            Button("Unblock all", role: .destructive) {
                for creator in moderation.blockedCreators { moderation.unblock(creator) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Clears every creator block on this device. Reports already sent to the operator are unaffected.")
        }
    }

    // MARK: - Error Monitor

    /// Diagnostic card showing recent StoreKit and app errors. Essential for
    /// TestFlight debugging — without this the "Credit packs unavailable"
    /// screen shows no hint of *why* products failed to load.
    private var errorMonitorCard: some View {
        GlassCard(title: "Error monitor", icon: "ant.fill", tint: errorMonitor.entries.isEmpty ? Theme.success : Theme.warning) {
            VStack(alignment: .leading, spacing: 8) {
                if errorMonitor.entries.isEmpty {
                    Text("No errors recorded.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text("\(errorMonitor.entries.count) logged — most recent below")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)

                    let recent = Array(errorMonitor.entries.suffix(5)).reversed()
                    ForEach(recent) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.timestamp, style: .time)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.inkFaint)
                                Text(entry.category)
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(entry.category == "StoreKit" ? Theme.warning : Theme.inkSoft)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Capsule().fill(Theme.warning.opacity(0.15)))
                            }
                            Text(entry.message)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Theme.inkFaint)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.04)))
                    }
                }

                HStack(spacing: 12) {
                    PrimaryButton(title: "Clear log", systemImage: "trash",
                                  style: .ghost, tint: Theme.warning) {
                        errorMonitor.clear()
                    }
                    PrimaryButton(title: "Reload StoreKit", systemImage: "arrow.clockwise",
                                  style: .ghost, tint: Theme.accent) {
                        Task { await storeKit.loadProducts() }
                    }
                }
            }
        }
    }

    private var automationCard: some View {
        GlassCard(title: "Automation", icon: "gearshape.2.fill", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.userPostedRecently
                     ? "The Scout is in outreach mode (you're posting)."
                     : "The Scout is auto-sourcing a premium daily slate (you're not posting).")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)

                Toggle(isOn: $store.scoutAutoProduceEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let the Scout make media")
                            .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("When on, the Scout produces its daily slate automatically — the AI Editor still gates everything at \(AIReviewResult.threshold)+/100. Paid external providers always wait for your authorization. Off → every proposal waits in the deck.")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .tint(Theme.accent)

                // Drafting engine status. Without one, "make media" silently
                // produced nothing — say so HERE, where the controls live.
                if OnDeviceAI.isReady {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.success)
                            .accessibilityHidden(true)
                        Text("On-device AI ready — Scout drafts free, on device.")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.success)
                    }
                } else if scoutFeed.providers.textGenConfigured {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        Text("On-device AI unavailable — Scout drafts via your Worker's Claude fallback instead (uses your API credit).")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                    }
                } else if let reason = OnDeviceAI.unavailabilityMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13)).foregroundStyle(Theme.warning)
                            .accessibilityHidden(true)
                        Text("No drafting engine — \(reason) Scout can propose and serve requests, but can't draft media. Fix: enable Apple Intelligence, or set ANTHROPIC_API_KEY on the Worker to draft via the cloud.")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.warning)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(Theme.warning.opacity(0.12)))
                }
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

    /// Moderation panel. Reports the user submits go out as email to the
    /// operator inbox (handled by the Worker's /moderation/report → Resend
    /// path); blocks are per-device only. This card exposes:
    /// — the count of in-app reports sent from THIS device,
    /// — the live blocked-creators list with per-row unblock,
    /// — a one-tap "unblock everyone" reset (confirmation required).
    /// Pulling a creator's content marketplace-wide is a separate action —
    /// use Delete on each of their titles from the list below.
    private var moderationCard: some View {
        GlassCard(title: "Reports & blocks", icon: "shield.lefthalf.filled", tint: Theme.warning) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    moderationStat("\(moderation.reportedItemIDs.count)", "Reports sent")
                    moderationStat("\(moderation.blockedCreators.count)", "Creators blocked")
                }
                PrimaryButton(title: "Open report queue", systemImage: "tray.full.fill",
                              style: .ghost, tint: Theme.warning) {
                    activeSheet = .moderation
                }
                Text("Reports email the operator (mvalasek77@gmail.com) and persist in the Worker's queue for resolution. Blocks hide a creator's content for this device only — buyers on other devices still see them. To pull a title marketplace-wide, resolve its report as “Remove title” (or use Delete from the catalog list below).")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                if moderation.blockedCreators.isEmpty {
                    Text("No creators blocked on this device.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkFaint)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(moderation.blockedCreators.sorted()), id: \.self) { creator in
                            HStack(spacing: 8) {
                                Image(systemName: "hand.raised.fill").font(.system(size: 12)).foregroundStyle(Theme.warning)
                                Text(creator)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer()
                                Button("Unblock") { moderation.unblock(creator) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Theme.accent))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                        }
                    }
                    PrimaryButton(title: "Unblock all", systemImage: "hand.raised.slash.fill",
                                  style: .ghost, tint: Theme.warning) {
                        confirmUnblockAll = true
                    }
                }
            }
        }
    }

    private func moderationStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))
    }

    /// Quick access to the owed-creators queue. After an NSF or any other
    /// failed transfer the creator is owed but unpaid — this is where you
    /// fund them manually once the platform float is restored.
    /// Live platform-float status. Green when the Stripe balance is at/above
    /// the buffer; amber when a top-up is needed. For accounts where Stripe's
    /// Top-ups API isn't available (e.g. Canada), it spells out that funding
    /// is manual via the Stripe Dashboard rather than promising an auto-pull.
    @ViewBuilder
    private var floatStatusCard: some View {
        if let f = store.floatStatus {
            let C = f.currency.uppercased()
            let tint: Color = f.needsTopUp ? Theme.warning : Theme.success
            GlassCard(title: "Payout float", icon: f.needsTopUp ? "exclamationmark.triangle.fill" : "checkmark.seal.fill", tint: tint) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%@ %.2f", C, f.availableUSD))
                            .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text(String(format: "/ %@ %.2f buffer", C, f.bufferUSD))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        Spacer()
                    }
                    if f.needsTopUp {
                        Text(String(format: "Float low — add %@ %.2f to cover creator payouts.", C, f.topUpNeededUSD))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.warning)
                        Text(f.autoTopUp
                             ? "Your configured bank source will auto-pull this on the next cron run."
                             : "Add funds manually: Stripe Dashboard → Balance → Add to balance. Automatic top-ups are off because Stripe's Top-ups API isn't available for this account's country/currency.")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    } else {
                        Text("Float is healthy — creator transfers are covered.")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    Text(String(format: "Today: %d sale%@ · %@ %.2f paid to creators",
                                f.salesTodayCount, f.salesTodayCount == 1 ? "" : "s", C, f.salesTodayUSD))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
    }

    private var payoutsCard: some View {
        GlassCard(title: "Creator payouts", icon: "banknote.fill", tint: Theme.warning) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pay any creator whose transfer failed (e.g. NSF when the float was short). Open this after you top up Stripe.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                PrimaryButton(title: "Owed creators · pay manually", systemImage: "banknote.fill",
                              style: .ghost, tint: Theme.warning) {
                    activeSheet = .payouts
                }
                PrimaryButton(title: "Money-flow ledger", systemImage: "list.bullet.rectangle.portrait.fill",
                              style: .ghost, tint: Theme.accent) {
                    activeSheet = .ledger
                }
                PrimaryButton(title: "Release Stripe email (rejected accounts)",
                              systemImage: "person.badge.minus",
                              style: .ghost, tint: Theme.kdp) {
                    releaseEmail = ""
                    showReleaseEmail = true
                }
                Text("Use Release after a creator's Stripe application was declined — frees their email for a fresh onboarding attempt.")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private var addBar: some View {
        PrimaryButton(title: "Add a title", systemImage: "plus", tint: Theme.success) { activeSheet = .createNew }
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
            Button { activeSheet = .edit(item) } label: {
                Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34).background(Circle().fill(Theme.accent.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(item.title)")
            Button { deletingTitle = item } label: {
                Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.warning)
                    .frame(width: 34, height: 34).background(Circle().fill(Theme.warning.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(item.title)")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
    }
}
