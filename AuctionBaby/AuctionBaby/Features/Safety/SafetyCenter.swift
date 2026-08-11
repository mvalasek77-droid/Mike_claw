import SwiftUI
import UIKit

/// Trust & safety hub — date-safety guidance, how reporting works, and the
/// verification nudge. The layer serious daters (and App Review) expect.
struct SafetyCenterView: View {
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    private let tips: [(String, String, String)] = [
        ("video", "Meet in public, first time", "Pick a busy bar or restaurant. Tell a friend where you'll be."),
        ("creditcard", "Settle money your way", "A bid is a letter of intent — never wire money or send deposits before a date. Real bidders pay in person."),
        ("checkmark.seal.fill", "Look for the blue check", "Verified profiles have matched a live selfie to their photos. Copycats never can."),
        ("sparkles", "Spot the Copycats", "AI lure profiles walk the floor unlabelled — spotting them is part of the game. Bid on one and you're told instantly, no Gavels are taken, and your Auction Credit pays for it. If a profile feels too perfect, it probably is."),
        ("flag", "Report anything off", "Use Report & Block on any profile or chat. Reported users are removed from your floor immediately."),
    ]

    private var bugReportURL: URL? { BugReport.mailtoURL() }

    private var blockedSubtitle: String {
        let n = store.blockedIDs.count
        return n == 0 ? "Nobody blocked yet. Report anyone who feels off — they'll land here."
                      : "\(n) profile\(n == 1 ? "" : "s") blocked. Tap to review or unblock."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    GlassCard(tint: Theme.verify) {
                        HStack(spacing: 12) {
                            Image(systemName: "shield.lefthalf.filled").font(.scaled(26, weight: .bold, relativeTo: .title1))
                                .foregroundStyle(Theme.verify)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your safety comes first")
                                    .font(.scaled(16, weight: .heavy, design: .serif, relativeTo: .callout)).foregroundStyle(Theme.ink)
                                Text("Date smart. Trust the checks. Report the rest.")
                                    .font(.scaled(12, relativeTo: .caption1)).foregroundStyle(Theme.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    ForEach(tips, id: \.1) { tip in
                        GlassSurface(corner: Theme.cornerL) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: tip.0).font(.scaled(16, weight: .bold, relativeTo: .callout))
                                    .foregroundStyle(Theme.gold).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tip.1).font(.scaled(14, weight: .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                                    Text(tip.2).font(.scaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                        }
                    }
                    if let url = bugReportURL {
                        Link(destination: url) {
                            GlassSurface(corner: Theme.cornerL, tint: Theme.gold) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "ladybug.fill")
                                        .font(.scaled(16, weight: .bold, relativeTo: .callout))
                                        .foregroundStyle(Theme.gold).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Report a bug")
                                            .font(.scaled(14, weight: .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                                        Text("Something look wrong? Opens Mail with a pre-filled report — your device info is already attached.")
                                            .font(.scaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.scaled(12, weight: .bold, relativeTo: .caption1))
                                        .foregroundStyle(Theme.inkFaint)
                                }
                                .padding(14)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Report a bug via email")
                    }
                    NavigationLink {
                        BlockedUsersView()
                    } label: {
                        GlassSurface(corner: Theme.cornerL) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "hand.raised.slash.fill")
                                    .font(.scaled(16, weight: .bold, relativeTo: .callout))
                                    .foregroundStyle(Theme.rose).frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Blocked users")
                                        .font(.scaled(14, weight: .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                                    Text(blockedSubtitle)
                                        .font(.scaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.scaled(12, weight: .bold, relativeTo: .caption1))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                            .padding(14)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 8)
            }
            .background(AppBackground())
            .navigationTitle("Safety Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.gold)
                }
            }
        }
    }
}

/// Reason picker for reporting + blocking a profile.
struct ReportSheet: View {
    let profile: Profile
    var onReported: () -> Void
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    private let reasons = ["Fake / not a real person", "Inappropriate content",
                           "Harassment or abuse", "Didn't pay the bid (deadbeat)",
                           "Spam or scam", "Something else"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Report \(profile.name)")
                        .font(.scaled(18, weight: .heavy, design: .serif, relativeTo: .body)).foregroundStyle(Theme.ink)
                        .padding(.top, 8)
                    Text("They'll be removed from your floor and won't be able to reach you. Reports are reviewed by our team.")
                        .font(.scaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    ForEach(reasons, id: \.self) { reason in
                        Button {
                            store.blockAndReport(profile, reason: reason)
                            dismiss()
                            onReported()
                        } label: {
                            HStack {
                                Text(reason).font(.scaled(15, weight: .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.inkFaint)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 20)
                }
                .screenPadding().padding(.top, 8)
            }
            .background(AppBackground())
            .navigationTitle("Report & Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}

// MARK: - Blocked users (slice 6)

/// Signed-in users see their server-persisted block list here and can unblock
/// with one tap. Demo Mode + local-only sessions show whatever's in the local
/// `blockedIDs` set as read-only names (there's no server record to remove;
/// their blocks live for the session only).
struct BlockedUsersView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var profileSync: ProfileService
    @State private var blocks: [BlockedRow] = []
    @State private var loading = false
    @State private var unblockingId: String?

    struct BlockedRow: Identifiable, Equatable {
        let id: String            // blockedId, lowercase uuid
        var name: String
        var hue: Double
        let reason: String?
        let createdAt: Double
    }

    var body: some View {
        Group {
            if loading && blocks.isEmpty {
                ProgressView().tint(Theme.gold)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if blocks.isEmpty {
                EmptyStateView(icon: "hand.raised.slash",
                               title: "Nobody blocked",
                               message: store.demoMode
                                ? "Demo Mode is local-only — blocks don't sync here."
                                : (auth.isSignedIn
                                    ? "Anyone you Report & Block will show up here so you can undo it."
                                    : "Sign in to see your blocks synced across devices."))
                    .background(AppBackground())
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(blocks) { row in
                            blockedCard(row)
                        }
                        Spacer(minLength: 20)
                    }
                    .screenPadding().padding(.top, 8)
                }
                .background(AppBackground())
            }
        }
        .navigationTitle("Blocked users")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func blockedCard(_ row: BlockedRow) -> some View {
        GlassSurface(corner: Theme.cornerL) {
            HStack(spacing: 12) {
                AvatarCircle(name: row.name, hue: row.hue, photoName: nil, size: 44, revealed: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.scaled(14, weight: .heavy, design: .serif, relativeTo: .footnote))
                        .foregroundStyle(Theme.ink)
                    if let reason = row.reason, !reason.isEmpty {
                        Text(reason).font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint).lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    Task { await unblock(row.id) }
                } label: {
                    HStack(spacing: 4) {
                        if unblockingId == row.id { ProgressView().tint(Theme.ink) }
                        else { Text("Unblock") }
                    }
                    .font(.scaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .disabled(unblockingId != nil)
            }
            .padding(12)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        // Signed-in path: authoritative list from the server. Local-only path:
        // fall back to whatever the store already knows.
        if auth.isSignedIn, !store.demoMode, let remote = await auth.listBlocks() {
            var rows: [BlockedRow] = remote.map { r in
                BlockedRow(id: r.blockedId, name: "Someone", hue: 0.6,
                           reason: r.reason, createdAt: r.createdAt)
            }
            // Hydrate names + hues from the profile endpoint. One roundtrip per
            // row; small in practice (a user rarely blocks dozens). If the peer
            // never set a public profile, the "Someone" default sticks.
            await withTaskGroup(of: (Int, PublicProfile?).self) { group in
                for (i, row) in rows.enumerated() {
                    group.addTask { [row] in
                        if case .success(let p) = await profileSync.fetchProfile(userId: row.id) {
                            return (i, p)
                        }
                        return (i, nil)
                    }
                }
                for await (i, p) in group {
                    guard let p else { continue }
                    rows[i].name = p.name
                    rows[i].hue = p.hue
                }
            }
            rows.sort { $0.createdAt > $1.createdAt }
            blocks = rows
            return
        }
        // Local-only fallback — surface whatever the sim knows.
        let ids = store.blockedIDs
        blocks = ids.compactMap { id in
            let name = localName(for: id) ?? "Someone"
            let hue = localHue(for: id) ?? 0.6
            return BlockedRow(id: id.uuidString.lowercased(), name: name, hue: hue,
                              reason: nil, createdAt: 0)
        }
    }

    private func unblock(_ id: String) async {
        unblockingId = id
        defer { unblockingId = nil }
        if auth.isSignedIn, !store.demoMode {
            _ = await auth.unblockUser(userId: id)
        }
        // Also clear the local mirror so the user immediately sees the change
        // in both the list and (later) their floor. UUID round-trip is fine —
        // the server stores lowercase; UUID parsing is case-insensitive.
        if let uuid = UUID(uuidString: id) { store.blockedIDs.remove(uuid) }
        blocks.removeAll { $0.id == id }
        store.toastFlash("Unblocked. They can see your profile again.")
    }

    private func localName(for id: UUID) -> String? {
        store.floor.first(where: { $0.id == id })?.name
            ?? store.bidders.first(where: { $0.id == id })?.name
    }
    private func localHue(for id: UUID) -> Double? {
        store.floor.first(where: { $0.id == id })?.hue
            ?? store.bidders.first(where: { $0.id == id })?.hue
    }
}
