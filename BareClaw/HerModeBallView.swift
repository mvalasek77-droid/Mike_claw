import SwiftUI

// MARK: - HerModeBallView
//
// Persistent floating bear-logo ball that lives over every screen
// while Her Mode is active.
//
// Behaviour:
//   • Draggable — snaps to nearest edge when released (iOS convention)
//   • Pulsing glow ring that responds to AmbientMood states
//   • Tap once → compact transcript pill slides in for 4 seconds
//   • Hold (long-press) → opens full Her Mode panel
//   • Vanishes (opacity 0) when companion is speaking so it doesn't
//     feel like two things happening at once
//
// Mood → visual mapping:
//   .quiet     → slow amber pulse, low opacity
//   .listening → faster teal ring sweep, higher opacity
//   .thinking  → warm orange glow shimmer
//   .speaking  → hidden (companion voice is the presence)

struct HerModeBallView: View {
    @ObservedObject private var herMode = HerModeEngine.shared

    // Position — starts near bottom-right safe area
    @State private var position:   CGPoint = .zero
    @State private var isDragging: Bool    = false
    @State private var dragOffset: CGSize  = .zero

    @State private var showGuide: Bool = false

    // Glow animation
    @State private var glowPulse: Bool = false
    @State private var ringScale: CGFloat = 1.0

