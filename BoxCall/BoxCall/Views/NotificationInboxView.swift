import SwiftUI

struct NotificationInboxView: View {
    @EnvironmentObject var notifications: NotificationsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if notifications.inbox.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "bell.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("You're all caught up.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    ForEach(notifications.inbox) { item in
                        row(item)
                            .contentShape(Rectangle())
                            .onTapGesture { notifications.markRead(id: item.id) }
                    }
                }
                if notifications.authorizationStatus != .authorized {
                    Section {
                        Button {
                            notifications.requestAuthorizationIfNeeded()
                        } label: {
                            Label("Enable push notifications", systemImage: "bell.badge.fill")
                        }
                    } footer: {
                        Text("We use pushes for settlement results, new followers, badge unlocks, and 24-hour opening-day reminders. No promo blasts.")
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") { notifications.markAllRead() }
                        .disabled(notifications.unreadCount == 0)
                }
            }
        }
    }

    private func row(_ item: InboxItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.kind.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(item.isRead ? .regular : .semibold))
                Text(item.body).font(.caption).foregroundStyle(.secondary)
                Text(relative(item.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if !item.isRead {
                Circle().fill(.orange).frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
