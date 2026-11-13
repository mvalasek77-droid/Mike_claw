import SwiftUI
import UIKit

// MARK: - Guide

struct AppStoreConnectGuideView: View {
    let job: BuildJob

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: AppSession
    @StateObject private var store = ASCSubmissionStore.shared
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
    /// The project, packed and downloaded, ready to hand to AirDrop.
    @State private var projectArchive: URL?
    @State private var preparingProject = false
    @State private var projectError: String?
    @State private var showTutorial = false
    @State private var showAfterSubmission = false
    @State private var didLoad = false
    /// Focus mode is the default: one step on screen at a time. This
    /// reveals the whole list only when the user asks for it, because
    /// seeing every step at once is what made this screen unreadable
    /// for a first-time submitter.
    @State private var showAllSteps = false
    @StateObject private var coachChat = ASCCoachChat()
    @State private var showCoachChat = false
    @State private var showChecklist = false
    @State private var showAppleSetup = false
    /// Mirrors the store so the review panel re-renders on every
    /// status change without reaching into the singleton mid-body.
    @State private var record: ASCSubmissionRecord?

    /// AI-proactive pre-flight gate. Nothing runs the guide's steps
    /// until CodeGenie has actually checked the app — the user never
    /// has to remember to tap a "run checks" button, and a stale pass
    /// never carries over from a previous open.
    @State private var preflight: PreflightState = .checking

    enum PreflightState: Equatable {
        case checking
        case blocked(PerfectionRun?)
        case unverifiable(String)
        case clear
    }

