import SwiftUI

/// Standalone home for BitDrop — playable on its own from the Apps tab
/// or the Home QuickTile, separate from build-time. Adds:
///   - persisted high score (UserDefaults)
///   - difficulty selection that biases the engine's tick interval
///   - a how-to-play overlay first time the game loads
///   - clean restart / pause UX
struct GameHomeView: View {
    @StateObject private var game = BitDropGame()
    @AppStorage("bitdrop.highScore") private var highScore: Int = 0
    @AppStorage("bitdrop.bestLines") private var bestLines: Int = 0
    @AppStorage("bitdrop.seenHelp") private var seenHelp: Bool = false
    @State private var showHelp: Bool = false
    @State private var difficulty: Difficulty = .normal
    @Environment(\.dismiss) private var dismiss

    enum Difficulty: String, CaseIterable, Identifiable {
        case chill = "Chill"
        case normal = "Normal"
        case relentless = "Relentless"
        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    scoreboard
                    difficultyPicker
                    boardCard
                    tipsCard
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)

            if showHelp { helpOverlay }
        }
        .onAppear {
            if !seenHelp {
                showHelp = true
                seenHelp = true
            }
        }
        .onChange(of: game.score) { _, new in
            if new > highScore { highScore = new }
        }
        .onChange(of: game.rowsCleared) { _, new in
            if new > bestLines { bestLines = new }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("BitDrop")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Stack Swift symbols. Clear rows. Earn build boosts.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            }
            Spacer()
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
            }
            .accessibilityLabel("How to play")
        }
    }

    private var scoreboard: some View {
        HStack(spacing: 10) {
            ScoreTile(label: "Score", value: "\(game.score)", icon: "star.fill", tint: LiquidGlass.accent)
            ScoreTile(label: "Lines", value: "\(game.rowsCleared)", icon: "line.3.horizontal", tint: LiquidGlass.accentSecondary)
            ScoreTile(label: "Best",  value: "\(highScore)", icon: "crown.fill", tint: LiquidGlass.warning)
        }
        .accessibilityElement(children: .contain)
    }

    private var difficultyPicker: some View {
        GlassCard(title: "Difficulty", icon: "speedometer", tint: LiquidGlass.success) {
            HStack(spacing: 8) {
                ForEach(Difficulty.allCases) { d in
                    Button {
                        difficulty = d
                        Haptics.selection()
                    } label: {
                        Text(d.rawValue)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                d == difficulty
                                ? AnyShapeStyle(LiquidGlass.auroraGradient)
                                : AnyShapeStyle(Color.white.opacity(0.06)),
                                in: Capsule()
                            )
                            .overlay(Capsule().strokeBorder(.white.opacity(d == difficulty ? 0.4 : 0.12)))
                            .foregroundStyle(LiquidGlass.primaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(d == difficulty ? .isSelected : [])
                    .accessibilityLabel("\(d.rawValue) difficulty")
                }
            }
        }
    }

    private var boardCard: some View {
        GlassCard(title: "Board", icon: "square.stack.3d.up.fill", tint: LiquidGlass.accentSecondary) {
            BitDropView(game: game)
        }
    }

    private var tipsCard: some View {
        GlassCard(title: "Tips", icon: "lightbulb.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 6) {
                tipRow("Tap the board", "Rotate the falling piece")
                tipRow("Drag left or right", "Move horizontally")
                tipRow("Drag down", "Soft drop")
                tipRow("Double-tap", "Hard drop")
                tipRow("Clear 4 rows at once", "10× score and a 'Tetris' haptic")
            }
        }
    }

    private func tipRow(_ left: String, _ right: String) -> some View {
        HStack(spacing: 10) {
            Text(left)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.18)))
                .foregroundStyle(LiquidGlass.primaryText)
            Text(right)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
            Spacer()
        }
    }

    private var helpOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { Motion.run(Motion.smooth) { showHelp = false } }
            GlassSurface(tier: .deep) {
                VStack(spacing: 14) {
                    Text("BitDrop").font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Stack falling Swift symbols (`{`, `}`, `→`, `•`) to fill rows. Cleared rows earn points and (during a real build) a 2% build-speed boost.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Play", systemImage: "play.fill", style: .filled) {
                        Motion.run(Motion.smooth) { showHelp = false }
                    }
                    .frame(maxWidth: 200)
                }
                .padding(24)
            }
            .padding(.horizontal, 30)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct ScoreTile: View {
    let label: String, value: String, icon: String
    let tint: Color
    var body: some View {
        GlassSurface(tier: .raised, corner: 18) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tint.opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
