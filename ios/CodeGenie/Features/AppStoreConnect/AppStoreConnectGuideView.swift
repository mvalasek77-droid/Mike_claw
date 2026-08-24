import SwiftUI
import UIKit

struct ASCStep: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    let title: String
    let body: String
    let action: ActionKind
    let safariRoute: String?

    enum ActionKind: Hashable {
        /// CodeGenie opens the URL in the paired Mac's Safari.
        case openSafariOnMac(String)
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
        case .openSafariOnMac, .fillForm: return .hybrid
        case .prepareAsset:               return .you
        case .wait:                       return .apple
        case .manual:                     return .you
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
            case .hybrid: "CodeGenie opens the page and fills the fields. You review and save."
            case .you:    "You do this — CodeGenie can't tap buttons in your Apple account."
            case .apple:  "Apple's servers do this. Nothing for you to do but wait."
            }
        }
    }
}

extension ASCStep {
    static let all: [ASCStep] = [
        .init(number: 1,
              title: "Sign in to App Store Connect",
              body: "CodeGenie opens appstoreconnect.apple.com in your Mac's Safari. You sign in there — your password and 2-factor codes never touch CodeGenie.",
              action: .openSafariOnMac("https://appstoreconnect.apple.com"),
              safariRoute: "https://appstoreconnect.apple.com"),

        .init(number: 2,
              title: "Create the app record",
              body: "Click + → New App. Platform iOS, and the bundle ID must match your Xcode target exactly or the upload in step 8 fails.",
              action: .openSafariOnMac("https://appstoreconnect.apple.com/apps"),
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 3,
              title: "Prepare your 1024×1024 icon",
              body: "Exactly 1024×1024, PNG, no alpha channel, no pre-rounded corners. Apple rejects anything else without review.",
              action: .prepareAsset("icon-1024.png"),
              safariRoute: nil),

        .init(number: 4,
              title: "Prepare screenshots",
              body: "At least one iPhone display size. Screenshots showing placeholder or lorem-ipsum content are a common rejection reason.",
              action: .prepareAsset("screenshots"),
              safariRoute: nil),

        .init(number: 5,
              title: "Fill in the listing",
              body: "Name, subtitle, keywords, description and URLs. CodeGenie checks every field against Apple's length limits before you paste anything.",
              action: .fillForm,
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 6,
              title: "Answer the privacy questions",
              body: "Apple asks what data you collect. Answer honestly — this is audited, and a wrong answer here pulls a live app.",
              action: .manual,
              safariRoute: nil),

        .init(number: 7,
              title: "Set pricing and availability",
              body: "Free in all territories is the safe default. Price can change later without a new review.",
              action: .manual,
              safariRoute: nil),

        .init(number: 8,
              title: "Upload the build",
              body: "Needs a signed App Store build. CodeGenie runs Apple's validate-then-upload flow and streams every line so failures surface immediately.",
              action: .manual,
              safariRoute: nil),

        .init(number: 9,
              title: "Wait for processing",
              body: "Apple takes 5–30 minutes to process a binary. Close CodeGenie if you like — your progress is saved.",
              action: .wait("Apple is processing your build"),
              safariRoute: nil),

        .init(number: 10,
              title: "Submit for review",
              body: "Pick the processed build, confirm export compliance and content rights, then press Submit. Apple requires the account holder to do this.",
              action: .manual,
              safariRoute: nil)
    ]
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
    @State private var showSubmitBlocked = false
    @State private var didLoad = false

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

