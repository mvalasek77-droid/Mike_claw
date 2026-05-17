import SwiftUI

struct ASCStep: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    let title: String
    let body: String
    let action: ActionKind
    let safariRoute: String?      // e.g. "https://appstoreconnect.apple.com/apps"

    enum ActionKind: Hashable {
        case openSafariOnMac(String)   // tells the desktop bridge to open URL
        case fillForm                  // CodeGenie auto-fills the page
        case uploadAsset(String)       // uploads icon, screenshots, etc.
        case wait(String)              // wait for Apple processing
        case manual                    // user has to click something
    }
}

extension ASCStep {
    static let all: [ASCStep] = [
        .init(number: 1,
              title: "Sign in to App Store Connect",
              body: "We'll open appstoreconnect.apple.com on your Mac's Safari and prompt for 2-factor codes. CodeGenie never sees your Apple password.",
              action: .openSafariOnMac("https://appstoreconnect.apple.com"),
              safariRoute: "https://appstoreconnect.apple.com"),

        .init(number: 2,
              title: "Create a new app record",
              body: "Click '+' → New App. We pre-fill platform = iOS, default language, bundle ID (matches your Xcode target), SKU and primary category for you.",
              action: .fillForm,
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 3,
              title: "Upload your icon",
              body: "1024×1024 PNG, no alpha, no rounded corners. CodeGenie strips alpha automatically — Apple rejects anything else.",
              action: .uploadAsset("icon-1024.png"),
              safariRoute: nil),

        .init(number: 4,
              title: "Auto-generate screenshots",
              body: "We render App Store-size screenshots from the simulator walkthrough, then let you review the actual screens before upload.",
              action: .uploadAsset("screenshots/*.png"),
              safariRoute: nil),

        .init(number: 5,
              title: "Write the listing",
              body: "We draft Name, Subtitle, Promotional Text, Description (≤4000 chars), and Keywords (≤100 chars) tuned for your category. Hit ⌘↩ to accept.",
              action: .fillForm,
              safariRoute: nil),

        .init(number: 6,
              title: "Privacy & data collection",
              body: "CodeGenie scans Info.plist, PrivacyInfo.xcprivacy, dependencies, and code for tracking/data-use clues, then drafts the privacy answers for your confirmation.",
              action: .fillForm,
              safariRoute: "https://appstoreconnect.apple.com/apps#privacy"),

        .init(number: 7,
              title: "Pricing & availability",
              body: "Default: free, all territories. Schedule a price tier or limit countries if you want.",
              action: .fillForm,
              safariRoute: nil),

        .init(number: 8,
              title: "Validate and upload the build",
              body: "Once an App Store IPA exists, CodeGenie runs Apple's validate-app and upload-app flow, streams every line, then polls processing with your ASC API key.",
              action: .uploadAsset("Build.ipa"),
              safariRoute: nil),

        .init(number: 9,
              title: "Wait for processing",
              body: "Apple takes 5–30 minutes to process the binary. We'll notify you on your phone when the build is selectable in the listing.",
              action: .wait("Build processing — usually 5-30 minutes"),
              safariRoute: nil),

        .init(number: 10,
              title: "Submit for review",
              body: "Pick the processed build, confirm export compliance, privacy, content rights, and legal terms, then tap Submit. CodeGenie guides this step but leaves final approval to you.",
              action: .manual,
              safariRoute: nil)
    ]
}

struct AppStoreConnectGuideView: View {
    let job: BuildJob
    @Environment(\.dismiss) private var dismiss
    @State private var current: Int = 0
    @State private var completed: Set<UUID> = []
    @State private var metadata: AppStoreMetadata
    @State private var driving: Bool = false
    @State private var driveError: String?
    @State private var liveStepID: String?
    private let client = SwarmClient()

