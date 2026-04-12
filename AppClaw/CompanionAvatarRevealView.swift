import SwiftUI
import AVFoundation

// MARK: - CompanionLiveView
//
// TikTok-style full-screen animated companion background.
// No video files required — uses SwiftUI animations to feel alive:
//   • Two breathing radial gradients that shift position over time
//   • Huge watermark initial letter (subtle, kinetic)
//   • Three pulsing rings around a centre avatar circle
//   • Everything synced to the companion's accent colour

struct CompanionLiveView: View {
    let companion: CompanionPersonality

    @State private var breathe = false
    @State private var drift   = false
    @State private var glow    = false

    private var initial: String { String(companion.name.prefix(1)) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Primary radial — breathes in/out
                RadialGradient(
                    colors: [
                        companion.accentColor.opacity(glow ? 0.50 : 0.28),
                        companion.accentColor.opacity(0.10),
                        Color.black
                    ],
                    center: .init(x: 0.50, y: breathe ? 0.40 : 0.50),
                    startRadius: 0,
                    endRadius: geo.size.width * (breathe ? 0.90 : 0.72)
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: breathe)

                // Secondary radial — drifts diagonally (depth illusion)
                RadialGradient(
                    colors: [companion.accentColor.opacity(0.22), Color.clear],
                    center: .init(x: drift ? 0.30 : 0.70, y: drift ? 0.65 : 0.35),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.65
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true), value: drift)

                // Huge watermark initial — TikTok "creator" feel
                Text(initial)
                    .font(.system(
                        size: min(geo.size.width, geo.size.height) * 0.60,
                        weight: .black,
                        design: .rounded
                    ))
                    .foregroundColor(companion.accentColor.opacity(breathe ? 0.13 : 0.06))
                    .offset(y: breathe ? -24 : 24)
                    .animation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true), value: breathe)

                // Centre avatar cluster
                VStack {
                    Spacer()
                    ZStack {
                        // Outer pulse rings
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .strokeBorder(
                                    companion.accentColor.opacity(
                                        breathe
                                            ? 0.55 / Double(i + 1)
                                            : 0.18 / Double(i + 1)
                                    ),
                                    lineWidth: 1.4
                                )
                                .frame(
                                    width:  156 + CGFloat(i * 30),
                                    height: 156 + CGFloat(i * 30)
                                )
                                .scaleEffect(breathe ? 1.0 + CGFloat(i) * 0.05 : 1.0)
                                .animation(
                                    .easeInOut(duration: 2.6 + Double(i) * 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(i) * 0.35),
                                    value: breathe
                                )
                        }

                        // Avatar fill circle
                        Circle()
                            .fill(companion.accentColor.opacity(0.18))
                            .frame(width: 136, height: 136)

                        // Initial letter inside circle
                        Text(initial)
                            .font(.system(size: 54, weight: .ultraLight, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .offset(y: breathe ? -10 : 10)
                    .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: breathe)

                    Spacer()
                }
            }
        }
        .onAppear {
            breathe = true
            drift   = true
            glow    = true
        }
    }
}

// MARK: - CompanionFaceTimeView
//
// One-time "incoming call" reveal after companion selection.
// CompanionLiveView handles the full-screen animated background.
// Voice engine speaks the personalised intro once the user answers.

struct CompanionFaceTimeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var phase: RevealPhase = .incoming
    @State private var infoOpacity:   Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var callTimerText: String = "Incoming call…"
    @State private var callTimer: Int = 0
    @State private var dismissed = false

    private let companion: CompanionPersonality
    private let userName:  String

    init() {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        companion = CompanionPersonality.find(id: id) ?? .luna
        userName  = UserPersona.load().userName
    }

    var body: some View {
        ZStack {
            // Full-screen animated background — no video files needed
            CompanionLiveView(companion: companion)
                .ignoresSafeArea()

            // Dark vignette so text stays readable
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Pulse rings during ringing phase
            if phase == .incoming || phase == .ringing {
                RingPulseView(color: companion.accentColor)
            }

            VStack(spacing: 20) {
                Spacer()

                // Name + status
                VStack(spacing: 6) {
                    Text(companion.name)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(callTimerText)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.7))
                        .monospacedDigit()
                }
                .opacity(infoOpacity)

                Spacer(); Spacer()

                if phase == .incoming || phase == .ringing {
                    IncomingCallButtons(
                        accentColor: companion.accentColor,
                        onDecline: decline,
                        onAnswer:  answer
                    )
                    .opacity(buttonOpacity)
                }

                if phase == .connected {
                    ConnectedButtons(onContinue: enter)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer().frame(height: 60)
            }
        }
        .onAppear(perform: startIncomingSequence)
        .statusBarHidden(true)
    }

    // MARK: - State machine

    private func startIncomingSequence() {
        configureAudio()
        withAnimation(.easeIn(duration: 0.8).delay(0.4)) { infoOpacity = 1 }
        withAnimation(.spring(response: 0.5).delay(0.8)) { buttonOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation { phase = .ringing }
        }
    }

    private func answer() {
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .connected
            callTimerText = "Connected"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            CompanionVoiceEngine.shared.speak(
                companion.personalizedIntro(for: userName),
                character: companion.voiceCharacter
            )
        }
        startCallTimer()
    }

    private func decline() {
        withAnimation(.easeOut(duration: 0.3)) {
            infoOpacity = 0; buttonOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { enter() }
    }

    private func enter() {
        guard !dismissed else { return }
        dismissed = true
        CompanionVoiceEngine.shared.stopSpeaking()
        appState.markAvatarSeen()
    }

    private func startCallTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            guard !dismissed else { timer.invalidate(); return }
            callTimer += 1
            callTimerText = String(format: "%d:%02d", callTimer / 60, callTimer % 60)
        }
    }

    private func configureAudio() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - CompanionVideoView
