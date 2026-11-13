import Foundation

/// The whole trip from an idea to a live app, reduced to one answer:
/// what should this person do next?
///
/// Home used to offer eleven things to tap and no opinion about which
/// came first. This looks at what actually exists — a build, a paired
/// Mac, a submission, a status from Apple — and names a single next
/// step, so a first-timer is always one tap from making progress.
enum Journey {

    enum Milestone: Int, CaseIterable, Identifiable {
        case describe, build, phone, test, store, live

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .describe: "Describe"
            case .build:    "Build"
            case .phone:    "On your phone"
            case .test:     "Tested"
            case .store:    "App Store"
            case .live:     "Live"
            }
        }
    }

    enum Action: Hashable {
        case describeApp
        case resumeBuild
        case openLatestBuild
        case openSubmission(jobID: UUID)
        case startAnother
    }

    struct Facts {
        var buildInProgressTitle: String?
        var latestJobID: UUID?
        var latestJobTitle: String?
        var latestJobStage: BuildJob.Stage?
        /// The submission that matters most right now, if any.
        var submission: ASCSubmissionRecord?

        init(
            buildInProgressTitle: String? = nil,
            latestJobID: UUID? = nil,
            latestJobTitle: String? = nil,
            latestJobStage: BuildJob.Stage? = nil,
            submission: ASCSubmissionRecord? = nil
        ) {
            self.buildInProgressTitle = buildInProgressTitle
            self.latestJobID = latestJobID
            self.latestJobTitle = latestJobTitle
            self.latestJobStage = latestJobStage
            self.submission = submission
        }
    }

    struct NextStep: Equatable {
        /// The milestone the user is currently working towards.
        let milestone: Milestone
        let eyebrow: String
        let title: String
        let detail: String
        let buttonTitle: String
        let action: Action
        /// True when the ball is in Apple's court.
        let isWaiting: Bool
    }

    /// Pick the submission worth surfacing: one that needs the user
    /// first, then anything still in flight, most recent first.
    static func primarySubmission(among records: [ASCSubmissionRecord]) -> ASCSubmissionRecord? {
        let started = records.filter { !$0.completedSteps.isEmpty || $0.isSubmitted }
        let open = started.filter { !$0.isComplete }
        let pool = open.isEmpty ? started : open
        return pool.sorted { a, b in
            if a.needsAttention != b.needsAttention { return a.needsAttention }
            return a.lastTouchedAt > b.lastTouchedAt
        }.first
    }

    static func nextStep(_ facts: Facts) -> NextStep {
        if let record = facts.submission {
            return step(for: record)
        }

        if let title = facts.buildInProgressTitle {
            return NextStep(
                milestone: .build,
                eyebrow: "Building",
                title: "\(title) is still building",
                detail: "Pick up where you left off. Nothing was lost.",
                buttonTitle: "Back to the build",
                action: .resumeBuild,
                isWaiting: false
            )
        }

        guard let stage = facts.latestJobStage, let title = facts.latestJobTitle else {
            return NextStep(
                milestone: .describe,
                eyebrow: "Start here",
                title: "Describe the app you want",
                detail: "A sentence or two is enough. CodeGenie plans it, writes it, and shows you every change before it's kept.",
                buttonTitle: "Describe my app",
                action: .describeApp,
                isWaiting: false
            )
        }

        switch stage {
        case .failed:
            return NextStep(
                milestone: .build,
                eyebrow: "Needs a look",
                title: "\(title) hit a problem",
                detail: "Open it to see what went wrong. Most builds recover from where they stopped.",
                buttonTitle: "See what happened",
                action: .openLatestBuild,
                isWaiting: false
            )

        case .readyForTest, .shipping:
            guard let id = facts.latestJobID else {
                return NextStep(
                    milestone: .build, eyebrow: "Built", title: "\(title) is built",
                    detail: "Open it to carry on.", buttonTitle: "Open", action: .openLatestBuild,
                    isWaiting: false
                )
            }
            return NextStep(
                milestone: .phone,
                eyebrow: "Next",
                title: "Put \(title) on your iPhone",
                detail: "It's built, but nobody has seen it run yet. A short guide takes you through opening it in Xcode on a Mac and installing the real app on your phone.",
                buttonTitle: "Show me how",
                action: .openSubmission(jobID: id),
                isWaiting: false
            )

        default:
            return NextStep(
                milestone: .build,
                eyebrow: "Building",
                title: "\(title) isn't finished yet",
                detail: "Open it to carry on from \(stage.label.lowercased()).",
                buttonTitle: "Open the build",
                action: .openLatestBuild,
                isWaiting: false
            )
        }
    }

    private static func step(for record: ASCSubmissionRecord) -> NextStep {
        let open = Action.openSubmission(jobID: record.jobID)

        if let review = record.review, record.isSubmitted {
            let state = review.state
            if state == .live {
                return NextStep(
                    milestone: .live,
                    eyebrow: "Live",
                    title: "\(record.appTitle) is on the App Store",
                    detail: "Anyone can download it. Ready for the next one?",
                    buttonTitle: "Build another app",
                    action: .startAnother,
                    isWaiting: false
                )
            }
            return NextStep(
                milestone: state.isApproved ? .live : .store,
                eyebrow: "\(record.appTitle) · \(state.isWaitingOnApple ? "with Apple" : "needs you")",
                title: state.headline,
                detail: state.nextActions.first ?? state.meaning,
                buttonTitle: state.needsFix ? "See how to fix it" : "Open review status",
                action: open,
                isWaiting: state.isWaitingOnApple
            )
        }

        let number = record.resumeStep
        let step = ASCStep.step(number)
        let phase = step?.phase ?? .testflight
        let milestone: Milestone
        let detail: String
        switch phase {
        case .testflight:
            milestone = .phone
            detail = "You're part-way to having the real app on your iPhone."
        case .testing:
            milestone = .test
            detail = "It's installed. Now find out whether it actually works — before Apple or anyone else does."
        case .appStore:
            milestone = .store
            detail = "Tested and working. These steps put it on the public App Store."
        case .review:
            milestone = .store
            detail = "Open the guide to see where Apple's review stands."
        }
        return NextStep(
            milestone: milestone,
            eyebrow: "\(record.appTitle) · step \(number) of \(ASCStep.all.count)",
            title: step?.title ?? "Continue your submission",
            detail: detail,
            buttonTitle: phase == .testing ? "Continue testing" : "Continue",
            action: open,
            isWaiting: step?.ownership == .apple
        )
    }

    /// Which milestones are behind the user, given the next step.
    static func reached(_ milestone: Milestone, for next: NextStep) -> Bool {
        milestone.rawValue < next.milestone.rawValue
            || (next.milestone == .live && next.action == .startAnother)
    }
}

