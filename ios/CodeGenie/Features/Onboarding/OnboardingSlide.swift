import SwiftUI

struct OnboardingSlide: Identifiable, Hashable {
    let id = UUID()
    let chapter: String        // "Step 1 of 8"
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
        case pricing
        case simulatorToDevice
        /// Placeholder slot for a future bundled tutorial video. Renders
        /// a TV-frame UI with a "Video coming soon" caption — the
        /// videoURL is plumbed through but optional, so we can drop in
        /// real .mp4 / .m3u8 assets later without changing call sites.
        case videoPlaceholder(caption: String, videoURL: URL?)
    }
}

extension OnboardingSlide {
    /// The seven-step storyline mirrors the YouTube tutorial process the user
    /// pointed us at (Setup → Init → AI link → Train → Build → Icon → Deploy)
    /// but reframed as the *automated* CodeGenie path so the user can see
    /// what the app is going to do for them.
    static let all: [OnboardingSlide] = [
        .init(
            chapter: "Step 1 of 8",
            title: "Meet your pocket Xcode",
            body: "All you need is your iPhone. CodeGenie talks to a Mac with Xcode in the cloud, so you can ship apps without owning a laptop.",
            illustration: .macWithXcode,
            palette: [.indigo, .purple],
            xcodeTip: "Need your own Mac? Open Xcode → Settings → Accounts and add your Apple ID. CodeGenie can also run remote."
        ),
        .init(
            chapter: "Step 2 of 8",
            title: "Project, scaffolded",
            body: "We spin up a real Xcode project for you — App target, asset catalog, SwiftUI entry point, the works.",
            illustration: .projectInitialized,
            palette: [.blue, .cyan],
            xcodeTip: "Manually: File → New → Project → iOS App → SwiftUI / Swift. CodeGenie does this for you in 8 seconds."
        ),
        .init(
            chapter: "Step 3 of 8",
            title: "AI is wired in",
            body: "Like Cursor's Composer, CodeGenie pipes your prompt into a code-savvy model that already speaks Swift and SwiftUI.",
            illustration: .cursorLink,
            palette: [.purple, .pink],
            xcodeTip: "We use Claude + GPT-5 in tandem — code by Claude, naming and copy by GPT, judged head-to-head."
        ),
        .init(
            chapter: "Step 4 of 8",
            title: "Trained on Apple's HIG",
            body: "The model is grounded in Apple's Human Interface Guidelines, SwiftUI docs, and Liquid Glass design language so the output feels native.",
            illustration: .aiTraining,
            palette: [.teal, .blue],
            xcodeTip: "AI can make mistakes. CodeGenie always shows the diff and lints with SwiftFormat + SwiftLint before you ship."
        ),
        .init(
            chapter: "Step 5 of 8",
            title: "Describe → build",
            body: "Tell CodeGenie what you want (\"a tide times app for surfers\") and it iterates until the UI is correct, the data flows, and the build is green.",
            illustration: .videoPlaceholder(
                caption: "Watch a real prompt-to-app build in 30 seconds",
                videoURL: nil
            ),
            palette: [.orange, .pink],
            xcodeTip: "While we build, play BitDrop — our take on Tetris with Swift symbols. Earn boosts that speed up the build."
        ),
        .init(
            chapter: "Step 6 of 8",
            title: "Icon forged with ChatGPT",
            body: "We generate your app icon with the latest ChatGPT image model — sharper than DALL·E, refined to Apple's icon grid automatically.",
            illustration: .iconForge,
            palette: [.yellow, .orange],
            xcodeTip: "Icon must be 1024×1024 PNG, no alpha, no rounded corners. CodeGenie strips alpha and exports every required size."
        ),
        .init(
            chapter: "Step 7 of 8",
            title: "What does this cost?",
            body: "Three free hosted builds per month, then $9.99/month for Pro (unlimited Sonnet + 20 Opus) or $29/month for Studio. Prefer your own API key? Bring it — we don't take a cut. A $5 safety cap is on by default.",
            illustration: .pricing,
            palette: [.green, .teal],
            xcodeTip: "Apple Developer Program is the only outside fee — $99/year, and only if you ship to TestFlight or the App Store. The App Store itself is free to publish to."
        ),
        .init(
            chapter: "Step 8 of 8",
            title: "Simulator → device → App Store",
            body: "Tap to test in the cloud simulator. When you're ready to ship, your Mac drives App Store Connect while you watch on your phone.",
            illustration: .videoPlaceholder(
                caption: "See a finished build run end-to-end on a real iPhone",
                videoURL: nil
            ),
            palette: [.green, .mint],
            xcodeTip: "Free Apple ID = re-sign every 7 days. $99/year Developer Program = 1-year + App Store. We'll prompt when needed."
        )
    ]
}
