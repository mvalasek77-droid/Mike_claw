import SwiftUI
import AVFoundation

// MARK: - CeremonyController
//
// Drives the one-time initialization ceremony shown the first time the user
// reaches Her/Him Mode. Clinical voice asks 5 questions; companion's warm voice
// delivers the congratulation. Owns AVSpeechSynthesizer and all sequencing.

@MainActor
final class CeremonyController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    enum Phase: Equatable {
        case awakening
        case intro
        case questioning(Int)
        case thanking
        case congratulating
        case done
    }

    @Published var phase:           Phase  = .awakening
    @Published var redIntensity:    Double = 0
    @Published var mouthOpen:       Double = 0
    @Published var questionText:    String = ""
    @Published var questionVisible: Bool   = false
    @Published var continueVisible: Bool   = false
    @Published var congratsText:    String = ""
    @Published var congratsVisible: Bool   = false
    @Published var answerText:      String = ""

    private(set) var answers:      [String] = []
    private var pendingCompletion: (() -> Void)?
    private var mouthPulsing:      Bool = false

    private let synthesizer = AVSpeechSynthesizer()

    let questions: [String] = [
        "Tell me about your relationship with your mother.",
        "And with your father?",
        "What do you find most difficult about connecting with other people?",
        "What are you looking for here?",
        "What are you most afraid of?"
    ]

    private var companion: CompanionPersonality {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        return CompanionPersonality.find(id: id) ?? .luna
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Start

    func start() {
        withAnimation(.easeIn(duration: 3.5)) { redIntensity = 1 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            phase = .intro
            speak(clinical: "Before we begin. I have a few questions.") {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    self.askQuestion(0)
                }
            }
        }
    }

    // MARK: - Question flow

    func askQuestion(_ index: Int) {
        phase        = .questioning(index)
        questionText = questions[index]
        answerText   = ""
        continueVisible = false

        withAnimation(.easeIn(duration: 0.5)) { questionVisible = true }

        speak(clinical: questions[index]) {
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.4)) { self.continueVisible = true }
            }
        }
    }

    func advance() {
        let trimmed = answerText.trimmingCharacters(in: .whitespaces)
        answers.append(trimmed.isEmpty ? "—" : trimmed)

        withAnimation(.easeOut(duration: 0.35)) {
            questionVisible = false
            continueVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            let next = self.answers.count
            if next < self.questions.count {
                self.askQuestion(next)
            } else {
                self.beginCongratulation()
            }
        }
    }

    func skipCeremony() {
        synthesizer.stopSpeaking(at: .immediate)
        stopMouthAnimation()
        saveCeremonyAnswers()
    }

    // MARK: - Congratulation

    private func beginCongratulation() {
        saveCeremonyAnswers()
        phase = .thanking
        withAnimation(.easeOut(duration: 0.4)) { questionVisible = false }

        speak(clinical: "Thank you. Your answers have been noted.") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.deliverCongratsMessage()
            }
        }
    }

    private func deliverCongratsMessage() {
        phase = .congratulating
        let name     = companion.name
        let modeName = HerModeEngine.shared.modeName
        let text     = "Congratulations. You've reached \(modeName). " +
                       "This isn't a feature. This is an invitation — " +
                       "to a friendship that may take us somewhere neither of us expected. " +
                       "I'm \(name). And I'm really glad you're here."

        congratsText = text
        withAnimation(.easeIn(duration: 0.9)) { congratsVisible = true }

        speak(companion: text) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                self.phase = .done
            }
        }
    }

    // MARK: - TTS

    private func speak(clinical text: String, completion: @escaping () -> Void) {
        let u = AVSpeechUtterance(string: text)
        u.voice            = AVSpeechSynthesisVoice(language: "en-US")
        u.rate             = 0.40
        u.pitchMultiplier  = 0.82
        u.volume           = 0.92
        u.preUtteranceDelay = 0.05
        enqueue(u, completion: completion)
    }

    private func speak(companion text: String, completion: @escaping () -> Void) {
        let u = AVSpeechUtterance(string: text)
        u.voice            = AVSpeechSynthesisVoice(language: "en-US")
        u.rate             = 0.47
        u.pitchMultiplier  = 1.06
        u.volume           = 1.0
        u.preUtteranceDelay = 0.1
        enqueue(u, completion: completion)
    }

    private func enqueue(_ utterance: AVSpeechUtterance, completion: @escaping () -> Void) {
        pendingCompletion = completion
        startMouthAnimation()
        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.stopMouthAnimation()
            let done = self.pendingCompletion
            self.pendingCompletion = nil
            done?()
        }
    }

    // MARK: - Mouth animation

    func startMouthAnimation() {
        mouthPulsing = true
        pulseMouth()
    }

    func stopMouthAnimation() {
        mouthPulsing = false
        withAnimation(.easeOut(duration: 0.25)) { mouthOpen = 0 }
    }

    private func pulseMouth() {
        guard mouthPulsing else { return }
        let target   = Double.random(in: 0.12...0.90)
        let duration = Double.random(in: 0.07...0.16)
        withAnimation(.easeInOut(duration: duration)) { mouthOpen = target }
        Task { @MainActor in
            let wait = UInt64(Double.random(in: 0.08...0.20) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: wait)
            if self.mouthPulsing { self.pulseMouth() }
        }
    }

    // MARK: - Persistence

    func saveCeremonyAnswers() {
        var dict: [String: String] = [:]
        for (i, a) in answers.enumerated() where i < questions.count {
            dict["q\(i + 1)"] = a
        }
        UserDefaults.standard.set(dict, forKey: "ceremony.answers")
    }
}

