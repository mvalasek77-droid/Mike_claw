import SwiftUI
import AVFoundation
import AVKit

// MARK: - CompanionFaceTimeView
//
// One-time "FaceTime-style" intro call after companion selection.
//
// Video+Audio approach used here (same as TikTok/Instagram):
//   • Video runs through AVPlayerLayer inside a UIViewRepresentable.
//     This avoids AVKit's VideoPlayer, which re-routes AVAudioSession on
//     init and blocks AVSpeechSynthesizer from outputting through AVAudioEngine.
//   • Audio session is set to .playback + .mixWithOthers BEFORE both start,
//     so video (muted) and companion voice coexist without either interrupting
//     the other.
//   • Voice engine speaks the intro message once the user answers.

struct CompanionFaceTimeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var phase: RevealPhase = .incoming
    @State private var avatarOpacity: Double = 0
    @State private var avatarScale: CGFloat = 0.88
    @State private var infoOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var callTimerText: String = "Incoming call…"
    @State private var callTimer: Int = 0
    @State private var dismissed = false
    @State private var player: AVPlayer?

    private let companion: CompanionPersonality

    init() {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        self.companion = CompanionPersonality.find(id: id) ?? .luna
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── Video layer (muted; voice engine handles audio) ──────────
            if let player = player {
                AVPlayerLayerView(player: player)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else {
                // Fallback: blurred static avatar until/unless video loads
                CompanionAvatarView(companion: companion, size: .detail)
                    .scaledToFill()
                    .ignoresSafeArea()
                    .scaleEffect(avatarScale)
                    .opacity(avatarOpacity * 0.45)
                    .blur(radius: 5)
                    .animation(.easeIn(duration: 1.2), value: avatarOpacity)
            }

            // Dim gradient so UI stays readable
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // ── Pulse rings ──────────────────────────────────────────────
            if phase == .incoming || phase == .ringing {
                RingPulseView(color: companion.accentColor)
            }

            // ── Centre content ───────────────────────────────────────────
            VStack(spacing: 20) {
                Spacer()

                if phase != .connected || player == nil {
                    ZStack {
                        Circle()
                            .fill(companion.accentColor.opacity(0.2))
                            .frame(width: 150, height: 150)
                        CompanionAvatarView(companion: companion, size: .chat)
                            .frame(width: 130, height: 130)
                            .clipShape(Circle())
                            .overlay(Circle()
                                .strokeBorder(companion.accentColor.opacity(0.6), lineWidth: 2))
                    }
                    .scaleEffect(phase == .connected ? 0.7 : 1.0)
                    .animation(.spring(response: 0.5), value: phase)
                }

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
                        onAnswer: answer
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
        .onDisappear(perform: tearDown)
        .statusBarHidden(true)
    }

    // MARK: - State machine

    private func startIncomingSequence() {
        // Configure audio session FIRST so voice + video can coexist
        configureSharedAudioSession()

        withAnimation(.easeIn(duration: 1.2)) { avatarOpacity = 1; avatarScale = 1.0 }
        withAnimation(.easeIn(duration: 0.8).delay(0.5)) { infoOpacity = 1 }
        withAnimation(.spring(response: 0.5).delay(0.9)) { buttonOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { phase = .ringing }
        }
    }

    private func answer() {
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .connected
            callTimerText = "Connected"
        }
        loadAndPlayVideo()
        // Small delay so video frame is visible before voice starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            CompanionVoiceEngine.shared.speak(companion.introMessage,
                                              character: companion.voiceCharacter)
        }
        startCallTimer()
    }

    private func decline() {
        withAnimation(.easeOut(duration: 0.3)) {
            avatarOpacity = 0; infoOpacity = 0; buttonOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { enter() }
    }

    private func enter() {
        guard !dismissed else { return }
        dismissed = true
        CompanionVoiceEngine.shared.stopSpeaking()
        tearDown()
        appState.markAvatarSeen()
    }

    private func tearDown() {
        player?.pause()
        player = nil
    }

    // MARK: - Video loading

    private func loadAndPlayVideo() {
        guard let name = companion.revealVideoName else { return }

        let url = Bundle.main.url(forResource: name, withExtension: "mp4")
            ?? Bundle.main.url(forResource: name, withExtension: "mov")
            ?? Bundle.main.url(forResource: name, withExtension: nil)
        guard let videoURL = url else { return }

        let item = AVPlayerItem(url: videoURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        // Loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { _ in newPlayer.seek(to: .zero); newPlayer.play() }

        withAnimation(.easeIn(duration: 0.5)) { player = newPlayer }
        newPlayer.play()
    }

    // MARK: - Audio session
    // .mixWithOthers lets muted AVPlayer and AVSpeechSynthesizer coexist
    // without either one evicting the other from the audio route.

    private func configureSharedAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Call timer

    private func startCallTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            guard !dismissed else { timer.invalidate(); return }
            callTimer += 1
            callTimerText = String(format: "%d:%02d", callTimer / 60, callTimer % 60)
        }
    }
}

