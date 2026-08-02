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
    @State private var pendingAction: (report: BackendService.AuthReport, kind: TargetAction)?

    enum TargetAction { case unverify, ban }

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
        .alert(actionAlertTitle,
               isPresented: .init(get: { pendingAction != nil },
                                  set: { if !$0 { pendingAction = nil } })) {
            Button(actionAlertConfirm, role: .destructive) { performAction() }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(actionAlertMessage)
        }
    }

    private var actionAlertTitle: String {
        switch pendingAction?.kind {
        case .unverify: return "Unverify target?"
        case .ban:      return "Delete target account?"
        case nil:       return ""
        }
    }
    private var actionAlertConfirm: String {
        switch pendingAction?.kind {
        case .unverify: return "Unverify"
        case .ban:      return "Delete permanently"
        case nil:       return ""
        }
    }
    private var actionAlertMessage: String {
        let idPrefix = (pendingAction?.report.targetId.prefix(8)).map(String.init) ?? ""
        switch pendingAction?.kind {
        case .unverify:
            return "Removes the blue check on user \(idPrefix)…. They can re-verify through the normal flow."
        case .ban:
            return "Hard-deletes user \(idPrefix)… and every bid, match, message, block, and report tied to them. This cannot be undone."
        case nil:
            return ""
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
                // Batch H — repeat-offender signal. A target with a lot of
                // open reports or blocks against them is worth prioritising.
                if (r.targetReportCount ?? 0) > 1 || (r.targetBlockCount ?? 0) > 0 {
                    HStack(spacing: 6) {
                        if let n = r.targetReportCount, n > 1 {
                            Chip(text: "\(n) reports on target", color: Theme.danger)
                        }
                        if let n = r.targetBlockCount, n > 0 {
                            Chip(text: "\(n) block\(n == 1 ? "" : "s")", color: Theme.warning)
                        }
                        Spacer()
                    }
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
                    HStack(spacing: 8) {
                        Button {
                            pendingAction = (r, .unverify)
                        } label: {
                            Label("Unverify", systemImage: "checkmark.seal")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.warning)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Theme.warning.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        Button {
                            pendingAction = (r, .ban)
                        } label: {
                            Label("Delete", systemImage: "xmark.octagon.fill")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Theme.danger.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
    }

    private func performAction() {
        guard let pending = pendingAction else { return }
        let (report, kind) = pending
        pendingAction = nil
        Task {
            let err: String?
            switch kind {
            case .unverify: err = await backend.adminUnverifyUser(id: report.targetId)
            case .ban:      err = await backend.adminDeleteUser(id: report.targetId)
            }
            if let err {
                lastError = err
                Haptics.warning()
            } else {
                // Auto-resolve the report as "actioned" so the queue clears
                // — the moderator just took action on the target.
                _ = await backend.resolveAuthReport(id: report.id, status: "actioned", note: "admin")
                reports.removeAll { $0.id == report.id }
                Haptics.success()
            }
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
