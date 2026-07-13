import StoreKit
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var purchases: PurchaseManager
    @EnvironmentObject var push: PushManager
    @Environment(\.openURL) private var openURL
    @State private var childToUnlink: Child?
    @State private var protection: ProtectionStatus?
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false
    @State private var showBugReport = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Plan", value: purchases.activeTier.displayName)
                    if purchases.activeTier != .none {
                        LabeledContent("Children covered", value: "\(store.children.count) of \(purchases.activeTier.maxChildren)")
                    }
                    if purchases.activeTier == .none {
                        Button("Subscribe") { showPaywall = true }
                    } else {
                        Button("Change plan") { showPaywall = true }
                        Button("Manage subscription") { showManageSubscriptions = true }
                    }
                } header: {
                    Text("Subscription")
                }

                Section {
                    notificationsRow
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get notified the moment a watch-level or elevated alert fires, without opening the app.")
                }

                Section("Linked accounts") {
                    if store.children.isEmpty {
                        Text("No accounts linked")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.children) { child in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(child.displayName.isEmpty ? child.robloxUsername : child.displayName)
                                Text("@\(child.robloxUsername)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unlink", role: .destructive) {
                                childToUnlink = child
                            }
                        }
                    }
                }

                Section {
                    if let protection {
                        LabeledContent("Threat definitions",
                                       value: "v\(protection.feed.version) · \(protection.feed.updatedAt)")
                        LabeledContent("Updates from",
                                       value: protection.feed.source == "seed"
                                       ? "built-in" : protection.feed.source)
                        if let run = protection.lastIntelRun {
                            LabeledContent("Last threat search",
                                           value: String(run.ranAt.prefix(10)))
                        } else if protection.sourcesConfigured == 0 {
                            Text("Daily threat search: not configured")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    } else {
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Protection updates")
                } footer: {
                    Text("Detection rules, term definitions, and the experience watchlist refresh themselves — new threats roll out without app updates. A daily search of safety sources proposes additions automatically.")
                }

                Section("Privacy") {
                    Text("RobloxGuard stores only your child's Roblox username and the safety alerts derived from public account information. Unlinking an account permanently deletes everything associated with it. Nothing is shared with third parties.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Privacy Policy", destination: PaywallView.privacyPolicyURL)
                        .font(.footnote)
                }

                Section {
                    Button {
                        showBugReport = true
                    } label: {
                        Label("Report a Bug", systemImage: "ladybug")
                    }
                } header: {
                    Text("Support")
                } footer: {
                    Text("Reports go to \(BugReportView.supportEmail) and are logged for the team to review.")
                }
            }
            .navigationTitle("Settings")
            .task { protection = try? await store.api.protectionStatus() }
            .task { await push.refreshStatus() }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showBugReport) { BugReportView() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .confirmationDialog(
                "Unlink this account? All stored alerts and history for it will be permanently deleted.",
                isPresented: .init(get: { childToUnlink != nil },
                                   set: { if !$0 { childToUnlink = nil } }),
                titleVisibility: .visible
            ) {
                Button("Unlink & delete data", role: .destructive) {
                    if let child = childToUnlink {
                        Task { await store.unlinkChild(child) }
                    }
                    childToUnlink = nil
                }
            }
        }
    }

    @ViewBuilder
    private var notificationsRow: some View {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Label(push.isRegistered ? "Notifications enabled" : "Notifications enabled — connecting…",
                  systemImage: "bell.badge.fill")
                .foregroundStyle(.green)
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Notifications off — open Settings", systemImage: "bell.slash")
            }
        case .notDetermined:
            Button {
                Task { await push.requestAuthorization() }
            } label: {
                Label("Enable Notifications", systemImage: "bell")
            }
        @unknown default:
            EmptyView()
        }
    }
}
