import SwiftUI

/// Phase 5: Final confirmation before submitting to App Store Review.
///
/// Shows a summary card with app icon, name, version, screenshots,
/// and a big "Submit to App Store Review" button. Status tracking
/// for the review process once submitted.
struct ShipConfirmView: View {
    let job: BuildJob
    @ObservedObject var pipeline: PipelineClient
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var submissionStatus: SubmissionStatus = .notStarted
    @State private var metadata: PipelineClient.MetadataResult?
    @State private var screenshotURLs: [String] = []
    @State private var buildVersion: String = "1.0.0 (1)"
    @State private var isSubmitting: Bool = false
    @State private var error: String?

    enum SubmissionStatus: String {
        case notStarted
        case submitting
        case waitingForReview
        case inReview
        case readyForSale
        case rejected
        case failed

        var label: String {
            switch self {
            case .notStarted:      "Not submitted"
            case .submitting:      "Submitting…"
            case .waitingForReview: "Waiting for review"
            case .inReview:        "In review"
            case .readyForSale:    "Ready for sale"
            case .rejected:        "Rejected"
            case .failed:          "Submission failed"
            }
        }

        var icon: String {
            switch self {
            case .notStarted:      "arrow.up.doc.fill"
            case .submitting:      "progress.indicator"
            case .waitingForReview: "hourglass"
            case .inReview:        "magnifyingglass"
            case .readyForSale:    "checkmark.seal.fill"
            case .rejected:        "xmark.octagon.fill"
            case .failed:          "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .notStarted:       LiquidGlass.primaryText.opacity(0.5)
            case .submitting:       LiquidGlass.warning
            case .waitingForReview: LiquidGlass.accent
            case .inReview:         LiquidGlass.accentSecondary
            case .readyForSale:     LiquidGlass.success
            case .rejected:         .red
            case .failed:           .red
            }
        }
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    appCard
                    screenshotGrid
                    metadataSummary
                    versionSection
                    statusTracker
                    submitSection

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
        .task { await loadMetadata() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ship to App Store")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Final review before submission.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            }
            Spacer()
        }
    }

    // MARK: - App card

