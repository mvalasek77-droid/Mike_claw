import SwiftUI
import UIKit

struct ReleaseGatewayView: View {
    @Environment(\.dismiss) private var dismiss

    private let appStoreValues: [(String, String, String)] = [
        ("Platform", "iOS", "Choose this when creating the app record."),
        ("Name", "ChadDrop", "Public App Store name if Apple says it is available."),
        ("Bundle ID", "com.valasek.chaddrop", "Must match the Xcode app."),
        ("SKU", "CHADDROP-IOS-1", "Private inventory code. Users do not see it."),
        ("Category", "Lifestyle", "Best App Store fit."),
        ("Subtitle", "Decode texts with humor.", "Short line shown under the app name."),
        ("Keywords", "text,dating,relationships,advice,humor,chat,replies,messages", "Paste without spaces after commas.")
    ]

    private let commands: [(String, String)] = [
        ("Open local guide", "TruthTranslator/Scripts/open_release_gateway.sh"),
        ("Open release links", "TruthTranslator/Scripts/open_release_gateway.sh --links"),
        ("Create app icon", "TruthTranslator/Scripts/create_app_icon.sh"),
        ("Run preflight", "TruthTranslator/Scripts/release_preflight.sh"),
        ("Capture screenshots", "TruthTranslator/Scripts/capture_appstore_screenshots.sh"),
        ("Xcode Cloud scripts", "TruthTranslator/ci_scripts"),
        ("Create support site", "TruthTranslator/Scripts/publish_github_pages_site.sh chaddrop-support public")
    ]