// MARK: - The tour

extension Journey {

    /// One stop on the tour shown at first launch and from Home.
    ///
    /// The tour walks the same six milestones as the rail on Home, in
    /// the same order and by the same names, so what a newcomer is
    /// shown before they start is the map they then find themselves
    /// on. Each stop answers the four things people actually want to
    /// know: what happens, what they do, how long it takes, and what
    /// they need.
    struct TourStop: Identifiable, Hashable {
        let milestone: Milestone
        let title: String
        let body: String
        /// The user's own part, in one line.
        let youDo: String
        let takes: String
        /// What this stop requires that the user might not have. Nil
        /// when it needs nothing beyond the phone in their hand.
        let needs: String?

        var id: Int { milestone.rawValue }
    }

    static let tour: [TourStop] = [
        TourStop(
            milestone: .describe,
            title: "Start with a sentence",
            body: "Say what you want — \"a tide times app for surfers\" is enough. Pick a look. CodeGenie does the planning.",
            youDo: "Type a sentence or two.",
            takes: "A minute",
            needs: "An AI key from Anthropic or OpenAI. CodeGenie shows you how to get one, and what each build will cost before it starts."
        ),
        TourStop(
            milestone: .build,
            title: "Watch it get built",
            body: "A team of AI agents plans the app, writes the code, sets up a real Xcode project and reviews its own work. You see each step, and every file is yours to read.",
            youDo: "Watch, or play the built-in game while you wait.",
            takes: "A few minutes",
            needs: nil
        ),
        TourStop(
            milestone: .phone,
            title: "Put it on your own iPhone",
            body: "Apple only lets iPhone apps be packaged on a Mac. CodeGenie sends the project to yours and tells you exactly what to click in Xcode — about six buttons — until the real app is on your Home Screen.",
            youDo: "Follow eight short steps, mostly on your Mac.",
            takes: "About an hour the first time",
            needs: "A Mac, the free Xcode app, and Apple's Developer Program ($99 a year)."
        ),
        TourStop(
            milestone: .test,
            title: "Test it before anyone else does",
            body: "AI wrote it, so nobody knows yet whether it works. You get a short test plan made for your app: what to tap, and what should happen. Anything that fails goes straight into a rebuild.",
            youDo: "Try each test and say whether it worked.",
            takes: "Ten to fifteen minutes",
            needs: "One other person to try it, if you can find one."
        ),
        TourStop(
            milestone: .store,
            title: "Prepare your App Store page",
            body: "Icon, screenshots, description, privacy answers. CodeGenie drafts what it can, checks every field against Apple's limits, and shows you where each one goes.",
            youDo: "Check the drafts and paste them into Apple's website.",
            takes: "An hour or two",
            needs: "A web page for support and one for your privacy policy. Simple ones are fine."
        ),
        TourStop(
            milestone: .live,
            title: "Through Apple's review, and live",
            body: "A person at Apple tries your app. CodeGenie follows the review with you, and if it's sent back — common on a first app — explains what Apple wants and what to change.",
            youDo: "Wait, and act on Apple's answer.",
            takes: "Usually a day or two",
            needs: nil
        ),
    ]

    /// What the whole trip needs, gathered from the stops, for the
    /// summary at the end of the tour.
    static var tourRequirements: [String] {
        [
            "An AI key from Anthropic or OpenAI — to build",
            "A Mac with Xcode — to install and submit",
            "Apple's Developer Program, $99 a year — to install and submit",
        ]
    }
}