    private let ballSize: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Floating ball ──────────────────────────────────────
                ballLayer
                    .position(effectivePosition(in: geo))
                    .opacity(herMode.ambientMood == .speaking ? 0 : 1)
                    .animation(.easeInOut(duration: 0.35), value: herMode.ambientMood)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { v in
                                isDragging = true
                                dragOffset = v.translation
                            }
                            .onEnded { v in
                                isDragging = false
                                let newX = effectivePosition(in: geo).x + v.translation.width
                                let newY = effectivePosition(in: geo).y + v.translation.height
                                position = snapToEdge(
                                    CGPoint(x: newX, y: newY),
                                    in: geo
                                )
                                dragOffset = .zero
                            }
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            showGuide = true
                        }
                    )
                    .onLongPressGesture(minimumDuration: 0.6) {
                        // Long-press: toggle Her Mode active/inactive
                        if herMode.isActive { herMode.deactivate() }
                        else { herMode.activate() }
                    }
                    .onAppear {
                        position = defaultPosition(in: geo)
                    }
            }
            .onChange(of: geo.size) { _, _ in
                position = defaultPosition(in: geo)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .sheet(isPresented: $showGuide) {
            HerModeBallGuideSheet(herMode: herMode)
        }
    }

    // MARK: - Ball layer

    private var ballLayer: some View {
        ZStack {
            // Outer glow rings — suppressed when inactive, mood-reactive when active
            if herMode.isActive {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .strokeBorder(ringColor.opacity(
                            glowPulse ? 0.55 / Double(i + 1) : 0.15 / Double(i + 1)
                        ), lineWidth: 1.5)
                        .frame(
                            width:  ballSize + CGFloat(i) * 14,
                            height: ballSize + CGFloat(i) * 14
                        )
                        .scaleEffect(glowPulse ? 1.0 + CGFloat(i) * 0.04 : 1.0)
                        .animation(
                            ringAnimation.delay(Double(i) * 0.25),
                            value: glowPulse
                        )
                }
            }

            // Ball background
            Circle()
                .fill(ballBackground)
                .frame(width: ballSize, height: ballSize)
                .shadow(color: ringColor.opacity(0.55), radius: 10, y: 3)

            // Bear logo — no background (circle IS the background)
            BearLogoView(size: ballSize * 0.72, showBackground: false)

            // Status indicator dot (top-right)
            // Green pulse = listening | grey = unlocked but paused
            if herMode.isActive {
                Circle()
                    .fill(herMode.isListening ? Color(hex: "#30D158") : Color(hex: "#FF9F0A"))
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1.5))
                    .shadow(color: herMode.isListening ? Color(hex: "#30D158").opacity(0.85) : Color(hex: "#FF9F0A").opacity(0.7),
                            radius: herMode.isListening ? 8 : 5)
                    .offset(x: ballSize * 0.34, y: -ballSize * 0.34)
            } else {
                // Inactive state — small grey dot so user knows it's paused
                Circle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
                    .offset(x: ballSize * 0.32, y: -ballSize * 0.32)
            }
        }
        .opacity(herMode.isActive ? 1.0 : 0.45)   // dim when paused — clearly inactive
        .scaleEffect(isDragging ? 1.12 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isDragging)
        .animation(.easeInOut(duration: 0.3), value: herMode.isActive)
    }

    // MARK: - Mood-reactive colours / animations

    private var ringColor: Color {
        switch herMode.ambientMood {
        case .quiet:     return Color(hex: "#FF9F0A")   // amber
        case .listening: return Color(hex: "#32ADE6")   // teal
        case .thinking:  return Color(hex: "#FF6B35")   // orange
        case .speaking:  return Color(hex: "#FF9F0A")   // amber (hidden anyway)
        }
    }

    private var ballBackground: LinearGradient {
        switch herMode.ambientMood {
        case .quiet:
            return LinearGradient(
                colors: [Color(hex: "#1C2438"), Color(hex: "#0D1117")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .listening:
            return LinearGradient(
                colors: [Color(hex: "#0A2A3A"), Color(hex: "#0D1117")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .thinking:
            return LinearGradient(
                colors: [Color(hex: "#2A1A08"), Color(hex: "#0D1117")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .speaking:
            return LinearGradient(
                colors: [Color(hex: "#1C2438"), Color(hex: "#0D1117")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var ringAnimation: Animation {
        switch herMode.ambientMood {
        case .quiet:     return .easeInOut(duration: 3.0).repeatForever(autoreverses: true)
        case .listening: return .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        case .thinking:  return .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
        case .speaking:  return .easeInOut(duration: 3.0).repeatForever(autoreverses: true)
        }
    }

    // MARK: - Positioning helpers

    private func defaultPosition(in geo: GeometryProxy) -> CGPoint {
        CGPoint(x: geo.size.width - ballSize / 2 - 20,
                y: geo.size.height - ballSize / 2 - 110)
    }

    private func effectivePosition(in geo: GeometryProxy) -> CGPoint {
        if position == .zero { return defaultPosition(in: geo) }
        return CGPoint(
            x: position.x + dragOffset.width,
            y: position.y + dragOffset.height
        )
    }

    /// Snaps the ball to whichever horizontal edge is closer, keeping Y clamped.
    private func snapToEdge(_ point: CGPoint, in geo: GeometryProxy) -> CGPoint {
        let margin: CGFloat = ballSize / 2 + 12
        let snappedX: CGFloat = point.x < geo.size.width / 2
            ? margin
            : geo.size.width - margin
        let clampedY = point.y.clamped(
            to: ballSize / 2 + 60 ... geo.size.height - ballSize / 2 - 80
        )
        return CGPoint(x: snappedX, y: clampedY)
    }
}

private struct HerModeBallGuideSheet: View {
    @ObservedObject var herMode: HerModeEngine
    @Environment(\.dismiss) private var dismiss

    private var companion: CompanionPersonality {
        UserPersona.shared.selectedCompanion
    }

    private var wakeName: String {
        let persona = UserPersona.shared
        let custom = persona.assistantName.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? companion.name : custom
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusHeader
                    guideRow(
                        icon: "waveform.badge.mic",
                        title: "Voice entry",
                        body: "Say \"\(wakeName)\" followed by what you want to say. Example: \"\(wakeName), how are you?\""
                    )
                    guideRow(
                        icon: "ear",
                        title: "Ambient listening",
                        body: "When active, it listens while the app is open, builds short local summaries of broad speech themes, and waits for a quiet moment before checking in."
                    )
                    guideRow(
                        icon: "exclamationmark.triangle",
                        title: "Stress cues",
                        body: "Loud audio or tense words can trigger a gentle check-in. It asks first unless you teach it a preferred action."
                    )
                    guideRow(
                        icon: "music.note",
                        title: "Music and shows",
                        body: "If it hears words about a song, music, or a show, it can ask whether you like it. It does not identify media like Shazam."
                    )
                    Button {
                        if herMode.isActive { herMode.deactivate() }
                        else { herMode.activate() }
                    } label: {
                        Label(herMode.isActive ? "Pause \(herMode.modeName)" : "Activate \(herMode.modeName)",
                              systemImage: herMode.isActive ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(companion.accentColor)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color(hex: "#F7F4EF").ignoresSafeArea())
            .navigationTitle("Bear Ball")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(herMode.isListening ? Color(hex: "#30D158") : herMode.isActive ? Color(hex: "#FF9F0A") : Color.gray)
                    .frame(width: 10, height: 10)
                Text(herMode.isActive ? herMode.statusMessage : "Paused")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "#1E3932"))
            }
            Text("\(herMode.modeName) is the companion layer behind the floating bear.")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "#1E3932"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func guideRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(companion.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#1E3932"))
                Text(body)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#42524B"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
