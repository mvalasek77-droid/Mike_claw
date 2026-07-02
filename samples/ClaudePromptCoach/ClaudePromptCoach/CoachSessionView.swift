import SwiftUI

/// A full coach session: one-sentence goal, mode pills, the 3-5 question
/// interview, then handoff to the draft review.
struct CoachSessionView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case describing
        case interviewing
        case reviewing
    }

    @State private var phase: Phase = .describing
    @State private var mode: CoachMode = .interview
    @State private var goal = ""
    @State private var questions: [CoachQuestion] = []
    @State private var answers: [String] = []
    @State private var currentIndex = 0
    @State private var currentAnswer = ""
    @State private var draft: SkillDraft?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                switch phase {
                case .describing:
                    describeView
                case .interviewing:
                    interviewView
                case .reviewing:
                    if let draft {
                        DraftReviewView(draft: draft) { dismiss() }
                    }
                }
            }
            .navigationTitle("Coach Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close coach session")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Phase 1: describe

    private var describeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Coaching mode", systemImage: "slider.horizontal.3")
                ModePillRow(selection: $mode)
                Text(mode.summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                SectionHeader(title: "Your goal", systemImage: "target")
                TextField("What are you trying to do, in one sentence?", text: $goal, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.primaryText)
                    .glassCard()
                    .accessibilityLabel("Goal, one sentence")

                Button {
                    startInterview()
                } label: {
                    Label("Start the interview", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            canStart ? Theme.accent : Theme.accent.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                .accessibilityLabel("Start the interview")
                .accessibilityHint(canStart ? "Begins the coach's questions" : "Type your goal first")
            }
            .padding()
        }
    }

    private var canStart: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startInterview() {
        Haptics.tap()
        questions = CoachEngine.questions(for: mode, goal: goal)
        answers = []
        currentIndex = 0
        currentAnswer = ""
        phase = .interviewing
    }

    // MARK: - Phase 2: interview

    private var interviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProgressView(value: Double(currentIndex), total: Double(max(questions.count, 1)))
                    .tint(Theme.accent)
                    .accessibilityLabel("Question \(currentIndex + 1) of \(questions.count)")

                if currentIndex < questions.count {
                    let question = questions[currentIndex]
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Question \(currentIndex + 1) of \(questions.count)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Text(question.prompt)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(question.detail)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .glassCard()

                    TextField(question.placeholder, text: $currentAnswer, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.primaryText)
                        .glassCard()
                        .accessibilityLabel("Your answer")

                    HStack {
                        Button("Skip") { advance(recording: "") }
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHint("Skips this question")
                        Spacer()
                        Button {
                            advance(recording: currentAnswer)
                        } label: {
                            Label(isLastQuestion ? "Draft my Skill" : "Next", systemImage: isLastQuestion ? "wand.and.stars" : "arrow.right")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Theme.accent, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isLastQuestion ? "Draft my Skill" : "Next question")
                    }
                }
            }
            .padding()
        }
    }

    private var isLastQuestion: Bool {
        currentIndex == questions.count - 1
    }

    private func advance(recording answer: String) {
        Haptics.tap()
        answers.append(answer)
        currentAnswer = ""
        if currentIndex + 1 < questions.count {
            currentIndex += 1
        } else {
            draft = CoachEngine.draft(goal: goal, mode: mode, questions: questions, answers: answers)
            phase = .reviewing
        }
    }
}
