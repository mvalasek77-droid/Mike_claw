import SwiftUI

/// Founder view of REAL signed-in users on the auth Worker (as opposed to
/// `AdminView`'s sim rosters). Paginated from `/admin/users`; each row can
/// be unverified or hard-deleted. Sits next to `AdminModerationView` as the
/// second half of the moderation dyad — reports show who was flagged,
/// this view shows the whole user list so a founder can take action even
/// without a report.
struct AdminRealUsersView: View {
    @EnvironmentObject private var backend: BackendService

    @State private var users: [BackendService.AdminUser] = []
    @State private var loading = false
    @State private var lastError: String?
    @State private var pending: (user: BackendService.AdminUser, kind: Action)?

    enum Action { case unverify, delete }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                if loading && users.isEmpty {
                    ProgressView().tint(Theme.gold)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else if users.isEmpty {
                    empty
                } else {
                    ForEach(users) { u in row(u) }
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
        .navigationTitle("Signed-in users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundStyle(Theme.gold).disabled(loading)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert(alertTitle,
               isPresented: .init(get: { pending != nil },
                                  set: { if !$0 { pending = nil } })) {
            Button(alertConfirm, role: .destructive) { performAction() }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text(alertMessage) }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.3").font(.system(size: 28)).foregroundStyle(Theme.inkSoft)
            Text("No signed-in users yet.")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Sign-in with Apple creates the first row here. Sim rosters live on the previous screen.")
                .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func row(_ u: BackendService.AdminUser) -> some View {
        GlassSurface(corner: Theme.cornerL) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(u.name ?? "(no name)")
                            .font(.system(size: 14, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text(u.id.prefix(8) + "…")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                    if u.verifiedAt != nil {
                        Chip(text: "verified", color: Theme.verify)
                    }
                }
                // Batch H — surface moderator counts so serial offenders
                // are visible without opening the reports queue.
                if (u.reportsAgainst ?? 0) > 0 || (u.blocksAgainst ?? 0) > 0 {
                    HStack(spacing: 6) {
                        if let n = u.reportsAgainst, n > 0 {
                            Chip(text: "\(n) report\(n == 1 ? "" : "s")", color: Theme.danger)
                        }
                        if let n = u.blocksAgainst, n > 0 {
                            Chip(text: "\(n) block\(n == 1 ? "" : "s")", color: Theme.warning)
                        }
                        Spacer()
                    }
                }
                HStack(spacing: 12) {
                    if let email = u.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer()
                    Text("joined \(shortDate(u.createdAt))")
                        .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                }
                HStack(spacing: 8) {
                    Button {
                        pending = (u, .unverify)
                    } label: {
                        Label("Unverify", systemImage: "checkmark.seal")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.warning.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .disabled(u.verifiedAt == nil)
                    .opacity(u.verifiedAt == nil ? 0.4 : 1)
                    Button {
                        pending = (u, .delete)
                    } label: {
                        Label("Delete", systemImage: "xmark.octagon.fill")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.danger.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    private var alertTitle: String {
        switch pending?.kind {
        case .unverify: return "Unverify \(pending?.user.name ?? "user")?"
        case .delete:   return "Delete \(pending?.user.name ?? "user")?"
        case nil:       return ""
        }
    }
    private var alertConfirm: String {
        switch pending?.kind {
        case .unverify: return "Unverify"
        case .delete:   return "Delete permanently"
        case nil:       return ""
        }
    }
    private var alertMessage: String {
        switch pending?.kind {
        case .unverify:
            return "Removes their blue check. They can re-verify through the normal flow."
        case .delete:
            return "Hard-deletes the account and every bid, match, message, block, and report tied to it. This cannot be undone."
        case nil: return ""
        }
    }

    private func shortDate(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none
        return f.string(from: d)
    }

    private func refresh() async {
        loading = true
        lastError = nil
        defer { loading = false }
        switch await backend.fetchAdminUsers() {
        case .success(let list): users = list
        case .failure(let message): lastError = message
        }
    }

    private func performAction() {
        guard let p = pending else { return }
        pending = nil
        Task {
            let err: String?
            switch p.kind {
            case .unverify: err = await backend.adminUnverifyUser(id: p.user.id)
            case .delete:   err = await backend.adminDeleteUser(id: p.user.id)
            }
            if let err {
                lastError = err
                Haptics.warning()
                return
            }
            Haptics.success()
            if p.kind == .delete {
                users.removeAll { $0.id == p.user.id }
            } else {
                await refresh()
            }
        }
    }
}
