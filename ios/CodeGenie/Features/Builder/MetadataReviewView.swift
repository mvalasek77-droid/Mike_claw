import SwiftUI

/// Phase 4: Review and edit auto-generated App Store metadata,
/// screenshots, and prepare for upload.
///
/// The server pre-fills all fields with AI-generated content;
/// the user reviews, adjusts, and then uploads the build to
/// App Store Connect.
struct MetadataReviewView: View {
    let job: BuildJob
    @ObservedObject var pipeline: PipelineClient
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var appName: String = ""
    @State private var subtitle: String = ""
    @State private var keywords: String = ""
    @State private var description: String = ""
    @State private var promotionalText: String = ""
    @State private var privacyPolicyURL: String = ""
    @State private var category: String = ""
    @State private var whatsNew: String = ""

    @State private var screenshotURLs: [String] = []
    @State private var isGeneratingMetadata: Bool = false
    @State private var isTakingScreenshots: Bool = false
    @State private var isUploading: Bool = false
    @State private var uploadResult: PipelineClient.UploadResult?
    @State private var metadataGenerated: Bool = false

    // TestFlight group
    @State private var tfGroupEmails: String = ""
    @State private var tfGroupName: String = "Beta testers"

    // Compliance
    @State private var usesEncryption: Bool = false
    @State private var exportsCompliance: Bool = false
    @State private var contentRatingConfirmed: Bool = false

    @State private var navigateToShip: Bool = false
    @State private var error: String?

    // Placeholder strings from AI metadata generation
    @State private var placeholderName: String = "My App"
    @State private var placeholderSubtitle: String = "Your app tagline"
    @State private var placeholderKeywords: String = "productivity, utility, swift"
    @State private var placeholderDescription: String = ""
    @State private var placeholderPromo: String = ""
    @State private var placeholderPrivacy: String = "https://example.com/privacy"

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    if !metadataGenerated {
                        generateMetadataSection
                    }

                    if metadataGenerated {
                        formSection
                        screenshotsSection
                        testFlightSection
                        complianceSection
                        uploadSection
                        actionsSection
                    }

