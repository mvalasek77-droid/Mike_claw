import SwiftUI

/// The founder-only admin console: add lots to the floor and remove anyone.
/// Reached from Settings → Admin console, gated on `store.isAdmin`. Everything
/// it does routes through `AuctionStore` so state stays in one place and
/// persists like the rest of the app.
struct AdminView: View {
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var pendingDelete: Profile?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    headerCard
                    if store.adminRoster.isEmpty {
                        EmptyStateView(icon: "person.2.slash",
                                       title: "No users on the floor",
                                       message: "Add the first lot to populate the marketplace.")
                    } else {
                        SectionHeader(title: "Floor roster · \(store.adminRoster.count)")
                        ForEach(store.adminRoster) { profile in
                            AdminUserRow(profile: profile) { pendingDelete = profile }
                        }
                    }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.gold)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddUserSheet() }
            .alert("Remove user?", isPresented: .init(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })) {
                Button("Remove", role: .destructive) {
                    if let p = pendingDelete { store.adminDeleteUser(p.id) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Removes \(pendingDelete?.name ?? "this user") from the floor and clears any bids or matches with them. This can't be undone.")
            }
        }
    }

    private var headerCard: some View {
        GlassCard(title: "Founder tools", icon: "person.2.badge.gearshape.fill", tint: Theme.verify) {
            Text("Add or remove lots on the floor. Changes go live immediately and persist across launches.")
                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One roster row with a delete affordance.
struct AdminUserRow: View {
    let profile: Profile
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
                    if let bid = profile.startingBid {
                        Text("Floor \(Money.compact(bid))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.gold)
                    }
                }
                Spacer()
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

/// The add-a-user form. Minimal by design — name is the only required field.
struct AddUserSheet: View {
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var ageText = "25"
    @State private var location = ""
    @State private var bio = ""
    @State private var bidText = ""
    @State private var verified = false
    @State private var isCopycat = false
    @State private var copycatStyle: CopycatStyle = .glam

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .navigationTitle("Add user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        store.adminAddUser(
                            name: name, age: Int(ageText) ?? 25, location: location,
                            bio: bio, startingBid: bidText.isEmpty ? nil : Int(bidText),
                            verified: verified, isCopycat: isCopycat, copycatStyle: copycatStyle)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(!canSave)
                }
            }
        }
    }
}
