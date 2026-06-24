import SwiftUI

struct MatchesView: View {
    @EnvironmentObject private var store: AuctionStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if store.matches.isEmpty {
                        EmptyStateView(icon: "bubble.left.and.bubble.right",
                                       title: "No matches yet",
                                       message: store.role == .man
                                        ? "Win a bid and she'll send the first invite."
                                        : "Accept a bid to open the conversation.")
                    }
                    ForEach(store.matches) { match in
                        NavigationLink(value: match.id) {
                            MatchRow(match: match)
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 20)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Matches")
            .navigationDestination(for: UUID.self) { id in
                if let match = store.matches.first(where: { $0.id == id }) {
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
                AvatarCircle(name: other.name, hue: other.hue, size: 56, copycat: other.isCopycat, copycatStyle: other.copycatStyle)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(other.name).font(.system(size: 16, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        if other.isCopycat { CopycatTag(compact: true) }
                    }
                    Text(match.messages.last?.text ?? "Say hello")
                        .font(.system(size: 13)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(Money.compact(match.bid.amount))
                        .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                    PhaseTag(phase: match.phase)
                }
            }
            .padding(14)
        }
    }
}

struct PhaseTag: View {
    let phase: MatchPhase
    var body: some View {
        let (text, color): (String, Color) = {
            switch phase {
            case .chatting: return ("Chatting", Theme.success)
            case .dateDone: return ("Review", Theme.warning)
            case .closed: return ("Closed", Theme.inkFaint)
            }
        }()
        return Text(text).font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}
