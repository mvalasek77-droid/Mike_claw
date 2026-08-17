import SwiftUI

/// Spins up a private group from a subset of your confirmed friends.
struct CreateGroupView: View {
    @State private var model: CreateGroupViewModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (FriendGroup) -> Void

    init(groupService: GroupService, friendsService: FriendsService, onCreated: @escaping (FriendGroup) -> Void) {
        _model = State(initialValue: CreateGroupViewModel(service: groupService, friendsService: friendsService))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About this group") {
                    TextField("Name", text: $model.name)
                    TextField("Description (optional)", text: $model.description)
                }
                Section("Invite friends") {
                    if model.friends.isEmpty {
                        Text("Add some friends first to start a group.")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(Tokens.Color.textSecondary)
                    } else {
                        ForEach(model.friends) { friend in
                            Button {
                                model.toggle(friend)
                            } label: {
                                HStack {
                                    UserAvatar(user: friend, size: 32)
                                    Text(friend.displayName)
                                        .foregroundStyle(Tokens.Color.textPrimary)
                                    Spacer()
                                    if model.selectedFriends.contains(friend) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Tokens.Color.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if case .failed(let message) = model.submitState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let group = await model.submit() {
                                onCreated(group)
                                dismiss()
                            }
                        }
                    } label: {
                        if model.submitState == .submitting {
                            ProgressView()
                        } else {
                            Text("Create").fontWeight(.bold)
                        }
                    }
                    .disabled(!model.canSubmit)
                }
            }
        }
        .task { await model.loadFriends() }
    }
}
