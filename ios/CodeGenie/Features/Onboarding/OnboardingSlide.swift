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
            title: "You'll need a Mac for the next part",
            body: "Apple only lets iPhone apps be packaged on a Mac with Xcode. Pair yours once and CodeGenie drives it from your phone — you never open Xcode yourself.",
            illustration: .macWithXcode,
            palette: [.teal, .blue],
            xcodeTip: "You also need the Apple Developer Program, which Apple charges $99 a year for. Neither is needed just to build."
        ),
        .init(
            chapter: "Step 5 of 7",
            title: "On your own iPhone first",
            body: "Six short steps put the real app on your Home Screen through TestFlight, Apple's testing app. Share it with friends before anyone else sees it.",
            illustration: .simulatorToDevice,
            palette: [.orange, .pink],
            xcodeTip: "TestFlight needs no screenshots, description or pricing. That all comes later, and only if you want to go public."
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
