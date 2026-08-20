import SwiftUI

struct BlockedUsersView: View {
    @ObservedObject var moderation = ModerationService.shared

    var body: some View {
        List {
            Section {
                if moderation.blockedHandles.isEmpty {
                    Text("You haven't blocked anyone.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(Array(moderation.blockedHandles).sorted(), id: \.self) { handle in
                        HStack {
                            Text("@\(handle)").font(.subheadline)
                            Spacer()
                            Button("Unblock") { moderation.unblock(handle: handle) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            } footer: {
                Text("Blocked users' posts, reviews, and comments never show up in your feed. Blocking is one-sided — they can't tell you blocked them.")
                    .font(.caption)
            }
        }
        .navigationTitle("Blocked users")
        .navigationBarTitleDisplayMode(.inline)
    }
}
