import SwiftUI

/// The Activity feed — every notable event on your account, newest first.
struct ActivityView: View {
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.activity.isEmpty {
                        EmptyStateView(icon: "bell.slash", title: "Nothing yet",
                                       message: "Bids, accepts, reviews and milestones will show up here.")
                    }
                    ForEach(store.activity) { event in
                        ActivityRow(event: event)
                    }
                    Spacer(minLength: 20)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.gold)
                }
            }
        }
    }
}

struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        GlassSurface(corner: Theme.cornerM) {
            HStack(spacing: 12) {
                Image(systemName: event.kind.icon)
                    .font(.scaled(16, weight: .bold, relativeTo: .callout))
                    .foregroundStyle(event.kind.tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(event.kind.tint.opacity(0.16)))
                Text(event.text).font(.scaled(14, weight: .medium, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(event.date, format: .relative(presentation: .numeric))
                    .font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
                    .fixedSize()
            }
            .padding(12)
        }
    }
}

/// Reusable bell button that opens the Activity feed, with a dot when there's
/// anything to see.
struct ActivityBell: View {
    @EnvironmentObject private var store: AuctionStore
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill").font(.scaled(16, weight: .semibold, relativeTo: .callout))
                if store.hasActivity {
                    Circle().fill(Theme.rose).frame(width: 8, height: 8).offset(x: 4, y: -3)
                }
            }
            .foregroundStyle(Theme.gold)
        }
    }
}
