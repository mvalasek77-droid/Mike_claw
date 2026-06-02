import SwiftUI

/// Operator-facing moderation queue. Lists reports persisted on the Worker
/// (KV-backed), lets the admin resolve each with a disposition + optional
/// note. Pending and Resolved are separate tabs. Without a configured
/// Worker (empty base URL or shared secret) the view shows a clear "not
/// configured" state instead of an empty list.
struct AdminModerationQueueView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var moderation: ModerationStore
    @Environment(\.dismiss) private var dismiss

    @State private var pending: [ModerationStore.QueueEntry] = []
    @State private var resolved: [ModerationStore.QueueEntry] = []
    @State private var loading = false
    @State private var selectedTab: ModerationStore.QueueStatus = .pending
    @State private var resolving: ModerationStore.QueueEntry?
    @State private var resolveNote = ""
    @State private var lastError: String?

    private var workerReady: Bool {
        !store.payoutBaseURL.trimmed.isEmpty && !store.payoutSharedSecret.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if !workerReady {
                        notConfiguredCard
                    } else {
                        Picker("", selection: $selectedTab) {
                            Text("Pending (\(pending.count))").tag(ModerationStore.QueueStatus.pending)
                            Text("Resolved (\(resolved.count))").tag(ModerationStore.QueueStatus.resolved)
                        }
                        .pickerStyle(.segmented)

                        if loading {
                            ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else {
                            let list = selectedTab == .pending ? pending : resolved
                            if list.isEmpty { emptyCard }
                            else { ForEach(list) { reportRow($0) } }
                        }
                        if let err = lastError {
                            Text(err).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.warning)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.warning).ignoresSafeArea())
            .navigationTitle("Report queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) {
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(loading || !workerReady)
                }
            }
        }
        .sheet(item: $resolving) { entry in
            resolveSheet(for: entry)
        }
        .task { if workerReady { await refresh() } }
    }

    private func refresh() async {
        loading = true
        lastError = nil
        async let p = moderation.fetchQueue(status: .pending,
                                            baseURL: store.payoutBaseURL,
                                            sharedSecret: store.payoutSharedSecret)
        async let r = moderation.fetchQueue(status: .resolved,
                                            baseURL: store.payoutBaseURL,
                                            sharedSecret: store.payoutSharedSecret)
        pending = await p
        resolved = await r
        loading = false
    }

    private func reportRow(_ entry: ModerationStore.QueueEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill").font(.system(size: 12)).foregroundStyle(Theme.warning)
                Text(entry.reason.isEmpty ? "Report" : entry.reason)
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Spacer()
                Text(entry.ts.prefix(10))
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Theme.inkFaint)
            }
            Text(entry.item_title.isEmpty ? "(unknown title)" : entry.item_title)
                .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text("by \(entry.creator_name.isEmpty ? "(unknown)" : entry.creator_name)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
            if !entry.details.isEmpty {
                Text(entry.details)
                    .font(.system(size: 12, weight: .regular)).foregroundStyle(Theme.inkSoft)
                    .lineLimit(4)
            }
            if !entry.reporter_email.isEmpty {
                Text("Reporter: \(entry.reporter_email)")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
            }
            if entry.status == "resolved" {
                HStack(spacing: 6) {
                    Image(systemName: dispositionIcon(entry.disposition))
                        .font(.system(size: 10, weight: .bold))
                    Text(entry.disposition.capitalized)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(dispositionColor(entry.disposition))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().stroke(dispositionColor(entry.disposition), lineWidth: 1))
                if !entry.resolution_note.isEmpty {
                    Text(entry.resolution_note)
                        .font(.system(size: 11, weight: .regular)).foregroundStyle(Theme.inkSoft)
                        .italic()
                }
            } else {
                Button("Resolve") {
                    resolveNote = ""
                    resolving = entry
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.accent))
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
    }

    private func resolveSheet(for entry: ModerationStore.QueueEntry) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\"\(entry.item_title)\" by \(entry.creator_name)")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(entry.details.isEmpty ? "(no details provided)" : entry.details)
                        .font(.system(size: 12, weight: .regular)).foregroundStyle(Theme.inkSoft)
                    Text("Optional note (visible in audit log)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    TextEditor(text: $resolveNote)
                        .frame(minHeight: 80)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
                        .foregroundStyle(Theme.ink)
                        .font(.system(size: 13))
                    dispositionButton(.removed, label: "Remove title",
                                       icon: "trash.fill", tint: Theme.warning, entry: entry)
                    dispositionButton(.warned, label: "Warn creator (logged only)",
                                       icon: "exclamationmark.bubble.fill", tint: Theme.kdp, entry: entry)
                    dispositionButton(.dismissed, label: "Dismiss — no action",
                                       icon: "xmark.circle.fill", tint: Theme.inkSoft, entry: entry)
                }
                .padding(18)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("Resolve report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { resolving = nil } }
            }
        }
    }

    private func dispositionButton(_ disp: ModerationStore.Disposition, label: String,
                                    icon: String, tint: Color,
                                    entry: ModerationStore.QueueEntry) -> some View {
        PrimaryButton(title: label, systemImage: icon, tint: tint) {
            Task {
                let ok = await moderation.resolve(reportID: entry.id, disposition: disp,
                                                  note: resolveNote,
                                                  baseURL: store.payoutBaseURL,
                                                  sharedSecret: store.payoutSharedSecret)
                if ok {
                    // Local-side action for "removed" — pull the title from the catalog
                    // so the operator doesn't have to do it twice.
                    if disp == .removed, let uuid = UUID(uuidString: entry.item_id) {
                        store.adminDelete(uuid)
                    }
                    resolving = nil
                    await refresh()
                } else {
                    lastError = "Couldn't reach the moderation queue. Check Worker config."
                }
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 28)).foregroundStyle(Theme.success)
            Text(selectedTab == .pending ? "Nothing pending." : "No resolved reports yet.")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var notConfiguredCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(Theme.warning)
            Text("Worker not configured").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
            Text("Set the Worker URL + shared secret in Payout Setup before the moderation queue can load.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func dispositionIcon(_ disp: String) -> String {
        switch disp {
        case "removed": return "trash.fill"
        case "warned": return "exclamationmark.bubble.fill"
        case "dismissed": return "xmark.circle.fill"
        default: return "checkmark.seal.fill"
        }
    }
    private func dispositionColor(_ disp: String) -> Color {
        switch disp {
        case "removed": return Theme.warning
        case "warned": return Theme.kdp
        default: return Theme.inkSoft
        }
    }
}
