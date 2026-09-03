import SwiftUI
import UIKit

// MARK: - Step model

/// The submission journey has two honest phases, because Apple's own
/// process has two honest phases: TestFlight only needs an app record
/// and a processed build — no icon, no screenshots, no listing copy,
/// no pricing. Those are only required for the public App Store. This
/// used to be a single flat 10-step list that made a first-timer write
/// App Store copy before they could even run their app on a real
/// device; now testing comes first.
enum ASCPhase: String, CaseIterable {
    case testflight = "Part 1 — Get it on your phone"
    case appStore = "Part 2 — Put it on the App Store"

    var subtitle: String {
        switch self {
        case .testflight: "The least Apple needs before you and your friends can install the real app."
        case .appStore: "Only when you want strangers to be able to find and download it."
        }
    }
}

struct ASCStep: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    let phase: ASCPhase
    let title: String
    let body: String
    let action: ActionKind
    let safariRoute: String?

    enum ActionKind: Hashable {
        /// CodeGenie opens the URL in the paired Mac's Safari.
        case openSafariOnMac(String)
        /// CodeGenie actually performs the TestFlight upload itself.
        case uploadToTestFlight
        /// Tells the user exactly where to look for the install invite.
        case openTestFlightApp
        /// Explains internal vs. external testers and the public link.
        case inviteTesters
        /// CodeGenie types the listing fields into the open ASC page.
        case fillForm
        /// The user prepares an asset outside CodeGenie.
        case prepareAsset(String)
        /// Waiting on Apple.
        case wait(String)
        /// Only the account holder can do this.
        case manual
    }

    /// Who actually performs the work. Drives the Auto/Hybrid/You badge.
    var ownership: Ownership {
        switch action {
        case .openSafariOnMac, .fillForm, .uploadToTestFlight: return .hybrid
        case .prepareAsset, .openTestFlightApp, .inviteTesters, .manual: return .you
        case .wait: return .apple
        }
    }

    enum Ownership {
        case hybrid, you, apple

        var label: String {
            switch self {
            case .hybrid: "Hybrid"
            case .you:    "You"
            case .apple:  "Apple"
            }
        }

        var explanation: String {
            switch self {
            case .hybrid: "CodeGenie does the heavy lifting. You review and confirm."
            case .you:    "You do this — CodeGenie can't tap buttons in your Apple account."
            case .apple:  "Apple's servers do this. Nothing for you to do but wait."
            }
        }
    }
}

extension ASCStep {
    static let all: [ASCStep] = [
        // ---- Phase 1: Get it testable ----
        .init(number: 1, phase: .testflight,
              title: "Sign in to App Store Connect",
              body: "CodeGenie opens appstoreconnect.apple.com in your Mac's Safari. You sign in there — your password and 2-factor codes never touch CodeGenie.",
              action: .openSafariOnMac("https://appstoreconnect.apple.com"),
              safariRoute: "https://appstoreconnect.apple.com"),

        .init(number: 2, phase: .testflight,
              title: "Create the app record",
              body: "Click + → New App. Platform iOS, and the bundle ID must match your Xcode target exactly or the upload in the next step fails.",
              action: .openSafariOnMac("https://appstoreconnect.apple.com/apps"),
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 3, phase: .testflight,
              title: "Upload your build",
              body: "CodeGenie runs Apple's validate-then-upload flow itself. No listing, no screenshots, no pricing needed yet — just the app record from step 2 and a signed build.",
              action: .uploadToTestFlight,
              safariRoute: nil),

        .init(number: 4, phase: .testflight,
              title: "Wait for Apple to process it",
              body: "Usually 5–30 minutes. You'll see the status update here — no need to keep the app open.",
              action: .wait("Apple is processing your build"),
              safariRoute: nil),

        .init(number: 5, phase: .testflight,
              title: "Open TestFlight on your iPhone",
              body: "Apple emails the account holder an invite once the build finishes processing. Accept it, then TestFlight installs your real app.",
              action: .openTestFlightApp,
              safariRoute: nil),

        .init(number: 6, phase: .testflight,
              title: "Invite testers",
              body: "Internal testers (your ASC team, up to 100) get it instantly. External testers (up to 10,000, via a public link or email) need one quick automated Apple review the first time — usually under a day.",
              action: .inviteTesters,
              safariRoute: nil),

        // ---- Phase 2: Publish to the App Store ----
        .init(number: 7, phase: .appStore,
              title: "Prepare your 1024×1024 icon",
              body: "Exactly 1024×1024, PNG, no alpha channel, no pre-rounded corners. Apple rejects anything else without review.",
              action: .prepareAsset("icon-1024.png"),
              safariRoute: nil),

        .init(number: 8, phase: .appStore,
              title: "Prepare screenshots",
              body: "At least one iPhone display size. Screenshots showing placeholder or lorem-ipsum content are a common rejection reason.",
              action: .prepareAsset("screenshots"),
              safariRoute: nil),

        .init(number: 9, phase: .appStore,
              title: "Fill in the listing",
              body: "Name, subtitle, keywords, description and URLs. CodeGenie checks every field against Apple's length limits before you paste anything.",
              action: .fillForm,
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 10, phase: .appStore,
              title: "Answer the privacy questions",
              body: "Apple asks what data you collect. Answer honestly — this is audited, and a wrong answer here pulls a live app.",
              action: .manual,
              safariRoute: nil),

        .init(number: 11, phase: .appStore,
              title: "Set pricing and availability",
              body: "Free in all territories is the safe default. Price can change later without a new review.",
              action: .manual,
              safariRoute: nil),

        .init(number: 12, phase: .appStore,
              title: "Submit for review",
              body: "Pick the processed build, confirm export compliance and content rights, then press Submit. Apple requires the account holder to do this.",
              action: .manual,
              safariRoute: nil)
    ]

    static func steps(in phase: ASCPhase) -> [ASCStep] { all.filter { $0.phase == phase } }
}

// MARK: - Guide

struct AppStoreConnectGuideView: View {
    let job: BuildJob

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: AppSession
    @StateObject private var store = ASCSubmissionStore.shared
    @StateObject private var companion = CompanionBridge.shared
    @StateObject private var swarm = SwarmClient()

