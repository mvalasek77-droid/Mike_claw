import SwiftUI
import AVFoundation
import AVKit

// MARK: - CompanionFaceTimeView
//
// One-time "FaceTime-style" intro call shown after companion selection.
// Black background → incoming call animation → Answer → plays companion reveal
// video (if bundled) or full-screen blurred avatar → companion voice intro.
//
// The reveal video should be an mp4 bundled in the Xcode target named e.g.
// "reveal_luna.mp4". Drop the file into the project and add it to the target.
// If no video is found the view falls back to the static avatar background.

struct CompanionFaceTimeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var phase: RevealPhase = .incoming
    @State private var avatarScale: CGFloat = 0.85
    @State private var avatarOpacity: Double = 0
    @State private var infoOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var callTimerText: String = "Incoming call…"
    @State private var callTimer: Int = 0
    @State private var dismissed = false
    @State private var player: AVPlayer?
    @State private var playerOpacity: Double = 0

    private let companion: CompanionPersonality

    init() {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        self.companion = CompanionPersonality.find(id: id) ?? .luna
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // MARK: Background layer — video (preferred) or blurred avatar
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .opacity(playerOpacity)
                    .allowsHitTesting(false)
            } else {
                CompanionAvatarView(companion: companion, size: .detail)
                    .scaledToFill()
                    .ignoresSafeArea()
                    .scaleEffect(avatarScale)
                    .opacity(avatarOpacity * 0.45)
                    .blur(radius: 4)
            }

            // Dim overlay so UI stays readable over video
            if phase == .connected {
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear, .black.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            // MARK: Pulse rings (incoming / ringing only)
            if phase == .incoming || phase == .ringing {
                RingPulseView(color: companion.accentColor)
            }

            // MARK: Center content
            VStack(spacing: 20) {
                Spacer()

                // Avatar circle — shrinks after connect when video takes over
                if phase != .connected || player == nil {
                    ZStack {
                        Circle()
                            .fill(companion.accentColor.opacity(0.2))
                            .frame(width: 150, height: 150)

                        CompanionAvatarView(companion: companion, size: .chat)
                            .frame(width: 130, height: 130)
                            .clipShape(Circle())
                            .overlay(
                                Circle().strokeBorder(companion.accentColor.opacity(0.6), lineWidth: 2)
                            )
                    }
                    .scaleEffect(phase == .connected ? 0.7 : 1.0)
                    .animation(.spring(response: 0.5), value: phase)
                }

                VStack(spacing: 6) {
                    Text(companion.name)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(callTimerText)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .monospacedDigit()
                }
                .opacity(infoOpacity)

                Spacer()
                Spacer()

                // MARK: Buttons
                if phase == .incoming || phase == .ringing {
                    IncomingCallButtons(
                        accentColor: companion.accentColor,
                        onDecline: { decline() },
                        onAnswer:  { answer() }
                    )
                    .opacity(buttonOpacity)
                }

                if phase == .connected {
                    ConnectedButtons(onContinue: { enter() })
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer().frame(height: 60)
            }
        }
        .onAppear { startIncomingSequence() }
        .onDisappear { tearDownPlayer() }
        .statusBarHidden(true)
    }

    // MARK: - State machine

    private func startIncomingSequence() {
        withAnimation(.easeIn(duration: 1.2)) {
            avatarOpacity = 1
            avatarScale = 1.0
        }
        withAnimation(.easeIn(duration: 0.8).delay(0.5)) {
            infoOpacity = 1
        }
        withAnimation(.spring(response: 0.5).delay(0.9)) {
            buttonOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { phase = .ringing }
        }
    }

    private func answer() {
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .connected
            callTimerText = "Connected"
        }

        // Try to load and play the reveal video
        loadRevealVideo()

        // Companion voice intro
        CompanionVoiceEngine.shared.speak(companion.introMessage, character: companion.voiceCharacter)
        startCallTimer()
    }

    private func loadRevealVideo() {
        guard let videoName = companion.revealVideoName else { return }

        // Search bundle for the file with or without extension
        let url: URL? = Bundle.main.url(forResource: videoName, withExtension: "mp4")
            ?? Bundle.main.url(forResource: videoName, withExtension: "mov")
            ?? Bundle.main.url(forResource: videoName, withExtension: nil)

        guard let videoURL = url else {
            // No video found — the blurred avatar background continues to show
            return
        }

        let newPlayer = AVPlayer(url: videoURL)
        newPlayer.isMuted = true          // Voice engine handles audio
        newPlayer.actionAtItemEnd = .none // Loop

        // Loop playback
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in newPlayer.seek(to: .zero); newPlayer.play() }

        self.player = newPlayer
        newPlayer.play()

        withAnimation(.easeIn(duration: 0.8)) {
            playerOpacity = 1
        }
    }

    private func decline() {
        withAnimation(.easeOut(duration: 0.3)) {
            avatarOpacity = 0
            infoOpacity   = 0
            buttonOpacity = 0
            playerOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { enter() }
    }

    private func enter() {
        guard !dismissed else { return }
        dismissed = true
        CompanionVoiceEngine.shared.stopSpeaking()
        tearDownPlayer()
        appState.markAvatarSeen()
    }

    private func tearDownPlayer() {
        player?.pause()
        player = nil
    }

    private func startCallTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            callTimer += 1
            let m = callTimer / 60
            let s = callTimer % 60
            callTimerText = String(format: "%d:%02d", m, s)
            if dismissed { timer.invalidate() }
        }
    }
}

// MARK: - RevealPhase

private enum RevealPhase {
    case incoming, ringing, connected
}

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
                    .frame(width: 180 + CGFloat(i) * 50,
                           height: 180 + CGFloat(i) * 50)
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
    let onDecline: () -> Void
    let onAnswer:  () -> Void

    var body: some View {
        HStack(spacing: 60) {
            callButton(icon: "phone.down.fill", color: .red, label: "Decline", action: onDecline)
            callButton(icon: "phone.fill",      color: .green, label: "Answer", action: onAnswer)
        }
    }

    private func callButton(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.88))
                        .frame(width: 72, height: 72)
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                }
            }
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
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
                    Text("Start Chatting")
                        .font(OCFont.headline())
                }
                .foregroundColor(.black)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
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
