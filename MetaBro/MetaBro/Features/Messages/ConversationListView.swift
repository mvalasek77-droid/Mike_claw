import SwiftUI

/// The Messages tab: a list of DM threads (1:1 and group), each opening a chat.
struct ConversationListView: View {
    private let service: MessagingService
    @State private var model: ConversationListViewModel
    @State private var path: [Conversation] = []

    init(service: MessagingService) {
        self.service = service
        _model = State(initialValue: ConversationListViewModel(service: service))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Messages")
                .navigationDestination(for: Conversation.self) { convo in
                    ChatView(conversation: convo, service: service)
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
            ContentUnavailableView("No messages yet",
                                   systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Start a chat with a bro."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let conversations):
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.md) {
                    ForEach(conversations) { convo in
                        Button { path.append(convo) } label: {
                            ConversationRow(conversation: convo)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Tokens.Spacing.lg)
            }
            .refreshable { await model.load() }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.displayTitle).font(Tokens.Typography.headline)
                Text(conversation.lastMessage)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Tokens.Spacing.xs) {
                Text(conversation.lastActivity.relative)
                    .font(.caption2)
                    .foregroundStyle(Tokens.Color.textSecondary)
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Tokens.Color.accent, in: Capsule())
                }
            }
        }
        .padding(Tokens.Spacing.md)
        .liquidGlass()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var avatar: some View {
        Group {
            // 1:1 chats show the other bro's avatar; groups keep a glyph.
            if !conversation.isGroup, let other = conversation.participants.first {
                UserAvatar(user: other, size: 48)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
                        .fill(Tokens.Color.accent.opacity(0.25))
                        .frame(width: 48, height: 48)
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(Tokens.Color.accent)
                }
            }
        }
    }

    private var accessibilityText: String {
        let unread = conversation.unreadCount > 0 ? ", \(conversation.unreadCount) unread" : ""
        return "\(conversation.displayTitle)\(unread). \(conversation.lastMessage)"
    }
}