    private let placeholderValues: [(String, String, String)] = [
        ("Where", "App Store Connect -> Apps -> + -> New App", "This creates the placeholder record before upload."),
        ("Record status", "Prepare for Submission", "This is the normal status after the placeholder is created."),
        ("Bundle ID", "com.valasek.chaddrop", "If missing, create it in Apple Developer or let Xcode automatic signing create it."),
        ("SKU", "CHADDROP-IOS-1", "Private code for Apple only."),
        ("User access", "Full Access", "Simplest option for a single-owner launch.")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        releasePath
                        appPlaceholderPanel
                        iconCreatorPanel
                        automationStatus
                        signingGuide
                        xcodeCloudPanel
                        appStoreValuesPanel
                        subscriptionsPanel
                        screenshotsPanel
                        iphoneCapturePanel
                        privacyPanel
                        aiPanel
                        linksPanel
                        commandPanel
                        finalApprovalPanel
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 28)
                }
            }
            .navigationTitle("Release Gateway")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
    }

    private var hero: some View {
        ReleasePanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("ChadDrop Release Gateway", systemImage: "paperplane.circle.fill")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("A no-code map for getting this app from simulator to App Store. It shows what CodeGenie can automate, what you must approve, and what to paste into Apple screens.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var releasePath: some View {
        ReleasePanel(title: "The release path", icon: "arrow.triangle.branch") {
            VStack(spacing: 10) {
                ReleaseStepRow(number: "1", title: "ChadDrop app", text: "Generated, built, simulator tested, and archived unsigned.")
                ReleaseStepRow(number: "2", title: "Signing", text: "You sign in to Apple. Xcode creates the trusted developer paperwork.")
                ReleaseStepRow(number: "3", title: "App Store Connect", text: "Create the ChadDrop app record with the values below.")
                ReleaseStepRow(number: "4", title: "Screenshots and privacy", text: "CodeGenie can capture screenshots and prepare the privacy answers.")
                ReleaseStepRow(number: "5", title: "Submit", text: "You press the final App Review confirmation button.")
            }
        }
    }

    private var automationStatus: some View {
        VStack(spacing: 10) {
            ReleaseStatusCard(
                title: "Already automated",
                icon: "checkmark.seal.fill",
                tint: AppTheme.lime,
                text: "Builds, simulator launch, screenshot smoke test, test bundle compile, plist checks, icon checks, and unsigned archive."
            )
            ReleaseStatusCard(
                title: "Automated after you sign in",
                icon: "wand.and.stars",
                tint: AppTheme.lavender,
                text: "Xcode Cloud signed builds, TestFlight delivery, more screenshots, GitHub Pages support site, and AI proxy deployment after account prompts are approved."
            )
            ReleaseStatusCard(
                title: "Must be approved by you",
                icon: "hand.raised.fill",
                tint: AppTheme.orange,
                text: "Apple payment, passwords, two-factor codes, legal agreements, private API keys, and final App Review submission."
            )
        }
    }

    private var appPlaceholderPanel: some View {
        ReleasePanel(title: "App placeholder creation", icon: "plus.app.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("The placeholder is the App Store Connect record for ChadDrop. It reserves the app setup screen and gives Apple a place to receive builds, screenshots, privacy answers, and review notes.")
                    .releaseBody()

                ReleaseStepRow(number: "1", title: "Open App Store Connect", text: "Go to Apps, press the plus button, then choose New App.")
                ReleaseStepRow(number: "2", title: "Fill the New App form", text: "Use iOS, ChadDrop, English (U.S.), com.valasek.chaddrop, and CHADDROP-IOS-1.")
                ReleaseStepRow(number: "3", title: "Create the record", text: "Apple should show the app as Prepare for Submission. That means the placeholder is ready.")
                ReleaseStepRow(number: "4", title: "Hand back to CodeGenie", text: "After the placeholder exists, CodeGenie can build/upload once signing is configured.")

                ForEach(placeholderValues, id: \.0) { row in
                    CopyValueRow(label: row.0, value: row.1, note: row.2)
                }
            }
        }
    }

    private var iconCreatorPanel: some View {
        ReleasePanel(title: "App icon creator", icon: "paintbrush.pointed.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("The icon creator makes a 1024 x 1024 ChadDrop icon, puts it in the Xcode asset catalog, and checks that it has no alpha channel. Apple reads the icon from the uploaded build.")
                    .releaseBody()

                ReleaseStepRow(number: "1", title: "Generate the icon", text: "Run the command below. It writes AppIcon-1024.png into the app icon asset catalog.")
                ReleaseStepRow(number: "2", title: "Check the icon", text: "The script prints width, height, and alpha. You want 1024, 1024, and hasAlpha: no.")
                ReleaseStepRow(number: "3", title: "Rebuild the app", text: "After changing the icon, rebuild or archive so Apple receives the new icon inside the app.")

                CopyValueRow(
                    label: "Icon command",
                    value: "TruthTranslator/Scripts/create_app_icon.sh",
                    note: "Run from the repo root. No Apple account needed."
                )
                CopyValueRow(
                    label: "Icon file",
                    value: "TruthTranslator/TruthTranslator/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
                    note: "This is the app icon asset Xcode packages into the build."
                )
            }
        }
    }

    private var signingGuide: some View {
        ReleasePanel(title: "Signing in plain English", icon: "signature") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Signing is Apple proving ChadDrop came from your Apple Developer account. The app cannot be uploaded until Apple knows which team owns com.valasek.chaddrop.")
                    .releaseBody()

                ReleaseStepRow(number: "A", title: "Open Xcode Accounts", text: "Xcode -> Settings -> Accounts. Add your Apple ID and finish two-factor authentication.")
                ReleaseStepRow(number: "B", title: "Choose your team", text: "Open the TruthTranslator target, then Signing & Capabilities, then select your Apple Developer Team.")
                ReleaseStepRow(number: "C", title: "Let CodeGenie build", text: "After the team is selected, CodeGenie can run the archive/upload commands.")
            }
        }
    }

    private var xcodeCloudPanel: some View {
        ReleasePanel(title: "Avoid local signing with Xcode Cloud", icon: "cloud.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use this path when you want Apple to build and sign ChadDrop in App Store Connect instead of fighting local signing on this Mac. CodeGenie prepared the ci_scripts folder so cloud builds have clean setup checks.")
                    .releaseBody()

                ReleaseStepRow(number: "1", title: "Create the app record", text: "App Store Connect needs ChadDrop first: iOS, com.valasek.chaddrop, SKU CHADDROP-IOS-1.")
                ReleaseStepRow(number: "2", title: "Open Xcode Cloud", text: "In Xcode, open the Report Navigator, choose Cloud, then Get Started. Grant Apple access to the GitHub repo when asked.")
                ReleaseStepRow(number: "3", title: "Create workflow", text: "Use scheme TruthTranslator. Add Test on a recommended iPhone simulator and Archive for TestFlight internal testing.")
                ReleaseStepRow(number: "4", title: "Watch the build", text: "The cloud build signs inside Apple after your account approvals. If it passes, the build appears in TestFlight.")
                ReleaseStepRow(number: "5", title: "Submit later", text: "Use TestFlight first. Keep final App Review submission as a human confirmation.")

                CopyValueRow(label: "Scheme", value: "TruthTranslator", note: "Use this in Xcode Cloud workflow actions.")
                CopyValueRow(label: "Bundle ID", value: "com.valasek.chaddrop", note: "Must match the App Store Connect record.")
                CopyValueRow(label: "CI scripts folder", value: "TruthTranslator/ci_scripts", note: "Apple runs these during Xcode Cloud builds.")
            }
        }
    }

    private var appStoreValuesPanel: some View {
        ReleasePanel(title: "App Store values", icon: "app.badge") {
            VStack(spacing: 10) {
                ForEach(appStoreValues, id: \.0) { row in
                    CopyValueRow(label: row.0, value: row.1, note: row.2)
                }
            }
        }
    }

    private var subscriptionsPanel: some View {
        ReleasePanel(title: "Subscriptions", icon: "crown.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Prices are configured in App Store Connect. The app only needs product IDs that exactly match the subscription products Apple returns to StoreKit.")
                    .releaseBody()

                ReleaseStepRow(number: "1", title: "Create group", text: "In App Store Connect -> Subscriptions, create a group named ChadDrop Pro.")
                ReleaseStepRow(number: "2", title: "Add weekly", text: "Create a one-week auto-renewable subscription using the product ID below.")
                ReleaseStepRow(number: "3", title: "Add annual", text: "Create a one-year auto-renewable subscription and set the U.S. price to $29.99.")
                ReleaseStepRow(number: "4", title: "Add metadata", text: "Add English display names and descriptions for both products. Missing metadata usually means these localization fields are blank.")
                ReleaseStepRow(number: "5", title: "Submit with app", text: "For the first subscription review, attach both subscriptions to the app version before submitting.")

                CopyValueRow(label: "Group display name", value: "ChadDrop Pro", note: "User-facing subscription group name.")
                CopyValueRow(label: "Weekly product ID", value: "com.valasek.chaddrop.premium.weekly", note: "Use exactly this value in App Store Connect.")
                CopyValueRow(label: "Weekly display name", value: "ChadDrop Pro Weekly", note: "Paste under English (U.S.) localization.")
                CopyValueRow(label: "Weekly description", value: "Unlimited ChadDrop decodes and suggested replies for one week.", note: "Required subscription metadata.")
                CopyValueRow(label: "Annual product ID", value: "com.valasek.chaddrop.premium.annual", note: "Use exactly this value in App Store Connect.")
                CopyValueRow(label: "Annual display name", value: "ChadDrop Pro Annual", note: "Paste under English (U.S.) localization.")
                CopyValueRow(label: "Annual description", value: "Unlimited ChadDrop decodes and suggested replies for one year.", note: "Required subscription metadata.")
                CopyValueRow(label: "Annual price", value: "US$29.99", note: "Change from the old US$24.99 target in App Store Connect, not in Swift.")
            }
        }
    }

    private var screenshotsPanel: some View {
        ReleasePanel(title: "Screenshots", icon: "camera.viewfinder") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Screenshots are what users see on the App Store page. CodeGenie can capture simulator screenshots, but you still choose which ones look best before upload.")
                    .releaseBody()

                ReleaseStepRow(number: "1", title: "Boot a simulator", text: "Use a large iPhone simulator first. App Store Connect will show any extra sizes it wants.")
                ReleaseStepRow(number: "2", title: "Capture the app", text: "Run the screenshot script. It builds, installs, launches, and saves images in AppStore/Screenshots.")
                ReleaseStepRow(number: "3", title: "Pick clean shots", text: "Use public ChadDrop feature screens: paste screen, decoded result, suggested replies. Do not use internal release-gateway screenshots for the public listing.")
                ReleaseStepRow(number: "4", title: "Upload in Apple", text: "In the app version page, upload screenshots under the iOS screenshot area. Apple can scale high-resolution screenshots for related device sizes.")

                CopyValueRow(
                    label: "Screenshot command",
                    value: "TruthTranslator/Scripts/capture_appstore_screenshots.sh",
                    note: "Run from the repo root after a simulator is booted."
                )
                CopyValueRow(
                    label: "Screenshot folder",
                    value: "TruthTranslator/AppStore/Screenshots",
                    note: "The script opens this folder after capture."
                )
            }
        }
    }

    private var iphoneCapturePanel: some View {
        ReleasePanel(title: "Real iPhone capture walkthrough", icon: "iphone.gen3") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use this when the user wants screenshots from a real iPhone instead of the simulator. CodeGenie can guide the steps, but the person holding the phone must press the buttons and approve trust prompts.")
                    .releaseBody()

                ReleaseStepRow(number: "1", title: "Install on iPhone", text: "Connect the iPhone to the Mac, trust the computer, sign in to Xcode, choose your Apple Developer Team, then run the app from Xcode.")
                ReleaseStepRow(number: "2", title: "Capture the screen", text: "Open ChadDrop on the phone. Press Side Button + Volume Up to take each screenshot.")
                ReleaseStepRow(number: "3", title: "Send to Mac", text: "Use AirDrop, Photos import, or Image Capture to move screenshots to the Mac.")
                ReleaseStepRow(number: "4", title: "Place in folder", text: "Put the chosen images in TruthTranslator/AppStore/Screenshots/Public before uploading to App Store Connect.")

                CopyValueRow(
                    label: "Public screenshot folder",
                    value: "TruthTranslator/AppStore/Screenshots/Public",
                    note: "Keep only the screenshots you want Apple to see."
                )
            }
        }
    }

    private var privacyPanel: some View {
        ReleasePanel(title: "Privacy answers", icon: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 10) {
                ReleaseChoiceRow(title: "Offline mode", badge: "Fastest", text: "Tracking: No. Data collection: None. Third-party advertising: No.", tint: AppTheme.lime)
                ReleaseChoiceRow(title: "AI proxy mode", badge: "Optional", text: "Tracking: No. User Content is processed only for App Functionality. Do not log raw pasted messages.", tint: AppTheme.lavender)
                Text("Never put an OpenAI key inside the iPhone app. Keep it on the server proxy.")
                    .releaseBody()
            }
        }
    }

    private var aiPanel: some View {
        ReleasePanel(title: "AI decision", icon: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 10) {
                ReleaseChoiceRow(title: "Ship offline first", badge: "Recommended", text: "Use the built-in rule engine and get through App Store setup with simpler privacy answers.", tint: AppTheme.lime)
                ReleaseChoiceRow(title: "Ship with AI", badge: "More setup", text: "Deploy the Cloudflare Worker, store OPENAI_API_KEY as a server secret, then set AI_PROXY_URL.", tint: AppTheme.orange)
            }
        }
    }

    private var linksPanel: some View {
        ReleasePanel(title: "Open account pages", icon: "link") {
            VStack(spacing: 10) {
                ReleaseLinkRow(title: "App Store Connect", subtitle: "Create app record, upload build, submit review", url: "https://appstoreconnect.apple.com/apps")
                ReleaseLinkRow(title: "Xcode Cloud setup", subtitle: "Apple cloud build and TestFlight workflow", url: "https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow/")
                ReleaseLinkRow(title: "Apple Developer", subtitle: "Enrollment, signing account, certificates", url: "https://developer.apple.com/account/")
                ReleaseLinkRow(title: "GitHub new repo", subtitle: "Support and privacy site", url: "https://github.com/new")
                ReleaseLinkRow(title: "Cloudflare Workers", subtitle: "Optional AI proxy hosting", url: "https://dash.cloudflare.com/?to=/:account/workers-and-pages")
                ReleaseLinkRow(title: "OpenAI API Keys", subtitle: "Optional AI key for server proxy only", url: "https://platform.openai.com/api-keys")
            }
        }
    }

    private var commandPanel: some View {
        ReleasePanel(title: "Commands CodeGenie can run", icon: "terminal.fill") {
            VStack(spacing: 10) {
                ForEach(commands, id: \.0) { command in
                    CopyValueRow(label: command.0, value: command.1, note: "Copy this if you want to run it from Terminal.")
                }
            }
        }
    }

    private var finalApprovalPanel: some View {
        ReleasePanel(title: "Final approval", icon: "person.crop.circle.badge.checkmark") {
            Text("CodeGenie can prepare the build, metadata, screenshots, privacy text, support site, and links. You should confirm the final App Review submission because Apple treats that as a legal account action.")
                .releaseBody()
        }
    }
}

