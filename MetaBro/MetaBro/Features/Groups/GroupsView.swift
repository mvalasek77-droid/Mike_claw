import SwiftUI

/// Private friend groups, beyond Bro-hoods: a small invite-only circle with
/// its own feed. The + button invites confirmed friends into a new one.
struct GroupsView: View {
    private let container: AppContainer
    @State private var model: GroupsViewModel
    @State private var showingCreate = false
    @Environment(\.dismiss) private var dismiss

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: GroupsViewModel(service: container.groupService))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Groups")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: FriendGroup.self) { group in
                    GroupDetailView(group: group, service: container.groupService)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingCreate = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create group")
                    }
                }
                .sheet(isPresented: $showingCreate) {
                    CreateGroupView(groupService: container.groupService,
                                     friendsService: container.friendsService) { group in
                        model.created(group)
                    }
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No groups yet", systemImage: "person.3.sequence",
                                   description: Text("Start one with the + button and invite a few bros."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let groups):
            List(groups) { group in
                NavigationLink(value: group) {
                    GroupRow(group: group)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.load() }
        }
    }
}

private struct GroupRow: View {
    let group: FriendGroup

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            ZStack {
                ForEach(Array(group.members.prefix(3).enumerated()), id: \.element.id) { index, member in
                    UserAvatar(user: member, size: 36)
                        .offset(x: CGFloat(index) * 14)
                }
            }
            .frame(width: 36 + CGFloat(min(group.members.count, 3) - 1) * 14, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(Tokens.Typography.headline)
                if !group.description.isEmpty {
                    Text(group.description)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Color.textPrimary)
                        .lineLimit(2)
                }
                Text("\(group.memberCount) members")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
        }
        .padding(.vertical, Tokens.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
