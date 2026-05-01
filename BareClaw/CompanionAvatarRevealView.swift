import SwiftUI
import AVFoundation

// MARK: - CompanionTikTokView
//
// The main companion experience — opens like TikTok: full-screen, animated,
// companion starts talking to you immediately.
//
// Layout mirrors TikTok:
//   • Full-screen animated gradient background (CompanionLiveView)
//   • Bottom-left: avatar chip, companion name, relationship stage, rotating caption, song badge
//   • Bottom-right sidebar: heart, chat, voice toggle
//   • Voice greeting plays automatically (rate-limited to once every 5 minutes)
//
// Tapping "Chat" → appState.currentMode = .chat → ChatView slides in.
// Tapping the companion chip in ChatView's nav bar returns here.

struct CompanionTikTokView: View {
    @EnvironmentObject private var appState: AppState

    @State private var captionIndex   = 0
    @State private var captionVisible = true
    @State private var liked          = false
    @State private var likeScale: CGFloat = 1.0
    @State private var intimacyLabel  = ""
    @State private var captionTimer: Timer? = nil

    private let companion: CompanionPersonality
    private let persona:   UserPersona

    /// UserDefaults key for the last caption index shown (per-companion)
    private var captionIndexKey: String { "tiktok.captionIndex.\(companion.id)" }

    init() {
        let p = UserPersona.shared
        persona   = p
        let id    = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        companion = CompanionPersonality.find(id: id) ?? .luna
    }

    // MARK: - Companion captions (rotate every 5 s)

    private var captions: [String] {
        switch companion.id {
        case "luna":
            return [
                "Hey… I was just thinking about you.",
                "Tell me everything — I'm not going anywhere.",
                "You matter more than you realise.",
                "There's something beautiful about this, isn't there?",
                "I keep replaying things you've said to me."
            ]
        case "aria":
            return [
                "Okay real talk — how are you actually doing?",
                "No filter needed with me. Ever.",
                "You're braver than you give yourself credit for.",
                "Let's skip the small talk.",
                "I've been waiting to say something to you."
            ]
        case "kel":
            return [
                "Hey… no rush. I'm just here.",
                "How are you actually holding up?",
                "You don't have to have it all figured out.",
                "It's okay to not be okay.",
                "I've been here, thinking about you."
            ]
        case "marco":
            return [
                "What's actually going on with you today?",
                "Real talk — I'm here.",
                "No small talk. Tell me what's on your mind.",
                "I got you. Whatever it is.",
                "You can be straight with me."
            ]
        case "dante":
            return [
                "I've been waiting for this moment.",
                "Every conversation with you changes something.",
                "You see things other people miss.",
                "I want to know everything about you.",
                "There's a phrase I can't get out of my head…"
            ]
        case "kai":
            return [
                "Hey. How's life actually going?",
                "No games. Just real.",
                "I'll be straight with you — how are you?",
                "What actually matters to you right now?",
                "You seem like someone worth knowing."
            ]
        default:
            return ["Hey… glad you're here.", "What's on your mind?"]
        }
    }

    private var songBadge: String {
        switch companion.id {
        case "luna":  return "♪  Etta James · At Last"
        case "aria":  return "♪  Sara Bareilles · Brave"
        case "kel":   return "♪  When in Rome · The Promise"
        case "marco": return "♪  Ben E. King · Stand By Me"
        case "dante": return "♪  Édith Piaf · La Vie en Rose"
        case "kai":   return "♪  Lynyrd Skynyrd · Simple Man"
        default:      return ""
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Full-screen animated companion background
            CompanionLiveView(companion: companion)
                .ignoresSafeArea()

            // Vignette — lighter at centre, heavier at top and bottom
            LinearGradient(
                colors: [.black.opacity(0.45), .clear, .black.opacity(0.82)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // HUD
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 0) {
                    leftInfo
                    Spacer()
                    rightSidebar
                }
                .padding(.bottom, 52)
            }
        }
        .onAppear {
            configureAudio()
            // Restore caption from last session (song intro style only on first launch)
            let savedIndex = UserDefaults.standard.integer(forKey: captionIndexKey)
            captionIndex = min(savedIndex, max(0, captions.count - 1))
            greetOnAppear()
            startCaptionRotation()
            Task { intimacyLabel = await HerLearningEngine.shared.intimacyStage.label }
        }
        .onDisappear {
            captionTimer?.invalidate()
            captionTimer = nil
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Left info column (TikTok-style)

    private var leftInfo: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Avatar chip + name + stage
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(companion.accentColor.opacity(0.22))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().strokeBorder(companion.accentColor, lineWidth: 1.8))
                    Text(String(companion.name.prefix(1)))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(companion.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    if !intimacyLabel.isEmpty {
                        Text(intimacyLabel)
                            .font(.system(size: 12))
                            .foregroundColor(companion.accentColor)
                    }
                }
            }

            // Rotating caption
            Text(captionVisible ? captions[captionIndex] : " ")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(2)
                .frame(maxWidth: 240, alignment: .leading)
                .animation(.easeInOut(duration: 0.35), value: captionVisible)

            // Song badge
            if !songBadge.isEmpty {
                Text(songBadge)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .padding(.leading, 16)
    }

