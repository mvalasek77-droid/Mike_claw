import SwiftUI

/// The Facebook half of the hybrid: incoming Bro requests, suggested Bros, and
/// your confirmed friend list — each a Liquid Glass row with a single clear
/// action, mirroring the Bro-hood join card.
struct FriendsView: View {
    @State private var model: FriendsViewModel

    init(service: FriendsService) {
        _model = State(initialValue: FriendsViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Your Bros")
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let requests, let suggestions, let friends):
            if requests.isEmpty && suggestions.isEmpty && friends.isEmpty {
                ContentUnavailableView("No Bros yet",
                                       systemImage: "person.2",
                                       description: Text("Suggestions will show up here."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
                        section("Bro requests", requests) { user in
                            requestRow(user)
                        }
                        section("Suggested Bros", suggestions) { user in
                            suggestionRow(user)
                        }
                        section("Your Bros", friends) { user in
                            friendRow(user)
                        }
                    }
                    .padding(Tokens.Spacing.lg)
                    .animation(Tokens.Motion.gentle, value: model.state)
                }
                .refreshable { await model.load() }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, _ users: [User], @ViewBuilder row: @escaping (User) -> Content
    ) -> some View {
        if !users.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text(title).font(Tokens.Typography.headline)
                VStack(spacing: Tokens.Spacing.sm) {
                    ForEach(users) { row($0) }
                }
            }
        }
    }

    private func requestRow(_ user: User) -> some View {
        FriendRow(user: user) {
            HStack(spacing: Tokens.Spacing.sm) {
                Button { Task { await model.decline(user) } } label: {
                    Text("Decline").font(Tokens.Typography.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                Button { Task { await model.accept(user) } } label: {
                    Text("Accept").font(Tokens.Typography.caption.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .accessibilityLabel("\(user.displayName) sent you a Bro request")
    }

    private func suggestionRow(_ user: User) -> some View {
        FriendRow(user: user) {
            Button { Task { await model.sendRequest(to: user) } } label: {
                Text("Add").font(Tokens.Typography.caption.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
        }
        .accessibilityLabel("Add \(user.displayName) as a Bro")
    }

    private func friendRow(_ user: User) -> some View {
        FriendRow(user: user) {
            Text("\(user.broCred.abbreviated) Bro Cred")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
        }
    }
}

private struct FriendRow<Trailing: View>: View {
    let user: User
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            UserAvatar(user: user, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    if user.isOnline {
                        Circle()
                            .fill(.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(Tokens.Typography.headline)
                HStack(spacing: 4) {
                    Text(user.handle)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Color.textSecondary)
                    if user.isOnline {
                        Text("· Online")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
            Spacer()
            trailing
        }
        .padding(Tokens.Spacing.md)
        .liquidGlass()
    }
}