    private struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let tone: Tone
        enum Tone { case success, warning, info }
    }

    private var issues: [ASCCoach.Issue] { ASCCoach.validate(metadata) }
    private var blocking: [ASCCoach.Issue] { issues.filter { $0.severity == .blocking } }

    /// The test plan for this app. Derived, not stored: it depends only
    /// on the description and on whether the app has a sign-in.
    private var testPlan: [TestCase] {
        TestPlan.make(for: job.description, requiresLogin: metadata.requiresLogin ?? false)
    }

    private var testResults: [String: TestResult] { record?.results ?? [:] }

    /// The milestone moment: TestFlight phase finished, App Store phase
    /// not started. Worth calling out explicitly — a first-timer should
    /// know they already have a real, testable app and can stop here.
    private var justBecameTestable: Bool {
        ASCStep.steps(in: .testflight).allSatisfy { completed.contains($0.number) }
            && !ASCStep.steps(in: .testing).contains { completed.contains($0.number) }
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
                Haptics.success()
                // Straight into the explanation: this is the moment a
                // first-timer's instructions used to run out.
                showAfterSubmission = true
            }
        } message: {
            Text("Only say yes once the status in App Store Connect reads Waiting for Review. Add for Review on its own doesn't send anything.")
        }
        .sheet(isPresented: $showChecklist) {
            SubmissionChecklistView(
                jobID: job.id,
                appName: job.description.title,
                forAppStore: testingDone,
                autoSatisfied: checklistSettledByTesting,
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
                blockingIssues: blocking.map { "\($0.message) \($0.fix)" } + reviewContextForCoach,
                outstandingItems: testingContextForCoach
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showAppleSetup) {
            AppleDevWalkthroughView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: $showTutorial) {
            ASCTutorialView(appName: job.description.title) {
                store.markTutorialSeen(for: job.id)
                record = store.record(for: job.id)
            }
        }
        .sheet(isPresented: $showAfterSubmission) {
            ASCAfterSubmissionView(appName: job.description.title) {
                store.markAfterSubmissionSeen(for: job.id)
                record = store.record(for: job.id)
            }
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
            return
        }
        // First time here: the shape of the whole thing before step
        // one, so nobody learns at step three that they needed a Mac.
        if saved.tutorialSeen != true && saved.completedSteps.isEmpty {
            showTutorial = true
        }
        if !saved.completedSteps.isEmpty {
            banner = Banner(
                text: "Picked up where you left off — step \(saved.resumeStep) of \(ASCStep.all.count).",
                tone: .info
            )
        }
        await runPreflight()
    }

    /// The quality gate. Runs the static check of the project's code
    /// — common App Review risks, accessibility,
    /// performance, privacy/security, polish — fresh every time the
    /// guide opens. This is deliberately a hard gate: it costs no
    /// tokens (pure rules engine) and it is the one check that's
    /// achievable the instant the build finishes, before any App
    /// Store Connect asset exists. Nothing past this screen is
    /// reachable until it passes.
    private func runPreflight() async {
        preflight = .checking
        guard let backendID = session.backendJobIDs[job.id] else {
            preflight = .unverifiable("This app's files aren't on the build server any more, so CodeGenie can't check them. You can carry on, or build it again from Home.")
            return
        }
        do {
            let run = try await swarm.runPerfection(jobID: backendID)
            store.recordPreflight(passed: run.isReady, score: run.score, for: job.id)
            if run.isReady {
                preflight = .clear
                banner = Banner(
                    text: "CodeGenie's check of your project passed (\(Int(run.score))/100). Let's get this into your hands.",
                    tone: .success
                )
            } else {
                preflight = .blocked(run)
            }
        } catch {
            preflight = .unverifiable("Couldn't reach the backend to verify this build (\(error)).")
        }
    }

    /// Single source of truth — see `AppBundleID`. Derived here and in
    /// the build screen independently, this used to disagree with the
    /// identifier the project was actually signed with.
    private func defaultBundleID(for title: String) -> String {
        // The ID the project was actually built with, when known. The
        // prefix setting may have changed since, and Apple compares the
        // upload against what is inside the app, not against Settings.
        job.bundleID ?? session.recentJobs.first { $0.id == job.id }?.bundleID ?? AppBundleID.make(title: title)
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

    private var testingDone: Bool {
        ASCStep.steps(in: .testing).allSatisfy { completed.contains($0.number) }
    }

    private var checklistSettledByTesting: Set<String> {
        SubmissionChecklist.satisfiedByTesting(plan: testPlan, results: testResults)
    }

    /// What testing has found so far, so the coach's first answer is
    /// about this app's actual failures.
    private var testingContextForCoach: [String] {
        let failed = TestPlan.failures(in: testPlan, results: testResults).map { item in
            "Test failed — \(item.test.title)" + (item.note.map { ": \($0)" } ?? "")
        }
        let summary = TestPlan.summary(of: testPlan, results: testResults)
        guard summary.done > 0 || !failed.isEmpty else { return [] }
        return failed + ["Testing: \(summary.passed) passed, \(summary.failed) failed, \(summary.requiredRemaining) required tests not tried yet."]
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

    private func open(_ address: String) {
        if let url = URL(string: address) { openURL(url) }
    }

    private func openAppStoreConnect() {
        open("https://appstoreconnect.apple.com/apps")
    }

    // MARK: Getting the project to the Mac

    /// Pack the project on the server and bring it to the phone, so
    /// the share sheet has a real file to hand to AirDrop.
    private func prepareProject() async {
        guard let backendID = session.backendJobIDs[job.id] else {
            projectError = "This app's files aren't on the build server any more. Build it again from Home, then come back to this step."
            Haptics.error()
            return
        }
        preparingProject = true
        projectError = nil
        defer { preparingProject = false }
        do {
            let downloaded = try await swarm.downloadExport(jobID: backendID)
            // A readable name, since this is what appears on the Mac.
            let name = job.description.title
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined()
            let named = downloaded.deletingLastPathComponent()
                .appendingPathComponent("\(name.isEmpty ? "MyApp" : name)-Xcode-project.zip")
            try? FileManager.default.removeItem(at: named)
            try FileManager.default.moveItem(at: downloaded, to: named)
            projectArchive = named
            Haptics.success()
        } catch {
            projectError = "Couldn't fetch the project. \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription) Check your connection and try again."
            Haptics.error()
        }
    }

    // MARK: Testing

    private func recordTest(_ testID: String, _ result: TestResult?) {
        store.setTestResult(result, for: testID, in: testPlan, jobID: job.id)
        syncFromStore(jumpToResume: false)
    }

    /// Build again with everything testing found, and take this
    /// submission along to the new build.
    private func rebuildFromTesting(extra: String) {
        var parts: [String] = []
        if let brief = TestPlan.fixBrief(for: testPlan, results: testResults) { parts.append(brief) }
        let tester = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tester.isEmpty {
            parts.append("Someone using the app for the first time also ran into this:\n- " + tester)
        }
        guard !parts.isEmpty else { return }
        startRebuild(brief: parts.joined(separator: "\n\n"))
    }

    private func startRebuild(brief: String) {
        let current = job
        dismiss()
        // After the cover has gone: presenting the build screen while
        // this one is still dismissing can drop the presentation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            session.rebuild(current, fixing: brief)
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
            Button {
                Haptics.selection()
                showTutorial = true
            } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 14, weight: .bold))
                    .padding(10).background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            .accessibilityLabel("How this works")
            .accessibilityHint("Replays the overview of the whole process")
            Spacer()
            VStack(spacing: 2) {
                Text(job.description.title)
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
                Text("CodeGenie is reading through your project for the things that most often get a first app sent back: placeholder text, missing accessibility labels, privacy details, hard-coded secrets. It takes a few seconds and costs nothing.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking your project for common App Store problems. Please wait.")
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
                         ? "CodeGenie's check scored your project \(Int(run!.score))/100 and found things that commonly get an app sent back. Here they are, worst first. You can still put it on your own iPhone to try it — these need fixing before the public App Store."
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

            if let run {
                PrimaryButton(title: "Rebuild with these fixed", systemImage: "wand.and.stars", style: .filled) {
                    rebuild(fixing: run)
                }
                .accessibilityHint("Starts a new build of the same app with these problems added to the instructions")
            }
            PrimaryButton(title: "Try it on my iPhone first", systemImage: "iphone.gen3", style: .glass) {
                preflight = .clear
                banner = Banner(text: "Carrying on to TestFlight. These findings will need fixing before the App Store steps.", tone: .warning)
                Haptics.selection()
            }
            .accessibilityHint("Continues to the TestFlight steps. The App Store submission stays blocked until the check passes.")
            Button {
                Task { await runPreflight() }
            } label: {
                Label("Check again", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
                    .frame(minHeight: 44)
            }
        }
    }

    /// The findings are about the code, and the user can't edit code
    /// here — so the way to act on them is another build that is told
    /// about them.
    private func rebuild(fixing run: PerfectionRun) {
        let fixes = run.findings.prefix(8).map { finding in
            "- \(finding.title): \(finding.recommendation ?? finding.body)"
        }.joined(separator: "\n")
        startRebuild(brief: "A review of the code found these problems:\n" + fixes)
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
                banner = Banner(text: "Carrying on without the check. CodeGenie couldn't read this build, so it will check again before the App Store submission.", tone: .warning)
                Haptics.warning()
            } label: {
                Text("Continue without verification")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
            }
            .accessibilityHint("Skips CodeGenie's check for now. It runs again before you submit to the App Store.")
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
                    if record?.isSubmitted == true { afterSubmissionLink }
                    if currentStep.phase == .appStore { checklistCard }
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
        case .testPlan:
            ASCTestPlanCard(
                appName: job.description.title,
                plan: testPlan,
                results: testResults,
                onResult: { recordTest($0, $1) }
            )
        case .testVerdict:
            ASCTestVerdictCard(
                plan: testPlan,
                results: testResults,
                onReady: {
                    if store.confirmTestingPassed(with: testPlan, for: job.id) {
                        syncFromStore(jumpToResume: true)
                        banner = Banner(text: "Tested and working. Now the store page.", tone: .success)
                        Haptics.success()
                    }
                },
                onRebuild: { rebuildFromTesting(extra: $0) },
                onBackToTests: {
                    Motion.run(.spring(response: 0.4)) { current = ASCStep.testPlanStepNumber }
                }
            )
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

    /// The explanation is shown once automatically; this keeps it one
    /// tap away for as long as the review lasts.
    private var afterSubmissionLink: some View {
        Button {
            Haptics.selection()
            showAfterSubmission = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                    .accessibilityHidden(true)
                Text("What happens now?")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.4))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Explains Apple's review and what to do while you wait")
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
                store.resetForNewBuild(jobID: job.id)
                syncFromStore(jumpToResume: false)
                Motion.run(.spring(response: 0.4)) { current = ASCStep.uploadStepNumber }
                banner = Banner(text: "Archive and upload the fixed build here, test it again, then attach it in step \(ASCStep.buildSelectionStepNumber) and resubmit.", tone: .info)
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
            bundleID: defaultBundleID(for: job.description.title)
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

                Label(step.place.rawValue, systemImage: placeSymbol(step.place))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    .accessibilityLabel("Where: \(step.place.rawValue)")

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
                if completed.contains(step.number), step.phase != .review, step.action != .testPlan {
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

    private func placeSymbol(_ place: ASCStep.Place) -> String {
        switch place {
        case .phone: "iphone"
        case .xcode: "macbook"
        case .web:   "safari"
        case .apple: "applelogo"
        }
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
                    if value.hasPrefix("https://"), let url = URL(string: value) {
                        Link(destination: url) {
                            Label("Open this page", systemImage: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.accent)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    }
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
        let phases = ASCPhase.allCases
        let index = phases.firstIndex(of: currentPhase) ?? 0
        let here = "Part \(index + 1) of \(phases.count) — \(currentPhase.shortLabel)"
        guard index > 0 else { return here }
        return "\(phases[index - 1].doneLabel) ✓ · \(here)"
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
        case .testing:    LiquidGlass.warning
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
                    Text("It's on your iPhone")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("That's a real app, installed the real way. Next comes the part that decides whether Apple approves it: finding out if it works.")
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
        let items = SubmissionChecklist.items(forAppStore: true)
        let auto = checklistSettledByTesting
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
        case .together: LiquidGlass.accent
        case .you:      LiquidGlass.warning
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
            case .transferProject:
                transferActions(step)

            case .xcode:
                xcodeActions(step)

            case .website(let address):
                PrimaryButton(title: "Open the page here", systemImage: "safari", style: .glass) {
                    open(address)
                }
                .accessibilityHint("Opens Apple's website on this iPhone. It's easier on your Mac — the address is in the steps above.")
                markDoneButton(step, title: "I did this")

            case .openTestFlightApp:
                PrimaryButton(title: "Open TestFlight", systemImage: "arrow.up.forward.app.fill", style: .filled) {
                    openTestFlight()
                }
                Text("Look for an email from Apple inviting you to test \(job.description.title) if TestFlight doesn't show it yet.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                markDoneButton(step, title: "It's installed on my iPhone")

            case .testPlan:
                // Finished by the results, never by a tap.
                Text(TestPlan.summary(of: testPlan, results: testResults).isPassing
                     ? "Required tests passed. Carry on below, or finish the advised ones first."
                     : "This step completes itself when every required test below passes.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if completed.contains(step.number) {
                    PrimaryButton(title: "Next: have someone else try it", systemImage: "arrow.right", style: .filled) {
                        Motion.run(.spring(response: 0.4)) { current = step.number + 1 }
                    }
                }

            case .inviteTesters:
                PrimaryButton(title: "Open the page here", systemImage: "safari", style: .glass) {
                    openAppStoreConnect()
                }
                markDoneButton(step, title: "Someone else has used it")
                Button {
                    advance(step)
                    banner = Banner(text: "Skipped. Your own testing still counts — but one outside pair of eyes is the cheapest insurance there is.", tone: .warning)
                } label: {
                    Text("I can't get anyone right now")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Skips this step. Not recommended.")

            case .testVerdict:
                // The card below carries the decision.
                EmptyView()

            case .fillForm:
                PrimaryButton(
                    title: blocking.isEmpty ? "Copy listing to clipboard" : "Fix the listing first",
                    systemImage: blocking.isEmpty ? "doc.on.doc" : "exclamationmark.triangle.fill",
                    style: .filled
                ) {
                    if blocking.isEmpty {
                        UIPasteboard.general.string = plainTextListing
                        banner = Banner(text: "Copied. Paste each field into App Store Connect, then mark this done.", tone: .success)
                        Haptics.success()
                    } else {
                        showMetadataEditor = true
                    }
                }
                markDoneButton(step, title: "I filled in the listing")

            case .prepareAsset(let asset):
                if asset == "screenshots" {
                    Text("Take them on your Mac, from the Simulator, as the steps describe.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                markDoneButton(step, title: "I've got this ready")

            case .wait(let detail):
                waitActions(step, detail: detail)

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
                .accessibilityHint("CodeGenie checks nothing is missing first, then explains what happens next")

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

    /// Step 1: fetch the project, then hand it to the share sheet.
    @ViewBuilder
    private func transferActions(_ step: ASCStep) -> some View {
        if let projectArchive {
            ShareLink(item: projectArchive) {
                Label("Send project to my Mac", systemImage: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(LiquidGlass.auroraGradient, in: Capsule())
            }
            .accessibilityHint("Opens the share sheet. Choose AirDrop, then your Mac.")
            Text("In the share sheet choose AirDrop, then your Mac.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
            markDoneButton(step, title: "It's on my Mac")
        } else {
            PrimaryButton(
                title: preparingProject ? "Packing your project…" : "Get the project ready to send",
                systemImage: "shippingbox.fill",
                style: .filled
            ) {
                Task { await prepareProject() }
            }
            .disabled(preparingProject)
            if let projectError {
                Text(projectError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if completed.contains(step.number) {
                Text("Already on your Mac. Fetch it again only if you rebuilt the app.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Steps done in Xcode: the phone can't see the Mac, so the user
    /// reports back — and the two honest answers are "it worked" and
    /// "it showed an error".
    @ViewBuilder
    private func xcodeActions(_ step: ASCStep) -> some View {
        markDoneButton(step, title: step.number == ASCStep.uploadStepNumber ? "Xcode says the upload finished" : "Done in Xcode")
        Button {
            Haptics.selection()
            showCoachChat = true
        } label: {
            Label("It showed an error", systemImage: "exclamationmark.bubble.fill")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.warning)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LiquidGlass.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LiquidGlass.warning.opacity(0.3)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the coach. Paste or describe the error and it explains what to do.")
        if step.number == 4 {
            Button {
                Haptics.selection()
                startRebuild(brief: "The project did not build in Xcode. Make sure it compiles cleanly for iOS with no errors.")
            } label: {
                Text("It won't build at all — rebuild it")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts a new build of the same app, told that the last one didn't compile")
        }
    }

    /// Waiting on Apple's processing. With an API key CodeGenie asks
    /// Apple itself; without one the user reads it off the page.
    @ViewBuilder
    private func waitActions(_ step: ASCStep, detail: String) -> some View {
        if ASCStatusPoller.canAskApple() {
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
            PrimaryButton(title: statusCheckTitle, systemImage: "arrow.clockwise", style: .filled) {
                Task { await checkBuildStatus(announce: true) }
            }
            .disabled(statusPoller.isChecking)
        } else {
            Text("Check your app's TestFlight tab in App Store Connect, or wait for Apple's email. Add an App Store Connect API key in Settings and CodeGenie can check this for you.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Haptics.selection()
                showAppleSetup = true
            } label: {
                Text("Set up automatic checking")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        markDoneButton(step, title: "The build finished processing")
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

    /// The gate at the very end. Everything that can be known is
    /// checked again, fresh, before the user is allowed to say they
    /// pressed Submit: the code check, the tests, the listing, and the
    /// things only they can vouch for.
    private func attemptFinalSubmit() async {
        if let backendID = session.backendJobIDs[job.id],
           let run = try? await swarm.runPerfection(jobID: backendID) {
            store.recordPreflight(passed: run.isReady, score: run.score, for: job.id)
            if !run.isReady {
                preflight = .blocked(run)
                Haptics.warning()
                return
            }
        }

        // Untested apps are what Apple rejects most. This is the one
        // gate with no way round it.
        let testing = TestPlan.summary(of: testPlan, results: testResults)
        guard testing.isPassing, testingDone else {
            banner = Banner(
                text: testing.failed > 0
                    ? "\(testing.failed) test\(testing.failed == 1 ? " is" : "s are") still failing. Fix \(testing.failed == 1 ? "it" : "them") with a rebuild before submitting."
                    : "Testing isn't finished. Apple's most common rejection is an app that didn't work when they tried it.",
                tone: .warning
            )
            Motion.run(.spring(response: 0.4)) {
                current = testing.isPassing ? ASCStep.testVerdictStepNumber : ASCStep.testPlanStepNumber
            }
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

        let outstandingChecklist = SubmissionChecklist.outstanding(
            checked: store.checkedItems(for: job.id),
            autoSatisfied: checklistSettledByTesting,
            forAppStore: true
        )
        guard outstandingChecklist.isEmpty else {
            banner = Banner(
                text: "\(outstandingChecklist.count) thing\(outstandingChecklist.count == 1 ? "" : "s") on your checklist still need confirming. These are the ones only you can vouch for.",
                tone: .warning
            )
            showChecklist = true
            Haptics.warning()
            return
        }

        showSubmitConfirm = true
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
