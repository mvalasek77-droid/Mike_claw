import SwiftUI

struct MatchesView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var matching: MatchingService
    /// Driven externally by `MainTabView` when a push tap targets a specific
    /// match. Defaults to `.constant([])` so existing callers need no changes.
    @Binding var navPath: [UUID]

    init(navPath: Binding<[UUID]> = .constant([])) {
        _navPath = navPath
    }

    private var rows: [Match] { store.effectiveMatches }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if rows.isEmpty {
                        EmptyStateView(icon: "bubble.left.and.bubble.right",
                                       title: "No matches yet",
                                       message: store.role == .man
                                        ? "Win a bid and she'll send the first invite."
                                        : "Accept a bid to open the conversation.")
                    }
                    ForEach(rows) { match in
                        NavigationLink(value: match.id) {
                            MatchRow(match: match)
                        }.buttonStyle(ScaleButtonStyle())
                    }
                    Spacer(minLength: 20)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Matches")
            .task(id: matching.isEnabled) { await store.refreshRemoteMatches(matching: matching) }
            .refreshable { await store.refreshRemoteMatches(matching: matching) }
            .navigationDestination(for: UUID.self) { id in
                if let match = store.match(withId: id) {
                    ChatView(matchID: id).navigationTitle(match.other(for: store.role ?? .man).name)
                }
            }
        }
    }
}

struct MatchRow: View {
    @EnvironmentObject private var store: AuctionStore
    let match: Match

    private var other: Profile { match.other(for: store.role ?? .man) }

    var body: some View {
        GlassSurface(corner: Theme.cornerL) {
            HStack(spacing: 12) {
                AvatarCircle(name: other.name, hue: other.hue, photoName: other.photoName,
                             remotePhotoURL: other.remotePhotoURLs.first, size: 56,
                             revealed: true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(other.name).font(.dynamicScaled(16, weight: .heavy, design: .serif, relativeTo: .callout))
                            .foregroundStyle(Theme.ink)
                        if other.verified { VerifiedBadge(size: 13) }
                    }
                    Text(match.messages.last.map { $0.imageData != nil && $0.text.isEmpty ? "📷 Photo"
                                                        : ($0.text.isEmpty ? "Say hello" : $0.text) } ?? "Say hello")
                        .font(.dynamicScaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    if match.dateReserved {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill").font(.dynamicScaled(10, relativeTo: .caption2))
                            Text(match.reservedLabel).font(.dynamicScaled(11, weight: .heavy, design: .rounded, relativeTo: .caption2))
                        }
                        .foregroundStyle(Theme.verify)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Money.compact(match.bid.amount))
                        .font(.dynamicScaled(14, weight: .heavy, design: .rounded, relativeTo: .footnote)).foregroundStyle(Theme.gold)
                    if let until = match.expiresAt, !match.isExpired {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill").font(.dynamicScaled(8, weight: .bold, relativeTo: .caption2))
                            Text(timerInterval: Date.now...max(until, Date.now.addingTimeInterval(1)), countsDown: true)
                                .monospacedDigit()
                        }
                        .font(.dynamicScaled(10, weight: .heavy, design: .rounded, relativeTo: .caption2))
                        .foregroundStyle(Theme.warning)
                    } else {
                        PhaseTag(phase: match.phase, expired: match.isExpired)
                    }
                }
            }
            .padding(14)
        }
        .opacity(match.isExpired ? 0.55 : 1)
    }
}

struct PhaseTag: View {
    let phase: MatchPhase
    var expired: Bool = false
    var body: some View {
        let (text, color): (String, Color) = {
            if expired { return ("Cold", Theme.inkFaint) }
            switch phase {
            case .chatting: return ("Chatting", Theme.success)
            case .dateDone: return ("Review", Theme.warning)
            case .closed: return ("Closed", Theme.inkFaint)
            }
        }()
        return Text(text).font(.dynamicScaled(10, weight: .heavy, design: .rounded, relativeTo: .caption2))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}
