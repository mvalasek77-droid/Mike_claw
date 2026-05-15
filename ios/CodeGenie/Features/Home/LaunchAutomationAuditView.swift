import SwiftUI

struct LaunchAutomationAuditView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    verdictCard
                    ForEach(LaunchAutomationGroup.all) { group in
                        AutomationGroupCard(group: group)
                    }
                    Color.clear.frame(height: 26)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Automation audit")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("The launch pipeline, separated into real automation, Mac-assisted automation, and Apple-required confirmation.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.72))
            }
            .accessibilityLabel("Close automation audit")
        }
    }

    private var verdictCard: some View {
        GlassSurface(tier: .deep, corner: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LiquidGlass.warning)
                        .accessibilityHidden(true)
                    Text("Current verdict")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                }
                Text("CodeGenie now has a backend release-readiness gate for Xcode archive state, Apple credentials, privacy, terms, metadata, screenshots, GitHub sync, and TestFlight upload. It automates what Apple allows and keeps account ownership, legal truthfulness, 2FA, and final App Review submit explicit.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                    .lineSpacing(3)
            }
            .padding(18)
        }
    }
}

private struct LaunchAutomationGroup: Identifiable {
    let title: String
    let icon: String
    let tint: Color
    let rows: [LaunchAutomationRow]
    var id: String { title }

    static let all: [LaunchAutomationGroup] = [
        .init(
            title: "Automated now",
            icon: "bolt.badge.checkmark.fill",
            tint: LiquidGlass.success,
            rows: [
                .init("Xcode project generation", "Tracked CodeGenie.xcodeproj builds from a clean checkout.", .automated),
                .init("Release readiness gate", "Audits archive, IPA, Apple credentials, privacy manifest, terms, screenshots, metadata, GitHub, and final confirmation.", .automated),
                .init("Perfection Mode", "Runs after a green backend build and blocks submission on critical findings.", .automated),
                .init("Decision memory", "Searchable reasoning ledger across jobs.", .automated),
                .init("Icon Forge", "Generates 1024 px icons and strips alpha before export.", .automated),
                .init("TestFlight upload", "Backend validates and uploads via altool when IPA and credentials are present.", .automated),
                .init("Processing poll", "ASC API key polling emits TestFlight status events.", .automated),
                .init("GitHub sync", "Backend commits the workspace and pushes a branch when a repo and token are provided.", .automated)
            ]
        ),
        .init(
            title: "Mac-assisted",
            icon: "macbook.and.iphone",
            tint: LiquidGlass.accent,
            rows: [
                .init("Pair Mac", "iPhone can pair with the companion over local network.", .assisted),
                .init("Open Xcode/Safari", "Companion has command hooks for Xcode projects and ASC pages.", .assisted),
                .init("ASC auto-fill", "Companion can fill approved fields after the user is on App Store Connect.", .assisted),
                .init("Archive/export", "Xcode signing and export can be driven by the Mac runner once the Apple account is signed in.", .assisted),
                .init("Screenshots", "Companion can capture screens; scripted App Store-size walkthrough still needs final wiring.", .assisted)
            ]
        ),
        .init(
            title: "Apple-required",
            icon: "person.crop.circle.badge.checkmark",
            tint: LiquidGlass.warning,
            rows: [
                .init("Developer enrollment", "Apple account, paid team, agreements, tax, and banking stay user-owned.", .requiresUser),
                .init("Two-factor sign-in", "Apple may require human approval codes.", .requiresUser),
                .init("Privacy & terms", "CodeGenie drafts and checks, but the developer must confirm truthfulness and legal fit.", .requiresUser),
                .init("Final submit", "The last App Review submission action should remain explicit.", .requiresUser)
            ]
        )
    ]
}

private struct LaunchAutomationRow: Identifiable {
    enum State {
        case automated, assisted, requiresUser

        var label: String {
            switch self {
            case .automated: "Auto"
            case .assisted: "Companion"
            case .requiresUser: "Confirm"
            }
        }

        var color: Color {
            switch self {
            case .automated: LiquidGlass.success
            case .assisted: LiquidGlass.accent
            case .requiresUser: LiquidGlass.warning
            }
        }
    }

    let title: String
    let detail: String
    let state: State
    var id: String { title }

    init(_ title: String, _ detail: String, _ state: State) {
        self.title = title
        self.detail = detail
        self.state = state
    }
}

private struct AutomationGroupCard: View {
    let group: LaunchAutomationGroup

    var body: some View {
        GlassCard(title: group.title, icon: group.icon, tint: group.tint) {
            VStack(spacing: 10) {
                ForEach(group.rows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Text(row.state.label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(row.state.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(row.state.color.opacity(0.15), in: Capsule())
                            .overlay(Capsule().strokeBorder(row.state.color.opacity(0.28)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text(row.detail)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.68))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
