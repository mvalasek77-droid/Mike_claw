import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: Store
    @State private var showLinkSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if store.children.isEmpty {
                    emptyState
                } else {
                    childList
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                Button {
                    showLinkSheet = true
                } label: {
                    Label("Link a child", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showLinkSheet) {
                LinkChildSheet()
            }
            .refreshable { await store.loadAll() }
            .overlay {
                if let message = store.errorMessage {
                    ErrorBanner(message: message)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No accounts linked",
            systemImage: "person.badge.shield.checkmark",
            description: Text("Link your child's Roblox username to start receiving safety signals.")
        )
    }

    private var childList: some View {
        List {
            ForEach(store.children) { child in
                Section {
                    let alerts = store.alertsByChild[child.id] ?? []
                    if alerts.isEmpty {
                        Label("No open alerts", systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alerts) { alert in
                            NavigationLink(value: AlertRoute(child: child, alert: alert)) {
                                AlertRow(alert: alert)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(child.displayName.isEmpty ? child.robloxUsername : child.displayName)
                        Spacer()
                        Button {
                            Task { await store.refresh(child) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .navigationDestination(for: AlertRoute.self) { route in
            AlertDetailView(child: route.child, alert: route.alert)
        }
    }
}

struct AlertRoute: Hashable {
    let child: Child
    let alert: SafetyAlert
}

struct AlertRow: View {
    let alert: SafetyAlert

    var body: some View {
        HStack(spacing: 12) {
            severityIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(alert.severity.label)
                    .font(.caption)
                    .foregroundStyle(severityColor)
            }
        }
    }

    private var severityColor: Color {
        switch alert.severity {
        case .info: return .secondary
        case .watch: return .orange
        case .elevated: return .red
        }
    }

    private var severityIcon: some View {
        Image(systemName: alert.severity == .elevated
              ? "exclamationmark.shield.fill"
              : alert.severity == .watch ? "eye.fill" : "info.circle")
        .foregroundStyle(severityColor)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.footnote)
                .padding(12)
                .background(.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
                .padding()
        }
        .transition(.move(edge: .bottom))
    }
}
