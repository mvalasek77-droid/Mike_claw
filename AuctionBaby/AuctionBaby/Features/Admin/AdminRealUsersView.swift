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

    enum Action { case unverify, delete, suspend1d, suspend7d, suspend30d, unsuspend }

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
                    Text(err).font(.dynamicScaled(12, weight: .semibold, relativeTo: .caption1))
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
            Image(systemName: "person.3").font(.dynamicScaled(28, relativeTo: .title1)).foregroundStyle(Theme.inkSoft)
            Text("No signed-in users yet.")
                .font(.dynamicScaled(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
            Text("Sign-in with Apple creates the first row here. Sim rosters live on the previous screen.")
                .font(.dynamicScaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkSoft)
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
                            .font(.dynamicScaled(14, weight: .heavy, design: .serif, relativeTo: .footnote))
                            .foregroundStyle(Theme.ink)
                        Text(u.id.prefix(8) + "…")
                            .font(.dynamicScaled(10, weight: .medium, design: .monospaced, relativeTo: .caption2))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                    if isSuspended(u) {
                        Chip(text: "suspended", color: Theme.warning)
                    }
                    if u.verifiedAt != nil {
                        Chip(text: "verified", color: Theme.verify)
                    }
                }
                if isSuspended(u), let until = u.suspendedUntil {
                    Text("Suspended until \(fullDate(until))")
                        .font(.dynamicScaled(11, weight: .semibold, relativeTo: .caption2))
                        .foregroundStyle(Theme.warning)
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
                            .font(.dynamicScaled(11, weight: .medium, design: .monospaced, relativeTo: .caption2))
                            .foregroundStyle(Theme.inkSoft).lineLimit(1)
                    }
                    Spacer()
                    Text("joined \(shortDate(u.createdAt))")
                        .font(.dynamicScaled(10, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
                }
                HStack(spacing: 8) {
                    Button {
                        pending = (u, .unverify)
                    } label: {
                        Label("Unverify", systemImage: "checkmark.seal")
                            .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                            .foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().fill(Theme.warning.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .disabled(u.verifiedAt == nil)
                    .opacity(u.verifiedAt == nil ? 0.4 : 1)
                    // Suspend menu — presets keep the flow one tap most of
                    // the time; unsuspend replaces the menu when active.
                    if isSuspended(u) {
                        Button {
                            pending = (u, .unsuspend)
                        } label: {
                            Label("Unsuspend", systemImage: "clock.arrow.circlepath")
                                .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                                .foregroundStyle(Theme.success)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Capsule().fill(Theme.success.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Menu {
                            Button("Suspend 24 hours") { pending = (u, .suspend1d) }
                            Button("Suspend 7 days") { pending = (u, .suspend7d) }
                            Button("Suspend 30 days") { pending = (u, .suspend30d) }
                        } label: {
                            Label("Suspend", systemImage: "clock.badge.exclamationmark")
                                .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                                .foregroundStyle(Theme.warning)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(Capsule().fill(Theme.warning.opacity(0.14)))
                        }
                    }
                    Button {
                        pending = (u, .delete)
                    } label: {
                        Label("Delete", systemImage: "xmark.octagon.fill")
                            .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
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
        let name = pending?.user.name ?? "user"
        switch pending?.kind {
        case .unverify: return "Unverify \(name)?"
        case .delete:   return "Delete \(name)?"
        case .suspend1d, .suspend7d, .suspend30d: return "Suspend \(name)?"
        case .unsuspend: return "Unsuspend \(name)?"
        case nil:       return ""
        }
    }
    private var alertConfirm: String {
        switch pending?.kind {
        case .unverify: return "Unverify"
        case .delete:   return "Delete permanently"
        case .suspend1d: return "Suspend 24h"
        case .suspend7d: return "Suspend 7 days"
        case .suspend30d: return "Suspend 30 days"
        case .unsuspend: return "Unsuspend"
        case nil:       return ""
        }
    }
    private var alertMessage: String {
        switch pending?.kind {
        case .unverify:
            return "Removes their blue check. They can re-verify through the normal flow."
        case .delete:
            return "Hard-deletes the account and every bid, match, message, block, and report tied to it. This cannot be undone."
        case .suspend1d, .suspend7d, .suspend30d:
            return "Blocks new sign-ins, profile writes, and bids for the chosen window. Existing sessions run to their normal expiry. Reversible with Unsuspend."
        case .unsuspend:
            return "Lifts the suspension immediately. Sign-ins and bids resume."
        case nil: return ""
        }
    }

    private func isSuspended(_ u: BackendService.AdminUser) -> Bool {
        guard let until = u.suspendedUntil else { return false }
        return until > Date().timeIntervalSince1970 * 1000
    }

    private func shortDate(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none
        return f.string(from: d)
    }

    private func fullDate(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: d)
    }

    private static let dayMs: Double = 24 * 60 * 60 * 1000

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
            let now = Date().timeIntervalSince1970 * 1000
            switch p.kind {
            case .unverify:
                err = await backend.adminUnverifyUser(id: p.user.id)
            case .delete:
                err = await backend.adminDeleteUser(id: p.user.id)
            case .suspend1d:
                err = await backend.adminSuspendUser(id: p.user.id, untilMs: now + Self.dayMs)
            case .suspend7d:
                err = await backend.adminSuspendUser(id: p.user.id, untilMs: now + 7 * Self.dayMs)
            case .suspend30d:
                err = await backend.adminSuspendUser(id: p.user.id, untilMs: now + 30 * Self.dayMs)
            case .unsuspend:
                err = await backend.adminUnsuspendUser(id: p.user.id)
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
