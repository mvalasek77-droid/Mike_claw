//
//  PayoutConfigView.swift
//  AI Marketplace
//
//  The creator's "get paid" screen. For non-admins this is plain-English,
//  one-decision-at-a-time: see the current step → tap the single button →
//  Safari handles the rest. Admins see additional dev/config UI.
//

import SwiftUI

struct PayoutConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MarketplaceStore
    @State private var workerURL: String = ""
    @State private var sharedSecret: String = ""
    @State private var saved = false
    @State private var showWhatYouNeed = false
    @State private var showDemoStripe = false

    /// What stage of onboarding the creator is in — drives which CTA shows.
    private enum Stage {
        case notStarted        // no Stripe account yet
        case incompleteFlow    // account exists; creator abandoned Stripe form
        case underReview       // form submitted; Stripe still verifying
        case ready             // payouts enabled
        case rejected          // Stripe declined the account
    }
    /// True when Stripe has set a real rejection reason (not a "needs more
    /// info" requirements list — those are recoverable via resume).
    private var isRejected: Bool {
        guard let r = store.payoutDisabledReason?.lowercased(), !r.isEmpty else { return false }
        return r.contains("rejected") || r.contains("listed") || r.contains("terms_of_service")
    }
    private var stage: Stage {
        if isRejected { return .rejected }
        if store.payoutConnected { return .ready }
        if store.connectAccountID != nil && store.payoutDetailsSubmitted { return .underReview }
        if store.connectAccountID != nil { return .incompleteFlow }
        return .notStarted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        hero
                        if store.isAdmin {
                            configFields
                        }
                        statusCard
                        if stage == .notStarted && !store.isAdmin {
                            whatYouNeedCard
                        }
                        actionCard
                        if let err = store.lastPayoutError {
                            errorCard(err)
                        }
                        if store.isAdmin {
                            saveButton
                        }
                    }
                    .screenPadding()
                }
            }
            .navigationTitle(store.isAdmin ? "Payout Setup" : "Get Paid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .sheet(isPresented: $showDemoStripe) { DemoStripeView() }
        }
        .onAppear {
            workerURL = store.payoutBaseURL
            sharedSecret = store.payoutSharedSecret
            // Refresh live status from Stripe whenever the screen opens, so
            // the creator sees the current state (especially after returning
            // from Stripe in Safari).
            if store.connectAccountID != nil && !store.payoutBaseURL.isEmpty {
                Task { await store.refreshPayoutStatus() }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.and.bolt.horizontal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.success)
            Text(heroTitle)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(heroBody)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var heroTitle: String {
        if store.isAdmin { return "Get paid for your titles" }
        switch stage {
        case .notStarted:     return "Get paid for your work"
        case .incompleteFlow: return "Pick up where you left off"
        case .underReview:    return "Almost there"
        case .ready:          return "You're all set"
        case .rejected:       return "Application declined"
        }
    }

    private var heroBody: String {
        if store.isAdmin {
            return "Admin: wire the Cloudflare Worker the app talks to. Creators won't see this card."
        }
        switch stage {
        case .notStarted:
            return "Connect your bank so we can send you money when people buy what you make. We use Stripe — a payments service trusted by millions of businesses. Your bank details go straight to Stripe; we never see them."
        case .incompleteFlow:
            return "You started signing up with Stripe but didn't finish. Tap the button below to pick up where you left off."
        case .underReview:
            return "Stripe is checking the info you sent. This usually takes a few minutes — sometimes up to 24 hours. You'll be ready to receive payouts as soon as they're done."
        case .ready:
            return "Your bank is connected. Your 85% share of every sale lands in your account automatically."
        case .rejected:
            let reason = store.payoutDisabledReason ?? ""
            return "Stripe declined your account application\(reason.isEmpty ? "" : " (\(reason))"). This usually means the identity or business info couldn't be verified. Contact support and we'll help you set up a fresh account."
        }
    }

    // MARK: - "What you'll need" (creator-facing prep)

    private var whatYouNeedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showWhatYouNeed.toggle() }
                Haptics.tap()
            } label: {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundStyle(Theme.accent)
                    Text("What you'll need (about 5 minutes)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: showWhatYouNeed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if showWhatYouNeed {
                VStack(alignment: .leading, spacing: 8) {
                    needItem("creditcard", "Your bank info", "Account and transit numbers (Canada) or routing and account numbers (US)")
                    needItem("person.text.rectangle", "A photo ID", "Driver's licence or passport — Stripe will ask you to take a picture")
                    needItem("number", "Tax info", "Last 4 of your SIN (Canada) or SSN (US). Stripe asks because the government requires it for payouts.")
                    Text("If you don't have all this handy, come back when you do. Nothing is saved if you bail.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.top, 4)
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    private func needItem(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    // MARK: - Status

    /// For non-admins: a single plain-English status line + visual progress.
    /// For admins: the technical row-by-row diagnostic.
    @ViewBuilder
    private var statusCard: some View {
        if store.isAdmin {
            GlassCard(title: "Status", icon: "checkmark.seal.fill", tint: store.payoutConnected ? Theme.success : Theme.inkSoft) {
                VStack(alignment: .leading, spacing: 8) {
                    statusRow("Worker configured", !store.payoutBaseURL.isEmpty)
                    statusRow("Secret set", !store.payoutSharedSecret.isEmpty)
                    statusRow("Stripe account created", store.connectAccountID != nil)
                    statusRow("Onboarding form submitted", store.payoutDetailsSubmitted)
                    statusRow("Payouts enabled", store.payoutConnected)
                    if let accountId = store.connectAccountID {
                        Text("Account: \(accountId)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        } else {
            simpleProgressCard
        }
    }

    /// Creator-facing progress: 3 numbered dots showing where they are in the
    /// flow — no jargon, no acronyms, no account IDs.
    private var simpleProgressCard: some View {
        let step: Int = {
            switch stage {
            case .notStarted:     return 0
            case .incompleteFlow: return 1
            case .underReview:    return 2
            case .ready:          return 3
            case .rejected:       return 0
            }
        }()
        return VStack(spacing: 14) {
            HStack(spacing: 0) {
                progressDot(label: "Tap connect",    index: 1, currentStep: step)
                progressLine(filled: step >= 1)
                progressDot(label: "Finish at Stripe", index: 2, currentStep: step)
                progressLine(filled: step >= 2)
                progressDot(label: "Ready",         index: 3, currentStep: step)
            }
            Text(simpleStatusLine)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(stage == .ready ? Theme.success : Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    private var simpleStatusLine: String {
        switch stage {
        case .notStarted:     return "You haven't set up payouts yet."
        case .incompleteFlow: return "You started but didn't finish."
        case .underReview:    return "Stripe is checking your info."
        case .ready:          return "All set — your bank is connected."
        case .rejected:       return "Stripe declined your account."
        }
    }

    private func progressDot(label: String, index: Int, currentStep: Int) -> some View {
        let done = index <= currentStep
        let active = index == currentStep + 1
        let color: Color = done ? Theme.success : (active ? Theme.accent : Theme.inkFaint)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(done ? 1 : 0.15))
                    .frame(width: 30, height: 30)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.black)
                } else {
                    Text("\(index)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(color)
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressLine(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? Theme.success : Theme.inkFaint.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)
    }

    // MARK: - Action

    @ViewBuilder
    private var actionCard: some View {
        switch stage {
        case .notStarted:
            if store.demoMode {
                PrimaryButton(title: "Demo: connect a fake bank",
                              systemImage: "building.columns.fill",
                              tint: Theme.success) {
                    showDemoStripe = true
                }
                Text("Demo mode: opens a local screen where you can type any numbers. No real Stripe call. No data is saved.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.center)
            } else {
                PrimaryButton(title: store.isGuest ? "Sign up to connect a bank" : "Connect my bank",
                              systemImage: store.isGuest ? "person.crop.circle.badge.plus" : "building.columns.fill",
                              tint: Theme.success,
                              enabled: !store.payoutBaseURL.isEmpty
                                    && !store.payoutSharedSecret.isEmpty) {
                    // Guest gate: Stripe Connect needs a real name + email
                    // for KYC; guests have neither. Drop them back to
                    // RegisterView so they can sign up — wallet credits
                    // and library carry over (signOut preserves them).
                    if store.isGuest { store.signOut(); return }
                    store.connectPayout()
                }
                Text(store.isGuest
                     ? "You're browsing as a guest. To get paid we need a publisher name and email."
                     : "Opens Stripe in your browser. Come back to the app when Stripe says you're done.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.center)
            }
        case .incompleteFlow:
            PrimaryButton(title: "Finish signing up",
                          systemImage: "arrow.up.right.square.fill",
                          tint: Theme.warning) {
                store.resumePayoutOnboarding()
            }
            Text("Stripe links expire after a few minutes, so we'll grab a fresh one for you.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        case .underReview:
            Label("Stripe is checking your info. Usually a few minutes; sometimes up to 24 hours.",
                  systemImage: "clock.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.10)))
            Button("Check now") {
                Task { await store.refreshPayoutStatus() }
                Haptics.tap()
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Capsule().stroke(Theme.accent, lineWidth: 1.5))
        case .ready:
            Label("Your 85% share of every sale will arrive in your bank automatically.",
                  systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.success)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.success.opacity(0.12)))
            // Show the Stripe account id (masked) + a way to actually OPEN
            // the Stripe dashboard. Without this the user had no proof the
            // setup was real — just a green checkmark.
            if let acct = store.connectAccountID, !acct.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "building.columns.fill").foregroundStyle(Theme.inkSoft)
                        Text("Connected to Stripe account ending in \(acct.suffix(4))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    PrimaryButton(title: "Open my Stripe dashboard",
                                  systemImage: "arrow.up.right.square",
                                  style: .ghost, tint: Theme.accent) {
                        store.resumePayoutOnboarding()
                    }
                    Text("Opens Stripe Express in your browser — verify your bank details, update tax info, see incoming transfers.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))
            }
            Text("Heads-up: payouts can take up to a month. Apple settles in-app purchases monthly, so a sale today may not reach your bank until the next Apple settlement.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        case .rejected:
            // Stripe declined the account — no retry path inside the app
            // because re-running onboarding hits Stripe's idempotency cache
            // and lands on the same rejected account. The creator needs
            // operator help to free their email for a fresh account.
            Label("Stripe declined this account. Contact support to set up a fresh one.",
                  systemImage: "xmark.octagon.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.warning.opacity(0.15)))
            if let reason = store.payoutDisabledReason {
                Text("Reason returned by Stripe: \(reason)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.center)
            }
            Text("Email mvalasek77@gmail.com with your account email and we'll reset it on our side. You'll be able to re-onboard with a fresh Stripe account afterward.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Admin-only

    private var configFields: some View {
        GlassCard(title: "Worker Config (admin)", icon: "server.rack", tint: Theme.accent) {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Worker URL")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                    TextField("https://your-worker.workers.dev", text: $workerURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shared Secret")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                    SecureField("Paste your APP_SHARED_SECRET", text: $sharedSecret)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    // MARK: - Helpers

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("Dismiss") { store.lastPayoutError = nil }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.10)))
    }

    private func statusRow(_ label: String, _ on: Bool) -> some View {
        HStack {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(on ? Theme.success : Theme.inkFaint)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }

    private var saveButton: some View {
        PrimaryButton(title: saved ? "Saved ✓" : "Save configuration",
                      systemImage: saved ? "checkmark" : "arrow.triangle.2.circlepath",
                      tint: Theme.success,
                      enabled: !saved) {
            store.payoutBaseURL = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            store.payoutSharedSecret = sharedSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            withAnimation { saved = true }
            Haptics.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saved = false
            }
        }
    }
}
