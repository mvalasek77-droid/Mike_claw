import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var purchases: PurchaseManager
    @State private var showLinkSheet = false
    @State private var showPaywall = false
    @State private var paywallReason = ""

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
                    requestLinkChild()
                } label: {
                    Label("Link a child", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showLinkSheet) {
                LinkChildSheet()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: paywallReason)
            }
            .refreshable { await store.loadAll() }
            .overlay {
                if let message = store.errorMessage {
                    ErrorBanner(message: message)
                }
            }
        }
    }

    /// Free accounts and accounts at their plan's child limit are routed to
    /// the paywall instead of the link sheet.
    private func requestLinkChild() {
        if purchases.activeTier == .none {
            paywallReason = "Subscribe to start protecting your child on Roblox."
            showPaywall = true
        } else if store.children.count >= purchases.activeTier.maxChildren {
            paywallReason = "Your \(purchases.activeTier.displayName) plan covers \(purchases.activeTier.maxChildren) child\(purchases.activeTier.maxChildren == 1 ? "" : "ren"). Upgrade to Family to add more."
            showPaywall = true
        } else {
            showLinkSheet = true
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts linked", systemImage: "person.badge.shield.checkmark")
        } description: {
            Text(purchases.activeTier == .none
                 ? "Subscribe, then link your child's Roblox username to start receiving safety signals."
                 : "Link your child's Roblox username to start receiving safety signals.")
        } actions: {
            Button(purchases.activeTier == .none ? "Subscribe" : "Link a child") {
                requestLinkChild()
            }
            .buttonStyle(.borderedProminent)
        }
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
                    NavigationLink {
                        EvidenceReportView(child: child)
                    } label: {
                        Label("Evidence & incident report", systemImage: "folder.badge.person.crop")
                            .font(.subheadline)
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
                } footer: {
                    if child.id == store.children.last?.id {
                        Text("Alerts are automated pattern matches, not verdicts — they can be wrong in either direction. Use RobloxGuard alongside conversation and supervision, not in place of them.")
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: store.alertsByChild)
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
            Image(systemName: Theme.severityIcon(alert.severity))
                .foregroundStyle(Theme.severityColor(alert.severity))
                .symbolEffect(.pulse, options: .repeat(2),
                              isActive: alert.severity == .elevated)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(alert.severity.label)
                    .font(.caption)
                    .foregroundStyle(Theme.severityColor(alert.severity))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.severity.label) alert: \(alert.title)")
        .accessibilityHint("Opens details, evidence, and what to do next")
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
