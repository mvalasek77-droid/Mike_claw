import SwiftUI

/// Answers the question a first-time builder asks the moment a build
/// finishes: "OK... so where actually *is* it?"
///
/// The honest answer is that "your app" means four different things
/// depending on what you want to do next, and the app never said so.
/// People went looking for a file on their phone, found nothing, and
/// assumed the build had failed.
///
/// Each row states plainly what lives there, whether it exists yet,
/// and what it is good for.
struct WhereIsMyAppView: View {
    /// Nil when opened from the Apps tab in general rather than for one
    /// specific build.
    var job: BuildJob? = nil
    /// Download link for the generated Xcode project, when there is
    /// one. Its absence is what makes the project-files row read as
    /// unavailable: a phone-only preview build produces no download.
    var exportURL: URL? = nil

    @StateObject private var creds = Credentials.shared

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    inCodeGenieCard
                    projectFilesCard
                    onGitHubCard
                    onYourPhoneCard
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where is my app?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text(job.map { "\"\($0.description.title)\" exists in a few places, and each one is for something different." }
                ?? "Your apps exist in a few places, and each one is for something different.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Places

    private var inCodeGenieCard: some View {
        placeCard(
            icon: "square.grid.2x2.fill",
            tint: LiquidGlass.accent,
            title: "Here, in CodeGenie",
            status: .available("Saved on this phone"),
            body: "Every build you start is listed on the Apps tab and stays there until you remove it. This is the one place your app is always available, even with no Mac and no Apple account.",
            goodFor: "Reopening the build, reading the transcript, starting the submission guide."
        ) { EmptyView() }
    }

    private var projectFilesCard: some View {
        placeCard(
            icon: "folder.fill",
            tint: LiquidGlass.accentSecondary,
            title: "The Xcode project files",
            status: exportURL != nil
                ? .available("Ready to download as a .zip")
                : .unavailable("Needs a build that ran on the backend"),
            body: exportURL != nil
                ? "The actual Swift source CodeGenie wrote. Downloading saves a .zip into the Files app on this phone, which you can then move to a Mac and open in Xcode."
                : "The actual Swift source CodeGenie wrote. This build ran in preview mode on your phone, so there is no project to download yet — connect a Mac and run a real build to get one.",
            goodFor: "Opening in Xcode yourself, or keeping a copy of the code."
        ) {
            if let exportURL {
                ShareLink(
                    item: exportURL,
                    preview: SharePreview(
                        "\(job?.description.title ?? "App").zip",
                        image: Image(systemName: "shippingbox.fill")
                    )
                ) {
                    actionLabel("Download the project", systemImage: "square.and.arrow.down")
                }
                .accessibilityLabel("Download the Xcode project as a zip")
            }
        }
    }

    private var onGitHubCard: some View {
        placeCard(
            icon: "chevron.left.forwardslash.chevron.right",
            tint: LiquidGlass.success,
            title: "Backed up on GitHub",
            status: creds.hasGithub
                ? .available("Connected as @\(creds.githubUsername)")
                : .optional("Not connected — optional"),
            body: creds.hasGithub
                ? "Use \"Back up to GitHub\" when a build finishes and the code is pushed to your account on its own branch."
                : "Optional. Connecting GitHub lets CodeGenie push each finished build to your own account so you never lose the code.",
            goodFor: "Never losing your work, and sharing it with other people."
        ) { EmptyView() }
    }

    private var onYourPhoneCard: some View {
        placeCard(
            icon: "iphone.gen3",
            tint: LiquidGlass.warning,
            title: "Installed on your iPhone",
            status: .unavailable("Needs Apple's TestFlight"),
            body: "An app can only get onto a real iPhone through Apple, never straight from CodeGenie. That means a Mac, an Apple Developer account, and a trip through TestFlight. The submission guide walks you through all of it.",
            goodFor: "Actually using your app, and letting other people try it."
        ) { EmptyView() }
    }

    // MARK: Building blocks

    private enum PlaceStatus {
        case available(String)
        case unavailable(String)
        case optional(String)

        var text: String {
            switch self {
            case .available(let s), .unavailable(let s), .optional(let s): s
            }
        }
        var tint: Color {
            switch self {
            case .available:   LiquidGlass.success
            case .unavailable: LiquidGlass.primaryText.opacity(0.45)
            case .optional:    LiquidGlass.warning
            }
        }
        var icon: String {
            switch self {
            case .available:   "checkmark.circle.fill"
            case .unavailable: "minus.circle.fill"
            case .optional:    "circle.dashed"
            }
        }
    }

    private func placeCard<Action: View>(
        icon: String,
        tint: Color,
        title: String,
        status: PlaceStatus,
        body: String,
        goodFor: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        GlassSurface(tier: .raised, corner: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(tint.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        HStack(spacing: 5) {
                            Image(systemName: status.icon)
                                .font(.system(size: 10, weight: .bold))
                                .accessibilityHidden(true)
                            Text(status.text)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(status.tint)
                    }
                    Spacer(minLength: 0)
                }

                Text(body)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 6) {
                    Text("Good for")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.45))
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(goodFor)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }

                action()
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(status.text). \(body)")
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .foregroundStyle(LiquidGlass.primaryText)
    }
}
