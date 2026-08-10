import SwiftUI
import UIKit

/// The conversation after a bid is accepted, plus the date lifecycle controls:
/// mark the date done, then leave a review.
struct ChatView: View {
    let matchID: UUID
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @EnvironmentObject private var backend: BackendService
    @EnvironmentObject private var matching: MatchingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draft = ""
    @State private var showReview = false
    @State private var showReport = false
    @State private var showReceiptPaywall = false
    @State private var reserving = false
    @State private var reserveTiers: [BackendService.ReservationTier] = []
    @State private var reserveEnabled = false
    @State private var selectedTierCents: Int?
    @State private var sending = false

    private var match: Match? { store.match(withId: matchID) }
    /// True iff this match is (or should be) authoritative on the server.
    /// We can't rely on `store.remoteMatches.contains(...)` alone — a cold
    /// tap-through-push can land us here before refreshRemoteMatch has
    /// populated the row. Any signed-in session with matching wired treats
    /// the chat as remote by default; the sim path fires only for Demo /
    /// local-only sessions.
    private var isRemote: Bool {
        if store.demoMode { return false }
        return matching.isEnabled
    }
    /// Frozen by C6 when the server refuses a send with 403 (block, DOB
    /// gate). Composer locks with a static banner so the user isn't stuck
    /// retrying against a wall.
    @State private var chatFrozen: String?

    var body: some View {
        Group {
            if let match {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                bidBanner(match)
                                if let until = match.expiresAt, !match.isExpired {
                                    expiryBanner(until: until)
                                } else if match.isExpired {
                                    expiredBanner
                                }
                                ForEach(match.messages) { msg in
                                    // Role should always be set once we've reached ChatView
                                    // (RootView gates on isRegistered); the fallback matters
                                    // only during a transient tear-down and is deliberately
                                    // conservative — .man means the "other" resolves to the
                                    // woman, which is the more common label at rest.
                                    MessageBubble(message: msg, otherName: match.other(for: store.role ?? .man).name) { emoji in
                                        store.toggleReaction(emoji, on: msg.id, in: match, matching: matching)
                                    }
                                    .id(msg.id)
                                }
                                if store.typingMatchID == match.id { TypingBubble() }
                                readReceipt(match)
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .screenPadding().padding(.top, 10)
                        }
                        .onChange(of: match.messages.count) { _, _ in
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .onChange(of: store.typingMatchID) { _, _ in
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    composer(match)
                }
                .background(AppBackground())
                .task(id: matchID) {
                    await loadReserveInfo()
                    // Always fire when signed in — refreshRemoteMatch is a
                    // no-op for Demo / local-only, and it will insert the
                    // row even if the match was previously unknown locally
                    // (tap-through-push on a cold app).
                    if isRemote { await store.refreshRemoteMatch(matchId: matchID, matching: matching) }
                }
                .sheet(isPresented: $showReview) {
                    RateDateView(match: match).presentationDetents([.large])
                        .presentationBackground(.ultraThinMaterial)
                }
            } else {
                EmptyStateView(icon: "bubble.left", title: "Match closed", message: "This conversation has ended.")
                    .background(AppBackground())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let match {
                ToolbarItem(placement: .principal) {
                    let other = match.other(for: store.role ?? .man)
                    HStack(spacing: 8) {
                        AvatarCircle(name: other.name, hue: other.hue,
                                     photoName: other.photoName,
                                     remotePhotoURL: other.remotePhotoURLs.first,
                                     size: 32, revealed: true)
                        Text(other.name)
                            .font(.system(size: 16, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        if other.verified { VerifiedBadge(size: 13) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { showReport = true } label: {
                            Label("Report & Block", systemImage: "flag")
                        }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.inkSoft) }
                }
            }
        }
        .sheet(isPresented: $showReport) {
            if let match, let role = store.role {
                // ReportSheet's onReported dismisses the sheet AND pops us
                // out of ChatView — the match is scrubbed from remoteMatches
                // by blockAndReport, so staying here would render the
                // "Match closed" empty state.
                ReportSheet(profile: match.other(for: role)) { dismiss() }
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showReceiptPaywall) { PaywallView(trigger: .readReceipts) }
    }

    /// Black Card read receipt under your latest message — or a one-tap teaser
    /// for everyone else (a peak-intent paywall moment). The paywall pitch
    /// itself is bidder-facing (`PaywallView.readReceipts` copy uses "she
    /// read it"); on the woman side we still show the delivered/seen state
    /// for Black Card holders but skip the paywall CTA and its awkward copy.
    @ViewBuilder
    private func readReceipt(_ match: Match) -> some View {
        if match.phase == .chatting, match.messages.last?.fromMe == true {
            HStack {
                Spacer()
                if storeKit.isSubscribed(to: .blackcard) {
                    HStack(spacing: 4) {
                        Image(systemName: match.seenByOther ? "checkmark.circle.fill" : "checkmark.circle")
                        Text(match.seenByOther ? "Seen" : "Delivered")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(match.seenByOther ? Theme.verify : Theme.inkFaint)
                } else if store.role == .man {
                    Button { showReceiptPaywall = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                            Text("Did she read it?")
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.rose)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 2)
        }
    }

    /// Bumble-style urgency: a live countdown while the reply window is open.
    private func expiryBanner(until: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill").font(.system(size: 11, weight: .bold))
            Text("Reply within")
            Text(timerInterval: Date.now...max(until, Date.now.addingTimeInterval(1)), countsDown: true)
                .monospacedDigit()
            Text("or this goes cold")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Theme.warning.opacity(0.14)))
        .padding(.bottom, 4)
    }

    private var expiredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "snowflake").font(.system(size: 12, weight: .bold))
            Text("This match went cold — nobody replied in time.")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Theme.inkFaint)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(.white.opacity(0.05)))
        .padding(.bottom, 4)
    }

