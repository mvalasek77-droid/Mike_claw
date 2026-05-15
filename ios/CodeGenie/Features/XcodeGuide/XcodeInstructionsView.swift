import SwiftUI

struct XcodeStep: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    let title: String
    let summary: String
    let detail: String
    let icon: String
    let timestamp: String  // mirrors the YouTube reference
}

extension XcodeStep {
    static let all: [XcodeStep] = [
        .init(number: 1, title: "Setup",
              summary: "Mac + Xcode installed",
              detail: "You need a Mac running macOS 14+ and Xcode 16+ from the App Store. Open Xcode once and accept the license (a Terminal prompt will appear). Sign in with your Apple ID under Xcode → Settings → Accounts so signing works.",
              icon: "macbook",
              timestamp: "0:35 – 1:08"),
        .init(number: 2, title: "Project init",
              summary: "Create a new Xcode project",
              detail: "Xcode → File → New → Project → iOS → App. Pick SwiftUI + Swift, set a Product Name and Organization Identifier (reverse-DNS like com.you.app). Save the folder somewhere you can find later — CodeGenie uses ~/code by default.",
              icon: "folder.fill.badge.plus",
              timestamp: "1:08 – 2:09"),
        .init(number: 3, title: "Link the AI",
              summary: "Connect Cursor / Claude / Codex",
              detail: "Open the project folder in your AI tool of choice. CodeGenie does this for you over a remote build socket — but if you're driving Xcode by hand, drag the project folder onto Cursor and let it index.",
              icon: "cursorarrow.rays",
              timestamp: "3:02 – 3:48"),
        .init(number: 4, title: "Train the AI",
              summary: "Feed it Apple's HIG + SwiftUI docs",
              detail: "Paste Apple's Human Interface Guidelines, the SwiftUI cheat-sheet, and the Liquid Glass overview into the AI's context. CodeGenie ships these as a system prompt so every build follows Apple's standards.",
              icon: "books.vertical.fill",
              timestamp: "4:00 – 5:24"),
        .init(number: 5, title: "Build with prompts",
              summary: "Iteratively refine UI + logic",
              detail: "Describe the app in plain English, then ask for tweaks. CodeGenie streams diffs you can preview before applying. AI can hallucinate — always read the diff before merging.",
              icon: "wand.and.stars",
              timestamp: "5:24 – 8:12"),
        .init(number: 6, title: "Generate icon",
              summary: "ChatGPT image model + grid fix",
              detail: "Use ChatGPT's image tool (replaces the older DALL·E flow) for the 1024×1024 source. CodeGenie auto-generates every required size and removes the alpha channel — a common App Store rejection.",
              icon: "app.gift.fill",
              timestamp: "9:00 – 10:34"),
        .init(number: 7, title: "Run the simulator",
              summary: "Try the app on virtual iPhone",
              detail: "Pick an iPhone scheme in Xcode and press ⌘R. CodeGenie hosts a remote simulator session you can stream to your phone — no Mac required for testing.",
              icon: "display",
              timestamp: "8:12 – 9:00"),
        .init(number: 8, title: "Deploy to your iPhone",
              summary: "Plug in, sign, run",
              detail: "Connect your iPhone, trust the computer, pick your device as run target. With a free Apple ID the app is signed for 7 days. With the $99/yr Developer Program you get one year + App Store distribution.",
              icon: "iphone.gen3",
              timestamp: "11:10 – 12:12"),
        .init(number: 9, title: "App Store Connect",
              summary: "Archive → Upload → Submit",
              detail: "Product → Archive in Xcode, then Distribute App → App Store Connect. CodeGenie's ASC walkthrough opens Safari on your Mac and types the metadata for you, screenshot by screenshot.",
              icon: "paperplane.fill",
              timestamp: "12:20 – 12:45")
    ]
}

struct XcodeInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: XcodeStep.ID?

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    aiCaution
                    ForEach(XcodeStep.all) { step in
                        StepCard(step: step, isExpanded: expanded == step.id) {
                            Motion.run(.spring(response: 0.45, dampingFraction: 0.85)) {
                                expanded = expanded == step.id ? nil : step.id
                            }
                            Haptics.selection()
                        }
                    }
                    cheatSheet
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7), .black.opacity(0.4))
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Xcode in your pocket")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Every step the YouTube tutorial covers — annotated, automated where we can, manual where you want control.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aiCaution: some View {
        GlassSurface(tier: .flat, corner: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(LiquidGlass.warning)
                Text("AI can make mistakes. CodeGenie shows you the diff before applying anything, runs SwiftLint + SwiftFormat, and re-builds in the simulator before you ship.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    .lineSpacing(2)
            }
            .padding(14)
        }
    }

    private var cheatSheet: some View {
        GlassCard(title: "Pocket cheat-sheet", icon: "command", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 6) {
                cheat("⌘R", "Run on simulator / device")
                cheat("⌘B", "Build (no run)")
                cheat("⌘.", "Stop the running app")
                cheat("⌘⇧K", "Clean build folder")
                cheat("⌘⌥⇧K", "Hard clean + DerivedData")
                cheat("⌘⇧Y", "Toggle debug area")
            }
        }
    }

    private func cheat(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.18)))
                .foregroundStyle(LiquidGlass.primaryText)
            Text(desc)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
            Spacer()
        }
    }
}

private struct StepCard: View {
    let step: XcodeStep
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassSurface(tier: isExpanded ? .deep : .raised) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(LiquidGlass.auroraGradient)
                            Text("\(step.number)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text(step.summary)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        }
                        Spacer()
                        Image(systemName: step.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    }

                    if isExpanded {
                        Divider().background(.white.opacity(0.15))
                        Text(step.detail)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 10) {
                            Label(step.timestamp, systemImage: "play.rectangle.fill")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.white.opacity(0.06), in: Capsule())
                            Spacer()
                        }
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview { XcodeInstructionsView() }