                    if let err = error {
                        errorBanner(err)
                    }

                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .navigationDestination(isPresented: $navigateToShip) {
            ShipConfirmView(job: job, pipeline: pipeline)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("App Store Metadata")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Review and edit your listing before upload.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            }
            Spacer()
        }
    }

    // MARK: - Generate metadata

    private var generateMetadataSection: some View {
        GlassSurface(tier: .deep) {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                Text("Generate App Store listing")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("AI will create your app's name, description, keywords, and more — you can edit everything afterwards.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)

                PrimaryButton(
                    title: isGeneratingMetadata ? "Generating…" : "Generate metadata",
                    systemImage: "sparkles",
                    style: .filled
                ) {
                    Task { await generateMetadata() }
                }
                .disabled(isGeneratingMetadata)
            }
            .padding(24)
        }
    }

    // MARK: - Form

    private var formSection: some View {
        GlassCard(title: "Listing details", icon: "text.page.fill", tint: LiquidGlass.accent) {
            VStack(spacing: 14) {
                fieldRow(label: "App Name", placeholder: placeholderName, text: $appName)
                fieldRow(label: "Subtitle", placeholder: placeholderSubtitle, text: $subtitle)
                fieldRow(label: "Keywords", placeholder: placeholderKeywords, text: $keywords)
                fieldRow(label: "What's New", placeholder: "Initial release", text: $whatsNew)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    TextField(placeholderDescription, text: $description, axis: .vertical)
                        .lineLimit(5...12)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                }

                fieldRow(label: "Promotional Text", placeholder: placeholderPromo, text: $promotionalText)
                fieldRow(label: "Privacy Policy URL", placeholder: placeholderPrivacy, text: $privacyPolicyURL)
                fieldRow(label: "Category", placeholder: category, text: $category)
            }
        }
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
        }
    }

    // MARK: - Screenshots

    private var screenshotsSection: some View {
        GlassCard(title: "Screenshots", icon: "photo.on.rectangle.angled", tint: LiquidGlass.accentSecondary) {
            VStack(spacing: 12) {
                if screenshotURLs.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.06))
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.3))
                                )
                                .frame(width: 80, height: 160)
                        }
                    }
                    PrimaryButton(
                        title: isTakingScreenshots ? "Taking screenshots…" : "Auto-take screenshots",
                        systemImage: "camera.shutter.button",
                        style: .glass
                    ) {
                        Task { await takeScreenshots() }
                    }
                    .disabled(isTakingScreenshots)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(screenshotURLs, id: \.self) { urlStr in
                                AsyncImage(url: URL(string: urlStr)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 80, height: 160)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    default:
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.white.opacity(0.06))
                                            .frame(width: 80, height: 160)
                                            .overlay(ProgressView().tint(LiquidGlass.primaryText))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - TestFlight

    private var testFlightSection: some View {
        GlassCard(title: "TestFlight Group", icon: "person.2.fill", tint: LiquidGlass.accent) {
            VStack(spacing: 12) {
                fieldRow(label: "Group name", placeholder: "Beta testers", text: $tfGroupName)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Email addresses (one per line)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    TextField("alice@example.com\nbob@example.com", text: $tfGroupEmails, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                }
            }
        }
    }

    // MARK: - Compliance

    private var complianceSection: some View {
        GlassCard(title: "Compliance", icon: "checkmark.shield.fill", tint: LiquidGlass.success) {
            VStack(spacing: 12) {
                complianceToggle(title: "This app does not use custom encryption", isOn: $usesEncryption.inverted)
                complianceToggle(title: "Export compliance confirmed", isOn: $exportsCompliance)
                complianceToggle(title: "Age rating confirmed", isOn: $contentRatingConfirmed)
            }
        }
    }

    private func complianceToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
        }
        .tint(LiquidGlass.accent)
    }

    // MARK: - Upload

    private var uploadSection: some View {
        GlassSurface(tier: .deep) {
            VStack(spacing: 12) {
                if let result = uploadResult, result.ok {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(LiquidGlass.success)
                        Text("Build uploaded — build \(result.buildNumber)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.success)
                    }
                } else {
                    PrimaryButton(
                        title: isUploading ? "Uploading…" : "Upload Build to App Store Connect",
                        systemImage: "arrow.up.doc.fill",
                        style: .filled
                    ) {
                        Task { await uploadBuild() }
                    }
                    .disabled(isUploading || !allComplianceConfirmed)
                    .opacity(allComplianceConfirmed ? 1.0 : 0.5)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var allComplianceConfirmed: Bool {
        !usesEncryption && exportsCompliance && contentRatingConfirmed
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if metadataGenerated {
                PrimaryButton(title: "Continue to Ship →", systemImage: "paperplane.fill", style: .filled) {
                    Haptics.success()
                    navigateToShip = true
                }
            }
        }
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.red.opacity(0.9))
        }
        .padding(12)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Logic

    private func generateMetadata() async {
        isGeneratingMetadata = true
        error = nil
        defer { isGeneratingMetadata = false }
        do {
            let jobID = session.currentJobBackendID ?? ""
            let result = try await pipeline.generateMetadata(jobID: jobID)
            withAnimation(Motion.spring) {
                appName = result.name
                placeholderName = result.name
                subtitle = result.subtitle
                placeholderSubtitle = result.subtitle
                keywords = result.keywords.joined(separator: ", ")
                placeholderKeywords = result.keywords.joined(separator: ", ")
                description = result.description
                placeholderDescription = result.description
                promotionalText = result.promotionalText
                placeholderPromo = result.promotionalText
                privacyPolicyURL = result.privacyPolicyURL
                placeholderPrivacy = result.privacyPolicyURL
                category = result.category
                metadataGenerated = true
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }

    private func takeScreenshots() async {
        isTakingScreenshots = true
        defer { isTakingScreenshots = false }
        do {
            let jobID = session.currentJobBackendID ?? ""
            let result = try await pipeline.takeScreenshots(jobID: jobID)
            withAnimation(Motion.spring) {
                screenshotURLs = result.screenshotURLs
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }

    private func uploadBuild() async {
        isUploading = true
        error = nil
        defer { isUploading = false }
        do {
            let jobID = session.currentJobBackendID ?? ""
            let result = try await pipeline.uploadBuild(jobID: jobID)
            withAnimation(Motion.spring) {
                uploadResult = result
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
    }
}

// MARK: - Bool inversion helper for compliance toggle

private extension Binding where Value == Bool {
    var inverted: Binding<Bool> {
        Binding<Bool>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}