    /// Suggested opener chips, shown only while the conversation is still cold
    /// (the human hasn't sent a real message yet). Tapping fills the draft.
    @ViewBuilder
    private func icebreakers(_ match: Match) -> some View {
        let other = match.other(for: store.role ?? .man)
        // Only offer openers when the other party actually has some AND the
        // human hasn't sent a real message yet — otherwise the header renders
        // above an empty chip row (common for men, who rarely set icebreakers).
        if !other.icebreakers.isEmpty,
           !match.messages.contains(where: { $0.fromMe && !$0.isSystem }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEED AN OPENER?").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(Theme.inkFaint)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(other.icebreakers, id: \.self) { line in
                            Button { draft = line } label: {
                                Text(line)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(.white.opacity(0.07)))
                                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func bidBanner(_ match: Match) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").font(.system(size: 11))
            Text("Accepted bid · \(Money.full(match.bid.amount))")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
            if match.bid.onCopycat {
                Text("· Copycat").foregroundStyle(Theme.copycat).font(.system(size: 12, weight: .heavy))
            }
            if match.dateReserved {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 11))
                    .foregroundStyle(Theme.verify)
                Text(match.reservedLabel).foregroundStyle(Theme.verify).font(.system(size: 12, weight: .heavy))
            }
        }
        .foregroundStyle(Theme.gold)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Theme.gold.opacity(0.14)))
        .padding(.bottom, 4)
    }

    /// Bidder-only "Reserve the date" card. Reserving pays a real-world booking
    /// fee via Stripe (kept by the platform, never sent to her) and marks the
    /// date booked. It deliberately unlocks NO in-app content — it's a
    /// real-world confirmation, which is exactly why it's a Stripe charge and
    /// not IAP. Hidden for the woman and on copycats.
    @ViewBuilder
    private func reserveCard(_ match: Match) -> some View {
        if store.role == .man {
            if match.dateReserved {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.verify)
                    Text("Date reserved — you're locked in")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.verify.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.verify.opacity(0.5), lineWidth: 1))
            } else if store.demoMode || (backend.isConsumablesConfigured && reserveEnabled) {
                // Dormant unless the Stripe web shop is configured AND the
                // remote kill-switch is on — so it can be turned off fleet-wide
                // (e.g. if Apple objects) without an app update.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.gold)
                        Text("Reserve the date")
                            .font(.system(size: 15, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    Text("A booking fee to lock in your in-person date. It goes to Auction Baby for the reservation — never to \(match.other(for: .man).name) — and unlocks nothing in the app. You still spend your bid on the date itself, and she keeps the receipts.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    tierPicker
                    Button {
                        reserve(match)
                    } label: {
                        HStack(spacing: 8) {
                            if reserving { ProgressView().tint(.black) }
                            else { Image(systemName: store.demoMode ? "wand.and.stars" : "creditcard.fill") }
                            Text(reserveButtonTitle)
                        }
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(Theme.goldGradient))
                    }
                    .buttonStyle(.plain)
                    .disabled(reserving || selectedTierCents == nil)
                    .opacity(selectedTierCents == nil ? 0.5 : 1)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.gold.opacity(0.3), lineWidth: 1))
            }
        }
    }

    /// The selectable booking-fee tiers ($10 / 15 / 25 / 50 / 100).
    @ViewBuilder private var tierPicker: some View {
        FlexLayout(spacing: 8, lineSpacing: 8) {
            ForEach(reserveTiers, id: \.cents) { tier in
                let selected = tier.cents == selectedTierCents
                Button {
                    Haptics.selection(); selectedTierCents = tier.cents
                } label: {
                    Text(tier.display)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(selected ? .black : Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(selected ? AnyShapeStyle(Theme.goldGradient)
                                                            : AnyShapeStyle(Color.white.opacity(0.07))))
                        .overlay(Capsule().strokeBorder(selected ? .clear : Theme.hairline, lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reserveButtonTitle: String {
        let label = reserveTiers.first(where: { $0.cents == selectedTierCents })?.display
        if store.demoMode { return "Demo: reserve free" }
        return label.map { "Reserve for \($0)" } ?? "Reserve the date"
    }

    /// Load the tier ladder + kill-switch state. Demo seeds the ladder locally
    /// so App Review sees the full picker with no Stripe account.
    private func loadReserveInfo() async {
        if store.demoMode {
            reserveEnabled = true
            reserveTiers = [
                .init(cents: 1000, display: "$10.00"), .init(cents: 1500, display: "$15.00"),
                .init(cents: 2500, display: "$25.00"), .init(cents: 5000, display: "$50.00"),
                .init(cents: 10000, display: "$100.00"),
            ]
            if selectedTierCents == nil { selectedTierCents = reserveTiers.first?.cents }
            return
        }
        guard backend.isConsumablesConfigured else { return }
        if case .success(let info) = await backend.fetchReservationInfo() {
            reserveEnabled = info.enabled
            reserveTiers = info.tiers
            if selectedTierCents == nil { selectedTierCents = info.tiers.first?.cents }
        }
    }

    /// Send the current draft. Remote matches go through the matching Worker
    /// with optimistic UI + rollback on failure; sim matches use the local
    /// `AuctionStore.send(_:in:)` path.
    ///
    /// C6: when the Worker returns 403 (block placed mid-chat, DOB gate
    /// tripped, etc.), freeze the composer with a "can no longer be
    /// messaged" banner instead of leaving the user retrying against a wall.
    private func sendDraft(_ match: Match) {
        let text = draft
        draft = ""
        if !isRemote {
            store.send(text, in: match)
            return
        }
        sending = true
        Task {
            let ok = await store.sendRemoteMessage(matchId: match.id, text: text, matching: matching)
            sending = false
            if !ok {
                draft = text
                if let last = matching.lastError, last.contains("can't be delivered") {
                    chatFrozen = "This match can no longer be messaged."
                }
            }
        }
    }

    /// Demo → mark booked free. Live → open Stripe hosted Checkout at the chosen
    /// tier; the completed payment is reflected on next foreground via
    /// `store.refreshReservations`.
    private func reserve(_ match: Match) {
        if store.demoMode { store.reserveDateDemo(match.id, amountCents: selectedTierCents); return }
        guard !reserving, let cents = selectedTierCents else { return }
        guard backend.isConsumablesConfigured else {
            store.toastFlash("Reservations need the web shop configured (Stripe Worker).")
            return
        }
        reserving = true
        Task {
            let result = await backend.reserveDateCheckout(matchID: match.id,
                                                           appAccountToken: store.appAccountToken,
                                                           amountCents: cents)
            reserving = false
            switch result {
            case .success(let url):
                if url.absoluteString == "about:blank" {
                    store.markDateReserved(match.id, amountCents: cents)   // already booked server-side
                } else {
                    openURL(url)                        // Stripe Checkout in Safari
                }
            case .failure(let message):
                store.toastFlash(message)
            }
        }
    }

    @ViewBuilder
    private func composer(_ match: Match) -> some View {
        VStack(spacing: 10) {
            switch match.phase {
            case _ where chatFrozen != nil:
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.slash.fill").font(.system(size: 13, weight: .bold))
                    Text(chatFrozen ?? "This match can no longer be messaged.")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            case .chatting where match.isExpired:
                HStack(spacing: 8) {
                    Image(systemName: "snowflake").font(.system(size: 13, weight: .bold))
                    Text("This match has gone cold. No replies land here anymore.")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            case .chatting:
                icebreakers(match)
                HStack(spacing: 10) {
                    TextField("", text: $draft,
                              prompt: Text("Message…").foregroundStyle(Theme.inkFaint), axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(Theme.ink)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Capsule().fill(.white.opacity(0.08)))
                    Button {
                        sendDraft(match)
                    } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.black).frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.goldGradient))
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                if !match.bid.onCopycat {
                    reserveCard(match)
                    GhostButton(title: "We went on the date", systemImage: "checkmark.circle") {
                        store.markDateDone(match, matching: matching)
                    }
                }
            case .dateDone:
                PrimaryButton(title: "Leave your review", systemImage: "star.fill",
                              gradient: store.role == .woman ? Theme.roseGradient : Theme.goldGradient) {
                    showReview = true
                }
            case .closed:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
                    Text("Reviews posted · lot closed")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
        .screenPadding().padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let otherName: String
    var onReact: (String) -> Void = { _ in }

    @State private var showReactionBar = false

    var body: some View {
        if message.isSystem {
            Text(message.text)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: message.fromMe ? .trailing : .leading, spacing: 2) {
                HStack {
                    if message.fromMe { Spacer(minLength: 50) }
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(message.fromMe ? .black : Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(message.fromMe ? AnyShapeStyle(Theme.goldGradient)
                                                     : AnyShapeStyle(Color.white.opacity(0.08)))
                        )
                        .overlay(alignment: message.fromMe ? .bottomLeading : .bottomTrailing) {
                            if let reaction = message.reaction {
                                Text(reaction).font(.system(size: 16))
                                    .padding(4).background(Circle().fill(Theme.bg))
                                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.6))
                                    .offset(x: message.fromMe ? -8 : 8, y: 8)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .onTapGesture(count: 2) {
                            Haptics.selection()
                            Motion.run(Motion.bouncy) { onReact("❤️") }
                        }
                        .onLongPressGesture {
                            Haptics.tap()
                            Motion.run(Motion.snap) { showReactionBar.toggle() }
                        }
                    if !message.fromMe { Spacer(minLength: 50) }
                }
                if showReactionBar { reactionBar }
            }
            .accessibilityLabel("\(message.fromMe ? "You" : otherName): \(message.text)\(message.reaction.map { ", reacted \($0)" } ?? "")")
        }
    }

    private var reactionBar: some View {
        HStack(spacing: 6) {
            if message.fromMe { Spacer(minLength: 50) }
            ForEach(["❤️", "😂", "😮", "👍", "🔥"], id: \.self) { emoji in
                Button {
                    Haptics.selection()
                    Motion.run(Motion.bouncy) { onReact(emoji); showReactionBar = false }
                } label: { Text(emoji).font(.system(size: 18)) }
                    .buttonStyle(.plain)
            }
            if !message.fromMe { Spacer(minLength: 50) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.08)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// The animated "…typing" bubble shown while the sim is composing a reply.
struct TypingBubble: View {
    @State private var bounce = false
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Theme.inkSoft).frame(width: 6, height: 6)
                        .offset(y: bounce ? -3 : 0)
                        .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                                  value: bounce)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08)))
            Spacer(minLength: 50)
        }
        .onAppear {
            guard !Motion.prefersReducedMotion else { return }
            bounce = true
        }
        .accessibilityLabel("Typing")
    }
}