//
// Persistent companion screen shown every time the app opens (after the
// one-time reveal). CompanionLiveView provides the animated background.
// Tapping "Start Chatting" switches to .chat mode.

struct CompanionVideoView: View {
    @EnvironmentObject private var appState: AppState
    @State private var contentOpacity:    Double = 0
    @State private var intimacyStageLabel: String = ""

    private let companion: CompanionPersonality
    private let persona:   UserPersona

    init() {
        let p = UserPersona.load()
        persona   = p
        let id    = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        companion = CompanionPersonality.find(id: id) ?? .luna
    }

    var body: some View {
        ZStack {
            // Full-screen animated companion — TikTok feel, no assets needed
            CompanionLiveView(companion: companion)
                .ignoresSafeArea()

            // Vignette overlay
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .black.opacity(0.80)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Voice toggle top-right
                HStack {
                    Spacer()
                    CompanionVoiceToggleButton()
                }
                .padding(.horizontal, 24)
                .padding(.top, 58)

                Spacer()

                // Name + intimacy stage
                VStack(spacing: 6) {
                    Text(companion.name)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    if !intimacyStageLabel.isEmpty {
                        Text(intimacyStageLabel)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(companion.accentColor)
                    }
                }

                Spacer()

                // Start chatting
                Button {
                    CompanionVoiceEngine.shared.stopSpeaking()
                    appState.currentMode = .chat
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 16))
                        Text("Start Chatting")
                            .font(OCFont.headline())
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(OCSizing.radiusLG)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 56)
            }
            .opacity(contentOpacity)
        }
        .onAppear {
            configureAudio()
            maybeGreet()
            Task { intimacyStageLabel = await HerLearningEngine.shared.intimacyStage.label }
            withAnimation(.easeIn(duration: 0.6)) { contentOpacity = 1 }
        }
    }

    private func configureAudio() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func maybeGreet() {
        let key  = "videoView.lastGreeting"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 600 else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        Task { @MainActor in
            let stage = await HerLearningEngine.shared.intimacyStage
            let name  = persona.userName.isEmpty ? "" : " \(persona.userName)"
            let hour  = Calendar.current.component(.hour, from: Date())

            let greeting: String
            switch stage {
            case .justMet, .findingRhythm:
                switch hour {
                case 5..<12:  greeting = "Good morning\(name)."
                case 12..<17: greeting = "Good afternoon\(name)."
                case 17..<21: greeting = "Good evening\(name)."
                default:      greeting = "Hey\(name)."
                }
            case .growingClose:
                greeting = ["Hey\(name). Good to see you.",
                            "Hey\(name). I was thinking about you."].randomElement()!
            case .deepConnection, .intertwined:
                greeting = ["Hey\(name). Missed you.",
                            "Hey\(name). I'm glad you're here.",
                            "Hey. I was just thinking about you\(name)."].randomElement()!
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                CompanionVoiceEngine.shared.speak(greeting, character: companion.voiceCharacter)
            }
        }
    }
}

// MARK: - RevealPhase

private enum RevealPhase { case incoming, ringing, connected }

// MARK: - RingPulseView

private struct RingPulseView: View {
    let color: Color
    @State private var scale:   CGFloat = 1.0
    @State private var opacity: Double  = 0.6

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(color.opacity(opacity / Double(i + 1)), lineWidth: 1.5)
                    .frame(width: 180 + CGFloat(i) * 50, height: 180 + CGFloat(i) * 50)
                    .scaleEffect(scale)
                    .animation(
                        .easeOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.4),
                        value: scale
                    )
            }
        }
        .onAppear { scale = 1.25; opacity = 0 }
    }
}

// MARK: - IncomingCallButtons

private struct IncomingCallButtons: View {
    let accentColor: Color
    let onDecline:   () -> Void
    let onAnswer:    () -> Void

    var body: some View {
        HStack(spacing: 60) {
            callBtn("phone.down.fill", color: .red,   label: "Decline", action: onDecline)
            callBtn("phone.fill",      color: .green, label: "Answer",  action: onAnswer)
        }
    }

    private func callBtn(_ icon: String, color: Color, label: String,
                         action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                ZStack {
                    Circle().fill(color.opacity(0.88)).frame(width: 72, height: 72)
                    Image(systemName: icon).font(.system(size: 26)).foregroundColor(.white)
                }
            }
            Text(label).font(.system(size: 13)).foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - ConnectedButtons

private struct ConnectedButtons: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Your companion is ready.")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            Button(action: onContinue) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Start Chatting").font(OCFont.headline())
                }
                .foregroundColor(.black)
                .padding(.horizontal, 32).padding(.vertical, 14)
                .background(Color.white)
                .cornerRadius(OCSizing.radiusLG)
            }

            Button(action: onContinue) {
                Text("Skip intro")
                    .font(OCFont.caption())
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}
