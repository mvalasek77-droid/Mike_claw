import SwiftUI

/// The founder-only admin console: manage both rosters — lots (women) and
/// bidders (men) — add, edit, or remove anyone, and edit the signed-in account.
/// Reached from Settings → Admin console, gated on `store.isAdmin`. Everything
/// routes through `AuctionStore` so state stays in one place and persists.
struct AdminView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var backend: BackendService
    @Environment(\.dismiss) private var dismiss
    @State private var stats: BackendService.AdminStats?
    @State private var statsError: String?

    /// What the form sheet is currently doing, if anything.
    private enum Sheet: Identifiable {
        case addLot, addBidder
        case edit(Profile)
        case editMe
        case backend
        case realUsers
        case moderation
        var id: String {
            switch self {
            case .addLot: return "addLot"
            case .addBidder: return "addBidder"
            case .editMe: return "editMe"
            case .backend: return "backend"
            case .realUsers: return "realUsers"
            case .moderation: return "moderation"
            case .edit(let p): return "edit-\(p.id)"
            }
        }
    }
    @State private var sheet: Sheet?
    @State private var pendingDelete: Profile?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    headerCard
                    statsCard
                    myAccountCard
                    backendCard
                    realUsersCard
                    moderationCard

                    rosterSection(title: "Lots · \(store.adminRoster.count)",
                                  empty: "No lots on the floor yet.",
                                  people: store.adminRoster,
                                  addLabel: "Add lot") { sheet = .addLot }

                    rosterSection(title: "Bidders · \(store.adminBidders.count)",
                                  empty: "No bidders in the pool yet.",
                                  people: store.adminBidders,
                                  addLabel: "Add bidder") { sheet = .addBidder }

                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Admin console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.gold)
                }
            }
            .task { await loadStats() }
            .refreshable { await loadStats() }
            .sheet(item: $sheet) { which in
                switch which {
                case .addLot:      ProfileFormSheet(role: .woman)
                case .addBidder:   ProfileFormSheet(role: .man)
                case .editMe:      ProfileFormSheet(role: store.me.role, existing: store.me, isCurrentUser: true)
                case .backend:     AdminBackendView()
                case .realUsers:   NavigationStack { AdminRealUsersView() }
                case .moderation:  NavigationStack { AdminModerationView() }
                case .edit(let p): ProfileFormSheet(role: p.role, existing: p)
                }
            }
            .alert("Remove user?", isPresented: .init(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })) {
                Button("Remove", role: .destructive) {
                    if let p = pendingDelete { store.adminDeleteUser(p.id) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Removes \(pendingDelete?.name ?? "this user") and clears any bids or matches with them. This can't be undone.")
            }
        }
    }

    private var headerCard: some View {
        GlassCard(title: "Founder tools", icon: "person.2.badge.gearshape.fill", tint: Theme.verify) {
            Text("Add, edit or remove lots and bidders. Changes go live immediately and persist across launches.")
                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Batch P — platform heartbeat at a glance. Signed-in admin only; free
    /// users see it disabled if the auth Worker returns 403 (which is what
    /// happens before the founder gets is_admin flipped).
    @ViewBuilder
    private var statsCard: some View {
        GlassCard(title: "Platform · live", icon: "waveform.path.ecg", tint: Theme.gold) {
            if let s = stats {
                VStack(spacing: 10) {
                    statRow("Users", value: "\(s.users)",
                            trail: "\(s.verified) verified · \(s.admins) admin")
                    statRow("Reports", value: "\(s.reportsOpen) open",
                            trail: "\(s.reportsResolved) resolved · \(s.blocks) blocks",
                            highlight: s.reportsOpen > 0 ? Theme.danger : nil)
                    statRow("Matches", value: "\(s.matchesChatting) chatting",
                            trail: "\(s.matchesClosed) closed")
                    statRow("Last 24h", value: "\(s.bids24h) bids",
                            trail: "\(s.messages24h) messages")
                    if s.noDob > 0 {
                        statRow("No DOB", value: "\(s.noDob)",
                                trail: "Should be zero — DOB gate is enforced.",
                                highlight: Theme.warning)
                    }
                }
            } else if let err = statsError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(err).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.danger)
                    Text("Sign in with an admin account (is_admin = 1) to see the platform heartbeat.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().tint(Theme.gold)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
    }

    private func statRow(_ label: String, value: String, trail: String,
                         highlight: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(1)
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(highlight ?? Theme.ink)
            Spacer()
            Text(trail)
                .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
        }
    }

    private func loadStats() async {
        switch await backend.fetchAdminStats() {
        case .success(let s):
            stats = s
            statsError = nil
        case .failure(let message):
            stats = nil
            statsError = message
        }
    }

    /// Doorway into the money console: float funding, ledger, owed women.
    private var backendCard: some View {
        Button { sheet = .backend } label: {
            GlassSurface(corner: Theme.cornerL) {
                HStack(spacing: 12) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.success)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.success.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Money & backend").font(.system(size: 15, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("Float, ledger, payouts, backend URLs")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    /// Doorway into the real user roster (auth Worker) — search, unverify,
    /// hard-delete. Distinct from `rosterSection` which manages sim data.
    private var realUsersCard: some View {
        Button { sheet = .realUsers } label: {
            GlassSurface(corner: Theme.cornerL) {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.gold.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed-in users").font(.system(size: 15, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("Real accounts from Sign in with Apple. Unverify or delete.")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    /// Doorway into the report queue — user-filed Report & Block actions.
    private var moderationCard: some View {
        Button { sheet = .moderation } label: {
            GlassSurface(corner: Theme.cornerL) {
                HStack(spacing: 12) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.warning.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Moderation queue").font(.system(size: 15, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("User reports. Resolve, unverify, or delete the target.")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    /// Quick edit of the signed-in account.
    private var myAccountCard: some View {
        Button { sheet = .editMe } label: {
            GlassSurface(corner: Theme.cornerL) {
                HStack(spacing: 12) {
                    AvatarCircle(name: store.me.name, hue: store.me.hue,
                                 photoName: store.me.photoName, size: 44, revealed: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your account").font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.inkFaint)
                        Text(store.me.name.isEmpty ? "You" : store.me.name)
                            .font(.system(size: 15, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Label("Edit", systemImage: "pencil").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rosterSection(title: String, empty: String, people: [Profile],
                               addLabel: String, add: @escaping () -> Void) -> some View {
        HStack {
            SectionHeader(title: title)
            Spacer()
            Button(action: add) {
                Label(addLabel, systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
            }
        }
        .padding(.top, 4)
        if people.isEmpty {
            Text(empty).font(.system(size: 13)).foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(people) { profile in
                AdminUserRow(profile: profile,
                             onEdit: { sheet = .edit(profile) },
                             onDelete: { pendingDelete = profile })
            }
        }
    }
}

/// One roster row with edit + delete affordances.
struct AdminUserRow: View {
    let profile: Profile
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        GlassSurface(corner: Theme.cornerL) {
            HStack(spacing: 12) {
                AvatarCircle(name: profile.name, hue: profile.hue, photoName: profile.photoName,
                             size: 48, copycat: profile.isCopycat, revealed: true,
                             copycatStyle: profile.copycatStyle)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(profile.name).font(.system(size: 15, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        if profile.verified { VerifiedBadge(size: 12) }
                        if profile.isCopycat { CopycatTag(compact: true) }
                    }
                    Text("\(profile.age) · \(profile.location)")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                    if profile.role == .man, profile.archetype != .none {
                        Text(profile.archetype.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.gold)
                    } else if let bid = profile.startingBid {
                        Text("Floor \(Money.compact(bid))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.gold)
                    }
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.gold.opacity(0.14)))
                }
                .buttonStyle(.plain)
                Button(action: onDelete) {
                    Image(systemName: "trash.fill").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Theme.danger.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
    }
}

/// One form that adds or edits a lot, a bidder, or the signed-in account. The
/// role decides which fields show (archetype for men; floor + copycat for women).
struct ProfileFormSheet: View {
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    let role: Role
    var existing: Profile? = nil       // nil = adding a new person
    var isCurrentUser: Bool = false

    @State private var name = ""
    @State private var ageText = "25"
    @State private var location = ""
    @State private var bio = ""
    @State private var bidText = ""
    @State private var verified = false
    @State private var isCopycat = false
    @State private var copycatStyle: CopycatStyle = .glam
    @State private var archetype: Archetype = .none
    @State private var loaded = false

    private var isEditing: Bool { existing != nil }
    private var isMan: Bool { role == .man }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var titleText: String {
        if isCurrentUser { return "Edit your account" }
        if isEditing { return "Edit \(isMan ? "bidder" : "lot")" }
        return isMan ? "Add bidder" : "Add lot"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    TextField("Age", text: $ageText).keyboardType(.numberPad)
                    TextField("Location", text: $location)
                    TextField("Bio", text: $bio, axis: .vertical).lineLimit(2...4)
                }

                if isMan {
                    Section("Status") {
                        Picker("Archetype", selection: $archetype) {
                            ForEach(Archetype.allCases) { a in
                                Text(a.title).tag(a)
                            }
                        }
                        Toggle("Verified", isOn: $verified)
                    }
                } else {
                    Section("Floor") {
                        TextField("Starting bid (optional)", text: $bidText)
                            .keyboardType(.numberPad)
                    }
                    Section {
                        Toggle("Verified", isOn: $verified).disabled(isCopycat)
                        Toggle("AI Copycat lure", isOn: $isCopycat)
                        if isCopycat {
                            Picker("Style", selection: $copycatStyle) {
                                ForEach(CopycatStyle.allCases, id: \.self) { s in
                                    Text(s.caption).tag(s)
                                }
                            }
                        }
                    } footer: {
                        Text(isCopycat
                             ? "Copycats can never be verified and cost a bidder credit when bid on."
                             : "Verified lots earn more trust on the floor.")
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadIfNeeded)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Add") { commit(); dismiss() }
                        .fontWeight(.bold).disabled(!canSave)
                }
            }
        }
    }

    /// Seed the fields from the existing profile the first time the sheet shows.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let p = existing else { return }
        name = p.name
        ageText = String(p.age)
        location = p.location
        bio = p.bio
        bidText = p.startingBid.map(String.init) ?? ""
        verified = p.verified
        isCopycat = p.isCopycat
        copycatStyle = p.copycatStyle
        archetype = p.archetype
    }

    private func commit() {
        let age = Int(ageText) ?? 25
        let bid = bidText.isEmpty ? nil : Int(bidText)

        if var p = existing {
            // Edit in place, preserving id, reviews and history.
            p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            p.age = max(18, age)
            p.location = location
            p.bio = bio
            p.verified = verified
            if isMan {
                p.archetype = archetype
                if archetype == .trillionaire && verified { p.trillionaireVerified = true }
            } else {
                p.startingBid = bid
                p.isCopycat = isCopycat
                p.copycatStyle = copycatStyle
            }
            store.adminUpdate(p)
        } else if isMan {
            store.adminAddBidder(name: name, age: age, location: location, bio: bio,
                                 archetype: archetype, verified: verified)
        } else {
            store.adminAddUser(name: name, age: age, location: location, bio: bio,
                               startingBid: bid, verified: verified,
                               isCopycat: isCopycat, copycatStyle: copycatStyle)
        }
    }
}