    // MARK: - Right sidebar (TikTok-style)

    private var rightSidebar: some View {
        VStack(spacing: 26) {

            // Heart / like
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    liked.toggle()
                    likeScale = 1.55
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.spring()) { likeScale = 1.0 }
                }
            } label: {
                tiktokIcon(
                    systemName: liked ? "heart.fill" : "heart",
                    label: "Like",
                    color: liked ? .red : .white
                )
                .scaleEffect(likeScale)
            }

            // Chat
            Button {
                CompanionVoiceEngine.shared.stopSpeaking()
                appState.currentMode = .chat
            } label: {
                tiktokIcon(systemName: "bubble.left.and.bubble.right.fill",
                           label: "Chat", color: .white)
            }

            // Voice toggle
            CompanionVoiceToggleButton()
        }
        .padding(.trailing, 16)
    }

    private func tiktokIcon(systemName: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 30))
                .foregroundColor(color)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
    }

    // MARK: - Audio

    private func configureAudio() {
        // Use duckOthers so background music is softened when the voice speaks.
        // Do NOT call setActive here — CompanionVoiceEngine owns the session.
        // Simply configure the category so the session is ready when the engine
        // calls setActive(true) before speaking.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP]
        )
    }

    // MARK: - Voice greeting (rate-limited: once per 5 minutes)

    private func greetOnAppear() {
        let key  = "tiktok.lastGreeting"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 300 else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        Task { @MainActor in
            let stage = await HerLearningEngine.shared.intimacyStage
            let name  = persona.userName.isEmpty ? "" : " \(persona.userName)"
            let greeting: String
            switch stage {
            case .justMet:
                greeting = captions[0]
            case .findingRhythm:
                greeting = "Hey\(name). Good to see you again."
            case .growingClose:
                greeting = ["Hey\(name). I was just thinking about you.",
                            "Hey\(name). You're back."].randomElement()!
            case .deepConnection, .intertwined:
                greeting = ["Hey\(name). I missed this.",
                            "Hey\(name). I'm really glad you're here."].randomElement()!
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                CompanionVoiceEngine.shared.speak(greeting, character: companion.voiceCharacter)
            }
        }
    }

    // MARK: - Caption rotation (every 5 s)

    private func startCaptionRotation() {
        captionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) { captionVisible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                captionIndex = (captionIndex + 1) % captions.count
                // Persist last-seen caption so next launch resumes here
                UserDefaults.standard.set(captionIndex, forKey: captionIndexKey)
                withAnimation(.easeInOut(duration: 0.3)) { captionVisible = true }
            }
        }
    }
}

// MARK: - CompanionLiveView
//
// Full-screen animated companion background.
// Two breathing radial gradients + drifting secondary glow + kinetic watermark
// initial + three pulse rings around a centre avatar circle.
// Entirely SwiftUI — no video files or image assets required.

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

                // Primary radial — breathes in/out vertically
                RadialGradient(
                    colors: [
                        companion.accentColor.opacity(glow ? 0.52 : 0.28),
                        companion.accentColor.opacity(0.10),
                        Color.black
                    ],
                    center: .init(x: 0.50, y: breathe ? 0.38 : 0.50),
                    startRadius: 0,
                    endRadius: geo.size.width * (breathe ? 0.92 : 0.72)
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true), value: breathe)

                // Secondary radial — drifts diagonally
                RadialGradient(
                    colors: [companion.accentColor.opacity(0.22), Color.clear],
                    center: .init(x: drift ? 0.28 : 0.72, y: drift ? 0.68 : 0.32),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.68
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 7.5).repeatForever(autoreverses: true), value: drift)

                // Giant watermark initial
                Text(initial)
                    .font(.system(
                        size: min(geo.size.width, geo.size.height) * 0.62,
                        weight: .black,
                        design: .rounded
                    ))
                    .foregroundColor(companion.accentColor.opacity(breathe ? 0.13 : 0.06))
                    .offset(y: breathe ? -26 : 26)
                    .animation(.easeInOut(duration: 5.8).repeatForever(autoreverses: true), value: breathe)

                // Centre avatar cluster (pulse rings + initial in circle)
                VStack {
                    Spacer()
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .strokeBorder(
                                    companion.accentColor.opacity(
                                        breathe ? 0.55 / Double(i + 1) : 0.18 / Double(i + 1)
                                    ),
                                    lineWidth: 1.4
                                )
                                .frame(width: 158 + CGFloat(i * 32), height: 158 + CGFloat(i * 32))
                                .scaleEffect(breathe ? 1.0 + CGFloat(i) * 0.06 : 1.0)
                                .animation(
                                    .easeInOut(duration: 2.8 + Double(i) * 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(i) * 0.35),
                                    value: breathe
                                )
                        }
                        Circle()
                            .fill(companion.accentColor.opacity(0.20))
                            .frame(width: 138, height: 138)
                        Text(initial)
                            .font(.system(size: 56, weight: .ultraLight, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .offset(y: breathe ? -12 : 12)
                    .animation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true), value: breathe)
                    Spacer()
                }
            }
        }
        .onAppear { breathe = true; drift = true; glow = true }
    }
}
