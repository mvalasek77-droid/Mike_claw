import SwiftUI

/// The user's own profile and live "credit score" — Auction Credit for bidders,
/// Showcase score for lots — plus reviews and account settings.
struct MyProfileView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @EnvironmentObject private var auth: AuthService
    @State private var editingBid = false
    @State private var bidText = ""
    @State private var showReset = false
    @State private var showSignOut = false
    @State private var showDelete = false
    @State private var deleting = false
    @State private var showVerify = false
    @State private var showSafety = false
    @State private var showAdmin = false
    @State private var showPhotoEditor = false
    @State private var showOpeningScript = false
    @State private var showStanding = false
    @State private var showEditProfile = false

    private var me: Profile { store.me }
    private var isMan: Bool { store.role == .man }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if !me.verified { verifyCard }
                    if isMan { manStats } else { womanStats }
                    if !me.reviews.isEmpty {
                        GlassCard(title: isMan ? "What dates said about you" : "What bidders said",
                                  icon: "star.bubble.fill", tint: Theme.gold) {
                            VStack(spacing: 12) { ForEach(me.reviews) { ReviewRow(review: $0) } }
                        }
                    }
                    settingsCard
                    Text("Auction Baby · demo build · v1.0").font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("You")
            .sheet(isPresented: $showVerify) {
                VerificationSheet { store.verifyMe() }
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSafety) { SafetyCenterView() }
            .sheet(isPresented: $showPhotoEditor) { PhotoEditorSheet() }
            .sheet(isPresented: $showOpeningScript) { OpeningBidScriptSheet() }
            .sheet(isPresented: $showEditProfile) { EditProfileSheet() }
            .sheet(isPresented: $showStanding) { StandingView() }
            .sheet(isPresented: $showAdmin) { AdminGateView() }
            .alert("Reset account?", isPresented: $showReset) {
                Button("Reset", role: .destructive) {
                    Task {
                        // Sign the server session out first — otherwise the
                        // new local identity (with a fresh appAccountToken)
                        // orphans any refund queue keyed on the old token.
                        // signOut is a no-op when not signed in / not
                        // configured, so this stays safe for local sessions.
                        if auth.isSignedIn { await auth.signOut() }
                        storeKit.demoTier = nil   // demo Pass dies with the account
                        store.resetAccount()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Clears your profile, bids, matches and reviews, and returns to onboarding.") }
            .alert("Sign out?", isPresented: $showSignOut) {
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your account stays. You can sign back in with Apple to pick up where you left off.")
            }
            .alert("Delete account?", isPresented: $showDelete) {
                Button("Delete permanently", role: .destructive) {
                    deleting = true
                    Task {
                        _ = await auth.deleteAccount()
                        storeKit.demoTier = nil
                        store.resetAccount()
                        deleting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently deletes your account and everything tied to it — profile, bids, matches, messages, blocks, reports. This cannot be undone.")
            }
        }
    }

    private var headerCard: some View {
        GlassSurface(corner: Theme.cornerXL) {
            VStack(spacing: 0) {
                AvatarView(name: me.name, hue: me.hue, photoName: me.photoName,
                           photoData: me.photoData, corner: Theme.cornerXL)
                    .frame(height: 260)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(me.name.isEmpty ? "You" : me.name)
                                    .font(.system(size: 28, weight: .heavy, design: .serif))
                                if me.verified { VerifiedBadge(size: 20) }
                                Text("\(me.age)").font(.system(size: 20, design: .serif)).foregroundStyle(Theme.inkSoft)
                            }.foregroundStyle(Theme.ink)
                            HStack(spacing: 8) {
                                Chip(text: me.role.sideTitle, systemImage: me.role.systemImage,
                                     color: isMan ? Theme.gold : Theme.rose)
                                if !isMan { ArtTierBadge(tier: me.artTier, compact: true) }
                                else if me.masterpiece { MasterpieceBadge(compact: true) }
                                if store.demoMode {
                                    Chip(text: "DEMO MODE · App Review",
                                         systemImage: "testtube.2", color: Theme.verify)
                                }
                            }
                        }.padding(16)
                    }
                if !me.bio.isEmpty {
                    Text(me.bio).font(.system(size: 14)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
        }
    }

    private var verifyCard: some View {
        Button { showVerify = true } label: {
            GlassSurface(corner: Theme.cornerL, tint: Theme.verify) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white).frame(width: 46, height: 46)
                        .background(Circle().fill(Theme.verify))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Get verified").font(.system(size: 16, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("A blue check tells the floor you're a real person — verified profiles get accepted far more.")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.inkFaint)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Man stats

    private var manStats: some View {
        VStack(spacing: 16) {
            if me.showsPendingTrillionaire { trillionaireProgress }
            GlassCard(title: "Auction Credit", icon: "creditcard.fill", tint: Theme.gold) {
                HStack(spacing: 16) {
                    ScoreGauge(value: me.auctionCredit, range: 300...900, label: me.creditTier, tint: Theme.gold, size: 124)
                    VStack(alignment: .leading, spacing: 10) {
                        ArchetypeBadge(archetype: me.archetype, pending: me.showsPendingTrillionaire)
                        DeadbeatTag(score: me.deadbeatScore)
                        StatPill(icon: "calendar", label: "dates", value: "\(me.datesCompleted)", tint: Theme.rose)
                        if me.copycatBids > 0 {
                            StatPill(icon: "sparkles", label: "copycat bids", value: "\(me.copycatBids)", tint: Theme.copycat)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let next = me.archetype.next {
                    Divider().overlay(Theme.hairline)
                    HStack {
                        Text("Next tier: \(next.title)").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text(next.fallbackPriceLabel).font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
            CreditReportCard(title: "Your credit report", factors: me.creditFactors)
        }
    }

    /// The three-gate checklist shown while a Trillionaire badge is unverified.
    private var trillionaireProgress: some View {
        GlassCard(title: "Verify your Trillionaire", icon: "hourglass", tint: Theme.warning) {
            Text("Trillionaire is earned, not just bought. Clear all three:")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
            VStack(alignment: .leading, spacing: 10) {
                gate(done: true, "Bought the Trillionaire tier ($9,999)")
                gate(done: false, "Bid & spend the full $9,999 on a date")
                gate(done: false, "She confirms it against the receipts")
            }
            Text("Then your badge flips to Trillionaire ✓. The Masterpiece is a different mountain: bid & spend $1,000,000 on a single date, and she confirms it.")
                .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
        }
    }

    private func gate(done: Bool, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(done ? Theme.success : Theme.inkFaint)
            Text(text).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(done ? Theme.ink : Theme.inkSoft)
            Spacer(minLength: 0)
        }
    }

    /// "What you're worth tonight" — the lot's live demand dashboard.
    private var worthCard: some View {
        GlassCard(title: "What you're worth tonight", icon: "chart.line.uptrend.xyaxis", tint: Theme.gold) {
            HStack(spacing: 12) {
                worthStat("On the table", Money.compact(store.totalOnTable), Theme.gold)
                worthStat("Highest bid", store.highestLiveBid > 0 ? Money.compact(store.highestLiveBid) : "—", Theme.rose)
            }
            HStack(spacing: 12) {
                worthStat("Live bidders", "\(store.liveBidCount)", Theme.verify)
                worthStat("Accepted", "\(store.acceptedCount)", Theme.success)
            }
            if store.isBoosted, let until = store.boostUntil {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold))
                    Text("Boosted · bidders incoming ·").font(.system(size: 12, weight: .semibold))
                    Text(timerInterval: Date.now...max(until, Date.now.addingTimeInterval(1)), countsDown: true)
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(Theme.rose)
            }
        }
    }

    private func worthStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1)
                .foregroundStyle(Theme.inkFaint)
            Text(value).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(tint)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
    }

    // MARK: Woman stats

    private var womanStats: some View {
        VStack(spacing: 16) {
            worthCard
            GlassCard(title: "Showcase Credit", icon: "rosette", tint: Theme.rose) {
                HStack(spacing: 16) {
                    ScoreGauge(value: me.showcaseCredit, range: 300...900, label: me.showcaseTier, tint: Theme.rose, size: 124)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Market value").font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.inkFaint)
                        Text(Money.compact(me.marketValue)).font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gold)
                        StarRow(value: me.overallStars)
                        StatPill(icon: "dollarsign.circle.fill", label: "accepted", value: Money.compact(store.earnings), tint: Theme.rose)
                    }
                    Spacer(minLength: 0)
                }
                if !me.traitAverages.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Trait.allCases) { t in
                            if let v = me.traitAverages[t] { StatBar(label: t.rawValue, value: v, tint: Theme.rose) }
                        }
                    }.padding(.top, 4)
                }
            }

            honorsLadder

            CreditReportCard(title: "Your showcase report", factors: me.showcaseFactors, tint: Theme.rose)

            GlassCard(title: "Your floor", icon: "dollarsign.circle.fill", tint: Theme.gold) {
                if editingBid {
                    HStack {
                        TextField("", text: $bidText,
                                  prompt: Text("e.g. 250").foregroundStyle(Theme.inkFaint))
                            .keyboardType(.numberPad).textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                            .padding(10).background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
                        Button("Save") {
                            store.setStartingBid(bidText.isEmpty ? nil : Int(bidText))
                            Haptics.commit(); editingBid = false
                        }
                        .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(Theme.goldGradient))
                        Button("Clear") { store.setStartingBid(nil); bidText = ""; editingBid = false }
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    }
                } else {
                    HStack {
                        Text(me.startingBid.map { Money.full($0) } ?? "No floor — open bidding")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(me.startingBid == nil ? Theme.rose : Theme.gold)
                        Spacer()
                        Button { bidText = me.startingBid.map(String.init) ?? ""; editingBid = true } label: {
                            Label("Edit", systemImage: "pencil").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }
            }
        }
    }

    /// The auction-house honors ladder: where she hangs today, and what the
    /// next rung costs. Masterpiece is shown but never presented as climbable.
    private var honorsLadder: some View {
        GlassCard(title: "Honors ladder", icon: "photo.artframe", tint: Theme.gold) {
            HStack {
                ArtTierBadge(tier: me.artTier)
                Spacer()
                Text("\(me.reviews.count) reviewed date\(me.reviews.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
            if let next = me.nextArtTier {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT: \(next.title.uppercased())")
                        .font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1)
                        .foregroundStyle(next.tint)
                    Text(next.requirement)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.05)))
            } else if me.artTier == .exhibitionStar {
                Text("Only one thing hangs higher — and it can't be climbed to. \(ArtTier.masterpiece.requirement).")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
            } else if me.artTier == .masterpiece {
                Text("The rarest object on any floor. There is nothing above this.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.gold)
            }
        }
    }

    private var photoCountLabel: String {
        let total = (me.photoData == nil ? 0 : 1) + me.photoGallery.count
        return total == 0 ? "None" : "\(total) / \(PhotoUploadStep.maxTotal)"
    }

    private struct OpeningBidScriptSheet: View {
        @EnvironmentObject private var store: AuctionStore
        @Environment(\.dismiss) private var dismiss
        @State private var script: String = ""

        private let presets: [String] = [
            "You're in. Where are we going? Impress me.",
            "Bold move. Tell me the plan — I like a man who books it.",
            "Alright, you won the bid. Now win the night.",
            "Fine — you have my attention. What's the reservation?",
        ]

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard(title: "Your opener", icon: "text.bubble.fill", tint: Theme.rose) {
                            Text("This line auto-sends the moment you accept a bid. Set it once — every winning bidder gets the same welcome.")
                                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                            TextField("", text: $script,
                                      prompt: Text("Write your opener — e.g. \"You're in. Where are we going?\"")
                                        .foregroundStyle(Theme.inkFaint), axis: .vertical)
                                .textFieldStyle(.plain).font(.system(size: 15))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2...5)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                            Text("\(script.count) / 240")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(script.count > 240 ? Theme.danger : Theme.inkFaint)
                                .onChange(of: script) { _, newValue in
                                    // Hard clamp so Save can't silently drop
                                    // text the user believed was kept.
                                    if newValue.count > 240 { script = String(newValue.prefix(240)) }
                                }
                        }
                        GlassCard(title: "Presets", icon: "sparkles") {
                            VStack(spacing: 8) {
                                ForEach(presets, id: \.self) { preset in
                                    Button { script = preset } label: {
                                        HStack {
                                            Text(preset).font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(Theme.ink)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Image(systemName: "arrow.up.left").foregroundStyle(Theme.gold)
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: Theme.cornerS)
                                            .fill(.white.opacity(0.05)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Spacer(minLength: 20)
                    }
                    .screenPadding().padding(.top, 8)
                }
                .background(AppBackground())
                .navigationTitle("Opening Bid Script")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") { script = "" }.foregroundStyle(Theme.inkSoft)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.updateOpeningBidScript(trimmed.isEmpty ? nil : String(trimmed.prefix(240)))
                            dismiss()
                        }.foregroundStyle(Theme.gold).fontWeight(.bold)
                    }
                }
                .onAppear { script = store.me.openingBidScript ?? "" }
            }
        }
    }

    private struct PhotoEditorSheet: View {
        @EnvironmentObject private var store: AuctionStore
        @Environment(\.dismiss) private var dismiss
        @State private var primary: Data?
        @State private var gallery: [Data]

        init() {
            _primary = State(initialValue: nil)
            _gallery = State(initialValue: [])
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    PhotoUploadStep(primary: $primary, gallery: $gallery)
                        .screenPadding().padding(.top, 8)
                }
                .background(AppBackground())
                .navigationTitle("Edit photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.inkSoft)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            store.updateProfilePhotos(primary: primary, gallery: gallery)
                            dismiss()
                        }
                        .foregroundStyle(Theme.gold).fontWeight(.bold)
                    }
                }
                .onAppear {
                    // Sheet re-inits with a fresh @State each present, so we
                    // seed from the store here rather than in init (which
                    // wouldn't see the @EnvironmentObject).
                    primary = store.me.photoData
                    gallery = store.me.photoGallery
                }
            }
        }
    }

    private struct EditProfileSheet: View {
        @EnvironmentObject private var store: AuctionStore
        @Environment(\.dismiss) private var dismiss
        @State private var name = ""
        @State private var location = ""
        @State private var bio = ""
        @State private var promptQuestions: [String] = ["", "", ""]
        @State private var promptAnswers: [String] = ["", "", ""]
        @State private var selectedInterests: Set<String> = []

        private let promptPool = [
            "The way to win me over is", "My simple pleasures",
            "I geek out on", "Together we could", "Dating me is like",
            "My most controversial opinion", "Green flags I look for",
            "Best travel story", "I'm weirdly good at", "My love language"
        ]
        private let interestPool = [
            "Art", "Travel", "Food", "Fitness", "Music", "Startups",
            "Wine", "Film", "Reading", "Dogs", "Nightlife", "Design"
        ]

        private func commit() {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return }
            var prompts: [Prompt] = []
            for i in 0..<3 {
                let q = promptQuestions[i]
                let a = promptAnswers[i].trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty && !a.isEmpty { prompts.append(Prompt(question: q, answer: a)) }
            }
            store.updateMyProfile(
                name: trimmedName,
                location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                prompts: prompts,
                interests: Array(selectedInterests)
            )
            dismiss()
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard(title: "Basics", icon: "person.fill") {
                            VStack(alignment: .leading, spacing: 12) {
                                profileField("Name", text: $name)
                                profileField("Location", text: $location, prompt: "e.g. New York")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("BIO").font(.system(size: 10, weight: .heavy, design: .rounded))
                                        .tracking(1).foregroundStyle(Theme.inkFaint)
                                    TextField("", text: $bio,
                                              prompt: Text("A few words about you")
                                                .foregroundStyle(Theme.inkFaint), axis: .vertical)
                                        .textFieldStyle(.plain).font(.system(size: 15))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(2...6)
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: Theme.cornerM)
                                            .fill(.white.opacity(0.06)))
                                }
                                Text("\(bio.count) / 300")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(bio.count > 300 ? Theme.danger : Theme.inkFaint)
                                    .onChange(of: bio) { _, v in if v.count > 300 { bio = String(v.prefix(300)) } }
                            }
                        }

                        GlassCard(title: "Prompts", icon: "text.bubble.fill", tint: Theme.rose) {
                            Text("Pick a question and write your answer.")
                                .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                            VStack(spacing: 14) {
                                ForEach(0..<3, id: \.self) { i in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Menu {
                                            ForEach(promptPool, id: \.self) { q in
                                                Button(q) { promptQuestions[i] = q }
                                            }
                                        } label: {
                                            HStack {
                                                Text(promptQuestions[i].isEmpty ? "Choose a question" : promptQuestions[i])
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(promptQuestions[i].isEmpty ? Theme.inkFaint : Theme.gold)
                                                    .lineLimit(1)
                                                Spacer()
                                                Image(systemName: "chevron.up.chevron.down")
                                                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                                            }
                                            .padding(10)
                                            .background(RoundedRectangle(cornerRadius: Theme.cornerS)
                                                .fill(.white.opacity(0.06)))
                                        }
                                        if !promptQuestions[i].isEmpty {
                                            TextField("", text: $promptAnswers[i],
                                                      prompt: Text("Your answer").foregroundStyle(Theme.inkFaint),
                                                      axis: .vertical)
                                                .textFieldStyle(.plain).font(.system(size: 14))
                                                .foregroundStyle(Theme.ink)
                                                .lineLimit(1...4)
                                                .padding(10)
                                                .background(RoundedRectangle(cornerRadius: Theme.cornerS)
                                                    .fill(.white.opacity(0.04)))
                                        }
                                    }
                                }
                            }
                        }

                        GlassCard(title: "Interests", icon: "sparkles", tint: Theme.gold) {
                            FlowChips(items: interestPool, selected: $selectedInterests)
                        }

                        Spacer(minLength: 20)
                    }
                    .screenPadding().padding(.top, 8)
                }
                .background(AppBackground())
                .navigationTitle("Edit profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.inkSoft)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { commit() }
                            .foregroundStyle(Theme.gold).fontWeight(.bold)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear {
                    let me = store.me
                    name = me.name
                    location = me.location
                    bio = me.bio
                    selectedInterests = Set(me.interests)
                    for i in 0..<3 {
                        if i < me.prompts.count {
                            promptQuestions[i] = me.prompts[i].question
                            promptAnswers[i] = me.prompts[i].answer
                        }
                    }
                }
            }
        }

        private func profileField(_ label: String, text: Binding<String>,
                                   prompt: String? = nil) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1).foregroundStyle(Theme.inkFaint)
                TextField("", text: text,
                          prompt: Text(prompt ?? label).foregroundStyle(Theme.inkFaint))
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM)
                        .fill(.white.opacity(0.06)))
            }
        }
    }

    private var settingsCard: some View {
        GlassCard(title: "Settings", icon: "gearshape.fill") {
            Button { showEditProfile = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pencil.line").foregroundStyle(Theme.gold)
                    Text("Edit profile").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.hairline)
            Button { showPhotoEditor = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled").foregroundStyle(Theme.gold)
                    Text("Edit photos").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(photoCountLabel).font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            if !isMan {
                Divider().overlay(Theme.hairline)
                Button { showOpeningScript = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "text.bubble.fill").foregroundStyle(Theme.rose)
                        Text("Opening Bid Script").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(me.openingBidScript == nil ? "Off" : "On")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.inkFaint)
                        Image(systemName: "chevron.right").font(.system(size: 12))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(Theme.hairline)
            Button { showStanding = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").foregroundStyle(Theme.gold)
                    Text("The Standing").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("This week")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                    Image(systemName: "chevron.right").font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.hairline)
            Button { showSafety = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.verify)
                    Text("Safety Center").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            if store.isAdmin {
                Divider().overlay(Theme.hairline)
                Button { showAdmin = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.badge.gearshape.fill").foregroundStyle(Theme.gold)
                        Text("Admin console").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Founder").font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gold)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.gold.opacity(0.16)))
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(Theme.hairline)
            if let url = BugReport.mailtoURL() {
                Link(destination: url) {
                    HStack(spacing: 10) {
                        Image(systemName: "ladybug.fill").foregroundStyle(Theme.gold)
                        Text("Report a bug").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Report a bug via email")
                Divider().overlay(Theme.hairline)
            }
            // App Store 5.1.1 requires ToS + Privacy Policy links reachable
            // from within the app for any account-creation flow. Rows only
            // render when the URLs are configured in Secrets.xcconfig.
            if let url = BackendConfig.termsURL {
                Link(destination: url) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill").foregroundStyle(Theme.inkSoft)
                        Text("Terms of Service").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.hairline)
            }
            if let url = BackendConfig.privacyURL {
                Link(destination: url) {
                    HStack(spacing: 10) {
                        Image(systemName: "hand.raised.fill").foregroundStyle(Theme.inkSoft)
                        Text("Privacy Policy").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.hairline)
            }
            HStack {
                Text("Reduce Motion / Dark Mode honored system-wide")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                Spacer()
            }
            if auth.isSignedIn {
                Button { showSignOut = true } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            Button(role: .destructive) { showReset = true } label: {
                Label("Reset account", systemImage: "trash")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.danger.opacity(0.12)))
            }
            if auth.isSignedIn {
                Button(role: .destructive) { showDelete = true } label: {
                    HStack(spacing: 6) {
                        if deleting { ProgressView().tint(Theme.danger) }
                        Label("Delete account permanently", systemImage: "xmark.octagon.fill")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.danger)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.danger.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(deleting)
                Text("Required by Apple: signed-in users can permanently delete their account from here. GDPR/CCPA compliant.")
                    .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    .padding(.top, 2)
            }
        }
    }
}
