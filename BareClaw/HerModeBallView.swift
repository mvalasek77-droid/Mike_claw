import SwiftUI

// MARK: - HerModeBallView
//
// Persistent floating bear-logo ball that lives over every screen
// while Her Mode is active — inspired by the Siri orb, but warmer.
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

    // Transcript pill
    @State private var showTranscript: Bool = false
    @State private var transcriptTask:  Task<Void, Never>? = nil

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
                            flashTranscript()
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

                // ── Transcript pill ────────────────────────────────────
                if showTranscript, !herMode.liveTranscript.isEmpty {
                    transcriptPill
                        .position(
                            x: geo.size.width / 2,
                            y: effectivePosition(in: geo).y - ballSize / 2 - 28
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal:   .opacity
                        ))
                }
            }
            .onChange(of: geo.size) { _ in
                position = defaultPosition(in: geo)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
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
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .offset(x: ballSize * 0.32, y: -ballSize * 0.32)
            } else {
                // Inactive state — small grey dot so user knows it's paused
                Circle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
                    .offset(x: ballSize * 0.32, y: -ballSize * 0.32)
            }
        }
        .opacity(herMode.isActive ? 1.0 : 0.45)   // dim when paused — clearly inactive
        .scaleEffect(isDragging ? 1.12 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isDragging)
        .animation(.easeInOut(duration: 0.3), value: herMode.isActive)
    }

    // MARK: - Transcript pill

    private var transcriptPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: "#30D158"))
                .frame(width: 7, height: 7)
            Text(herMode.liveTranscript.suffix(60))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#1C2438").opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(ringColor.opacity(0.35), lineWidth: 1)
                )
        )
        .frame(maxWidth: 260)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
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

    // MARK: - Transcript flash

    private func flashTranscript() {
        guard !herMode.liveTranscript.isEmpty else { return }
        transcriptTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showTranscript = true
        }
        transcriptTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { showTranscript = false }
            }
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

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
