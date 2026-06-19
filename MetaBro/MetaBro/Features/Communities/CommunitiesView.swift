import SwiftUI

/// Discover Bro-hoods and join/leave them. Each row is a Liquid Glass card with
/// a springy join toggle.
struct CommunitiesView: View {
    @State private var model: CommunitiesViewModel

    init(service: CommunityService) {
        _model = State(initialValue: CommunitiesViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Bro-hoods")
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No Bro-hoods yet",
                                   systemImage: "person.3",
                                   description: Text("Check back soon."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let communities):
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.md) {
                    ForEach(communities) { community in
                        CommunityRow(community: community) {
                            Task { await model.toggleMembership(community) }
                        }
                    }
                }
                .padding(Tokens.Spacing.lg)
                .animation(Tokens.Motion.gentle, value: communities)
            }
            .refreshable { await model.load() }
        }
    }
}

private struct CommunityRow: View {
    let community: Community
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
                .fill(Tokens.Color.accent.opacity(0.25))
                .frame(width: 44, height: 44)
                .overlay(Text(String(community.name.prefix(1))).font(.headline.bold()))

            VStack(alignment: .leading, spacing: 2) {
                Text(community.name).font(Tokens.Typography.headline)
                Text("\(community.memberCount.abbreviated) bros · b/\(community.slug)")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Spacer()
            joinButton
        }
        .padding(Tokens.Spacing.md)
        .liquidGlass()
        .accessibilityElement(children: .combine)
    }

    private var joinButton: some View {
        Button(action: onToggle) {
            Text(community.isJoined ? "Joined" : "Join")
                .font(Tokens.Typography.caption.weight(.bold))
                .foregroundStyle(community.isJoined ? Tokens.Color.textSecondary : .white)
                .padding(.horizontal, Tokens.Spacing.lg)
                .padding(.vertical, Tokens.Spacing.sm)
                .background {
                    Capsule().fill(community.isJoined
                                   ? AnyShapeStyle(.ultraThinMaterial)
                                   : AnyShapeStyle(Tokens.Color.accent))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(community.isJoined ? "Leave \(community.name)" : "Join \(community.name)")
    }
}
