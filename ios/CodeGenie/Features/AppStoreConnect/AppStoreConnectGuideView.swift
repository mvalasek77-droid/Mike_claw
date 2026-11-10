import SwiftUI
import UIKit

// MARK: - Guide

struct AppStoreConnectGuideView: View {
    let job: BuildJob

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: AppSession
    @StateObject private var store = ASCSubmissionStore.shared
    @StateObject private var companion = CompanionBridge.shared
    @StateObject private var swarm = SwarmClient()
    /// Asks Apple directly, because the key that signs those requests
    /// stays on this phone and the backend has no copy to poll with.
    @StateObject private var statusPoller = ASCStatusPoller()

    @State private var metadata: AppStoreMetadata = .empty
    @State private var completed: Set<Int> = []
    @State private var current: Int = 1
    @State private var banner: Banner?
    @State private var showMetadataEditor = false
    @State private var showSubmitConfirm = false
    @State private var showTestFlightUploading = false
    /// Newest line from Apple's toolchain while packaging and
    /// uploading run, so a multi-minute wait doesn't look frozen.
    @State private var uploadStatusLine: String?
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
    /// Mirrors the store so the review panel re-renders on every
    /// status change without reaching into the singleton mid-body.
    @State private var record: ASCSubmissionRecord?

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
        .task(id: pollKey) { await pollWhileWaiting() }
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
                syncFromStore(jumpToResume: true)
                banner = Banner(text: "Submitted. CodeGenie follows the review with you from here.", tone: .success)
                Haptics.success()
            }
        } message: {
            Text("Only say yes once the status in App Store Connect reads Waiting for Review. Add for Review on its own doesn't send anything.")
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
                blockingIssues: blocking.map { "\($0.message) \($0.fix)" } + reviewContextForCoach,
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
        let saved = store.openOrCreate(for: job)
        record = saved
        metadata = saved.metadata
        completed = saved.completedSteps
        current = saved.resumeStep
        if saved.isSubmitted {
            // The build is already with Apple. Re-running the quality
            // gate now could only block the user from reading the
            // outcome of a review that has already started.
            preflight = .clear
            await runReadinessCheck()
            return
        }
        if !saved.completedSteps.isEmpty {
            banner = Banner(
                text: "Picked up where you left off — step \(saved.resumeStep) of \(ASCStep.all.count).",
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

    /// Single source of truth — see `AppBundleID`. Derived here and in
    /// the build screen independently, this used to disagree with the
    /// identifier the project was actually signed with.
    private func defaultBundleID(for title: String) -> String {
        AppBundleID.make(title: title)
    }

    /// Re-read the saved record after anything that can move steps on
    /// its own — a review status, a submission, a resubmission.
    private func syncFromStore(jumpToResume: Bool) {
        guard let saved = store.record(for: job.id) else { return }
        record = saved
        completed = saved.completedSteps
        if jumpToResume {
            Motion.run(.spring(response: 0.4)) { current = saved.resumeStep }
        }
    }

    private var reviewContextForCoach: [String] {
        guard let review = record?.review, record?.isSubmitted == true else { return [] }
        var line = "App Review status: \(review.state.appleLabel)."
        if let guideline = review.rejectionGuideline {
            line += " Rejected under guideline \(guideline)."
        }
        return [line]
    }

    // MARK: Waiting on Apple

    /// Changes whenever what we're waiting for changes, which restarts
    /// the polling task; leaving the screen cancels it.
    private var pollKey: String {
        guard preflight == .clear else { return "idle" }
        switch currentStep.action {
        case .wait:
            return "build-\(current)"
        case .review:
            let state = record?.review?.state ?? .waitingForReview
            return state.isWaitingOnApple ? "review-\(state.rawValue)" : "idle"
        default:
            return "idle"
        }
    }

    /// Ask Apple periodically while the user is parked on a wait, so
    /// the screen moves on by itself. Minutes apart, not seconds: the
    /// answer changes on Apple's timescale and a tight loop only costs
    /// battery.
    private func pollWhileWaiting() async {
        let key = pollKey
        guard key != "idle", ASCStatusPoller.canAskApple() else { return }
        let isBuild = key.hasPrefix("build")
        let interval: UInt64 = isBuild ? 60 : 300
        while !Task.isCancelled {
            if isBuild {
                await checkBuildStatus(announce: false)
                if statusPoller.status?.isFinished == true { return }
            } else {
                await checkReviewStatus(announce: false)
            }
            try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
        }
    }

    private func checkBuildStatus(announce: Bool) async {
        guard case .wait = currentStep.action else { return }
        let step = currentStep
        await statusPoller.check(bundleID: defaultBundleID(for: job.description.title))
        // Only VALID means the build is installable; the other
        // finished states mean stop waiting and go read Apple's email.
        if statusPoller.status?.state == "VALID" {
            if !announce {
                banner = Banner(text: "Apple finished processing your build.", tone: .success)
            }
            advance(step)
        }
    }

    private func checkReviewStatus(announce: Bool) async {
        guard let version = await statusPoller.checkReview(
            bundleID: defaultBundleID(for: job.description.title)
        ) else {
            if announce { Haptics.warning() }
            return
        }
        applyReview(version.state, version: version.versionString, announce: announce)
    }

    /// One path for a status from Apple and one the user reports by
    /// hand, so both tick the same steps and say the same things.
    private func applyReview(_ state: ASCReviewState, version: String?, announce: Bool) {
        let changed = store.applyReview(state, version: version, for: job.id)
        syncFromStore(jumpToResume: changed)
        guard changed || announce else { return }
        if changed {
            let tone: Banner.Tone = switch state.tone {
            case .good: .success
            case .problem, .action: .warning
            case .waiting: .info
            }
            banner = Banner(text: "Apple's status is now \(state.appleLabel).", tone: tone)
            switch state.tone {
            case .good: Haptics.success()
            case .problem: Haptics.warning()
            default: Haptics.selection()
            }
        } else {
            banner = Banner(text: "No change — still \(state.appleLabel).", tone: .info)
            Haptics.selection()
        }
    }

    private func openAppStoreConnect() {
        let address = "https://appstoreconnect.apple.com/apps"
        if macPaired {
            Task {
                do {
                    try await companion.openSafari(address, newWindow: true)
                    banner = Banner(text: "Opened on your Mac.", tone: .success)
                } catch {
                    if let url = URL(string: address) { openURL(url) }
                }
            }
        } else if let url = URL(string: address) {
            openURL(url)
        }
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
                        stepWorkArea
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

    /// The step's own working surface, when it has one beyond buttons.
    @ViewBuilder
    private var stepWorkArea: some View {
        switch currentStep.action {
        case .fillForm:
            listingCard
        case .reviewNotes:
            ASCReviewNotesCard(
                metadata: $metadata,
                appName: job.description.title,
                summary: job.description.prompt,
                features: job.description.features,
                onCopied: { banner = Banner(text: $0, tone: .success) }
            )
        case .review:
            if let record, record.isSubmitted {
                reviewPanel(record)
            } else {
                notSubmittedYetCard
            }
        default:
            EmptyView()
        }
    }

    /// Shown when someone jumps ahead to a review step from the full
    /// list. Offering status controls for a review that hasn't started
    /// would only invite them to record something untrue.
    private var notSubmittedYetCard: some View {
        let resume = record?.resumeStep ?? 1
        return GlassSurface(tier: .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nothing to track yet")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Review starts once you've submitted in step \(ASCStep.submitStepNumber). This part of the guide fills in by itself after that.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Back to step \(resume)", systemImage: "arrow.uturn.backward", style: .glass) {
                    Motion.run(.spring(response: 0.4)) { current = resume }
                }
            }
            .padding(16)
        }
    }

    private func reviewPanel(_ record: ASCSubmissionRecord) -> some View {
        ASCReviewPanel(
            record: record,
            canAskApple: ASCStatusPoller.canAskApple(),
            isChecking: statusPoller.isCheckingReview,
            errorText: statusPoller.reviewError,
            onCheck: { Task { await checkReviewStatus(announce: true) } },
            onReport: { applyReview($0, version: nil, announce: true) },
            onPickGuideline: { guideline in
                store.noteRejectionGuideline(guideline, for: job.id)
                syncFromStore(jumpToResume: false)
            },
            onResubmitted: {
                store.markResubmitted(for: job.id)
                syncFromStore(jumpToResume: true)
                banner = Banner(text: "Back in the queue. Resubmissions are usually looked at faster than the first time.", tone: .success)
                Haptics.success()
            },
            onUploadNewBuild: {
                store.markStepIncomplete(3, for: job.id)
                store.markStepIncomplete(4, for: job.id)
                syncFromStore(jumpToResume: false)
                Motion.run(.spring(response: 0.4)) { current = 3 }
                banner = Banner(text: "Upload the fixed build here, then attach it in step 14 and resubmit.", tone: .info)
            },
            onOpenAppStoreConnect: { openAppStoreConnect() },
            onCopied: { banner = Banner(text: $0, tone: .success) }
        )
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

                // Step 2 is where the bundle ID gets registered with
                // Apple for good. Saying this afterwards is too late.
                if step.number == 2, AppBundleID.usesFallbackPrefix() {
                    watchOutCard("You haven't set your own app ID prefix, so this uses CodeGenie's shared one. Bundle IDs are unique across the entire App Store — if someone else already registered this exact ID, Apple will refuse yours. Set a prefix of your own in Settings, Apple Developer.")
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
                if completed.contains(step.number), step.phase != .review {
                    Button {
                        store.markStepIncomplete(step.number, for: job.id)
                        completed.remove(step.number)
                        record = store.record(for: job.id)
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
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(LiquidGlass.success)
                    .accessibilityHidden(true)
                Text("\(job.description.title) is live")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .multilineTextAlignment(.center)
                Text("It passed review and it's on the App Store. Search can take a few hours to catch up; the link in App Store Connect works straight away. When you ship an update, the same steps apply from the upload onwards.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.description.title) is live on the App Store.")
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

    /// One segment per phase instead of one flat bar — "testable",
    /// "submitted" and "live" are different finish lines, and a bare
    /// "4 of 18" hides that the user is already at a real milestone
    /// once the first six are done.
    private var phaseProgress: some View {
        VStack(spacing: 6) {
            HStack {
                Text(phaseHeadline)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(testflightDone ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.7))
                Spacer()
                Text("\(completed.count) of \(ASCStep.all.count) complete")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)
            }
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(ASCPhase.allCases, id: \.self) { phase in
                        segment(proxy: proxy, phase: phase)
                    }
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completed.count) of \(ASCStep.all.count) steps complete. \(phaseHeadline).")
    }

    private var currentPhase: ASCPhase {
        ASCPhase.allCases.first { phase in
            !ASCStep.steps(in: phase).allSatisfy { completed.contains($0.number) }
        } ?? .review
    }

    private var phaseHeadline: String {
        if allStepsDone { return "Live on the App Store" }
        switch currentPhase {
        case .testflight: return "Part 1 of 3 — \(ASCPhase.testflight.shortLabel)"
        case .appStore:   return "Testable ✓ · Part 2 of 3 — \(ASCPhase.appStore.shortLabel)"
        case .review:     return "Submitted ✓ · Part 3 of 3 — \(ASCPhase.review.shortLabel)"
        }
    }

    private var testflightDone: Bool {
        ASCStep.steps(in: .testflight).allSatisfy { completed.contains($0.number) }
    }

    private func segment(proxy: GeometryProxy, phase: ASCPhase) -> some View {
        let steps = ASCStep.steps(in: phase)
        let done = steps.filter { completed.contains($0.number) }.count
        let width = proxy.size.width * (Double(steps.count) / Double(ASCStep.all.count)) - 2
        let fill: Color = switch phase {
        case .testflight: LiquidGlass.accent
        case .appStore:   LiquidGlass.accentSecondary
        case .review:     LiquidGlass.success
        }
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.1))
            Capsule().fill(fill)
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
        .padding(.top, phase == .testflight ? 0 : 8)
        .accessibilityAddTraits(.isHeader)
    }

    private var testableMilestoneCard: some View {
        GlassSurface(tier: .deep, corner: 18) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3.badge.play")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LiquidGlass.success)
                    .accessibilityHidden(true)
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
                kv("Privacy policy", metadata.privacyPolicyURL ?? "", limit: nil)
                kv("Copyright", metadata.copyright ?? "", limit: nil)
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
        Privacy policy URL: \(metadata.privacyPolicyURL ?? "")
        Marketing URL: \(metadata.marketingURL)
        Copyright: \(metadata.copyright ?? "")
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
                if showTestFlightUploading, let line = uploadStatusLine {
                    Text(line)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Latest step: \(line)")
                } else {
                    Text("CodeGenie packages and signs your app, then uploads it. This takes a few minutes — it'll tell you exactly what happened either way.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                // This used to be a spinner that never changed, on a
                // wait that genuinely runs for hours. Now it asks Apple.
                HStack(spacing: 10) {
                    if statusPoller.isChecking {
                        ProgressView().tint(LiquidGlass.primaryText)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(statusTint)
                    }
                    Text(statusPoller.status?.summary ?? detail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if let line = buildIdentityLine {
                    Text(line)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let problem = statusPoller.lastError {
                    Text(problem)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PrimaryButton(
                    title: statusCheckTitle,
                    systemImage: "arrow.clockwise",
                    style: .filled
                ) {
                    Task { await checkBuildStatus(announce: true) }
                }
                .disabled(statusPoller.isChecking)
                markDoneButton(step, title: "Build finished processing")

            case .manual:
                PrimaryButton(
                    title: macPaired ? "Open App Store Connect on my Mac" : "Open App Store Connect",
                    systemImage: macPaired ? "macbook" : "safari",
                    style: .filled
                ) { openAppStoreConnect() }
                markDoneButton(step, title: "I did this")

            case .reviewNotes:
                if blocking.contains(where: { $0.field == .reviewNotes }) {
                    Text("Your app has a sign-in, so the notes must tell the reviewer how to get in.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                markDoneButton(step, title: "I added this in App Store Connect")

            case .submit:
                PrimaryButton(title: "I submitted for review", systemImage: "paperplane.fill", style: .filled) {
                    Task { await attemptFinalSubmit() }
                }
                .accessibilityHint("CodeGenie checks nothing is missing first, then tracks the review")

            case .review:
                // The status panel below carries the controls. A review
                // step is never ticked by hand — it follows Apple.
                Text("This step completes itself when Apple's status moves on.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Once Apple has finished, inviting the user to keep refreshing a
    /// state that will not change again is just noise.
    private var statusCheckTitle: String {
        if statusPoller.isChecking { return "Checking…" }
        if statusPoller.status?.isFinished == true { return "Check again" }
        return "Check with Apple"
    }

    /// Built outside the view body: a closure inside a `Text`
    /// interpolation is expensive for the type-checker, and this file
    /// is already large.
    private var buildIdentityLine: String? {
        guard let build = statusPoller.status, let number = build.buildNumber else {
            return nil
        }
        var line = "Build \(number)"
        if let version = build.version { line += " · version \(version)" }
        return line + " · \(build.state)"
    }

    private var statusIcon: String {
        guard let state = statusPoller.status?.state else { return "clock.fill" }
        switch state {
        case "VALID":                     return "checkmark.seal.fill"
        case "INVALID", "FAILED":         return "xmark.octagon.fill"
        case "EXPIRED":                   return "hourglass.bottomhalf.filled"
        default:                          return "clock.fill"
        }
    }

    private var statusTint: Color {
        guard let state = statusPoller.status?.state else {
            return LiquidGlass.primaryText.opacity(0.6)
        }
        switch state {
        case "VALID":             return LiquidGlass.success
        case "INVALID", "FAILED": return LiquidGlass.error
        case "EXPIRED":           return LiquidGlass.warning
        default:                  return LiquidGlass.accent
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
        record = store.record(for: job.id)
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

        // Preferred path: sign and upload on the paired Mac. The
        // signing key stays on your devices — it is handed to the Mac
        // over the local connection for the length of the command and
        // never reaches CodeGenie's server, which is also the only
        // reason the server has no copy to sign with.
        let creds = Credentials.shared
        // All three parts are needed. With any one missing the Mac
        // silently archives unsigned and the upload has nothing to
        // authenticate with, so check them together rather than
        // discovering it minutes into a build.
        let hasKey = !creds.ascKeyID.isEmpty
            && !creds.ascIssuerID.isEmpty
            && !creds.ascP8PEM.isEmpty
        if macPaired && hasKey {
            await shipViaMac(step: step, backendID: backendID)
            return
        }

        guard let cfg = ShipConfig.fromCredentials(bundleID: defaultBundleID(for: job.description.title)) else {
            testFlightErrorMessage = "Missing Apple Developer credentials. Add them in Settings, then try again."
            showTestFlightErrorAlert = true
            return
        }
        do {
            try await swarm.ship(jobID: backendID, config: cfg)
        } catch {
            testFlightErrorMessage = "\(error)"
            showTestFlightErrorAlert = true
            Haptics.error()
            return
        }

        // The ship endpoint is fire-and-forget: it starts a background
        // task and returns `{"ok": true}` straight away. Treating that
        // as success told the user their app was uploaded before
        // anything had even been packaged, and moved them on to "wait
        // for Apple" for a build that never left the building.
        switch await awaitShipOutcome(backendID: backendID) {
        case .uploaded:
            banner = Banner(text: "Uploaded. Apple is validating and processing it now.", tone: .success)
            Haptics.success()
            advance(step)
        case .failed(let why):
            testFlightErrorMessage = why
            showTestFlightErrorAlert = true
            Haptics.error()
        case .stillRunning:
            banner = Banner(
                text: "Still working. This can take a while on a big app — leave it running and check back on the build screen.",
                tone: .warning
            )
            Haptics.warning()
        }
    }

    /// Fetch, sign, and upload entirely on the paired Mac.
    ///
    /// Three steps, each of which can take minutes, so each one
    /// narrates itself. The Mac streams tool output as companion
    /// events; `observeCompanionLines` mirrors the newest one into the
    /// status line under the button.
    private func shipViaMac(step: ASCStep, backendID: String) async {
        let creds = Credentials.shared
        let watcher = observeCompanionLines()
        defer {
            NotificationCenter.default.removeObserver(watcher)
            uploadStatusLine = nil
        }

        guard let exportURL = swarm.exportURL(jobID: backendID) else {
            testFlightErrorMessage = "CodeGenie couldn't work out where your app's files are on the server."
            showTestFlightErrorAlert = true
            return
        }

        do {
            uploadStatusLine = "Sending your app's files to your Mac…"
            let root = try await companion.fetchWorkspace(
                jobID: backendID,
                exportURL: exportURL.absoluteString,
                token: creds.backendToken
            )

            uploadStatusLine = "Building and signing on your Mac…"
            let archive = try await companion.archiveExport(
                workspaceRoot: root,
                teamID: creds.appleTeamID,
                keyID: creds.ascKeyID,
                issuerID: creds.ascIssuerID,
                keyPEM: creds.ascP8PEM
            )
            guard archive.ok, let ipa = archive.ipaPath else {
                testFlightErrorMessage = macFailureMessage(archive)
                showTestFlightErrorAlert = true
                Haptics.error()
                return
            }

            uploadStatusLine = "Uploading to Apple…"
            let upload = try await companion.uploadToTestFlight(
                ipaPath: ipa,
                keyID: creds.ascKeyID,
                issuerID: creds.ascIssuerID,
                keyPEM: creds.ascP8PEM,
                appSpecificPassword: creds.appSpecificPassword
            )
            guard upload.ok else {
                testFlightErrorMessage = macFailureMessage(upload)
                showTestFlightErrorAlert = true
                Haptics.error()
                return
            }

            banner = Banner(text: "Uploaded from your Mac. Apple is processing it now.", tone: .success)
            Haptics.success()
            advance(step)
        } catch {
            testFlightErrorMessage = "Lost contact with your Mac (\(error)). Check it's awake and CodeGenie Companion is still running, then try again."
            showTestFlightErrorAlert = true
            Haptics.error()
        }
    }

    /// Prefer the Mac's own plain-English reason, falling back to the
    /// tail of the tool output so the user is never left with nothing.
    private func macFailureMessage(_ result: CompanionBridge.MacStepResult) -> String {
        if !result.detail.isEmpty {
            return result.logTail.isEmpty
                ? result.detail
                : "\(result.detail)\n\n\(String(result.logTail.suffix(800)))"
        }
        let where_ = result.phase.isEmpty ? "packaging" : result.phase
        return "Something went wrong during \(where_).\n\n\(String(result.logTail.suffix(800)))"
    }

    /// Mirror the Mac's streamed tool output into the status line.
    private func observeCompanionLines() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .companionEvent,
            object: nil,
            queue: .main
        ) { note in
            guard let payload = note.userInfo?["payload"] as? [String: Any],
                  let line = payload["line"] as? String,
                  !line.trimmingCharacters(in: .whitespaces).isEmpty
            else { return }
            Task { @MainActor in uploadStatusLine = line }
        }
    }

    private enum ShipOutcome {
        case uploaded
        case failed(String)
        /// Neither finished nor failed before we stopped watching.
        case stillRunning
    }

    /// Watch the job's event stream until shipping actually resolves.
    ///
    /// Polls the client's accumulated events rather than racing a
    /// continuation against a timeout — the array is in memory and
    /// tiny, and this keeps the whole wait on the main actor with no
    /// shared mutable state to get wrong.
    private func awaitShipOutcome(backendID: String) async -> ShipOutcome {
        swarm.openStream(jobID: backendID)
        defer { swarm.closeStream() }

        // An archive plus a validate plus an upload legitimately runs
        // for many minutes on a real app.
        let deadline = Date().addingTimeInterval(15 * 60)
        while Date() < deadline {
            if let outcome = shipOutcome(in: swarm.events) { return outcome }
            uploadStatusLine = latestShipLine(in: swarm.events)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return .stillRunning
    }

    private func shipOutcome(in events: [SwarmEvent]) -> ShipOutcome? {
        for event in events {
            switch event.type {
            case "testflight.package":
                // A null `ok` means packaging is still running.
                if (event.payload["ok"] as? Bool) == false {
                    return .failed((event.payload["preview"] as? String)
                                   ?? "CodeGenie couldn't package your app.")
                }
            case "testflight.upload":
                if (event.payload["ok"] as? Bool) == true { return .uploaded }
                return .failed((event.payload["preview"] as? String)
                               ?? "The upload to Apple didn't go through.")
            default:
                continue
            }
        }
        return nil
    }

    /// The newest line from Apple's toolchain, so a multi-minute wait
    /// shows something moving instead of a frozen button.
    private func latestShipLine(in events: [SwarmEvent]) -> String? {
        events.last {
            $0.type == "testflight.package.progress"
                || $0.type == "testflight.upload.progress"
        }?.payload["line"] as? String
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

        guard blocking.isEmpty else {
            banner = Banner(
                text: "Your listing still has \(blocking.count) problem\(blocking.count == 1 ? "" : "s") Apple will reject: \(blocking[0].message)",
                tone: .warning
            )
            showMetadataEditor = true
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
                        // Grouped because a ViewBuilder block takes at
                        // most ten children, and this stack was at eleven.
                        Group {
                            field("Support URL", text: $metadata.supportURL, limit: nil,
                                  hint: "Required. A page where users can reach you.")
                            field("Marketing URL", text: $metadata.marketingURL, limit: nil,
                                  hint: "Optional. Leave empty rather than fake.")
                            field("Privacy policy URL", text: optional(\.privacyPolicyURL), limit: nil,
                                  hint: "Required for every app, even one that collects nothing.")
                            field("Copyright", text: optional(\.copyright), limit: nil,
                                  hint: "The year and the owner, e.g. 2026 Jane Appleseed. Apple adds the © itself.")
                            field("Category", text: $metadata.primaryCategory, limit: nil, hint: nil)
                            field("Price", text: $metadata.price, limit: nil, hint: nil)
                        }
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

    /// Fields added after the first release are optional in storage so
    /// older saved submissions still load; the form treats nil as "".
    private func optional(_ keyPath: WritableKeyPath<AppStoreMetadata, String?>) -> Binding<String> {
        Binding(
            get: { metadata[keyPath: keyPath] ?? "" },
            set: { metadata[keyPath: keyPath] = $0 }
        )
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