    private struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let tone: Tone
        enum Tone { case success, warning, info }
    }

    private var issues: [ASCCoach.Issue] { ASCCoach.validate(metadata) }
    private var blocking: [ASCCoach.Issue] { issues.filter { $0.severity == .blocking } }
    private var macPaired: Bool { companion.isConnected }

    private var nextAction: ASCCoach.NextAction {
        ASCCoach.nextAction(completed: completed, metadata: metadata, macPaired: macPaired)
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
                completed = Set(1...ASCStep.all.count)
                banner = Banner(text: "Submission recorded. Apple emails you when review finishes — usually 24–48 hours.", tone: .success)
                Haptics.success()
            }
        } message: {
            Text("Only mark this done once Apple has actually accepted the submission. We'll keep your record so you can come back to it.")
        }
        .sheet(isPresented: $showSubmitBlocked) {
            ASCReadinessBlockedSheet(
                readiness: $readiness,
                onRecheck: { await runReadinessCheck() }
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
                    text: "Pre-flight passed — \(Int(run.score))/100 on Apple's automated quality bar. Moving to the walkthrough.",
                    tone: .success
                )
                // Kick off the process-readiness check in the background —
                // it's informational here and becomes a hard gate at step 10.
                await runReadinessCheck()
            } else {
                preflight = .blocked(run)
            }
        } catch {
            preflight = .unverifiable("Couldn't reach the backend to verify this build (\(error)).")
        }
    }

    /// Process-readiness (assets, credentials, IPA, GitHub). Unlike
    /// the pre-flight gate, this is not blocking at guide-entry —
    /// several of its items (the IPA, Apple credentials) are exactly
    /// what steps 1–8 exist to produce. It becomes a hard gate only at
    /// step 10, immediately before the user is allowed to say they
    /// submitted.
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
            Color.clear.frame(width: 40, height: 40)
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
        case "critical": .red
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

    private var guideBody: some View {
        VStack(spacing: 0) {
            progressBar
            ScrollView {
                VStack(spacing: 16) {
                    coachCard
                    if let banner { bannerCard(banner) }
                    listingCard
                    macStatusCard
                    if let readiness { readinessCard(readiness) }
                    ForEach(ASCStep.all) { step in
                        stepCard(step)
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Step \(current) of \(ASCStep.all.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                Spacer()
                Text("\(completed.count) complete")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(LiquidGlass.auroraGradient)
                        .frame(width: proxy.size.width * Double(completed.count) / Double(ASCStep.all.count))
                        .motion(.spring(response: 0.5), value: completed.count)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completed.count) of \(ASCStep.all.count) steps complete")
    }

    // MARK: Coach

    /// The always-visible "what do I do right now" panel. This is the
    /// difference between a checklist and a guide — the user should
    /// never have to work out which of ten steps applies to them.
    private var coachCard: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: nextAction.isBlocking ? "exclamationmark.triangle.fill" : "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(nextAction.isBlocking ? LiquidGlass.warning : LiquidGlass.accent)
                        .accessibilityHidden(true)
                    Text(nextAction.headline)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer(minLength: 0)
                }
                Text(nextAction.detail)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)

                if nextAction.isBlocking {
                    PrimaryButton(title: "Fix the listing", systemImage: "pencil", style: .filled) {
                        showMetadataEditor = true
                    }
                } else if let step = nextAction.stepNumber {
                    PrimaryButton(title: "Go to step \(step)", systemImage: "arrow.down.circle.fill", style: .filled) {
                        Motion.run(.spring(response: 0.4)) { current = step }
                        Haptics.selection()
                    }
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach: \(nextAction.headline). \(nextAction.detail)")
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

    // MARK: Listing

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

    // MARK: Release readiness (live, informational; gates step 10)

    private func readinessCard(_ run: ReleaseReadinessRun) -> some View {
        let required = run.items.filter { $0.required }
        let outstanding = required.filter { $0.status != "automated" && $0.status != "assisted" && $0.status != "user_confirmation" }
        return GlassCard(title: "Release checklist", icon: "checklist", tint: run.isReadyForTestFlight ? LiquidGlass.success : LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: run.isReadyForTestFlight ? "checkmark.circle.fill" : "clock.fill")
                        .foregroundStyle(run.isReadyForTestFlight ? LiquidGlass.success : LiquidGlass.accent)
                        .accessibilityHidden(true)
                    Text(run.summary)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !outstanding.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(outstanding.prefix(4)) { item in
                            Text("• \(item.title): \(item.detail)")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button {
                    Task { await runReadinessCheck() }
                } label: {
                    Text("Recheck")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Release checklist: \(run.summary)")
    }

    // MARK: Steps

    private func stepCard(_ step: ASCStep) -> some View {
        let isDone = completed.contains(step.number)
        let isCurrent = step.number == current
        return GlassSurface(tier: isCurrent ? .deep : .raised) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    statusBadge(step, isDone: isDone, isCurrent: isCurrent)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Step \(step.number)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                                .textCase(.uppercase).tracking(1)
                            ownershipBadge(step)
                        }
                        Text(step.title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Text(isCurrent
                     ? ASCCoach.guidance(for: step, metadata: metadata,
                                         macPaired: macPaired, buildUploaded: completed.contains(8))
                     : step.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if isCurrent { actionRow(step) }
                if isDone && !isCurrent {
                    Button {
                        store.markStepIncomplete(step.number, for: job.id)
                        completed.remove(step.number)
                        current = step.number
                        Haptics.selection()
                    } label: {
                        Text("Reopen this step")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                    }
                }
            }
            .padding(16)
        }
        .id(step.number)
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
                if step.number == 10 {
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
        if step.number < ASCStep.all.count {
            Motion.run(.spring(response: 0.4)) { current = step.number + 1 }
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

    /// The second hard gate. Perfection Mode already guaranteed the
    /// code and listing are sound before the guide even opened; this
    /// one guarantees the *process* is actually finished — a real IPA
    /// uploaded, Apple credentials on file, privacy manifest present —
    /// before the user is allowed to tell CodeGenie they pressed
    /// Submit. Re-checks live rather than trusting a stale snapshot,
    /// since steps 1–9 happen in between.
    private func attemptFinalSubmit() async {
        await runReadinessCheck()
        if readiness?.isReadyForTestFlight == true {
            showSubmitConfirm = true
        } else {
            showSubmitBlocked = true
            Haptics.warning()
        }
    }
}

// MARK: - Blocked-at-submit sheet

/// Shown when the user tries to confirm submission but the release
/// checklist still has required items outstanding. Enumerates exactly
/// what's missing using the same plain-English detail/action text the
/// backend's readiness audit already writes — no separate copy to keep
/// in sync.
private struct ASCReadinessBlockedSheet: View {
    // A binding, not a snapshot — `onRecheck` mutates the parent's
    // readiness state, and the dismiss condition below must see the
    // fresh value, not whatever was true the moment this sheet opened.
    @Binding var readiness: ReleaseReadinessRun?
    let onRecheck: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rechecking = false

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("A few things are still missing before this can go to Apple.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(outstandingItems) { item in
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
                                if readiness?.isReadyForTestFlight == true { dismiss() }
                            }
                        }
                        .disabled(rechecking)
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Not quite ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var outstandingItems: [ReleaseReadinessItem] {
        (readiness?.items ?? []).filter {
            $0.required && $0.status != "automated" && $0.status != "assisted" && $0.status != "user_confirmation"
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
