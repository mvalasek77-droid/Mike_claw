import SwiftUI

/// The activity bell's destination: every friend, reaction, vote, comment,
/// award, and mention notification, newest first. Tapping a row marks it read;
/// unread items carry a leading accent dot.
struct NotificationsView: View {
    let model: NotificationsViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Notifications")
                .toolbar {
                    if model.unreadCount > 0 {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Mark all read") { Task { await model.markAllRead() } }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("You're all caught up",
                                   systemImage: "bell.slash",
                                   description: Text("New activity will show up here."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let items):
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.sm) {
                    ForEach(items) { item in
                        Button { Task { await model.markRead(item) } } label: {
                            NotificationRow(notification: item)
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

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            if !notification.isRead {
                Circle().fill(Tokens.Color.accent).frame(width: 8, height: 8)
            } else {
                Circle().fill(.clear).frame(width: 8, height: 8)
            }
            UserAvatar(user: notification.actor, size: 40)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: notification.kind.systemImage)
                        .font(.caption2.bold())
                        .padding(4)
                        .background(Tokens.Color.accent, in: Circle())
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.message)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Color.textPrimary)
                Text(notification.createdAt.relative)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Spacer()
        }
        .padding(Tokens.Spacing.md)
        .liquidGlass()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.message)\(notification.isRead ? "" : ", unread")")
    }
}
