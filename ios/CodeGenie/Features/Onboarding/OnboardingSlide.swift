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
    /// The same trip Home's journey card tracks, told once up front:
    /// describe, build, read, install, list, review, live. Every claim
    /// here is something the app does today — an onboarding that
    /// promises more than the product is the first thing a reviewer,
    /// or a user, catches.
    static let all: [OnboardingSlide] = [
        .init(
            chapter: "Step 1 of 7",
            title: "Start with a sentence",
            body: "Tell CodeGenie what you want — \"a tide times app for surfers\" is enough. You pick a look, it does the planning.",
            illustration: .aiTraining,
            palette: [.indigo, .purple],
            xcodeTip: "You bring your own Anthropic or OpenAI key and pay them directly. CodeGenie shows a cost estimate before every build."
        ),
        .init(
            chapter: "Step 2 of 7",
            title: "Watch it get built",
            body: "A team of AI agents plans the app, writes the SwiftUI code, sets up a real Xcode project, tests it and reviews it. You see each step as it happens.",
            illustration: .projectInitialized,
            palette: [.blue, .cyan],
            xcodeTip: "A build usually takes a few minutes. You can set a spending cap so it stops before it costs more than you want."
        ),
        .init(
            chapter: "Step 3 of 7",
            title: "You stay in charge",
            body: "Every file is yours to read. Changes are shown before they're kept, and you can roll back to an earlier point at any time.",
            illustration: .cursorLink,
            palette: [.purple, .pink],
            xcodeTip: "AI makes mistakes. CodeGenie checks its own work before you submit, but you are the final reviewer."
        ),
        .init(
            chapter: "Step 4 of 7",
            title: "Then onto your own iPhone",
            body: "Apple only lets iPhone apps be packaged on a Mac. CodeGenie sends the project to yours and tells you exactly what to click in Xcode — about six buttons — until the real app is on your Home Screen.",
            illustration: .macWithXcode,
            palette: [.teal, .blue],
            xcodeTip: "You need a Mac, the free Xcode app, and Apple's Developer Program at $99 a year. None of it is needed just to build."
        ),
        .init(
            chapter: "Step 5 of 7",
            title: "Test it before anyone else does",
            body: "AI wrote the app, so nobody knows yet whether it works. You get a short test plan made for your app: what to tap, what should happen. Whatever fails goes straight into a rebuild.",
            illustration: .simulatorToDevice,
            palette: [.orange, .pink],
            xcodeTip: "Apple's most common rejection is an app that didn't work when they tried it. Ten minutes of testing prevents it."
        ),
        .init(
            chapter: "Step 6 of 7",
            title: "Then the App Store",
            body: "Icon, screenshots, description, privacy answers. CodeGenie drafts what it can, checks every field against Apple's limits, and tells you exactly where to click.",
            illustration: .iconForge,
            palette: [.yellow, .orange],
            xcodeTip: "Stuck on any step? Ask the built-in coach. It knows which step you're on and what's blocking you."
        ),
        .init(
            chapter: "Step 7 of 7",
            title: "Through Apple's review",
            body: "CodeGenie follows the review with you. If Apple sends it back — which is common on a first app — it explains the guideline and what to change.",
            illustration: .appBuilding,
            palette: [.green, .mint],
            xcodeTip: "Most apps are reviewed within a day. You can resubmit as many times as it takes."
        )
    ]
}