private struct ReleasePanel<Content: View>: View {
    var title: String?
    var icon: String?
    let content: Content

    init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: icon ?? "circle.fill")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            content
        }
        .padding(16)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
    }
}

private struct ReleaseStepRow: View {
    let number: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(AppTheme.lavender.opacity(0.22), in: Circle())
                .overlay(Circle().stroke(AppTheme.lavender.opacity(0.32)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(text)
                    .releaseBody()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ReleaseStatusCard: View {
    let title: String
    let icon: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(text)
                    .releaseBody()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.24)))
    }
}

private struct ReleaseChoiceRow: View {
    let title: String
    let badge: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(badge)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.13), in: Capsule())
                Spacer(minLength: 0)
            }
            Text(text)
                .releaseBody()
        }
        .padding(12)
        .background(AppTheme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct CopyValueRow: View {
    let label: String
    let value: String
    let note: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.lavender)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = value
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(IconButtonStyle(size: 38))
            .accessibilityLabel("Copy \(label)")
        }
        .padding(12)
        .background(AppTheme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ReleaseLinkRow: View {
    let title: String
    let subtitle: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "safari.fill")
                    .foregroundStyle(AppTheme.lavender)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(12)
            .background(AppTheme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private extension Text {
    func releaseBody() -> some View {
        self
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.74))
            .fixedSize(horizontal: false, vertical: true)
    }
}
