import SwiftUI

/// In-app notification inbox — commission acceptances, deliveries, and system
/// messages. Tapping a delivery opens the produced title.
struct NotificationsView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: MediaItem?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if store.notifications.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(store.notifications) { note in row(note) }
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $selected) { MediaDetailView(item: $0) }
        .onAppear { store.markAllNotificationsRead() }
    }

    private func row(_ note: AppNotification) -> some View {
        let item = note.relatedItemID.flatMap { store.item(withID: $0) }
        return Button {
            if let item { selected = item }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: note.icon).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(note.kind == .delivery ? Theme.success : Theme.kdp)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill((note.kind == .delivery ? Theme.success : Theme.kdp).opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Text(note.body).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    Text(note.date, style: .relative).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }
                Spacer(minLength: 0)
                if item != nil {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash").font(.system(size: 44)).foregroundStyle(Theme.inkFaint)
            Text("No notifications yet").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text("Request content from your Library and you'll be notified here when an AI accepts and delivers it.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 80).padding(.horizontal, 36)
    }
}