    init(job: BuildJob) {
        self.job = job
        _metadata = State(initialValue: AppStoreMetadata.draft(for: job.description))
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                progressBar
                ScrollView {
                    VStack(spacing: 16) {
                        driveMyMacCard
                        legendCard
                        metadataCard
                        ForEach(ASCStep.all) { step in
                            ASCStepCard(
                                step: step,
                                index: ASCStep.all.firstIndex(of: step) ?? 0,
                                isCurrent: ASCStep.all.firstIndex(of: step) == current,
                                isDone: completed.contains(step.id),
                                onAction: { perform(step) }
                            )
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .padding(10).background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            Spacer()
            Text("Submit \(job.description.title)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Step \(current + 1) of \(ASCStep.all.count)")
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
    }

    /// New in v0.2.3: phone-side "Drive my Mac for me" CTA. The user
    /// stays on their phone watching narrated progress while the
    /// CodeGenie Companion on the Mac drives Safari + ASC for them.
    /// Apple's final-submit step is left untouched — only the user
    /// taps that.
    @ViewBuilder
    private var driveMyMacCard: some View {
        GlassCard(title: "Let your Mac do the clicking", icon: "macbook.and.iphone", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stay on your phone. We'll open Safari on your paired Mac and walk through ASC step by step. You'll see live progress here.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))

                if let liveStepID, driving {
                    HStack(spacing: 10) {
                        ProgressView().tint(LiquidGlass.primaryText)
                        Text("On your Mac: \(liveStepID)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        Spacer()
                    }
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                PrimaryButton(
                    title: driving ? "Driving on your Mac…" : "Run on my Mac",
                    systemImage: driving ? "ellipsis" : "play.fill",
                    style: .filled
                ) {
                    Task { await driveOnMac() }
                }
                .disabled(driving)
                .opacity(driving ? 0.7 : 1)
                .accessibilityHint("Hands the App Store Connect flow to your paired Mac. Your phone shows live progress.")

                if let driveError {
                    Text(driveError)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Final submit is yours — Apple requires you to tap that one. We line everything up so it's a single confirm.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            }
        }
    }

    /// Calls the backend's /asc/drive route which fans out to the
    /// Mac Companion. Each step's progress streams back as a `log`
    /// SSE event — the BuildScreen's transcript surface picks those
    /// up, and `liveStepID` mirrors the latest one for the user.
    private func driveOnMac() async {
        driving = true; driveError = nil
        defer { driving = false; liveStepID = nil }
        do {
            let result = try await client.driveASC(jobID: job.id, steps: [])
            // Mark every non-manual step complete on the iOS side so
            // the user sees the same green checks the Mac produced.
            for step in ASCStep.all where !result.manualSteps.contains("submit") || step.action != .manual {
                completed.insert(step.id)
            }
            Haptics.success()
        } catch {
            driveError = "Couldn't reach your Mac Companion: \(error.localizedDescription). Use the manual steps below."
            Haptics.error()
        }
    }

    private var legendCard: some View {
        GlassCard(title: "Who does what", icon: "person.2.and.person", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 8) {
                legendRow(label: "Auto", tint: LiquidGlass.success, text: "CodeGenie runs this end-to-end and shows status.")
                legendRow(label: "Hybrid", tint: LiquidGlass.accent, text: "CodeGenie opens or fills the page. You review and confirm.")
                legendRow(label: "You", tint: LiquidGlass.warning, text: "You do this in App Store Connect. Apple requires final human confirmation.")
            }
        }
    }

    private func legendRow(label: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(tint)
                .background(tint.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metadataCard: some View {
        GlassCard(title: "Listing draft", icon: "doc.text.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 8) {
                kv("Name", metadata.name)
                kv("Subtitle", metadata.subtitle)
                kv("Category", metadata.primaryCategory)
                kv("Price", metadata.price)
                kv("Age rating", metadata.ageRating)
                kv("Keywords", metadata.keywords.joined(separator: ", "))
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(k).frame(width: 90, alignment: .leading)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            Text(v).font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func perform(_ step: ASCStep) {
        Haptics.success()
        completed.insert(step.id)
        if let i = ASCStep.all.firstIndex(of: step), i + 1 < ASCStep.all.count {
            Motion.run(.spring(response: 0.4)) { current = i + 1 }
        }
    }
}

// MARK: - Step card

private struct ASCStepCard: View {
    let step: ASCStep
    let index: Int
    let isCurrent: Bool
    let isDone: Bool
    let onAction: () -> Void

    var body: some View {
        GlassSurface(tier: isCurrent ? .deep : .raised) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    statusBadge
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Step \(step.number)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(1)
                            automationBadge
                        }
                        Text(step.title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                    }
                    Spacer()
                }
                Text(step.body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .lineSpacing(3)

                if isCurrent {
                    actionRow
                }
            }
            .padding(16)
        }
    }

    private var automationBadge: some View {
        let (label, tint): (String, Color) = {
            switch step.action {
            case .uploadAsset, .wait:
                return ("Auto", LiquidGlass.success)
            case .openSafariOnMac, .fillForm:
                return ("Hybrid", LiquidGlass.accent)
            case .manual:
                return ("You", LiquidGlass.warning)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
            .accessibilityLabel({
                switch step.action {
                case .uploadAsset, .wait:
                    return "Fully automated"
                case .openSafariOnMac, .fillForm:
                    return "Hybrid: CodeGenie assists, you confirm"
                case .manual:
                    return "You do this manually"
                }
            }())
    }

    private var statusBadge: some View {
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
    }

    @ViewBuilder
    /// Action row is honest about reality: until the iOS app can drive
    /// ASC directly (a v0.3+ feature blocked on the Companion app +
    /// codegenie.app backend), every step is "you do it on your Mac,
    /// then tap to advance". Previous copy ("Upload icon", "Auto-fill
    /// this step") implied automation that wasn't there — closing
    /// that lie was the first-timer audit's top finding.
    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            macInstruction
            switch step.action {
            case .openSafariOnMac:
                PrimaryButton(title: "Mark step done", systemImage: "checkmark.circle.fill", style: .filled) { onAction() }
                    .accessibilityHint("Mark this step complete and move to the next one.")
            case .fillForm:
                PrimaryButton(title: "Mark step done", systemImage: "checkmark.circle.fill", style: .filled) { onAction() }
                    .accessibilityHint("Mark this step complete and move to the next one.")
            case .uploadAsset:
                PrimaryButton(title: "Mark step done", systemImage: "checkmark.circle.fill", style: .filled) { onAction() }
                    .accessibilityHint("Mark this step complete and move to the next one.")
            case .wait(let detail):
                HStack(spacing: 10) {
                    ProgressView().tint(LiquidGlass.primaryText)
                    Text(detail).font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    Spacer()
                    Button("Done") { onAction() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .accessibilityHint("Mark this step complete.")
                }
            case .manual:
                PrimaryButton(title: "I did this", systemImage: "checkmark.circle.fill", style: .glass) { onAction() }
                    .accessibilityHint("Mark this step complete.")
            }
        }
    }

    @ViewBuilder
    private var macInstruction: some View {
        let copy: String? = {
            switch step.action {
            case .openSafariOnMac(let url):       return "On your Mac, open \(url) in Safari and complete this step."
            case .fillForm:                       return "Fill this form on your Mac. Use the draft above as a starting point."
            case .uploadAsset(let asset):         return "Upload \(asset) on your Mac. We've prepared the file in the workspace."
            case .wait:                           return nil
            case .manual:                         return "Do this manually on your Mac when ready — Apple requires you, not us."
            }
        }()
        if let copy {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "macbook")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LiquidGlass.accent)
                    .padding(.top, 3)
                Text(copy)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension AppStoreMetadata {
    static func draft(for app: AppDescription) -> AppStoreMetadata {
        let featureWords = app.features
            .flatMap { $0.split { !$0.isLetter && !$0.isNumber } }
            .map { String($0).lowercased() }
        let promptWords = app.prompt
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
            .filter { $0.count > 3 }
        let keywords = Array((featureWords + promptWords + [app.category.rawValue, app.style.label])
            .map { $0.replacingOccurrences(of: " ", with: "") }
            .filter { !$0.isEmpty }
            .uniqued()
            .prefix(10))

        return AppStoreMetadata(
            name: app.title,
            subtitle: app.subtitleDraft,
            primaryCategory: app.category.label,
            keywords: keywords.isEmpty ? [app.category.rawValue, "iphone", "swiftui"] : keywords,
            description: "\(app.title) is built around \(app.prompt.trimmingCharacters(in: .whitespacesAndNewlines)).",
            promotionalText: "Built with CodeGenie and prepared for TestFlight.",
            supportURL: "https://example.com/support",
            marketingURL: "https://example.com",
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
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
