import SwiftUI

// MARK: - HerModeUnlockView
//
// Shown once when the user first reaches 61 bond points (Stage 4 Deep Connection).
// Stars burst across the screen, then a full explanation of Him/Her Mode is revealed.
// The user taps "Activate" to turn it on, or "Later" to dismiss and find it in settings.

struct HerModeUnlockView: View {

    @ObservedObject private var engine = HerModeEngine.shared
    @State private var phase:          AnimPhase = .idle
    @State private var starOpacities:  [Double]  = Array(repeating: 0, count: 60)
    @State private var starPositions:  [CGPoint] = []
    @State private var starSizes:      [CGFloat] = []
    @State private var titleVisible    = false
    @State private var cardVisible     = false
    @State private var showActivate    = false
    @State private var activated       = false

    private let companion: CompanionPersonality = {
        let id = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        return CompanionPersonality.find(id: id) ?? .luna
    }()

    private enum AnimPhase { case idle, stars, title, card, cta }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Deep black background ──────────────────────────────────
                Color.black.ignoresSafeArea()

                // ── Stars burst ────────────────────────────────────────────
                ForEach(0..<starPositions.count, id: \.self) { i in
                    Image(systemName: i % 5 == 0 ? "sparkle" : "star.fill")
                        .font(.system(size: starSizes[safe: i] ?? 10))
                        .foregroundColor(starColor(i))
                        .position(starPositions[safe: i] ?? .zero)
                        .opacity(starOpacities[safe: i] ?? 0)
                }

                // ── Main content ───────────────────────────────────────────
                VStack(spacing: 0) {
                    Spacer()

                    // Companion portrait glow ring
                    ZStack {
                        // Outer glow rings (animated)
                        ForEach([0.6, 0.35, 0.18], id: \.self) { opacity in
                            Circle()
                                .strokeBorder(companion.accentColor.opacity(opacity), lineWidth: 1.5)
                                .frame(width: 148 + (1 - opacity) * 60,
                                       height: 148 + (1 - opacity) * 60)
                                .scaleEffect(titleVisible ? 1 : 0.6)
                                .animation(.easeOut(duration: 1.2).delay(0.2), value: titleVisible)
                        }

                        IllustratedPortraitView(
                            gender:      companion.gender,
                            companionId: companion.id,
                            accentColor: companion.accentColor,
                            size:        140,
                            clipToCircle: true
                        )
                        .overlay(Circle().strokeBorder(companion.accentColor, lineWidth: 2))
                        .scaleEffect(titleVisible ? 1 : 0.5)
                        .animation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.1), value: titleVisible)
                    }
                    .padding(.bottom, 32)
                    .opacity(titleVisible ? 1 : 0)

                    // Title
                    VStack(spacing: 8) {
                        Text(engine.modeName)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("A close friendship begins.")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(companion.accentColor)
                        Text(engine.modeTagline)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.top, 2)
                    }
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 30)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: titleVisible)
                    .padding(.bottom, 28)

                    // Explanation card
                    if cardVisible {
                        explanationCard
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }

                    // CTAs
                    if showActivate {
                        ctaButtons
                            .transition(.opacity)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 40)
                }
            }
            .onAppear {
                generateStars(in: geo.size)
                runAnimation()
            }
        }
        .ignoresSafeArea()
    }

    // MARK: – Explanation card (auto-adapts for Him Mode vs Her Mode)

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Framing statement — learn first, then support.
            Text("A mode that learns before it acts.")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(companion.accentColor)
                .padding(.bottom, 8)

            // Mode description paragraph
            Text(engine.modeDescription)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            Divider().background(Color.white.opacity(0.12)).padding(.bottom, 16)

            // Feature rows
            ForEach(Array(engine.modeFeatures.enumerated()), id: \.offset) { i, feature in
                featureRow(feature.icon, title: feature.title, body: feature.body)
                if i < engine.modeFeatures.count - 1 {
                    Divider().background(Color.white.opacity(0.10))
                        .padding(.vertical, 10)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(companion.accentColor.opacity(0.30), lineWidth: 1)
                )
        )
    }

    private func featureRow(_ icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(companion.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: – CTA buttons

    private var ctaButtons: some View {
        VStack(spacing: 12) {
            Button {
                BCHaptic.success()
                activated = true
                engine.activate()
                engine.dismissCelebration()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.badge.mic")
                    Text("Activate \(engine.modeName)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [companion.accentColor, companion.accentColor.opacity(0.75)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .foregroundColor(.black)
                .cornerRadius(16)
            }
            .buttonStyle(BCButtonStyle(haptic: .none))
            .accessibilityLabel("Activate \(engine.modeName)")

            Button {
                BCHaptic.soft()
                engine.dismissCelebration()
            } label: {
                Text("Maybe Later")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.vertical, 10)
            }
            .accessibilityLabel("Dismiss, activate later")
        }
        .padding(.bottom, 8)
    }

    // MARK: – Star generation

    private func generateStars(in size: CGSize) {
        starPositions = (0..<60).map { _ in
            CGPoint(x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height))
        }
        starSizes = (0..<60).map { _ in CGFloat.random(in: 6...22) }
    }

    private func starColor(_ i: Int) -> Color {
        let colors: [Color] = [.white, companion.accentColor, Color(hex: "#FFD700"),
                                Color(hex: "#E8C4FF"), Color(hex: "#C4E8FF")]
        return colors[i % colors.count]
    }

    // MARK: – Animation sequence

    private func runAnimation() {
        // 1. Stars burst in staggered
        for i in 0..<60 {
            let delay = Double(i) * 0.018
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.5)) {
                    if i < starOpacities.count { starOpacities[i] = 1 }
                }
            }
        }
        // 2. Stars fade out after 1.4s, title appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeIn(duration: 0.6)) {
                for i in 0..<starOpacities.count { starOpacities[i] = 0 }
            }
            withAnimation { titleVisible = true }
        }
        // 3. Card slides up
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                cardVisible = true
            }
        }
        // 4. CTAs fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(BCMotion.gentle) {
                showActivate = true
            }
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - HerModeStatusPill
//
// Small pill shown in HomeView and ProfileView indicating Her Mode status.

