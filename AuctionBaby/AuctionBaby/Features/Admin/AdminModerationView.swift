import SwiftUI

/// The founder's moderation queue. Reads from the auth Worker's
/// `/admin/reports` (D1 `reports` table) — the current pipe, fed by the
/// `POST /me/reports` call every Report & Block on the client fires
/// (slice 5). Resolutions POST to `/admin/reports/:id/resolve` with
/// status `reviewed` | `actioned` | `dismissed`.
///
/// Apple Guideline 1.2 requires serious reports to be actioned within 24h —
/// this screen is that paper trail.
struct AdminModerationView: View {
    @EnvironmentObject private var backend: BackendService

    @State private var status: String = "open"
    @State private var reports: [BackendService.AuthReport] = []
    @State private var loading = false
    @State private var lastError: String?
    @State private var resolving: BackendService.AuthReport?

    private let statusOptions: [(String, String)] = [
        ("open", "Open"),
        ("actioned", "Actioned"),
        ("dismissed", "Dismissed"),
        ("all", "All"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                Picker("Queue", selection: $status) {
                    ForEach(statusOptions, id: \.0) { opt in
                        Text(opt.1).tag(opt.0)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: status) { _, _ in Task { await refresh() } }

                if loading {
                    ProgressView().tint(Theme.gold)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else if reports.isEmpty {
                    emptyCard
                } else {
                    ForEach(reports) { row($0) }
                }
                if let err = lastError {
                    Text(err).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                }
                Spacer(minLength: 24)
            }
            .screenPadding().padding(.top, 6)
        }
        .background(AppBackground())
        .navigationTitle("Moderation queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundStyle(Theme.gold)
                .disabled(loading)
            }
        }
        .task { await refresh() }
        .confirmationDialog(
            "Resolve report",
            isPresented: .init(get: { resolving != nil },
                               set: { if !$0 { resolving = nil } }),
            titleVisibility: .visible
        ) {
            Button("Actioned — user removed / warned", role: .destructive) { resolve("actioned") }
            Button("Reviewed — noted, no action") { resolve("reviewed") }
            Button("Dismissed — no violation") { resolve("dismissed") }
            Button("Cancel", role: .cancel) { resolving = nil }
        } message: {
            Text("Resolves the report on the server. The reporter isn't notified — this is triage state, not user comms.")
        }
    }

    private func row(_ r: BackendService.AuthReport) -> some View {
        GlassSurface(corner: Theme.cornerL) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target")
                            .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(1)
                            .foregroundStyle(Theme.inkFaint)
                        Text(r.targetId.prefix(8) + "…")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Theme.ink)
                        Text(dateString(r.createdAt))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                    Chip(text: r.status == "open" ? r.reason : r.status,
                         color: chipColor(r.status))
                }
                if let ctx = r.context, !ctx.isEmpty {
                    Text(ctx).font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft).lineLimit(6)
                }
                HStack(spacing: 6) {
                    Text("From").font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1).foregroundStyle(Theme.inkFaint)
                    Text(r.reporterId.prefix(8) + "…")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
                    if let by = r.resolvedBy, !by.isEmpty, r.status != "open" {
                        Text("· resolved by \(by)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                if r.status == "open" {
                    Button {
                        resolving = r
                    } label: {
                        Label("Resolve", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.gold))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    private func chipColor(_ status: String) -> Color {
        switch status {
        case "open":     return Theme.warning
        case "actioned": return Theme.danger
        case "reviewed", "dismissed": return Theme.success
        default:         return Theme.inkFaint
        }
    }

    private func dateString(_ msSinceEpoch: Double) -> String {
        let d = Date(timeIntervalSince1970: msSinceEpoch / 1000)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: status == "open" ? "checkmark.seal.fill" : "archivebox")
                .font(.system(size: 28))
                .foregroundStyle(status == "open" ? Theme.success : Theme.inkSoft)
            Text(status == "open" ? "Queue is clear." : "No \(status) reports.")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            if status == "open" {
                Text("New Report & Block actions land here.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func refresh() async {
        loading = true
        lastError = nil
        defer { loading = false }
        switch await backend.fetchAuthReports(status: status) {
        case .success(let list): reports = list
        case .failure(let message): lastError = message
        }
    }

    private func resolve(_ status: String) {
        guard let report = resolving else { return }
        resolving = nil
        Task {
            if let err = await backend.resolveAuthReport(id: report.id, status: status, note: "admin") {
                lastError = err
                Haptics.warning()
            } else {
                reports.removeAll { $0.id == report.id }
                Haptics.success()
            }
        }
    }
}