    private var appCard: some View {
        GlassSurface(tier: .raised) {
            HStack(spacing: 16) {
                // App icon placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LiquidGlass.auroraGradient)
                        .frame(width: 64, height: 64)
                    Image(systemName: "app.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata?.name ?? job.description.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(metadata?.subtitle ?? "Your app")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    if let cat = metadata?.category, !cat.isEmpty {
                        Text(cat.capitalized)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(LiquidGlass.accent.opacity(0.15), in: Capsule())
                    }
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Screenshot grid

    private var screenshotGrid: some View {
        GlassCard(title: "Screenshots", icon: "photo.on.rectangle.angled", tint: LiquidGlass.accentSecondary) {
            if screenshotURLs.isEmpty {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white.opacity(0.06))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.25))
                            )
                            .frame(width: 90, height: 160)
                    }
                }
                .frame(maxWidth: .infinity)
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
                                        .frame(width: 90, height: 160)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                default:
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.white.opacity(0.06))
                                        .frame(width: 90, height: 160)
                                        .overlay(ProgressView().tint(LiquidGlass.primaryText))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Metadata summary

    private var metadataSummary: some View {
        GlassCard(title: "Metadata", icon: "text.page.fill", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 8) {
                if let meta = metadata {
                    summaryRow(label: "Keywords", value: meta.keywords.joined(separator: ", "))
                    summaryRow(label: "Description", value: String(meta.description.prefix(120)) + "…")
                    if !meta.promotionalText.isEmpty {
                        summaryRow(label: "Promo Text", value: meta.promotionalText)
                    }
                } else {
                    Text("Metadata will appear here after generation.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                }
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                .lineLimit(2)
            Spacer()
        }
    }

    // MARK: - Version

    private var versionSection: some View {
        GlassSurface(tier: .flat) {
            HStack(spacing: 12) {
                Image(systemName: "number.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version / Build")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(buildVersion)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Status tracker

    private var statusTracker: some View {
        GlassSurface(tier: .deep) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: submissionStatus.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(submissionStatus.tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(submissionStatus.tint.opacity(0.18)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(submissionStatus.label)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        if submissionStatus == .inReview {
                            Text("Apple is reviewing your app — typically 24–48 hours.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                        } else if submissionStatus == .waitingForReview {
                            Text("Your app is in the queue. We'll notify you when review starts.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                        }
                    }
                    Spacer()
                }

                // Progress steps
                if submissionStatus != .notStarted {
                    HStack(spacing: 4) {
                        ForEach([SubmissionStatus.waitingForReview, .inReview, .readyForSale], id: \.self) { step in
                            Circle()
                                .fill(stepIndex(step) <= stepIndex(submissionStatus) ? LiquidGlass.success : .white.opacity(0.15))
                                .frame(width: 8, height: 8)
                            if step != .readyForSale {
                                Rectangle()
                                    .fill(stepIndex(step) < stepIndex(submissionStatus) ? LiquidGlass.success : .white.opacity(0.1))
                                    .frame(height: 2)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private func stepIndex(_ status: SubmissionStatus) -> Int {
        switch status {
        case .notStarted:      -1
        case .submitting:       0
        case .waitingForReview: 1
        case .inReview:         2
        case .readyForSale:     3
        case .rejected:        2
        case .failed:          -1
        }
    }

    // MARK: - Submit

    private var submitSection: some View {
        VStack(spacing: 12) {
            if submissionStatus == .notStarted || submissionStatus == .failed {
                PrimaryButton(
                    title: isSubmitting ? "Submitting to App Store…" : "Submit to App Store Review",
                    systemImage: "paperplane.fill",
                    style: .filled
                ) {
                    Task { await submitForReview() }
                }
                .disabled(isSubmitting)
            } else if submissionStatus == .readyForSale {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(LiquidGlass.success)
                    Text("Your app is live on the App Store!")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.success)
                }
                .padding(16)
                .background(LiquidGlass.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
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

    private func loadMetadata() async {
        // Attempt to load metadata if it was already generated
        do {
            let jobID = session.currentJobBackendID ?? ""
            let result = try await pipeline.generateMetadata(jobID: jobID)
            withAnimation(Motion.spring) {
                metadata = result
            }
            // Also try screenshots
            let screenshots = try await pipeline.takeScreenshots(jobID: jobID)
            withAnimation(Motion.spring) {
                screenshotURLs = screenshots.screenshotURLs
            }
        } catch {
            // Metadata might not be available yet — that's OK, user can go back to MetadataReviewView
        }
    }

    private func submitForReview() async {
        isSubmitting = true
        error = nil
        submissionStatus = .submitting
        defer { isSubmitting = false }
        do {
            let jobID = session.currentJobBackendID ?? ""
            let result = try await pipeline.submitForReview(jobID: jobID)
            withAnimation(Motion.spring) {
                if result.ok {
                    submissionStatus = .waitingForReview
                } else {
                    submissionStatus = .failed
                    error = result.message
                }
            }
            Haptics.success()
            // Poll for status updates (simplified — in production this would be push-notified)
            pollSubmissionStatus()
        } catch {
            submissionStatus = .failed
            self.error = error.localizedDescription
            Haptics.error()
        }
    }

    /// Simulated status polling. In production this would use
    /// Server-Sent Events or push notifications from ASC.
    private func pollSubmissionStatus() {
        Task {
            // After ~5 seconds, move to "in review" for demonstration
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(Motion.spring) {
                if submissionStatus == .waitingForReview {
                    submissionStatus = .inReview
                }
            }
            // After another ~8 seconds, mark as ready for sale
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            withAnimation(Motion.spring) {
                if submissionStatus == .inReview {
                    submissionStatus = .readyForSale
                }
            }
        }
    }
}