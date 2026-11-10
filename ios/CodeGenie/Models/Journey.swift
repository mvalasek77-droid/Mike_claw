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
        case describe, build, phone, store, live

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .describe: "Describe"
            case .build:    "Build"
            case .phone:    "On your phone"
            case .store:    "App Store"
            case .live:     "Live"
            }
        }
    }

    enum Action: Hashable {
        case describeApp
        case resumeBuild
        case openLatestBuild
        case setUpShipping
        case openSubmission(jobID: UUID)
        case startAnother
    }

    struct Facts {
        var buildInProgressTitle: String?
        var latestJobID: UUID?
        var latestJobTitle: String?
        var latestJobStage: BuildJob.Stage?
        var macPaired: Bool
        var appleAccountReady: Bool
        /// The submission that matters most right now, if any.
        var submission: ASCSubmissionRecord?

        init(
            buildInProgressTitle: String? = nil,
            latestJobID: UUID? = nil,
            latestJobTitle: String? = nil,
            latestJobStage: BuildJob.Stage? = nil,
            macPaired: Bool = false,
            appleAccountReady: Bool = false,
            submission: ASCSubmissionRecord? = nil
        ) {
            self.buildInProgressTitle = buildInProgressTitle
            self.latestJobID = latestJobID
            self.latestJobTitle = latestJobTitle
            self.latestJobStage = latestJobStage
            self.macPaired = macPaired
            self.appleAccountReady = appleAccountReady
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
            if facts.macPaired && facts.appleAccountReady, let id = facts.latestJobID {
                return NextStep(
                    milestone: .phone,
                    eyebrow: "Next",
                    title: "Put \(title) on your iPhone",
                    detail: "Six short steps get the real app onto your Home Screen through TestFlight. The App Store comes after, when you're ready.",
                    buttonTitle: "Start",
                    action: .openSubmission(jobID: id),
                    isWaiting: false
                )
            }
            let missing = [
                facts.macPaired ? nil : "a paired Mac",
                facts.appleAccountReady ? nil : "your Apple Developer details",
            ].compactMap { $0 }.joined(separator: " and ")
            return NextStep(
                milestone: .phone,
                eyebrow: "Next",
                title: "Get ready to install \(title)",
                detail: "Your app is built. Putting it on a real iPhone needs \(missing). It's a one-time setup and CodeGenie walks you through it.",
                buttonTitle: "Set up",
                action: .setUpShipping,
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
        let inStorePhase = record.isPhaseComplete(.testflight)
        return NextStep(
            milestone: inStorePhase ? .store : .phone,
            eyebrow: "\(record.appTitle) · step \(number) of \(ASCStep.all.count)",
            title: step?.title ?? "Continue your submission",
            detail: inStorePhase
                ? "Your app is already testable. These steps put it on the public App Store."
                : "You're part-way to having the real app on your iPhone.",
            buttonTitle: "Continue",
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