    @State private var metadata: AppStoreMetadata = .empty
    @State private var completed: Set<Int> = []
    @State private var current: Int = 1
    @State private var banner: Banner?
    @State private var showMetadataEditor = false
    @State private var showSubmitConfirm = false
    @State private var showTestFlightUploading = false
    @State private var testFlightErrorMessage: String?
    @State private var showTestFlightErrorAlert = false
    @State private var blockedGate: BlockedGate?
    @State private var didLoad = false
    /// Focus mode is the default: one step on screen at a time. This
    /// reveals the whole 12-step list only when the user asks for it,
    /// because seeing all twelve at once is what made this screen
    /// unreadable for a first-time submitter.
    @State private var showAllSteps = false
    @StateObject private var coachChat = ASCCoachChat()
    @State private var showCoachChat = false
    @State private var showChecklist = false

    /// AI-proactive pre-flight gate. Nothing runs the guide's steps
    /// until CodeGenie has actually checked the app — the user never
    /// has to remember to tap a "run checks" button, and a stale pass
    /// never carries over from a previous open.
    @State private var preflight: PreflightState = .checking
    @State private var readiness: ReleaseReadinessRun?

    enum PreflightState: Equatable {
        case checking
        case blocked(PerfectionRun?)
        case unverifiable(String)
        case clear
    }

    /// A blocking readiness sheet, scoped to whichever gate triggered
    /// it — the TestFlight upload gate (step 3) or the final App Store
    /// submit gate (step 12). Two different requirement sets, same UI;
    /// `kind` says which scoped helper to re-run on "Recheck now"
    /// rather than guessing from the item list.
    struct BlockedGate: Identifiable {
        enum Kind { case testflightUpload, appStoreSubmit }
        let id = UUID()
        let kind: Kind
        let title: String
        let items: [ReleaseReadinessItem]
    }

