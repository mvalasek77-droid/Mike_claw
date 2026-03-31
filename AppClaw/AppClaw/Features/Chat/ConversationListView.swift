import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showNewChat: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if appState.conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("AppClaw")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let convo = appState.newConversation()
                        appState.activeConversationId = convo.id
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.green)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "pawprint.circle")
                .font(.system(size: 64))
                .foregroundColor(.green.opacity(0.8))

            VStack(spacing: 8) {
                Text("AppClaw")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text("Agentic AI on iPhone")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Button {
                let convo = appState.newConversation()
                appState.activeConversationId = convo.id
            } label: {
                Label("Start a conversation", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .clipShape(Capsule())
            }

            if !appState.availableTools.isEmpty {
                Text("\(appState.availableTools.count) tools connected")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(appState.conversations) { convo in
                NavigationLink(destination: ChatView(conversation: convo)) {
                    ConversationRow(conversation: convo)
                }
                .listRowBackground(Color(white: 0.08))
            }
            .onDelete { indexSet in
                indexSet.forEach { appState.deleteConversation(appState.conversations[$0].id) }
            }
        }
        .listStyle(.plain)
        .background(Color.black)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    private var preview: String {
        conversation.messages.last(where: { $0.role == .user || $0.role == .assistant })?.content
            .prefix(80).replacingOccurrences(of: "\n", with: " ")
        ?? "No messages"
    }

    private var timeLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Text(timeLabel)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Text(preview)
                .font(.subheadline)
                .foregroundColor(.gray)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}
