import SwiftUI

struct OnboardingSlide: Identifiable, Hashable {
    let id = UUID()
    let chapter: String        // "Step 1 of 7"
    let title: String
    let body: String
    let illustration: Illustration
    let palette: [Color]
    let xcodeTip: String?      // shown in the Xcode-instructions sidebar

    enum Illustration: Hashable {
        case macWithXcode
        case projectInitialized
        case cursorLink
        case aiTraining
        case appBuilding
        case iconForge
        case simulatorToDevice
    }
}

extension OnboardingSlide {
    /// The seven-step storyline mirrors the YouTube tutorial process the user
    /// pointed us at (Setup → Init → AI link → Train → Build → Icon → Deploy)
    /// but reframed as the *automated* CodeGenie path so the user can see
    /// what the app is going to do for them.
    static let all: [OnboardingSlide] = [
        .init(
            chapter: "Step 1 of 7",
            title: "Meet your pocket Xcode",
            body: "All you need is your iPhone. CodeGenie talks to a Mac with Xcode in the cloud, so you can ship apps without owning a laptop.",
            illustration: .macWithXcode,
            palette: [.indigo, .purple],
            xcodeTip: "Need your own Mac? Open Xcode → Settings → Accounts and add your Apple ID. CodeGenie can also run remote."
        ),
        .init(
            chapter: "Step 2 of 7",
            title: "Project, scaffolded",
            body: "We spin up a real Xcode project for you — App target, asset catalog, SwiftUI entry point, the works.",
            illustration: .projectInitialized,
            palette: [.blue, .cyan],
            xcodeTip: "Manually: File → New → Project → iOS App → SwiftUI / Swift. CodeGenie does this for you in 8 seconds."
        ),
        .init(
            chapter: "Step 3 of 7",
            title: "AI is wired in",
            body: "Like Cursor's Composer, CodeGenie pipes your prompt into a code-savvy model that already speaks Swift and SwiftUI.",
            illustration: .cursorLink,
            palette: [.purple, .pink],
            xcodeTip: "We use Claude + GPT-5 in tandem — code by Claude, naming and copy by GPT, judged head-to-head."
        ),
        .init(
            chapter: "Step 4 of 7",
            title: "Trained on Apple's HIG",
            body: "The model is grounded in Apple's Human Interface Guidelines, SwiftUI docs, and Liquid Glass design language so the output feels native.",
            illustration: .aiTraining,
            palette: [.teal, .blue],
            xcodeTip: "AI can make mistakes. CodeGenie always shows the diff and lints with SwiftFormat + SwiftLint before you ship."
        ),
        .init(
            chapter: "Step 5 of 7",
            title: "Describe → build",
            body: "Tell CodeGenie what you want (\"a tide times app for surfers\") and it iterates until the UI is correct, the data flows, and the build is green.",
            illustration: .appBuilding,
            palette: [.orange, .pink],
            xcodeTip: "While we build, play BitDrop — our take on Tetris with Swift symbols. Earn boosts that speed up the build."
        ),
        .init(
            chapter: "Step 6 of 7",
            title: "Icon forged with ChatGPT",
            body: "We generate your app icon with the latest ChatGPT image model — sharper than DALL·E, refined to Apple's icon grid automatically.",
            illustration: .iconForge,
            palette: [.yellow, .orange],
            xcodeTip: "Icon must be 1024×1024 PNG, no alpha, no rounded corners. CodeGenie strips alpha and exports every required size."
        ),
        .init(
            chapter: "Step 7 of 7",
            title: "Simulator → device → App Store",
            body: "Tap to test in the cloud simulator, then we walk you through App Store Connect step-by-step on your Mac's Safari.",
            illustration: .simulatorToDevice,
            palette: [.green, .mint],
            xcodeTip: "Free Apple ID = re-sign every 7 days. $99/year Developer Program = 1-year + App Store. We'll prompt when needed."
        )
    ]
}
