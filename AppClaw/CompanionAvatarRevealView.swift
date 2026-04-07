import SwiftUI
import AVFoundation
import AVKit

// MARK: - CompanionAvatarRevealView
//
// The one-time "FaceTime-style" intro call shown after onboarding.
// Black background. Companion avatar fills the screen with a calling animation,
// then companion voice introduces herself/himself.
// Tapping "Answer" transitions into the app.
//
// Referenced as CompanionFaceTimeView in AppClawApp.swift.

struct CompanionFaceTimeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var phase: RevealPhase = .incoming
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.7
    @State private var avatarScale: CGFloat = 0.85
    @State private var avatarOpacity: Double = 0
    @State private var infoOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var callTimerText: String = "Incoming call…"
    @State private var callTimer: Int = 0
    @State private var dismissed = false

    private let companion: CompanionPersonality

    init() {
        // Load selected companion; fall back to Luna
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        self.companion = CompanionPersonality.find(id: id) ?? .luna
    }

    var body: some View {
        ZStack {
            // Pure black background
            Color.black.ignoresSafeArea()

            // Companion avatar (full screen, blurred / dimmed)
            CompanionAvatarView(companion: companion, size: .detail)
                .scaledToFill()
                .ignoresSafeArea()
                .scaleEffect(avatarScale)
                .opacity(avatarOpacity * 0.45)
                .blur(radius: 4)

            // Pulsing ring animation
            if phase == .incoming || phase == .ringing {
                RingPulseView(color: companion.accentColor)
                    .opacity(ringOpacity)
            }

            // Center avatar + name block
            VStack(spacing: 20) {
                Spacer()

                // Companion avatar circle
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

                // Companion name
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

                // Action buttons
                if phase == .incoming || phase == .ringing {
                    IncomingCallButtons(
                        accentColor: companion.accentColor,
                        onDecline: { decline() },
                        onAnswer:  { answer() }
                    )
                    .opacity(buttonOpacity)
                }

                if phase == .connected {
                    ConnectedButtons(
                        onContinue: { enter() }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer().frame(height: 60)
            }
        }
        .onAppear { startIncomingSequence() }
        .statusBarHidden(true)
    }

    // MARK: - State machine

    private func startIncomingSequence() {
        // Fade in avatar background
        withAnimation(.easeIn(duration: 1.2)) {
            avatarOpacity = 1
            avatarScale = 1.0
        }
        // Info text
        withAnimation(.easeIn(duration: 0.8).delay(0.5)) {
            infoOpacity = 1
        }
        // Buttons
        withAnimation(.spring(response: 0.5).delay(0.9)) {
            buttonOpacity = 1
        }
        // Transition to ringing after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { phase = .ringing }
        }
    }

    private func answer() {
        withAnimation(.easeInOut(duration: 0.4)) {
            phase = .connected
            callTimerText = "Connected"
        }
        // Play companion's voice intro
        let intro = companion.introMessage
        CompanionVoiceEngine.shared.speak(intro, character: companion.voiceCharacter)

        // Start call timer
        startCallTimer()
    }

    private func decline() {
        withAnimation(.easeOut(duration: 0.3)) {
            avatarOpacity = 0
            infoOpacity   = 0
            buttonOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            enter()
        }
    }

    private func enter() {
        guard !dismissed else { return }
        dismissed = true
        CompanionVoiceEngine.shared.stopSpeaking()
        appState.markAvatarSeen()
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

// MARK: - Pulsing ring animation

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
        .onAppear {
            scale = 1.25
            opacity = 0
        }
    }
}

// MARK: - Incoming call buttons (Answer / Decline)

private struct IncomingCallButtons: View {
    let accentColor: Color
    let onDecline: () -> Void
    let onAnswer:  () -> Void

    var body: some View {
        HStack(spacing: 60) {
            // Decline
            VStack(spacing: 10) {
                Button(action: onDecline) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 72, height: 72)
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }
                }
                Text("Decline")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
            }

            // Answer
            VStack(spacing: 10) {
                Button(action: onAnswer) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.9))
                            .frame(width: 72, height: 72)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }
                }
                Text("Answer")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - Connected screen buttons

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
