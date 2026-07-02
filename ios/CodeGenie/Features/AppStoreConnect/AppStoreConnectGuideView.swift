import SwiftUI
import UIKit

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
              body: "Click '+' → New App, then fill: platform = iOS, your app's name, default language, the bundle ID matching your Xcode target, and any unique SKU (your bundle ID works). Copy the draft below for the exact values.",
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
              body: "CodeGenie drafted your Name, Subtitle, Promotional Text, Description, and Keywords (shown in the Listing draft card above). Copy the draft and paste each field into App Store Connect.",
              action: .fillForm,
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 6,
              title: "Privacy & data collection",
              body: "Answer Apple's privacy questions honestly. For a typical CodeGenie build with no analytics SDKs: 'Data not collected' — unless YOUR app's features collect anything (accounts, location, health). When in doubt, say what your app actually does.",
              action: .fillForm,
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 7,
              title: "Pricing & availability",
              body: "In Pricing and Availability choose Free (or a price tier) and which countries. Free + all territories is the simplest first launch.",
              action: .fillForm,
              safariRoute: "https://appstoreconnect.apple.com/apps"),

        .init(number: 8,
              title: "Validate and upload the build",
              body: "Once an App Store IPA exists, CodeGenie runs Apple's validate-app and upload-app flow, streams every line, then polls processing with your ASC API key.",
              action: .uploadAsset("Build.ipa"),
              safariRoute: nil),

        .init(number: 9,
              title: "Wait for processing",
              body: "Apple takes 5–30 minutes to process the binary. Check back in App Store Connect → TestFlight; when the build appears there it's selectable in the listing.",
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
    @Environment(\.openURL) private var openURL
    @State private var current: Int = 0
    @State private var completed: Set<UUID> = []
    @State private var metadata: AppStoreMetadata
    @State private var showPairMac = false
    @State private var banner: String?
    @State private var macBusy = false
    @StateObject private var creds = Credentials.shared
    @StateObject private var bridge = CompanionBridge()

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
                if let banner {
                    Text(banner)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 4)
                        .transition(.opacity)
                }
                ScrollView {
                    VStack(spacing: 16) {
                        legendCard
                        metadataCard
                        ForEach(ASCStep.all) { step in
                            ASCStepCard(
                                step: step,
                                index: ASCStep.all.firstIndex(of: step) ?? 0,
                                isCurrent: ASCStep.all.firstIndex(of: step) == current,
                                isDone: completed.contains(step.id)
                            ) {
                                actionRow(for: step)
                            }
                        }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showPairMac) {
            PairMacView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: Step actions — every button does what it says, or says
    // plainly that the step is manual. No decorative automation.

    @ViewBuilder
    private func actionRow(for step: ASCStep) -> some View {
        switch step.action {
        case .openSafariOnMac(let url):
            openPageActions(url: url, step: step)
        case .fillForm:
            VStack(spacing: 8) {
                PrimaryButton(title: "Copy draft for this step", systemImage: "doc.on.doc.fill", style: .filled) {
                    copyListingDraft()
                }
                if let route = step.safariRoute {
                    openPageActions(url: route, step: step, markDoneOnOpen: false)
                }
                markDoneLink(step, label: "I've filled it in — mark done")
            }
        case .uploadAsset(let asset):
            VStack(spacing: 8) {
                Text(asset == "Build.ipa"
                     ? "This upload runs from the build screen's Submit flow — it happens automatically once you tap Submit to App Store there."
                     : "CodeGenie prepares \(asset) in your workspace download. Add it in App Store Connect, then mark this done.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                markDoneLink(step, label: "Mark step done")
            }
        case .wait(let detail):
            HStack(spacing: 10) {
                ProgressView().tint(LiquidGlass.primaryText)
                Text(detail).font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                Spacer()
                Button("Mark done") { markDone(step) }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
            }
        case .manual:
            PrimaryButton(title: "I did this", systemImage: "checkmark.circle.fill", style: .glass) {
                markDone(step)
            }
        }
    }

    /// Real "open this page" actions: drives the paired Mac's Safari
    /// when a Companion is connected, offers pairing when not, and
    /// always has an open-on-this-iPhone fallback so nobody is stuck.
    @ViewBuilder
    private func openPageActions(url: String, step: ASCStep, markDoneOnOpen: Bool = true) -> some View {
        VStack(spacing: 8) {
            if creds.hasCompanionPairing {
                PrimaryButton(
                    title: macBusy ? "Opening on your Mac…" : "Open on my Mac",
                    systemImage: "macbook",
                    style: .filled
                ) {
                    Task { await openOnMac(url, step: step, markDone: markDoneOnOpen) }
                }
                .disabled(macBusy)
            } else {
                PrimaryButton(title: "Pair a Mac to drive Safari", systemImage: "macbook.and.iphone", style: .filled) {
                    Haptics.selection()
                    showPairMac = true
                }
                Text("No Mac paired. You can pair one now, or do this step on this phone instead.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Haptics.selection()
                if let u = URL(string: url) { openURL(u) }
                if markDoneOnOpen { markDone(step) }
            } label: {
                Label("Open on this iPhone instead", systemImage: "safari")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
            }
            .buttonStyle(.plain)
            if markDoneOnOpen {
                markDoneLink(step, label: "Already did this — mark done")
            }
        }
    }

    private func markDoneLink(_ step: ASCStep, label: String) -> some View {
        Button {
            markDone(step)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)
        }
        .buttonStyle(.plain)
    }

    private func openOnMac(_ url: String, step: ASCStep, markDone: Bool) async {
        macBusy = true
        defer { macBusy = false }
        do {
            if bridge.status != .connected {
                guard await bridge.connectStoredPairing() else {
                    throw BridgeError.notConnected
                }
            }
            try await bridge.openSafari(url)
            banner = "Opened in Safari on your Mac — finish the step there."
            Haptics.success()
            if markDone { self.markDone(step, advance: true) }
        } catch {
            banner = "Couldn't reach your Mac (\(error)). Check it's awake and on the same Wi-Fi, or use \"Open on this iPhone instead\"."
            Haptics.error()
        }
    }

    private func copyListingDraft() {
        UIPasteboard.general.string = """
        Name: \(metadata.name)
        Subtitle: \(metadata.subtitle)
        Promotional text: \(metadata.promotionalText)
        Description: \(metadata.description)
        Keywords: \(metadata.keywords.joined(separator: ","))
        """
        banner = "Listing draft copied — paste each field into App Store Connect."
        Haptics.success()
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

    private func markDone(_ step: ASCStep, advance: Bool = true) {
        Haptics.success()
        completed.insert(step.id)
        if advance, let i = ASCStep.all.firstIndex(of: step), i + 1 < ASCStep.all.count {
            Motion.run(.spring(response: 0.4)) { current = i + 1 }
        }
    }
}

// MARK: - Step card

private struct ASCStepCard<Actions: View>: View {
    let step: ASCStep
    let index: Int
    let isCurrent: Bool
    let isDone: Bool
    @ViewBuilder let actions: () -> Actions

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
                    actions()
                }
            }
            .padding(16)
        }
    }

    private var automationBadge: some View {
        // Labels must match what the buttons actually do: the IPA
        // upload is the only truly automated asset step (via Submit
        // on the build screen); other uploads are hybrid at best.
        let (label, tint): (String, Color) = {
            switch step.action {
            case .wait:
                return ("Auto", LiquidGlass.success)
            case .uploadAsset(let asset):
                return asset == "Build.ipa" ? ("Auto", LiquidGlass.success) : ("Hybrid", LiquidGlass.accent)
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
                switch label {
                case "Auto":
                    return "Fully automated"
                case "Hybrid":
                    return "Hybrid: CodeGenie assists, you confirm"
                default:
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
