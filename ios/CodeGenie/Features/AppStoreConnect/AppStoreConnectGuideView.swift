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
    private var actionRow: some View {
        switch step.action {
        case .openSafariOnMac(let url):
            PrimaryButton(title: "Open on my Mac", systemImage: "macbook", style: .filled) { onAction() }
                .accessibilityHint("Opens \(url) in your Mac's Safari")
        case .fillForm:
            PrimaryButton(title: "Auto-fill this step", systemImage: "wand.and.stars", style: .filled) { onAction() }
        case .uploadAsset(let asset):
            PrimaryButton(title: "Upload \(asset)", systemImage: "icloud.and.arrow.up", style: .filled) { onAction() }
        case .wait(let detail):
            HStack(spacing: 10) {
                ProgressView().tint(LiquidGlass.primaryText)
                Text(detail).font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                Spacer()
                Button("Mark done") { onAction() }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
            }
        case .manual:
            PrimaryButton(title: "I did this", systemImage: "checkmark.circle.fill", style: .glass) { onAction() }
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