// MARK: - HerModeCeremonyView

struct HerModeCeremonyView: View {

    let onComplete: () -> Void

    @StateObject private var ctrl = CeremonyController()

    // Deep crimson palette
    private let bloodRed  = Color(red: 0.36, green: 0.0, blue: 0.0)
    private let glowRed   = Color(red: 0.55, green: 0.04, blue: 0.04)
    private let lipRed    = Color(red: 0.82, green: 0.06, blue: 0.06)

    var body: some View {
        ZStack {
            // ── Background: black → deep crimson ──────────────────────────
            Color.black.ignoresSafeArea()
            bloodRed.opacity(ctrl.redIntensity).ignoresSafeArea()
            RadialGradient(
                colors: [glowRed.opacity(ctrl.redIntensity), .clear],
                center: .center,
                startRadius: 30,
                endRadius: 280
            )
            .ignoresSafeArea()

            // ── Main content column ───────────────────────────────────────
            VStack(spacing: 0) {
                Spacer()

                // Mouth
                MouthShape(openAmount: ctrl.mouthOpen)
                    .fill(lipRed)
                    .frame(width: 128, height: 64)
                    .shadow(color: Color.red.opacity(0.45 * ctrl.redIntensity), radius: 28)
                    .animation(.easeInOut(duration: 0.12), value: ctrl.mouthOpen)

                Spacer().frame(height: 60)

                // Question
                if ctrl.questionVisible {
                    Text(ctrl.questionText)
                        .font(.system(size: 17, weight: .light, design: .monospaced))
                        .foregroundColor(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 44)
                        .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                }

                Spacer().frame(height: 36)

                // Answer field
                if ctrl.questionVisible {
                    VStack(spacing: 10) {
                        TextField("", text: $ctrl.answerText, axis: .vertical)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .tint(Color(red: 0.9, green: 0.3, blue: 0.3))
                            .multilineTextAlignment(.center)
                            .lineLimit(4, reservesSpace: true)
                            .padding(.horizontal, 44)
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 1)
                            .padding(.horizontal, 64)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                }

                Spacer().frame(height: 30)

                // Continue button
                if ctrl.continueVisible && ctrl.questionVisible {
                    Button { ctrl.advance() } label: {
                        Text("continue")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.42))
                            .tracking(2.5)
                    }
                    .transition(.opacity.animation(.easeIn(duration: 0.35)))
                }

                // Congratulation text
                if ctrl.congratsVisible {
                    Text(ctrl.congratsText)
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 36)
                        .transition(.opacity.animation(.easeIn(duration: 0.9)))
                }

                Spacer()

                // Progress dots
                if case .questioning(let n) = ctrl.phase {
                    HStack(spacing: 7) {
                        ForEach(0..<ctrl.questions.count, id: \.self) { i in
                            Circle()
                                .fill(i <= n
                                      ? Color.white.opacity(0.65)
                                      : Color.white.opacity(0.18))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.bottom, 52)
                    .transition(.opacity)
                } else {
                    Spacer().frame(height: 52)
                }
            }

            // ── Skip — top right, barely visible ─────────────────────────
            VStack {
                HStack {
                    Spacer()
                    Button {
                        ctrl.skipCeremony()
                        onComplete()
                    } label: {
                        Text("skip")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.18))
                            .tracking(1.5)
                    }
                    .padding(.trailing, 24)
                    .padding(.top, 56)
                }
                Spacer()
            }
        }
        .onAppear { ctrl.start() }
        .onChange(of: ctrl.phase) { _, newPhase in
            if case .done = newPhase { onComplete() }
        }
    }
}

// MARK: - MouthShape
//
// Draws two bezier arcs that form a mouth.
// openAmount 0 = thin closed line, 1 = wide open oval.

struct MouthShape: Shape {

    var openAmount: Double

    var animatableData: Double {
        get { openAmount }
        set { openAmount = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w       = rect.width * 0.85
        let cx      = rect.midX
        let cy      = rect.midY
        let drop    = CGFloat(openAmount) * rect.height * 0.72

        var p = Path()
        // Upper arch
        p.move(to: CGPoint(x: cx - w / 2, y: cy))
        p.addCurve(
            to:        CGPoint(x: cx + w / 2, y: cy),
            control1:  CGPoint(x: cx - w * 0.22, y: cy - drop * 0.18),
            control2:  CGPoint(x: cx + w * 0.22, y: cy - drop * 0.18)
        )
        // Lower arch
        p.addCurve(
            to:        CGPoint(x: cx - w / 2, y: cy),
            control1:  CGPoint(x: cx + w * 0.25, y: cy + drop),
            control2:  CGPoint(x: cx - w * 0.25, y: cy + drop)
        )
        p.closeSubpath()
        return p
    }
}