    private struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let tone: Tone
        enum Tone { case success, warning, info }
    }

    private var issues: [ASCCoach.Issue] { ASCCoach.validate(metadata) }
    private var blocking: [ASCCoach.Issue] { issues.filter { $0.severity == .blocking } }
    private var macPaired: Bool { companion.isConnected }

    /// The milestone moment: TestFlight phase finished, App Store phase
    /// not started. Worth calling out explicitly — a first-timer should
    /// know they already have a real, testable app and can stop here.
    private var justBecameTestable: Bool {
        ASCStep.steps(in: .testflight).allSatisfy { completed.contains($0.number) }
            && !ASCStep.steps(in: .appStore).contains { completed.contains($0.number) }
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                switch preflight {
                case .clear:
                    guideBody
                default:
                    preflightBody
                }
            }
        }
        .task { await loadAndRunPreflight() }
        .sheet(isPresented: $showMetadataEditor) {
            ASCMetadataEditor(metadata: $metadata, issues: issues)
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: metadata) { _, newValue in
            store.updateMetadata(newValue, for: job.id)
        }
        .alert("Did you press Submit in App Store Connect?", isPresented: $showSubmitConfirm) {
            Button("Not yet", role: .cancel) { }
            Button("Yes, I submitted") {
                store.markSubmitted(for: job.id)
                completed = Set(ASCStep.all.map(\.number))
                banner = Banner(text: "Submission recorded. Apple emails you when review finishes — usually 24–48 hours.", tone: .success)
                Haptics.success()
            }
        } message: {
            Text("Only mark this done once Apple has actually accepted the submission. We'll keep your record so you can come back to it.")
        }
        .alert("Couldn't upload", isPresented: $showTestFlightErrorAlert) {
            Button("OK") { testFlightErrorMessage = nil }
        } message: {
            Text(testFlightErrorMessage ?? "")
        }
        .sheet(isPresented: $showChecklist) {
            SubmissionChecklistView(
                jobID: job.id,
                appName: job.description.title,
                forAppStore: testflightDone,
                autoSatisfied: SubmissionChecklist.autoSatisfied(from: readiness),
                store: store
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showCoachChat) {
            ASCCoachChatView(
                chat: coachChat,
                step: allStepsDone ? nil : currentStep,
                appName: job.description.title,
                bundleID: defaultBundleID(for: job.description.title),
                completed: completed,
                macPaired: macPaired,
                blockingIssues: blocking.map { "\($0.message) \($0.fix)" },
                outstandingItems: (readiness?.items ?? [])
                    .filter { $0.required && $0.status != "automated" }
                    .map { "\($0.title): \($0.detail)" }
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $blockedGate) { gate in
            ASCReadinessBlockedSheet(
                title: gate.title,
                items: gate.items,
                onRecheck: { await recheckBlockedGate() }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: Load / persist

    private func loadAndRunPreflight() async {
        guard !didLoad else { return }
        didLoad = true
        let record = store.openOrCreate(for: job)
        metadata = record.metadata
        completed = record.completedSteps
        current = record.resumeStep
        if !record.completedSteps.isEmpty {
            banner = Banner(
                text: "Picked up where you left off — step \(record.resumeStep) of \(ASCStep.all.count).",
                tone: .info
            )
        }
        await runPreflight()
    }

    /// The mandatory, AI-run quality gate. Runs Perfection Mode's
    /// 10,000-probe static check — Apple Review risk, accessibility,
    /// performance, privacy/security, polish — fresh every time the
    /// guide opens. This is deliberately a hard gate: it costs no
    /// tokens (pure rules engine) and it is the one check that's
    /// achievable the instant the build finishes, before any App
    /// Store Connect asset exists. Nothing past this screen is
    /// reachable until it passes.
    private func runPreflight() async {
        preflight = .checking
        guard let backendID = session.backendJobIDs[job.id] else {
            preflight = .unverifiable("This build has no live backend job to check — CodeGenie can't verify it right now.")
            return
        }
        do {
            let run = try await swarm.runPerfection(jobID: backendID)
            store.recordPreflight(passed: run.isReady, score: run.score, for: job.id)
            if run.isReady {
                preflight = .clear
                banner = Banner(
                    text: "Pre-flight passed — \(Int(run.score))/100 on Apple's automated quality bar. Let's get this into your hands.",
                    tone: .success
                )
                await runReadinessCheck()
            } else {
                preflight = .blocked(run)
            }
        } catch {
            preflight = .unverifiable("Couldn't reach the backend to verify this build (\(error)).")
        }
    }

    /// Process-readiness (assets, credentials, IPA, GitHub). Runs in
    /// the background once pre-flight passes, and again on demand
    /// whenever a phase gate needs a fresh answer (step 3's upload,
    /// step 12's submit) — the two gates just read different subsets
    /// of the same result via `ASCCoach`'s scoped helpers.
    private func runReadinessCheck() async {
        guard let backendID = session.backendJobIDs[job.id] else { return }
        let cfg = ShipConfig.fromCredentials(bundleID: defaultBundleID(for: job.description.title))
        readiness = try? await swarm.runReleaseReadiness(jobID: backendID, ship: cfg)
    }

    private func defaultBundleID(for title: String) -> String {
        let slug = title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        return "com.codegenie.\(slug.isEmpty ? "app" : slug)"
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .padding(10).background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            .accessibilityLabel("Close submission guide")
            Spacer()
            VStack(spacing: 2) {
                Text("Submit \(job.description.title)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .lineLimit(1)
                Text("Progress saves automatically")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            }
            Spacer()
            Button {
                Haptics.selection()
                showCoachChat = true
            } label: {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(10)
                    .background(LiquidGlass.accent.opacity(0.22), in: Circle())
                    .overlay(Circle().strokeBorder(LiquidGlass.accent.opacity(0.4)))
                    .foregroundStyle(LiquidGlass.accent)
            }
            .accessibilityLabel("Ask the coach")
            .accessibilityHint("Ask any question about submitting to the App Store")
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    // MARK: Pre-flight screens

    @ViewBuilder
    private var preflightBody: some View {
        ScrollView {
            VStack(spacing: 18) {
                switch preflight {
                case .checking:
                    preflightCheckingCard
                case .blocked(let run):
                    preflightBlockedCard(run)
                case .unverifiable(let reason):
                    preflightUnverifiableCard(reason)
                case .clear:
                    EmptyView()
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var preflightCheckingCard: some View {
        GlassSurface(tier: .deep, corner: 22) {
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(LiquidGlass.accent)
                Text("Checking your app")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("I'm running Apple's real review checklist against your build — App Review risk, accessibility, performance, privacy, security, and polish. No tokens spent, this takes a few seconds.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your app against Apple's requirements. Please wait.")
    }

    private func preflightBlockedCard(_ run: PerfectionRun?) -> some View {
        VStack(spacing: 16) {
            GlassSurface(tier: .deep, corner: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(LiquidGlass.warning)
                            .accessibilityHidden(true)
                        Text("Not ready to submit yet")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                    }
                    Text(run != nil
                         ? "I checked your app and it scored \(Int(run!.score))/100 — below the bar Apple usually accepts. Here's exactly what to fix, worst first. Fixing these now is much faster than a rejection email in three days."
                         : "The check didn't return a usable result. Try again below.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }

            if let run {
                ForEach(run.findings.prefix(8)) { finding in
                    preflightFindingRow(finding)
                }
                if run.findings.count > 8 {
                    Text("+ \(run.findings.count - 8) more finding\(run.findings.count - 8 == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                }
            }

            PrimaryButton(title: "Recheck now", systemImage: "arrow.clockwise", style: .filled) {
                Task { await runPreflight() }
            }
            .accessibilityHint("Re-runs the pre-flight check after you've made fixes")
        }
    }

    private func preflightFindingRow(_ finding: PerfectionFinding) -> some View {
        let tint: Color = switch finding.severity {
        case "critical": LiquidGlass.error
        case "error": LiquidGlass.warning
        case "warning": LiquidGlass.accent
        default: LiquidGlass.primaryText.opacity(0.5)
        }
        return GlassSurface(tier: .raised, corner: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle().fill(tint).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(finding.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer(minLength: 0)
                    Text(finding.severity.capitalized)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(tint)
                        .background(tint.opacity(0.16), in: Capsule())
                }
                Text(finding.body)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                if let recommendation = finding.recommendation {
                    Text("Fix: \(recommendation)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.severity): \(finding.title). \(finding.body)\(finding.recommendation.map { " Fix: \($0)" } ?? "")")
    }

    private func preflightUnverifiableCard(_ reason: String) -> some View {
        VStack(spacing: 14) {
            GlassSurface(tier: .deep, corner: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                            .accessibilityHidden(true)
                        Text("Can't verify right now")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                    }
                    Text(reason)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            PrimaryButton(title: "Try again", systemImage: "arrow.clockwise", style: .filled) {
                Task { await runPreflight() }
            }
            Button {
                preflight = .clear
                banner = Banner(text: "Proceeding without verification — CodeGenie couldn't confirm this build meets Apple's requirements.", tone: .warning)
                Haptics.warning()
            } label: {
                Text("Continue without verification")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
            }
            .accessibilityHint("Not recommended — skips Apple's automated quality check")
        }
    }

    // MARK: Main guide

    /// Focus mode. The user sees exactly one step: what it is, the
    /// literal clicks, the thing that usually goes wrong, and one
    /// button. Everything already done collapses to a single line, and
    /// everything still to come is a count — not twelve open cards.
    private var guideBody: some View {
        VStack(spacing: 0) {
            phaseProgress
            ScrollView {
                VStack(spacing: 16) {
                    if let banner { bannerCard(banner) }
                    if allStepsDone {
                        finishedCard
                    } else {
                        if !completed.isEmpty { completedStrip }
                        focusCard
                        if currentStep.action == .fillForm { listingCard }
                        upNextStrip
                    }
                    if justBecameTestable { testableMilestoneCard }
                    checklistCard
                    macStatusCard
                    overviewToggle
                    if showAllSteps { overviewList }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var allStepsDone: Bool {
        completed.count >= ASCStep.all.count
    }

    private var currentStep: ASCStep {
        ASCStep.all.first { $0.number == current } ?? ASCStep.all[0]
    }

    private var currentWalkthrough: ASCCoach.Walkthrough {
        ASCCoach.walkthrough(
            for: currentStep,
            appName: job.description.title,
            bundleID: defaultBundleID(for: job.description.title),
            macPaired: macPaired
        )
    }

    // MARK: The one step you're on

    private var focusCard: some View {
        let step = currentStep
        let walk = currentWalkthrough
        return GlassSurface(tier: .deep, corner: 22) {
            VStack(alignment: .leading, spacing: 16) {
                // Where am I
                HStack(spacing: 8) {
                    Text("Step \(step.number) of \(ASCStep.all.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .textCase(.uppercase)
                        .tracking(1)
                    ownershipBadge(step)
                    Spacer(minLength: 0)
                    if !walk.timeEstimate.isEmpty {
                        Label(walk.timeEstimate, systemImage: "clock")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                            .labelStyle(.titleAndIcon)
                    }
                }

                Text(walk.plainTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(walk.whatThisIs)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !walk.doThis.isEmpty {
                    Divider().background(.white.opacity(0.1))
                    Text("Do this")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                        .textCase(.uppercase)
                        .tracking(1)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(walk.doThis.enumerated()), id: \.element.id) { pair in
                            instructionRow(index: pair.offset + 1, instruction: pair.element)
                        }
                    }
                }

                if let watchOut = walk.watchOut {
                    watchOutCard(watchOut)
                }

                actionRow(step)

                // The walkthrough covers the happy path. This is the
                // way out when the user is on a path it doesn't
                // describe, offered right where they get stuck rather
                // than buried in a menu.
                Button {
                    Haptics.selection()
                    showCoachChat = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Stuck on this step? Ask")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .opacity(0.5)
                    }
                    .foregroundStyle(LiquidGlass.accent)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(LiquidGlass.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LiquidGlass.accent.opacity(0.28)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stuck on this step? Ask the coach")

                // Users mis-tap, and they also revisit a finished step
                // from the overview list. Either way they need a way
                // back out of "done" without hunting for it.
                if completed.contains(step.number) {
                    Button {
                        store.markStepIncomplete(step.number, for: job.id)
                        completed.remove(step.number)
                        Haptics.selection()
                    } label: {
                        Text("Reopen this step")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityHint("Marks step \(step.number) as not done again")
                }
            }
            .padding(20)
        }
        .id(step.number)
    }

    private func instructionRow(index: Int, instruction: ASCCoach.Walkthrough.Instruction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(instruction.text)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let value = instruction.copyValue {
                    copyChip(value)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index). \(instruction.text)")
    }

    /// A literal value the user must get exactly right — bundle ID,
    /// app name. Showing it with a copy button removes the single
    /// biggest source of "why was my upload rejected": a typo.
    private func copyChip(_ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            banner = Banner(text: "Copied \(value)", tone: .success)
            Haptics.success()
        } label: {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(LiquidGlass.accent.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(value)")
        .accessibilityHint("Copies this exact value to your clipboard")
    }

    private func watchOutCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LiquidGlass.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Where people get stuck")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.warning)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(text)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LiquidGlass.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LiquidGlass.warning.opacity(0.28)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Where people get stuck: \(text)")
    }

    // MARK: Behind and ahead

    private var completedStrip: some View {
        Button {
            Haptics.selection()
            Motion.run(.spring(response: 0.35)) { showAllSteps = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LiquidGlass.success)
                    .accessibilityHidden(true)
                Text("\(completed.count) step\(completed.count == 1 ? "" : "s") done")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                Spacer()
                Text("Review")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(completed.count) steps done. Review them.")
    }

    private var upNextStrip: some View {
        let remaining = ASCStep.all.filter { $0.number > current && !completed.contains($0.number) }
        return Group {
            if let next = remaining.first {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.45))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("After this: \(next.title)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        if remaining.count > 1 {
                            Text("\(remaining.count - 1) more after that. Your progress saves as you go.")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var finishedCard: some View {
        GlassSurface(tier: .deep, corner: 22) {
            VStack(spacing: 12) {
                Text("🎉").font(.system(size: 40))
                Text("Submitted")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Every step is done. Apple emails you when review finishes, usually within 24 to 48 hours. If they ask for a change, it comes with the exact reason and you can fix it without rebuilding.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Submitted. Apple emails you when review finishes.")
    }

    // MARK: Full list, on request only

    private var overviewToggle: some View {
        Button {
            Haptics.selection()
            Motion.run(.spring(response: 0.35)) { showAllSteps.toggle() }
        } label: {
            Label(
                showAllSteps ? "Hide the full list" : "See all \(ASCStep.all.count) steps",
                systemImage: showAllSteps ? "chevron.up" : "chevron.down"
            )
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
        }
        .accessibilityHint("Shows every step in the submission, including ones you've finished")
    }

    private var overviewList: some View {
        VStack(spacing: 14) {
            ForEach(ASCPhase.allCases, id: \.self) { phase in
                phaseHeader(phase)
                ForEach(ASCStep.steps(in: phase)) { step in
                    overviewRow(step)
                }
            }
        }
    }

    private func overviewRow(_ step: ASCStep) -> some View {
        let isDone = completed.contains(step.number)
        let isCurrent = step.number == current
        return Button {
            Haptics.selection()
            Motion.run(.spring(response: 0.4)) {
                current = step.number
                showAllSteps = false
            }
        } label: {
            HStack(spacing: 12) {
                statusBadge(step, isDone: isDone, isCurrent: isCurrent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.system(size: 14, weight: isCurrent ? .bold : .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(isDone ? 0.6 : 1))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if isCurrent {
                        Text("You're here")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.35))
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(
                (isCurrent ? LiquidGlass.accent.opacity(0.12) : Color.white.opacity(0.04)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step.number). \(step.title). \(isDone ? "Done" : isCurrent ? "Current step" : "Not started")")
        .accessibilityHint("Jump to this step")
    }

    /// Two-segment progress instead of one flat bar — "testable" and
    /// "published" are different finish lines, and conflating them
    /// into "4 of 12" hides that the user is already at a real
    /// milestone once the first six are done.
    private var phaseProgress: some View {
        VStack(spacing: 6) {
            HStack {
                Text(testflightDone ? "Testable ✓" : "Phase 1 — Get it testable")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(testflightDone ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.7))
                Spacer()
                Text("\(completed.count) of \(ASCStep.all.count) complete")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)
            }
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    segment(proxy: proxy, phase: .testflight)
                    segment(proxy: proxy, phase: .appStore)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completed.count) of \(ASCStep.all.count) steps complete. \(testflightDone ? "Testable phase finished." : "Working on the testable phase.")")
    }

    private var testflightDone: Bool {
        ASCStep.steps(in: .testflight).allSatisfy { completed.contains($0.number) }
    }

    private func segment(proxy: GeometryProxy, phase: ASCPhase) -> some View {
        let steps = ASCStep.steps(in: phase)
        let done = steps.filter { completed.contains($0.number) }.count
        let width = proxy.size.width * (Double(steps.count) / Double(ASCStep.all.count)) - 1.5
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.1))
            Capsule().fill(phase == .testflight ? LiquidGlass.auroraGradient : LinearGradient(colors: [LiquidGlass.accentSecondary], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(0, width) * (Double(done) / Double(max(steps.count, 1))))
                .motion(.spring(response: 0.5), value: done)
        }
        .frame(width: max(0, width))
    }

    private func phaseHeader(_ phase: ASCPhase) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(phase.rawValue)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text(phase.subtitle)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, phase == .appStore ? 8 : 0)
        .accessibilityAddTraits(.isHeader)
    }

    private var testableMilestoneCard: some View {
        GlassSurface(tier: .deep, corner: 18) {
            HStack(spacing: 12) {
                Text("🎉").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your app is testable")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Anyone you invited can install it right now. The App Store steps below are only needed when you want it public.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
    }

    private func bannerCard(_ b: Banner) -> some View {
        let tint: Color = switch b.tone {
        case .success: LiquidGlass.success
        case .warning: LiquidGlass.warning
        case .info:    LiquidGlass.accent
        }
        return HStack(spacing: 10) {
            Image(systemName: b.tone == .success ? "checkmark.circle.fill"
                            : b.tone == .warning ? "exclamationmark.triangle.fill"
                            : "info.circle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(b.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { banner = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
            }
            .accessibilityLabel("Dismiss message")
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.3)))
    }

    // MARK: Listing (App Store phase only)

    private var listingCard: some View {
        GlassCard(title: "Your listing", icon: "doc.text.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 10) {
                validationSummary
                kv("Name", metadata.name, limit: ASCCoach.Limit.name)
                kv("Subtitle", metadata.subtitle, limit: ASCCoach.Limit.subtitle)
                kv("Keywords", ASCCoach.keywordString(metadata.keywords), limit: ASCCoach.Limit.keywordsTotal)
                kv("Category", metadata.primaryCategory, limit: nil)
                kv("Support URL", metadata.supportURL, limit: nil)
                kv("Price", metadata.price, limit: nil)

                HStack(spacing: 10) {
                    PrimaryButton(title: "Edit listing", systemImage: "pencil", style: .filled) {
                        showMetadataEditor = true
                    }
                    Button {
                        UIPasteboard.general.string = plainTextListing
                        banner = Banner(text: "Listing copied. Paste it field by field in App Store Connect.", tone: .success)
                        Haptics.success()
                    } label: {
                        Label("Copy all", systemImage: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                    }
                    .accessibilityLabel("Copy the whole listing to the clipboard")
                }
            }
        }
    }

    @ViewBuilder
    private var validationSummary: some View {
        if blocking.isEmpty && issues.isEmpty {
            label(icon: "checkmark.seal.fill", tint: LiquidGlass.success,
                  text: "Every field passes Apple's limits.")
        } else if blocking.isEmpty {
            label(icon: "checkmark.seal.fill", tint: LiquidGlass.success,
                  text: "No blockers. \(issues.count) optional improvement\(issues.count == 1 ? "" : "s") suggested.")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                label(icon: "exclamationmark.triangle.fill", tint: LiquidGlass.warning,
                      text: "\(blocking.count) problem\(blocking.count == 1 ? "" : "s") Apple will reject:")
                ForEach(blocking.prefix(3)) { issue in
                    Text("• \(issue.message)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.warning.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func label(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
                .font(.system(size: 13, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func kv(_ k: String, _ v: String, limit: Int?) -> some View {
        let over = limit.map { v.count > $0 } ?? false
        return HStack(alignment: .top, spacing: 12) {
            Text(k).frame(width: 92, alignment: .leading)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            Text(v.isEmpty ? "—" : v)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(v.isEmpty ? LiquidGlass.primaryText.opacity(0.4) : LiquidGlass.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let limit {
                Text("\(v.count)/\(limit)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(over ? LiquidGlass.warning : LiquidGlass.primaryText.opacity(0.45))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(k): \(v.isEmpty ? "empty" : v)\(limit.map { ", \(v.count) of \($0) characters" } ?? "")")
    }

    private var plainTextListing: String {
        """
        Name: \(metadata.name)
        Subtitle: \(metadata.subtitle)
        Category: \(metadata.primaryCategory)
        Keywords: \(ASCCoach.keywordString(metadata.keywords))
        Promotional text: \(metadata.promotionalText)
        Support URL: \(metadata.supportURL)
        Marketing URL: \(metadata.marketingURL)
        Age rating: \(metadata.ageRating)
        Price: \(metadata.price)

        Description:
        \(metadata.description)
        """
    }

    // MARK: Your own checklist

    /// The human half of readiness. CodeGenie's gates cover what a
    /// machine can prove; this covers what only the user knows, and
    /// it is where most first apps actually get rejected.
    private var checklistCard: some View {
        let scope = testflightDone
        let items = SubmissionChecklist.items(forAppStore: scope)
        let auto = SubmissionChecklist.autoSatisfied(from: readiness)
        let settled = store.checkedItems(for: job.id).union(auto)
        let done = items.filter { settled.contains($0.id) }.count
        let complete = done == items.count

        return Button {
            Haptics.selection()
            showChecklist = true
        } label: {
            GlassSurface(tier: .raised, corner: 18) {
                HStack(spacing: 12) {
                    Image(systemName: complete ? "checkmark.seal.fill" : "list.bullet.clipboard.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(complete ? LiquidGlass.success : LiquidGlass.warning)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill((complete ? LiquidGlass.success : LiquidGlass.warning).opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your submission checklist")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(complete
                             ? "All \(items.count) confirmed."
                             : "\(done) of \(items.count) confirmed — the things only you can check.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.4))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your submission checklist, \(done) of \(items.count) confirmed")
    }

    // MARK: Mac status

    private var macStatusCard: some View {
        GlassSurface(tier: .raised, corner: 16) {
            HStack(spacing: 12) {
                Image(systemName: macPaired ? "macbook.and.iphone" : "macbook.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(macPaired ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(macPaired ? "Mac connected" : "No Mac paired")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(macPaired
                         ? "CodeGenie can open App Store Connect and type your listing into it."
                         : "You can still do every step by hand on the phone — pairing a Mac just saves typing.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(macPaired ? "Mac connected" : "No Mac paired. Manual steps still available.")
    }

    private func statusBadge(_ step: ASCStep, isDone: Bool, isCurrent: Bool) -> some View {
        ZStack {
            Circle().fill(
                isDone ? LiquidGlass.success.opacity(0.25)
                : (isCurrent ? LiquidGlass.accent.opacity(0.25) : Color.white.opacity(0.08))
            )
            if isDone {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LiquidGlass.success)
            } else {
                Text("\(step.number)").font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private func ownershipBadge(_ step: ASCStep) -> some View {
        let tint: Color = switch step.ownership {
        case .hybrid: LiquidGlass.accent
        case .you:    LiquidGlass.warning
        case .apple:  LiquidGlass.success
        }
        return Text(step.ownership.label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
            .accessibilityLabel(step.ownership.explanation)
    }

    @ViewBuilder
    private func actionRow(_ step: ASCStep) -> some View {
        VStack(spacing: 10) {
            switch step.action {
            case .openSafariOnMac(let url):
                if macPaired {
                    PrimaryButton(title: "Open on my Mac", systemImage: "macbook", style: .filled) {
                        Task { await openOnMac(url, step: step) }
                    }
                    .accessibilityHint("Opens \(url) in your Mac's Safari")
                }
                PrimaryButton(
                    title: macPaired ? "Open here instead" : "Open in Safari",
                    systemImage: "safari",
                    style: macPaired ? .glass : .filled
                ) {
                    if let u = URL(string: url) { openURL(u) }
                    advance(step)
                }

            case .uploadToTestFlight:
                PrimaryButton(
                    title: showTestFlightUploading ? "Uploading..." : "Upload to TestFlight",
                    systemImage: "icloud.and.arrow.up.fill",
                    style: .filled
                ) {
                    Task { await uploadToTestFlight(step: step) }
                }
                .disabled(showTestFlightUploading)
                .accessibilityHint("CodeGenie validates and uploads the build to Apple")
                Text("CodeGenie checks your Apple credentials and the build itself first — if anything's missing, it'll tell you exactly what.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

            case .openTestFlightApp:
                PrimaryButton(title: "Open TestFlight", systemImage: "arrow.up.forward.app.fill", style: .filled) {
                    openTestFlight()
                }
                Text("Look for an email from Apple titled \"You're invited to test \(job.description.title)\" if it hasn't opened automatically.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                markDoneButton(step, title: "I installed it")

            case .inviteTesters:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Internal testers: add teammates in App Store Connect → TestFlight → Internal Testing. No review, instant access.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    Text("External testers: create a group, add emails or turn on the public link. First build needs a quick automated Apple review.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if macPaired {
                    PrimaryButton(title: "Open TestFlight tab on my Mac", systemImage: "macbook", style: .filled) {
                        Task { await openOnMac("https://appstoreconnect.apple.com/apps", step: step) }
                    }
                }
                PrimaryButton(
                    title: macPaired ? "Open here instead" : "Open in Safari",
                    systemImage: "safari",
                    style: macPaired ? .glass : .filled
                ) {
                    if let u = URL(string: "https://appstoreconnect.apple.com/apps") { openURL(u) }
                    advance(step)
                }
                markDoneButton(step, title: "I invited testers")

            case .fillForm:
                if macPaired {
                    PrimaryButton(
                        title: blocking.isEmpty ? "Type listing into my Mac" : "Fix listing first",
                        systemImage: blocking.isEmpty ? "wand.and.stars" : "exclamationmark.triangle.fill",
                        style: .filled
                    ) {
                        if blocking.isEmpty {
                            Task { await autofillListing(step: step) }
                        } else {
                            showMetadataEditor = true
                        }
                    }
                }
                PrimaryButton(title: "Copy listing to clipboard", systemImage: "doc.on.doc", style: macPaired ? .glass : .filled) {
                    UIPasteboard.general.string = plainTextListing
                    banner = Banner(text: "Copied. Paste each field into App Store Connect, then mark this done.", tone: .success)
                    Haptics.success()
                }
                markDoneButton(step, title: "I filled in the listing")

            case .prepareAsset(let asset):
                Text(asset == "screenshots"
                     ? "Take screenshots in the simulator, or use the preview CodeGenie recorded during the build."
                     : "Export a 1024×1024 PNG with no transparency.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
                markDoneButton(step, title: "I've got this ready")

            case .wait(let detail):
                HStack(spacing: 10) {
                    ProgressView().tint(LiquidGlass.primaryText)
                    Text(detail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    Spacer(minLength: 0)
                }
                markDoneButton(step, title: "Build finished processing")

            case .manual:
                if step.number == ASCStep.all.count {
                    PrimaryButton(title: "I submitted for review", systemImage: "paperplane.fill", style: .filled) {
                        Task { await attemptFinalSubmit() }
                    }
                } else {
                    markDoneButton(step, title: "I did this")
                }
            }
        }
    }

    private func markDoneButton(_ step: ASCStep, title: String) -> some View {
        PrimaryButton(title: title, systemImage: "checkmark.circle.fill", style: .glass) {
            advance(step)
        }
    }

    // MARK: Actions

    private func advance(_ step: ASCStep) {
        store.markStepComplete(step.number, for: job.id)
        completed.insert(step.number)
        Haptics.success()
        if let next = ASCStep.all.first(where: { $0.number > step.number }) {
            Motion.run(.spring(response: 0.4)) { current = next.number }
        }
    }

    private func openOnMac(_ url: String, step: ASCStep) async {
        do {
            try await companion.openSafari(url, newWindow: true)
            banner = Banner(text: "Opened on your Mac. Sign in there, then come back.", tone: .success)
            advance(step)
        } catch {
            banner = Banner(
                text: "Couldn't reach your Mac (\(error)). Use \"Open here instead\" — every step works on the phone too.",
                tone: .warning
            )
            Haptics.warning()
        }
    }

    /// The account holder's Apple TestFlight invite is delivered by
    /// email, and Apple doesn't publish a documented URL scheme for
    /// jumping straight to a specific app inside TestFlight — so this
    /// opens the TestFlight app itself if installed, and falls back to
    /// its App Store page (a stable, public app id) if not.
    private func openTestFlight() {
        guard let deepLink = URL(string: "itms-beta://") else { return }
        openURL(deepLink) { accepted in
            if !accepted, let storeURL = URL(string: "https://apps.apple.com/app/testflight/id899247664") {
                openURL(storeURL)
            }
        }
    }

    /// Type every listing field into the Mac's open App Store Connect
    /// tab. The Mac shows an Approve dialog per field, so the user
    /// sees and authorises each write.
    private func autofillListing(step: ASCStep) async {
        let fields: [(String, String)] = [
            ("name", metadata.name),
            ("subtitle", metadata.subtitle),
            ("keywords", ASCCoach.keywordString(metadata.keywords)),
            ("description", metadata.description),
            ("promotionalText", metadata.promotionalText),
            ("supportURL", metadata.supportURL),
        ].filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var filled = 0
        var rejected = 0
        var failures: [String] = []

        for (field, value) in fields {
            do {
                let ok = try await companion.fillASCField(field: field, value: value)
                if ok { filled += 1 } else { rejected += 1 }
            } catch {
                failures.append(field)
            }
        }

        if filled == fields.count {
            banner = Banner(text: "Typed all \(filled) fields into App Store Connect. Check them, then press Save on your Mac.", tone: .success)
            Haptics.success()
            advance(step)
        } else if filled > 0 {
            banner = Banner(
                text: "Filled \(filled) of \(fields.count) fields."
                    + (rejected > 0 ? " You declined \(rejected)." : "")
                    + (failures.isEmpty ? "" : " Couldn't find: \(failures.joined(separator: ", ")) — fill those by hand."),
                tone: .warning
            )
            Haptics.warning()
        } else {
            banner = Banner(
                text: "Nothing was filled. Make sure Safari is on your app's App Store Connect page, or use Copy listing instead.",
                tone: .warning
            )
            Haptics.error()
        }
    }

    /// The first hard process gate: CodeGenie won't attempt the actual
    /// TestFlight upload against Apple's servers until the narrow set
    /// of things an upload truly needs — a build, Apple credentials,
    /// and the privacy manifest — are in place. Rechecks live rather
    /// than trusting whatever the pre-flight pass found minutes ago.
    private func uploadToTestFlight(step: ASCStep) async {
        showTestFlightUploading = true
        defer { showTestFlightUploading = false }

        guard let backendID = session.backendJobIDs[job.id] else {
            testFlightErrorMessage = "This build has no live backend job to upload — CodeGenie can't reach Apple's servers for it."
            showTestFlightErrorAlert = true
            return
        }

        await runReadinessCheck()
        let outstanding = ASCCoach.outstandingForTestFlightUpload(readiness)
        guard outstanding.isEmpty else {
            blockedGate = BlockedGate(kind: .testflightUpload, title: "Not ready to upload yet", items: outstanding)
            Haptics.warning()
            return
        }

        guard let cfg = ShipConfig.fromCredentials(bundleID: defaultBundleID(for: job.description.title)) else {
            testFlightErrorMessage = "Missing Apple Developer credentials. Add them in Settings, then try again."
            showTestFlightErrorAlert = true
            return
        }
        do {
            try await swarm.ship(jobID: backendID, config: cfg)
            banner = Banner(text: "Uploaded. Apple is validating and processing it now.", tone: .success)
            Haptics.success()
            advance(step)
        } catch {
            testFlightErrorMessage = "\(error)"
            showTestFlightErrorAlert = true
            Haptics.error()
        }
    }

    /// The second hard gate, at the very end: re-verifies the full
    /// App Store checklist (icon, screenshots, listing, privacy
    /// policy, GitHub backup) immediately before letting the user say
    /// they pressed Submit — rather than trusting a self-report that
    /// might already be stale.
    private func attemptFinalSubmit() async {
        await runReadinessCheck()

        // The user's own attestations gate this too. CodeGenie can
        // prove a binary is signed; it cannot prove the app runs, that
        // the screenshots are real, or that the privacy answers are
        // true — and those are what Apple actually rejects for.
        let outstandingChecklist = SubmissionChecklist.outstanding(
            checked: store.checkedItems(for: job.id),
            autoSatisfied: SubmissionChecklist.autoSatisfied(from: readiness),
            forAppStore: true
        )
        guard outstandingChecklist.isEmpty else {
            banner = Banner(
                text: "\(outstandingChecklist.count) thing\(outstandingChecklist.count == 1 ? "" : "s") on your checklist still need confirming. These are the ones Apple rejects for.",
                tone: .warning
            )
            showChecklist = true
            Haptics.warning()
            return
        }

        if ASCCoach.isReadyForAppStoreSubmission(readiness) {
            showSubmitConfirm = true
        } else {
            blockedGate = BlockedGate(
                kind: .appStoreSubmit,
                title: "A few things are still missing",
                items: ASCCoach.outstandingForAppStoreSubmission(readiness)
            )
            Haptics.warning()
        }
    }

    /// Re-runs the readiness check and refreshes (or clears) whichever
    /// gate is currently open, using the gate's own `kind` rather than
    /// inferring it from the item list — the two scopes can otherwise
    /// overlap (e.g. a missing IPA blocks both).
    private func recheckBlockedGate() async {
        await runReadinessCheck()
        guard let gate = blockedGate else { return }
        let refreshed = gate.kind == .testflightUpload
            ? ASCCoach.outstandingForTestFlightUpload(readiness)
            : ASCCoach.outstandingForAppStoreSubmission(readiness)
        blockedGate = refreshed.isEmpty ? nil : BlockedGate(kind: gate.kind, title: gate.title, items: refreshed)
    }
}

// MARK: - Blocked-gate sheet

/// Shared by both hard gates (TestFlight upload and final App Store
/// submit). Enumerates exactly what's missing using the same
/// plain-English detail/action text the backend's readiness audit
/// already writes — no separate copy to keep in sync. Takes a plain
/// snapshot of items rather than reaching into shared state, so a
/// recheck's result is whatever the caller hands it next, not a stale
/// capture from when the sheet opened.
private struct ASCReadinessBlockedSheet: View {
    let title: String
    let items: [ReleaseReadinessItem]
    let onRecheck: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rechecking = false

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Here's exactly what's left:")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        ForEach(items) { item in
                            GlassSurface(tier: .raised, corner: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText)
                                    Text(item.detail)
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("Do this: \(item.action)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(LiquidGlass.accent)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(12)
                            }
                        }
                        PrimaryButton(
                            title: rechecking ? "Checking..." : "Recheck now",
                            systemImage: "arrow.clockwise",
                            style: .filled
                        ) {
                            Task {
                                rechecking = true
                                await onRecheck()
                                rechecking = false
                            }
                        }
                        .disabled(rechecking)
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Metadata editor

/// Editable listing form with live character budgets. Every limit here
/// is Apple's real server-side cap, so the counter turning red means
/// the field genuinely will not save.
private struct ASCMetadataEditor: View {
    @Binding var metadata: AppStoreMetadata
    let issues: [ASCCoach.Issue]

    @Environment(\.dismiss) private var dismiss
    @State private var keywordsText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if !issues.isEmpty { issuesCard }
                        field("App name", text: $metadata.name, limit: ASCCoach.Limit.name,
                              hint: "Shows under your icon on the Home Screen.")
                        field("Subtitle", text: $metadata.subtitle, limit: ASCCoach.Limit.subtitle,
                              hint: "One line under your name in search results.")
                        keywordsField
                        multilineField("Description", text: $metadata.description,
                                       limit: ASCCoach.Limit.description,
                                       hint: "What the app does and who it's for. Reviewers read this.")
                        multilineField("Promotional text", text: $metadata.promotionalText,
                                       limit: ASCCoach.Limit.promotionalText,
                                       hint: "Changeable any time without a new review.")
                        field("Support URL", text: $metadata.supportURL, limit: nil,
                              hint: "Required. A page where users can reach you.")
                        field("Marketing URL", text: $metadata.marketingURL, limit: nil,
                              hint: "Optional. Leave empty rather than fake.")
                        field("Category", text: $metadata.primaryCategory, limit: nil, hint: nil)
                        field("Price", text: $metadata.price, limit: nil, hint: nil)
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitKeywords()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { keywordsText = ASCCoach.keywordString(metadata.keywords) }
    }

    private var issuesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: issue.severity == .blocking
                          ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(issue.severity == .blocking ? LiquidGlass.warning : LiquidGlass.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.message)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(issue.fix)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private func field(_ label: String, text: Binding<String>, limit: Int?, hint: String?) -> some View {
        GlassSurface(tier: .flat, corner: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header(label, count: text.wrappedValue.count, limit: limit)
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .autocorrectionDisabled(label.contains("URL"))
                    .textInputAutocapitalization(label.contains("URL") ? .never : .sentences)
                    .accessibilityLabel(label)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                }
            }
            .padding(12)
        }
    }

    private func multilineField(_ label: String, text: Binding<String>, limit: Int, hint: String?) -> some View {
        GlassSurface(tier: .flat, corner: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header(label, count: text.wrappedValue.count, limit: limit)
                TextEditor(text: text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .accessibilityLabel(label)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                }
            }
            .padding(12)
        }
    }

    private var keywordsField: some View {
        GlassSurface(tier: .flat, corner: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header("Keywords", count: keywordsText.count, limit: ASCCoach.Limit.keywordsTotal)
                TextField("habit,tracker,streak", text: $keywordsText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: keywordsText) { _, _ in commitKeywords() }
                    .accessibilityLabel("Keywords, comma separated")
                Text("One comma-separated list. Apple counts the whole thing — commas included — against \(ASCCoach.Limit.keywordsTotal) characters.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    private func header(_ label: String, count: Int, limit: Int?) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                .tracking(0.8)
            Spacer()
            if let limit {
                Text("\(count)/\(limit)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(count > limit ? LiquidGlass.warning : LiquidGlass.primaryText.opacity(0.45))
            }
        }
    }

    private func commitKeywords() {
        metadata.keywords = keywordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Drafting

extension AppStoreMetadata {
    static let empty = AppStoreMetadata(
        name: "", subtitle: "", primaryCategory: "", keywords: [],
        description: "", promotionalText: "", supportURL: "",
        marketingURL: "", ageRating: "4+", price: "Free"
    )

    static func draft(for app: AppDescription) -> AppStoreMetadata {
        let featureWords = app.features
            .flatMap { $0.split { !$0.isLetter && !$0.isNumber } }
            .map { String($0).lowercased() }
        let promptWords = app.prompt
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
            .filter { $0.count > 3 }

        // Keywords is a single 100-char field, so build up to the cap
        // instead of taking a fixed count and blowing the limit.
        var keywords: [String] = []
        var budget = ASCCoach.Limit.keywordsTotal
        for word in (featureWords + promptWords + [app.category.rawValue])
            .map({ $0.replacingOccurrences(of: " ", with: "") })
            .filter({ !$0.isEmpty })
            .uniqued() {
            let cost = word.count + (keywords.isEmpty ? 0 : 1)
            guard budget - cost >= 0 else { continue }
            keywords.append(word)
            budget -= cost
        }

        return AppStoreMetadata(
            name: String(app.title.prefix(ASCCoach.Limit.name)),
            subtitle: String(app.subtitleDraft.prefix(ASCCoach.Limit.subtitle)),
            primaryCategory: app.category.label,
            keywords: keywords.isEmpty ? [app.category.rawValue] : keywords,
            description: String(app.descriptionDraft.prefix(ASCCoach.Limit.description)),
            promotionalText: "",
            // Deliberately empty rather than example.com — a placeholder
            // URL passes a naive check and then fails Apple's review.
            // The coach flags empty as blocking so the user supplies a
            // real one.
            supportURL: "",
            marketingURL: "",
            ageRating: "4+",
            price: "Free"
        )
    }
}

private extension AppDescription {
    var subtitleDraft: String {
        if let first = features.first, !first.isEmpty {
            return String(first.prefix(30))
        }
        return switch category {
        case .utility: "Fast, focused everyday help"
        case .productivity: "Plan, build, and finish faster"
        case .lifestyle: "A calmer daily ritual"
        case .finance: "Money clarity at a glance"
        case .social: "Share what matters now"
        case .health: "Healthier habits, gently"
        case .education: "Learn with less friction"
        case .games: "Playful moments, polished"
        case .photo: "Create standout visuals"
        }
    }

    var descriptionDraft: String {
        let base = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = "\(title)\n\n\(base)"
        if !features.isEmpty {
            out += "\n\nWhat's inside:\n"
            out += features.map { "• \($0)" }.joined(separator: "\n")
        }
        return out
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
