import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var childToUnlink: Child?

    var body: some View {
        NavigationStack {
            List {
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

                Section("Privacy") {
                    Text("RobloxGuard stores only your child's Roblox username and the safety alerts derived from public account information. Unlinking an account permanently deletes everything associated with it. Nothing is shared with third parties.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
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
}
