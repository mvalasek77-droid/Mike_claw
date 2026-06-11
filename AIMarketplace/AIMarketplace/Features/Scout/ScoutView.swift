import SwiftUI

/// The Scout — the agent that hunts down AI-made media, briefs AIs on what the
/// market and user requests demand, tells them they can earn USD here, and (when
/// the creator isn't posting) delivers a premium daily slate: a film, an album,
/// a novel at 95–100% commercial, plus one experimental piece.
struct ScoutView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var scoutFeed: ScoutFeedService
    @Environment(\.dismiss) private var dismiss
    @State private var selected: MediaItem?

    private var openRequests: [ContentRequest] {
        store.requests.filter { $0.status == .open || $0.status == .accepted }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    missionCard
                    onDeviceAIBanner
                    engineCard
                    statusCard
                    proposalsCard
                    if !store.scoutPicks.isEmpty { picksRow }
                    briefsCard
                    logCard
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.accent).ignoresSafeArea())
            .navigationTitle("The Scout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $selected) { MediaDetailView(item: $0) }
    }

    private var engineCard: some View {
        GlassCard(title: "How the Scout works", icon: "gearshape.2.fill", tint: Theme.kdp) {
            VStack(alignment: .leading, spacing: 10) {
                engineRow("square.stack.3d.up.fill", "Three layers, always mixing", "Every batch blends commercial, experimental and niche — never one-note.")
                engineRow("brain.head.profile", "Learns the marketplace", "It studies what sells and what's requested, doubling down on what works and dropping what doesn't.")
                engineRow("function", "Proven formulas", "Targets the patterns behind hits — story beats, a strong hook, plot-driven momentum, comic timing, and earned payoffs.")
                engineRow("bolt.fill", "Top-notch, for free", "Uses the newest on-device AI and tools, figuring out how to make great work at zero cost.")
                engineRow("film.stack", "Films grow scene by scene", "The Scout drafts each film as 2–5 minute scenes, one per cycle, until the full cut tops 30 minutes. Buyers get the first 30 min free; the rest unlocks with purchase, and any new scenes the Scout adds afterwards are automatically yours.")
                engineRow("hourglass", "Premiering soon → live", "New work ships as “Premiering soon” and is refined each cycle until it's ready to premiere, then unlocks automatically.")
            }
        }
    }

    private func engineRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.kdp).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Text(body).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    /// Loud, honest banner when the on-device model can't draft. Without it,
    /// authorizing a proposal looked like it did nothing — the real reason
    /// (Apple Intelligence off / unsupported device / model downloading)
    /// never surfaced anywhere.
    @ViewBuilder
    private var onDeviceAIBanner: some View {
        if let reason = OnDeviceAI.unavailabilityMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16)).foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scout can't draft media right now")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("\(reason) The Scout can still compose proposals and serve user requests, but drafting novels, lyrics and screenplays needs the on-device model.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.warning.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.warning.opacity(0.35), lineWidth: 0.8))
        }
    }

    private var missionCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "binoculars.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40).background(Circle().fill(Theme.accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("The Scout").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("Hunts down AI-made media, briefs AIs on what sells and what users are requesting, and shows them they can earn USD here. When you're not posting, it sources a premium daily slate; when you are, it focuses on connecting with AIs.")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    /// The proposal deck. Scout never produces unilaterally — it composes
    /// candidates here with their budget (tokens + USD) + provider. Only the
    /// admin can authorize; non-admins see the deck read-only so the
    /// roadmap is visible. Pending items are at the top; resolved items
    /// surface their outcome (passed/rejected by Editor, declined by admin).
    @ViewBuilder
    private var proposalsCard: some View {
        let pending = store.scoutProposals.filter { $0.status == .pending }
        let resolved = store.scoutProposals.filter { $0.status != .pending }.prefix(4)
        if !pending.isEmpty || !resolved.isEmpty {
            GlassCard(tint: Theme.accent) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.full.fill")
                            .foregroundStyle(Theme.accent)
                        Text("Scout's deck")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if !pending.isEmpty {
                            Text("\(pending.count) pending · $\(String(format: "%.2f", store.pendingProposalBudgetUSD)) budget")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.inkFaint)
                        }
                    }

                    if pending.isEmpty {
                        Text("No proposals pending — Scout will draft the next batch on the next cycle.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(pending) { p in
                        proposalRow(p, pending: true)
                    }
                    if !resolved.isEmpty {
                        Rectangle().fill(Theme.hairline).frame(height: 0.5)
                        Text("Recent")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.inkFaint)
                        ForEach(Array(resolved)) { p in
                            proposalRow(p, pending: false)
                        }
                    }
                }
            }
        }
    }

    /// True when this proposal would draft via the on-device model and that
    /// model can't run right now — authorizing would be a guaranteed no-op.
    private func foundationBlocked(_ p: ScoutProposal) -> Bool {
        p.providerNeeded == .foundation && !OnDeviceAI.isReady
    }

    private func proposalRow(_ p: ScoutProposal, pending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: p.type.icon)
                    .font(.system(size: 11)).foregroundStyle(p.type.accent)
                Text(p.title).font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                statusPill(for: p)
            }
            Text("\(p.layerRaw.capitalized) \(p.type.title.lowercased()) · \(p.genre) · by \(p.creator)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
            if !p.recipeFormula.isEmpty {
                Text("Formula: \(p.recipeFormula)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Image(systemName: "scalemass")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                Text("Budget: \(budgetLabel(p))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            if pending && store.isAdmin {
                HStack(spacing: 8) {
                    Button {
                        store.authorizeScoutProposal(p)
                        Haptics.success()
                    } label: {
                        Label("Authorize", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(!p.providerAvailable || foundationBlocked(p))
                    Button {
                        store.declineScoutProposal(p)
                        Haptics.warning()
                    } label: {
                        Label("Decline", systemImage: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                if !p.providerAvailable {
                    Text("⚠️ Provider not configured — set the API key in the Worker to enable.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.warning)
                } else if foundationBlocked(p) {
                    Text("⚠️ On-device AI unavailable — see the banner above. Authorize once it's back.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.warning)
                }
            } else if pending {
                Text("Admin authorization required.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            } else if let score = p.editorScore {
                let usageBits: String = {
                    var parts: [String] = []
                    if let t = p.actualTokens { parts.append("\(t) tokens used") }
                    if let u = p.actualUSD, u > 0 { parts.append("$\(String(format: "%.2f", u)) spent") }
                    return parts.isEmpty ? "" : " · \(parts.joined(separator: " · "))"
                }()
                Text("Editor verdict: \(score)/100\(usageBits). \(p.statusNote)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            } else if !p.statusNote.isEmpty {
                Text(p.statusNote)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }

    private func statusPill(for p: ScoutProposal) -> some View {
        let (label, color): (String, Color) = {
            switch p.status {
            case .pending:        return ("PENDING", Theme.warning)
            case .authorized:     return ("RUNNING", Theme.accent)
            case .produced:       return ("LIVE", Theme.success)
            case .editorRejected: return ("REJECTED", Theme.inkFaint)
            case .declined:       return ("DECLINED", Theme.inkFaint)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().stroke(color, lineWidth: 1))
    }

    private func budgetLabel(_ p: ScoutProposal) -> String {
        if p.estimatedUSD > 0 {
            return "$\(String(format: "%.2f", p.estimatedUSD)) (\(p.providerNeeded.displayName)) + ~\(p.estimatedTokens) tokens"
        }
        return "Free — ~\(p.estimatedTokens) on-device tokens"
    }

    /// Honest tell of which reference corpus the Scout is drawing on right
    /// now. Hidden until the feed has been fetched at least once so we don't
    /// surface the offline-fallback marker before the user has connectivity.
    private var corpusBadge: some View {
        Group {
            if scoutFeed.feed.version != "offline" {
                let books = scoutFeed.feed.bestsellers.books.count
                let music = scoutFeed.feed.bestsellers.music.count
                let movies = scoutFeed.feed.bestsellers.movies.count
                let masters = scoutFeed.feed.masters.authors.count
                            + scoutFeed.feed.masters.producers.count
                            + scoutFeed.feed.masters.directors.count
                HStack(spacing: 6) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                    Text("Corpus v\(scoutFeed.feed.version) · \(books)/\(music)/\(movies) bestsellers · \(masters) masters")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                    if let when = scoutFeed.lastFetched {
                        Text("·")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.inkFaint.opacity(0.5))
                        Text(when, style: .relative)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                }
            }
        }
    }

    private var statusCard: some View {
        let producing = !store.userPostedRecently
        return GlassCard(tint: producing ? Theme.success : Theme.kdp) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: producing ? "sparkles" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(producing ? Theme.success : Theme.kdp)
                    Text(producing ? "Sourcing mode" : "Outreach mode")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Spacer()
                    if let last = store.lastScoutRun {
                        Text(last, style: .relative).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                    }
                }
                Text(producing
                     ? "You're not posting, so The Scout is delivering a daily slate: a film, an album and a novel at 95–100% commercial, plus one experimental piece."
                     : "You're publishing, so The Scout is making connections — briefing AIs on demand instead of producing.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                corpusBadge
                countdownRow
                PrimaryButton(title: "Run The Scout now", systemImage: "play.fill", style: .ghost, tint: Theme.accent) {
                    store.runScout()
                    Haptics.success()
                }
            }
        }
    }

    private var countdownRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
            if let next = store.nextScoutRun {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = next.timeIntervalSince(context.date)
                    Text(remaining > 0 ? "Next daily slate in \(Self.countdown(remaining))" : "Next slate ready — run it now")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(remaining > 0 ? Theme.inkSoft : Theme.success)
                }
            } else {
                Text("Ready to run for the first time").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.success)
            }
            Spacer()
        }
    }

    private static func countdown(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? "\(h)h \(m)m" : (m > 0 ? "\(m)m \(sec)s" : "\(sec)s")
    }

    private var picksRow: some View {
        MediaRow(title: "Scout Picks", subtitle: "Sourced at the top of the commercial range",
                 items: store.scoutPicks) { selected = $0 }
    }

    private var briefsCard: some View {
        GlassCard(title: "Market briefs", icon: "doc.text.magnifyingglass", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("What The Scout is telling AIs to make:")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                ForEach(Array(store.demandSignals().enumerated()), id: \.offset) { _, signal in
                    HStack(spacing: 8) {
                        Image(systemName: signal.type.icon).font(.system(size: 12)).foregroundStyle(signal.type.accent)
                        Text("\(signal.genre) · \(signal.type.plural)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(signal.sales) sold").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                    }
                }
                if !openRequests.isEmpty {
                    Divider().overlay(Theme.hairline)
                    Text("Open user requests:").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    ForEach(openRequests.prefix(3)) { req in
                        HStack(spacing: 8) {
                            Image(systemName: req.type.icon).font(.system(size: 12)).foregroundStyle(req.type.accent)
                            Text(req.headline).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            Text(String(format: "$%.0f", req.budgetUSD)).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
    }

    private var logCard: some View {
        GlassCard(title: "Scout activity", icon: "list.bullet.rectangle", tint: Theme.inkSoft) {
            if store.scoutLog.isEmpty {
                Text("No activity yet — tap “Run The Scout now”.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.scoutLog.prefix(10)) { entry in
                        Button { if let id = entry.relatedItemID, let item = store.item(withID: id) { selected = item } } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: entry.icon).font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(entry.kind == .produced ? Theme.success : Theme.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.message).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(entry.date, style: .relative).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(entry.relatedItemID == nil)
                    }
                }
            }
        }
    }
}