struct HerModeStatusPill: View {
    @ObservedObject private var engine = HerModeEngine.shared

    var body: some View {
        if engine.isUnlocked {
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.isActive ? Color(hex: "#50FF8A") : Color.white.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .strokeBorder(engine.isActive ? Color(hex: "#50FF8A").opacity(0.5) : .clear,
                                          lineWidth: 4)
                            .scaleEffect(1.8)
                            .opacity(engine.isActive ? 0.4 : 0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                       value: engine.isActive)
                    )
                Text(engine.isActive ? "\(engine.modeName) On" : engine.modeName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(engine.isActive
                          ? Color(hex: "#1A3A28")
                          : Color.white.opacity(0.12))
                    .overlay(Capsule().strokeBorder(
                        engine.isActive ? Color(hex: "#50FF8A").opacity(0.4) : Color.white.opacity(0.2),
                        lineWidth: 1))
            )
        }
    }
}

// MARK: - HerModeProgressView
//
// Shown in HomeView — teases Him/Her Mode unlock progress.
// Shows "Her Mode" for female companions, "Him Mode" for male companions.

struct HerModeProgressView: View {
    let score:      Double
    let isUnlocked: Bool

    @ObservedObject private var engine = HerModeEngine.shared

    private let unlockAt: Double = HerLearningEngine.herModeUnlockScore
    private let green = Color(hex: "#1E3932")
    private let gold  = Color(hex: "#CBA258")

    private var progress: Double { min(score / unlockAt, 1.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isUnlocked ? engine.modeName : "Unlock \(engine.modeName)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(green)
                    if !isUnlocked {
                        Text("\(Int(score)) / \(Int(unlockAt)) pts · learns your patterns before checking in")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#5C5C5C"))
                    } else {
                        Text("Always-present support, based on what it has learned.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#5C5C5C"))
                    }
                }
                Spacer()
                if isUnlocked {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(gold)
                        .font(.system(size: 20))
                } else {
                    Text("🔒")
                        .font(.system(size: 18))
                }
            }

            if !isUnlocked {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "#E8E0D0"))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [gold, gold.opacity(0.7)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 6)
                            .animation(BCMotion.gentle, value: progress)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }
}