// MARK: - AVPlayerLayerView
//
// UIViewRepresentable that renders AVPlayer into an AVPlayerLayer.
// Unlike AVKit's VideoPlayer it does NOT touch AVAudioSession on init,
// so our own audio session configuration is preserved.

struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}

// MARK: - RevealPhase

private enum RevealPhase { case incoming, ringing, connected }

// MARK: - RingPulseView

private struct RingPulseView: View {
    let color: Color
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(color.opacity(opacity / Double(i + 1)), lineWidth: 1.5)
                    .frame(width: 180 + CGFloat(i) * 50, height: 180 + CGFloat(i) * 50)
                    .scaleEffect(scale)
                    .animation(.easeOut(duration: 1.5)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.4), value: scale)
            }
        }
        .onAppear { scale = 1.25; opacity = 0 }
    }
}

// MARK: - IncomingCallButtons

private struct IncomingCallButtons: View {
    let accentColor: Color
    let onDecline: () -> Void
    let onAnswer:  () -> Void

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

// MARK: - CompanionVideoView
//
// Persistent companion screen — shown every time the app opens (after the
// one-time FaceTime reveal) and any time the user taps "Video" from chat.
//
// Layout:
//   • Full-screen looping companion video (muted) or avatar fallback
//   • Dark gradient overlay so text/buttons remain readable
//   • Companion name + intimacy stage at top
//   • Short voice greeting on appear (rate-limited: at most once per 10 min)
//   • "Start Chatting" button → switches to .chat mode
//   • Voice toggle top-right

struct CompanionVideoView: View {
    @EnvironmentObject private var appState: AppState
    @State private var player: AVPlayer?
    @State private var avatarOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var intimacyStageLabel: String = ""

    private let companion: CompanionPersonality
    private let persona: UserPersona

    init() {
        let p = UserPersona.load()
        self.persona = p
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        self.companion = CompanionPersonality.find(id: id) ?? .luna
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // ── Video or blurred avatar background ────────────────────
            if let player = player {
                AVPlayerLayerView(player: player)
                    .ignoresSafeArea()
                    .transition(.opacity)
            } else {
                CompanionAvatarView(companion: companion, size: .detail)
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(avatarOpacity)
                    .blur(radius: 3)
            }

            // Dark gradient: heavier at top + bottom, clear in middle
            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.80)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // ── UI ────────────────────────────────────────────────────
            VStack(spacing: 0) {

                // Top bar: voice toggle
                HStack {
                    Spacer()
                    CompanionVoiceToggleButton()
                }
                .padding(.horizontal, 24)
                .padding(.top, 58)

                Spacer()

                // Companion name + stage
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

                // Start chatting button
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
            loadVideo()
            maybeGreet()
            Task {
                intimacyStageLabel = await HerLearningEngine.shared.intimacyStage.label
            }
            withAnimation(.easeIn(duration: 0.6)) {
                avatarOpacity = 1
                contentOpacity = 1
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Audio session

    private func configureAudio() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Video

    private func loadVideo() {
        guard let name = companion.revealVideoName else { return }
        let url = Bundle.main.url(forResource: name, withExtension: "mp4")
            ?? Bundle.main.url(forResource: name, withExtension: "mov")
        guard let videoURL = url else { return }

        let item = AVPlayerItem(url: videoURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { _ in newPlayer.seek(to: .zero); newPlayer.play() }

        withAnimation(.easeIn(duration: 0.5)) { player = newPlayer }
        newPlayer.play()
    }

    // MARK: - Voice greeting (rate-limited to once per 10 minutes)

    private func maybeGreet() {
        let key = "videoView.lastGreeting"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 600 else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        let name = persona.userName.isEmpty ? "" : " \(persona.userName)"
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case 5..<12:  greeting = "Good morning\(name)."
        case 12..<17: greeting = "Good afternoon\(name)."
        case 17..<21: greeting = "Good evening\(name)."
        default:      greeting = "Hey\(name)."
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            CompanionVoiceEngine.shared.speak(greeting, character: companion.voiceCharacter)
        }
    }
}
