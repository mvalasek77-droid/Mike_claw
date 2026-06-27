import Foundation
import AVFoundation
import SwiftUI
import WatchKit

struct GameScreen: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var engine = WatchfighterEngine()
    @State private var screenMode: GameScreenMode = .mainMenu
    @State private var activeMode: FightMode = .tournament
    @State private var selectedRosterIndex = 0
    @State private var selectedLearnDrill: LearnDrill = .movement
    @State private var completedLearnDrills: Set<LearnDrill> = []
    @State private var lastFrameDate: Date?
    @State private var crownX: Double = 0.25
    @State private var touchX: CGFloat = 0.25
    @State private var touchY: CGFloat = 0.5
    @State private var isPressing = false
    @State private var pendingDashStrike = false
    @State private var nextDemoSpecial: TimeInterval = 2.4
    @State private var voiceText = ""
    @State private var voiceTimer: TimeInterval = 0
    @State private var lastSpokenBanner = ""
    @State private var cutscenePanels: [CutscenePanel] = []
    @State private var cutsceneIndex = 0
    @State private var cutsceneToFight = false
    @State private var pitPending = false   // a loss happened; show the Pit beat at the next round start
    @State private var seenChapters: Set<StoryChapter> = []   // per-floor beats play once
    @State private var arcadeAudio = ArcadeAudio()
    @AppStorage("watchfighter.bestScore") private var bestScore = 0
    @AppStorage("watchfighter.unlockedRosterIndex") private var unlockedRosterIndex = 0
    @FocusState private var crownFocused: Bool

    private let demoMode = ProcessInfo.processInfo.environment["WATCHFIGHTER_DEMO"] == "1"
    private let frameTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                    WatchfighterCanvas(state: engine.state, date: timeline.date)
                        .ignoresSafeArea()
                }

                if screenMode == .fighting || screenMode == .pause {
                    hud
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(.horizontal, 5)
                        .padding(.top, 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                }

                if engine.state.bannerTimer > 0, engine.state.phase == .running, screenMode == .fighting {
                    storyBanner
                        .allowsHitTesting(false)
                        .padding(.horizontal, 10)
                }

                if engine.state.combo > 1, engine.state.phase == .running, screenMode == .fighting {
                    comboBadge
                        .allowsHitTesting(false)
                        .padding(.trailing, 8)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                if voiceTimer > 0 {
                    voiceBadge
                        .allowsHitTesting(false)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                if screenMode == .fighting, activeMode == .learn, engine.state.phase == .running {
                    learnCoachOverlay
                        .allowsHitTesting(false)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }

                if screenMode == .fighting, engine.state.phase == .running {
                    fightMenuButton
                        .padding(.leading, 8)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }

                if screenMode == .mainMenu {
                    mainMenuOverlay
                }

                if screenMode == .versusSelect {
                    versusSelectOverlay
                }

                if screenMode == .learnSelect {
                    learnSelectOverlay
                }

                if screenMode == .fighterCard {
                    fighterCardOverlay
                }

                if screenMode == .cutscene {
                    CutsceneOverlay(panels: cutscenePanels, index: cutsceneIndex) {
                        advanceCutscene()
                    }
                }

                if screenMode == .pause {
                    pauseOverlay
                }

                if engine.state.phase == .gameOver {
                    gameOverOverlay
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(size: proxy.size))
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                pendingDashStrike = true
                playHaptic(.directionUp)
            })
            .focusable(true)
            .focused($crownFocused)
            .digitalCrownRotation(
                $crownX,
                from: 0.14,
                through: 0.56,
                by: 0.01,
                sensitivity: .high,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onAppear {
                crownX = Double(engine.state.player.x)
                touchX = engine.state.player.x
                crownFocused = true
                arcadeAudio.startMusic()
                if demoMode {
                    startTournament(skipCard: true)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    lastFrameDate = nil
                    isPressing = false
                } else {
                    crownFocused = true
                }
            }
            .onReceive(frameTimer) { date in
                advance(to: date)
            }
        }
    }

    private var hud: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 5) {
                fighterPanel(engine.state.player, side: .player)

                VStack(spacing: 2) {
                    Text("\(Int(ceil(engine.state.roundTimer)))")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Color.watchfighterGold)
                        .monospacedDigit()
                        .frame(width: 29)

                    Text("R\(engine.state.round)")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }

                fighterPanel(engine.state.opponent, side: .opponent)
            }

            HStack(spacing: 6) {
                meter(value: engine.state.player.meter, color: .watchfighterMint, width: 42)
                winPips(playerWins: engine.state.playerWins, opponentWins: engine.state.opponentWins)
                meter(value: engine.state.opponent.meter, color: .watchfighterRed, width: 42)
            }
        }
        .shadow(color: .black.opacity(0.85), radius: 4, y: 2)
    }

    private var fightMenuButton: some View {
        Button {
            screenMode = .pause
            lastFrameDate = nil
            playHaptic(.click)
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 31, height: 31)
                .background(.black.opacity(0.62), in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.watchfighterGold.opacity(0.46), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Fight Menu")
    }

    private var mainMenuOverlay: some View {
        VStack(spacing: 8) {
            Text("WATCHFIGHTER")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterGold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("BEST \(bestScore)")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .monospacedDigit()

            Button {
                startTournament(skipCard: false)
            } label: {
                Label("TOURNEY", systemImage: "trophy.fill")
                    .font(.system(size: 12, weight: .black, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.watchfighterRed)

            Button {
                openVersusSelect()
            } label: {
                Label("VS", systemImage: "person.2.fill")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .buttonStyle(.bordered)

            Button {
                openLearnSelect()
            } label: {
                Label("LEARN", systemImage: "scope")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.watchfighterGold.opacity(0.55), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var versusSelectOverlay: some View {
        let roster = FighterArchetype.versusRoster
        let index = selectedRosterIndex.clamped(to: 0...(roster.count - 1))
        let rival = roster[index]
        let locked = index > normalizedUnlockedRosterIndex

        return VStack(spacing: 7) {
            Text("VS MODE")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterGold)

            Text("OPEN \(normalizedUnlockedRosterIndex + 1)/\(roster.count)")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .monospacedDigit()

            HStack(spacing: 7) {
                Button {
                    shiftRosterSelection(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 25, height: 30)
                }
                .buttonStyle(.bordered)

                VStack(spacing: 3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(styleColor(for: rival).opacity(locked ? 0.10 : 0.30))

                        VStack(spacing: 2) {
                            Image(systemName: locked ? "lock.fill" : "bolt.fill")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(locked ? .white.opacity(0.68) : styleColor(for: rival))

                            Text(rival.displayName)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(locked ? .white.opacity(0.58) : .white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)

                            Text(rival.combatStyle.label)
                                .font(.system(size: 6, weight: .black, design: .rounded))
                                .foregroundStyle(styleColor(for: rival))
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 78, height: 66)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(styleColor(for: rival).opacity(locked ? 0.35 : 0.78), lineWidth: 1)
                    )

                    Text(locked ? unlockHint(forRosterIndex: index) : rival.signatureMove)
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(locked ? .white.opacity(0.62) : Color.watchfighterMint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }

                Button {
                    shiftRosterSelection(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 25, height: 30)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button {
                    returnToMainMenu()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.bordered)

                Button {
                    startVersus()
                } label: {
                    Label(locked ? "LOCKED" : "FIGHT", systemImage: locked ? "lock.fill" : "flame.fill")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .tint(locked ? .gray : Color.watchfighterRed)
                .disabled(locked)
            }
        }
        .padding(10)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.watchfighterMint.opacity(0.54), lineWidth: 1)
        )
        .padding(.horizontal, 10)
    }

    private var learnSelectOverlay: some View {
        let drill = selectedLearnDrill

        return VStack(spacing: 7) {
            Text("LEARN")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterGold)

            HStack(spacing: 7) {
                Button {
                    shiftLearnDrill(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 25, height: 30)
                }
                .buttonStyle(.bordered)

                VStack(spacing: 3) {
                    Image(systemName: drill.symbolName)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Color.watchfighterMint)
                        .frame(width: 50, height: 34)

                    Text(drill.title)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(drill.shortPrompt)
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                        .minimumScaleFactor(0.70)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 86, height: 78)

                Button {
                    shiftLearnDrill(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 25, height: 30)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button {
                    returnToMainMenu()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.bordered)

                Button {
                    startLearn()
                } label: {
                    Label("START", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.watchfighterMint)
            }
        }
        .padding(10)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.watchfighterGold.opacity(0.52), lineWidth: 1)
        )
        .padding(.horizontal, 10)
    }

    private var fighterCardOverlay: some View {
        let rival = engine.state.opponent.archetype

        return VStack(spacing: 6) {
            Text(engine.state.chapter.title)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterGold)
                .lineLimit(1)

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(styleColor(for: rival).opacity(0.24))
                    Text(String(rival.displayName.prefix(2)))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 62)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(styleColor(for: rival).opacity(0.75), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(rival.displayName)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(rival.subtitle.uppercased())
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(styleColor(for: rival))
                        .lineLimit(1)
                    Text(rival.techniqueName.uppercased())
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(Color.watchfighterGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(rival.storyBlurb)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(rival.techniqueSummary)
                .font(.system(size: 7, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            HStack(spacing: 8) {
                Button {
                    returnToMainMenu()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.bordered)

                Button {
                    beginFight()
                } label: {
                    Label("FIGHT", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.watchfighterRed)
            }
        }
        .padding(10)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(styleColor(for: rival).opacity(0.75), lineWidth: 1.2)
        )
        .padding(.horizontal, 10)
    }

    private var pauseOverlay: some View {
        VStack(spacing: 8) {
            Text("FIGHT MENU")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterGold)

            HStack(spacing: 8) {
                Button {
                    beginFight()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    restartCurrentMode()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.bordered)

                Button {
                    returnToMainMenu()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.watchfighterMint.opacity(0.52), lineWidth: 1)
        )
    }

    private func fighterPanel(_ fighter: DuelFighter, side: FighterSide) -> some View {
        VStack(alignment: side == .player ? .leading : .trailing, spacing: 2) {
            HStack(spacing: 3) {
                if side == .opponent {
                    Text(fighter.archetype.displayName)
                }

                Text(side == .player ? fighter.archetype.displayName : "")
                    .opacity(side == .player ? 1 : 0)
            }
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            healthBar(
                value: CGFloat(fighter.health) / CGFloat(max(1, fighter.maxHealth)),
                color: side == .player ? .watchfighterGold : .watchfighterRed,
                width: 55,
                trailing: side == .opponent
            )

            guardBar(
                value: fighter.guardMeter,
                width: 55,
                trailing: side == .opponent
            )

            Text(fighter.archetype.subtitle.uppercased())
                .font(.system(size: 6, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: side == .player ? .leading : .trailing)
    }

    private func winPips(playerWins: Int, opponentWins: Int) -> some View {
        HStack(spacing: 3) {
            Text("\(playerWins)/\(StoryChapter.allCases.count)")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterGold)
                .monospacedDigit()

            Text("VS")
                .font(.system(size: 6, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(index < opponentWins ? Color.watchfighterRed : .white.opacity(0.20))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 55)
    }

    private var storyBanner: some View {
        VStack(spacing: 2) {
            Text(engine.state.bannerText)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.66)

            Text(engine.state.bannerDetail)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Color.watchfighterGold)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.watchfighterGold.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.82), radius: 8, y: 4)
    }

    private var comboBadge: some View {
        VStack(spacing: 0) {
            Text("\(engine.state.combo)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterMint)
                .monospacedDigit()

            Text("COMBO")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.watchfighterMint.opacity(0.5), lineWidth: 1)
        )
    }

    private var voiceBadge: some View {
        Text(voiceText)
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(Color.watchfighterGold)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.watchfighterRed.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.9), radius: 7, y: 3)
    }

    private var learnCoachOverlay: some View {
        HStack(spacing: 6) {
            Image(systemName: selectedLearnDrill.symbolName)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Color.watchfighterMint)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedLearnDrill.title)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Color.watchfighterGold)
                    .lineLimit(1)

                Text(selectedLearnDrill.fightPrompt)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
        }
        .padding(.leading, 44)
        .padding(.trailing, 7)
        .padding(.vertical, 5)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.watchfighterMint.opacity(0.42), lineWidth: 1)
        )
    }

    private var gameOverOverlay: some View {
        VStack(spacing: 8) {
            Text(engine.state.winnerText)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(engine.state.playerWins == StoryChapter.allCases.count ? Color.watchfighterGold : .white)
                .lineLimit(1)

            Text("\(engine.state.score)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterGold)
                .monospacedDigit()

            Text("BEST \(max(bestScore, engine.state.score))")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .monospacedDigit()
                .lineLimit(1)

            Text("MAX \(engine.state.maxCombo) HIT")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(Color.watchfighterMint)
                .lineLimit(1)

            Button {
                restartCurrentMode()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .heavy))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .accessibilityLabel("Retry")

            Button {
                returnToMainMenu()
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 13, weight: .black))
                    .frame(width: 30, height: 26)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Main Menu")
        }
        .padding(12)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.watchfighterGold.opacity(0.44), lineWidth: 1)
        )
    }

    private func healthBar(value: CGFloat, color: Color, width: CGFloat, trailing: Bool) -> some View {
        ZStack(alignment: trailing ? .trailing : .leading) {
            Capsule()
                .fill(.white.opacity(0.15))
            Capsule()
                .fill(color)
                .frame(width: max(3, width * value.clamped(to: 0...1)))
        }
        .frame(width: width, height: 6)
    }

    private func guardBar(value: CGFloat, width: CGFloat, trailing: Bool) -> some View {
        let guardValue = value.clamped(to: 0...1)
        let barWidth = max(20, width - 10)
        let guardColor = guardValue < 0.24 ? Color.watchfighterRed : Color.watchfighterMint

        return HStack(spacing: 2) {
            if !trailing {
                Image(systemName: "shield.fill")
                    .font(.system(size: 5, weight: .black))
                    .foregroundStyle(guardColor.opacity(0.92))
            }

            ZStack(alignment: trailing ? .trailing : .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                Capsule()
                    .fill(guardColor.opacity(0.86))
                    .frame(width: max(2, barWidth * guardValue))
            }
            .frame(width: barWidth, height: 3)

            if trailing {
                Image(systemName: "shield.fill")
                    .font(.system(size: 5, weight: .black))
                    .foregroundStyle(guardColor.opacity(0.92))
            }
        }
        .frame(width: width, alignment: trailing ? .trailing : .leading)
        .accessibilityLabel("Guard")
        .accessibilityValue("\(Int((guardValue * 100).rounded())) percent")
    }

    private func meter(value: CGFloat, color: Color, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.14))
            Capsule()
                .fill(color)
                .frame(width: max(3, width * value.clamped(to: 0...1)))
        }
        .frame(width: width, height: 4)
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let usableWidth = max(size.width, 1)
                let usableHeight = max(size.height, 1)
                let nextX = (value.location.x / usableWidth).clamped(to: 0.14...0.56)
                touchX = nextX
                touchY = (value.location.y / usableHeight).clamped(to: 0...1)
                crownX = Double(nextX)
                isPressing = true
            }
            .onEnded { _ in
                isPressing = false
                touchY = 0.5
            }
    }

    private func advance(to date: Date) {
        guard screenMode == .fighting else {
            let previousDate = lastFrameDate ?? date
            let delta = max(0, date.timeIntervalSince(previousDate))
            lastFrameDate = date
            voiceTimer = max(0, voiceTimer - delta)
            return
        }

        guard scenePhase == .active else {
            lastFrameDate = date
            return
        }

        let previousDate = lastFrameDate ?? date
        lastFrameDate = date

        let delta = date.timeIntervalSince(previousDate)
        guard delta > 0 else { return }

        if demoMode, engine.state.phase == .gameOver {
            activeMode = .tournament
            engine.reset(seed: 0xD1F1_71E)
            crownX = Double(engine.state.player.x)
            touchX = engine.state.player.x
            nextDemoSpecial = 2.4
        }

        let beforePlayerHealth = engine.state.player.health
        let beforeOpponentHealth = engine.state.opponent.health
        let beforeScore = engine.state.score
        let beforeCombo = engine.state.combo
        let beforeBanner = engine.state.bannerText
        let beforePhase = engine.state.phase
        let beforeRound = engine.state.round
        let beforeChapter = engine.state.chapter
        let beforePlayerWins = engine.state.playerWins
        let beforeOpponentWins = engine.state.opponentWins

        let spacingTarget = (engine.state.opponent.x - 0.25 + CGFloat(sin(engine.state.elapsed * 1.6)) * 0.035).clamped(to: 0.16...0.52)
        let targetX = isPressing ? touchX : (demoMode ? spacingTarget : CGFloat(crownX))
        let demoSpecial = demoMode && engine.state.player.meter >= 1 && engine.state.elapsed >= nextDemoSpecial
        let chargedDash = pendingDashStrike && engine.state.player.meter >= 1
        let didDashStrike = pendingDashStrike
        if demoSpecial {
            nextDemoSpecial = engine.state.elapsed + 3.8
        }

        let closeThreat = abs(engine.state.opponent.x - engine.state.player.x) < 0.31
        let wantsJumpKick = isPressing && touchY < 0.34
        let wantsCrouch = isPressing && touchY > 0.70
        let wantsThrow = isPressing && closeThreat && touchY >= 0.42 && touchY <= 0.60
        engine.tick(
            delta: delta,
            input: GameInput(
                targetX: targetX,
                attacking: (isPressing && !wantsJumpKick && !wantsCrouch && !wantsThrow) || demoMode,
                special: chargedDash || demoSpecial,
                dashStrike: pendingDashStrike && !chargedDash,
                jump: wantsJumpKick,
                crouching: wantsCrouch,
                throwing: wantsThrow,
                blocking: !isPressing && !demoMode && closeThreat
            )
        )
        pendingDashStrike = false
        voiceTimer = max(0, voiceTimer - delta)
        if engine.state.score > bestScore {
            bestScore = engine.state.score
        }

        if activeMode == .tournament, engine.state.playerWins > beforePlayerWins {
            unlockTournamentRoster(playerWins: engine.state.playerWins)
        }

        if activeMode == .learn {
            advanceLearnDrillIfNeeded(
                beforePlayerHealth: beforePlayerHealth,
                beforeOpponentHealth: beforeOpponentHealth,
                beforeCombo: beforeCombo,
                didDashStrike: didDashStrike
            )
        }

        // A loss registers now (round-resolve frame); the round actually restarts
        // ~2.25s later after the pause, so remember it until then.
        if activeMode == .tournament, engine.state.opponentWins > beforeOpponentWins {
            pitPending = true
        }

        if activeMode == .tournament, !demoMode, engine.state.phase == .running, (engine.state.round != beforeRound || engine.state.chapter != beforeChapter) {
            lastFrameDate = nil
            // FF story beats bridge into the next fight (good arcade cadence:
            // only on a loss, the midpoint, and the final boss — not every fight).
            if pitPending {
                pitPending = false
                playCutscene(FFScript.pit, toFight: false)              // lost a floor -> the Pit, climb back
            } else if engine.state.chapter == StoryChapter.allCases.last {
                playCutscene(FFScript.beforeBoss, toFight: false)        // final boss, every time
            } else if !seenChapters.contains(engine.state.chapter),
                      let beat = FFScript.chapter(engine.state.chapter) {
                seenChapters.insert(engine.state.chapter)               // floor beat, once
                playCutscene(beat, toFight: false)
            } else {
                screenMode = .fighterCard
                announce("NEXT FIGHT")
            }
            return
        }

        if engine.state.bannerText != beforeBanner || engine.state.bannerTimer > 0, engine.state.bannerText != lastSpokenBanner {
            announce(engine.state.bannerText)
        } else if engine.state.combo > beforeCombo, engine.state.combo == 3 || engine.state.combo == 5 || engine.state.combo == 8 {
            announce("COMBO")
        } else if beforePhase == .running, engine.state.phase == .gameOver {
            let playerWon = engine.state.winnerText == "VICTORY" || engine.state.winnerText.contains("WIN") || engine.state.winnerText == "TRAINED"
            announce(playerWon ? "KNOCKOUT" : "DEFEAT")
        }

        if engine.state.player.health < beforePlayerHealth {
            playHaptic(engine.state.phase == .gameOver ? .failure : .retry)
        } else if engine.state.opponent.health < beforeOpponentHealth || engine.state.score > beforeScore {
            playHaptic(.click)
        }
    }

    private func playHaptic(_ haptic: WKHapticType) {
        WKInterfaceDevice.current().play(haptic)
    }

    private func announce(_ text: String) {
        let normalized = text.uppercased()
        voiceText = normalized
        voiceTimer = 0.9
        lastSpokenBanner = normalized
        arcadeAudio.play(cue: ArcadeCue(text: normalized))
    }

    private var normalizedUnlockedRosterIndex: Int {
        let maxIndex = max(0, FighterArchetype.versusRoster.count - 1)
        return unlockedRosterIndex.clamped(to: 0...maxIndex)
    }

    private func openVersusSelect() {
        activeMode = .versus
        selectedRosterIndex = selectedRosterIndex.clamped(to: 0...(FighterArchetype.versusRoster.count - 1))
        lastFrameDate = nil
        screenMode = .versusSelect
        playHaptic(.click)
    }

    private func openLearnSelect() {
        activeMode = .learn
        lastFrameDate = nil
        screenMode = .learnSelect
        playHaptic(.click)
    }

    private func playCutscene(_ panels: [CutscenePanel], toFight: Bool) {
        cutscenePanels = panels
        cutsceneIndex = 0
        cutsceneToFight = toFight
        lastFrameDate = nil
        screenMode = .cutscene
    }

    private func advanceCutscene() {
        if cutsceneIndex + 1 < cutscenePanels.count {
            cutsceneIndex += 1
            playHaptic(.click)
        } else if cutsceneToFight {
            beginFight()
        } else {
            screenMode = .fighterCard
            announce("READY")
            playHaptic(.start)
        }
    }

    private func startTournament(skipCard: Bool) {
        activeMode = .tournament
        engine.reset()
        resetInputTracking()
        arcadeAudio.startMusic()
        playHaptic(.start)
        playCutscene(FFScript.intro, toFight: skipCard)   // FF intro, then the first fight
    }

    private func startVersus() {
        let roster = FighterArchetype.versusRoster
        let index = selectedRosterIndex.clamped(to: 0...(roster.count - 1))
        guard index <= normalizedUnlockedRosterIndex else {
            playHaptic(.failure)
            return
        }

        selectedRosterIndex = index
        activeMode = .versus
        engine.resetVersus(opponent: roster[index], chapter: StoryChapter.chapter(for: index + 1))
        resetInputTracking()
        screenMode = .fighting
        arcadeAudio.startMusic()
        announce("FIGHT")
        playHaptic(.start)
    }

    private func startLearn() {
        activeMode = .learn
        engine.resetLearn()
        resetInputTracking()
        completedLearnDrills = Set(LearnDrill.allCases.filter { $0.rawValue < selectedLearnDrill.rawValue })
        screenMode = .fighting
        arcadeAudio.startMusic()
        announce(selectedLearnDrill.callout)
        playHaptic(.start)
    }

    private func restartCurrentMode() {
        switch activeMode {
        case .tournament:
            startTournament(skipCard: false)
        case .versus:
            startVersus()
        case .learn:
            startLearn()
        }
    }

    private func beginFight() {
        lastFrameDate = nil
        isPressing = false
        crownFocused = true
        screenMode = .fighting
        announce("FIGHT")
        playHaptic(.start)
    }

    private func returnToMainMenu() {
        activeMode = .tournament
        engine.reset()
        resetInputTracking()
        screenMode = .mainMenu
        playHaptic(.stop)
    }

    private func resetInputTracking() {
        crownX = Double(engine.state.player.x)
        touchX = engine.state.player.x
        touchY = 0.5
        isPressing = false
        pendingDashStrike = false
        lastFrameDate = nil
        nextDemoSpecial = 2.4
        lastSpokenBanner = ""
        pitPending = false
        seenChapters.removeAll()
    }

    private func shiftRosterSelection(_ offset: Int) {
        let roster = FighterArchetype.versusRoster
        selectedRosterIndex = (selectedRosterIndex + offset + roster.count) % roster.count
        playHaptic(.click)
    }

    private func shiftLearnDrill(_ offset: Int) {
        let drills = LearnDrill.allCases
        guard let currentIndex = drills.firstIndex(of: selectedLearnDrill) else { return }
        selectedLearnDrill = drills[(currentIndex + offset + drills.count) % drills.count]
        playHaptic(.click)
    }

    private func unlockTournamentRoster(playerWins: Int) {
        let earnedIndex = min(FighterArchetype.versusRoster.count - 1, max(0, playerWins))
        if earnedIndex > unlockedRosterIndex {
            unlockedRosterIndex = earnedIndex
        }
    }

    private func unlockHint(forRosterIndex index: Int) -> String {
        guard index > 0 else { return "READY" }
        return "BEAT \(StoryChapter.chapter(for: index).arenaTag)"
    }

    private func advanceLearnDrillIfNeeded(beforePlayerHealth: Int, beforeOpponentHealth: Int, beforeCombo: Int, didDashStrike: Bool) {
        guard !completedLearnDrills.contains(selectedLearnDrill) else { return }
        guard selectedLearnDrill.isComplete(
            state: engine.state,
            beforePlayerHealth: beforePlayerHealth,
            beforeOpponentHealth: beforeOpponentHealth,
            beforeCombo: beforeCombo,
            didDashStrike: didDashStrike
        ) else {
            return
        }

        completedLearnDrills.insert(selectedLearnDrill)
        if let nextDrill = selectedLearnDrill.next {
            selectedLearnDrill = nextDrill
            announce(nextDrill.callout)
            playHaptic(.directionUp)
        } else {
            announce("TRAINED")
            playHaptic(.success)
        }
    }

    private func styleColor(for archetype: FighterArchetype) -> Color {
        switch archetype.combatStyle {
        case .balanced:
            return .watchfighterGold
        case .rushdown:
            return .watchfighterRed
        case .grappler:
            return Color(red: 0.70, green: 0.92, blue: 1.0)
        case .zoner:
            return .watchfighterMint
        case .acrobat:
            return Color(red: 1.0, green: 0.42, blue: 0.82)
        case .bruiser:
            return Color(red: 1.0, green: 0.58, blue: 0.24)
        case .titan:
            return Color(red: 1.0, green: 0.18, blue: 0.20)
        }
    }
}

private enum GameScreenMode {
    case mainMenu
    case versusSelect
    case learnSelect
    case fighterCard
    case fighting
    case pause
    case cutscene
}

private enum FightMode {
    case tournament
    case versus
    case learn
}

private enum LearnDrill: Int, CaseIterable, Hashable {
    case movement
    case strike
    case defense
    case dash
    case special

    var title: String {
        switch self {
        case .movement:
            return "FOOTWORK"
        case .strike:
            return "STRIKE"
        case .defense:
            return "GUARD"
        case .dash:
            return "DASH"
        case .special:
            return "METER"
        }
    }

    var symbolName: String {
        switch self {
        case .movement:
            return "arrow.left.and.right"
        case .strike:
            return "flame.fill"
        case .defense:
            return "shield.fill"
        case .dash:
            return "bolt.fill"
        case .special:
            return "scope"
        }
    }

    var shortPrompt: String {
        switch self {
        case .movement:
            return "Crown or drag to hold range."
        case .strike:
            return "Press center to chain hits."
        case .defense:
            return "Release near danger or drag low."
        case .dash:
            return "Double tap to burst forward."
        case .special:
            return "Full meter turns dash into power."
        }
    }

    var fightPrompt: String {
        switch self {
        case .movement:
            return "Move off the starting line"
        case .strike:
            return "Land a clean hit"
        case .defense:
            return "Block or crouch under pressure"
        case .dash:
            return "Double tap for dash strike"
        case .special:
            return "Spend full meter"
        }
    }

    var callout: String {
        switch self {
        case .movement:
            return "FOOTWORK"
        case .strike:
            return "STRIKE"
        case .defense:
            return "GUARD"
        case .dash:
            return "DASH"
        case .special:
            return "METER"
        }
    }

    var next: LearnDrill? {
        LearnDrill(rawValue: rawValue + 1)
    }

    func isComplete(state: WatchfighterState, beforePlayerHealth: Int, beforeOpponentHealth: Int, beforeCombo: Int, didDashStrike: Bool) -> Bool {
        switch self {
        case .movement:
            return abs(state.player.x - 0.25) > 0.045
        case .strike:
            return state.opponent.health < beforeOpponentHealth || state.combo > beforeCombo
        case .defense:
            return state.player.action == .blocking || state.player.action == .crouch || (state.player.health < beforePlayerHealth && state.player.guardMeter < 0.92)
        case .dash:
            return didDashStrike || (state.player.action == .kick && state.player.x > 0.34)
        case .special:
            return state.player.action == .special || state.player.action == .projectile
        }
    }
}

private extension CombatStyle {
    var label: String {
        switch self {
        case .balanced:
            return "BAL"
        case .rushdown:
            return "RUSH"
        case .grappler:
            return "GRAB"
        case .zoner:
            return "ZONE"
        case .acrobat:
            return "AIR"
        case .bruiser:
            return "POWER"
        case .titan:
            return "BOSS"
        }
    }
}

private enum ArcadeCue {
    case fight
    case combo
    case finish
    case ko
    case million
    case titan

    init(text: String) {
        if text.contains("MILLION") {
            self = .million
        } else if text.contains("TITAN") {
            self = .titan
        } else if text.contains("COMBO") {
            self = .combo
        } else if text.contains("FINISH") {
            self = .finish
        } else if text.contains("KNOCKOUT") || text.contains("VICTORY") {
            self = .ko
        } else {
            self = .fight
        }
    }

    var fileName: String {
        switch self {
        case .fight:
            return "fight"
        case .combo:
            return "combo"
        case .finish:
            return "finish"
        case .ko:
            return "ko"
        case .million:
            return "million"
        case .titan:
            return "titan"
        }
    }
}

private final class ArcadeAudio {
    private var players: [String: AVAudioPlayer] = [:]
    private var lastPlayedAt = Date.distantPast
    private let music = ArcadeMusic()

    init() {
        for fileName in ["fight", "combo", "finish", "ko", "million", "titan"] {
            guard let url = Self.voiceURL(for: fileName),
                  let player = try? AVAudioPlayer(contentsOf: url) else {
                continue
            }
            player.volume = 0.72
            player.prepareToPlay()
            players[fileName] = player
        }
    }

    private static func voiceURL(for fileName: String) -> URL? {
        Bundle.main.url(forResource: fileName, withExtension: "aiff", subdirectory: "Voice")
            ?? Bundle.main.url(forResource: fileName, withExtension: "aiff")
    }

    func play(cue: ArcadeCue) {
        let now = Date()
        guard now.timeIntervalSince(lastPlayedAt) > 0.45 else { return }
        guard let player = players[cue.fileName] else { return }
        lastPlayedAt = now
        player.currentTime = 0
        player.play()
    }

    func startMusic() {
        music.start()
    }
}

private final class ArcadeMusic {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var sampleIndex = 0.0
    private let sampleRate = 22_050.0
    private let tempo = 176.0
    private let melody = [196.0, 246.94, 293.66, 329.63, 392.0, 329.63, 293.66, 246.94]
    private let bass = [98.0, 98.0, 123.47, 146.83, 98.0, 164.81, 146.83, 123.47]

    func start() {
        guard !engine.isRunning else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let format else { return }

        if source == nil {
            let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self else { return noErr }
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

                for frame in 0..<Int(frameCount) {
                    let beat = self.sampleIndex / self.sampleRate * self.tempo / 60.0
                    let step = Int(beat * 2.0) % self.melody.count
                    let envelope = 1.0 - min(0.82, (beat * 2.0).truncatingRemainder(dividingBy: 1.0) * 1.1)
                    let leadPhase = self.sampleIndex * self.melody[step] / self.sampleRate
                    let bassPhase = self.sampleIndex * self.bass[Int(beat) % self.bass.count] / self.sampleRate
                    let hat = Int(beat * 4.0).isMultiple(of: 2) ? 0.025 : -0.015
                    let lead = sin(leadPhase * 2.0 * .pi) >= 0 ? 0.12 : -0.12
                    let low = sin(bassPhase * 2.0 * .pi) * 0.10
                    let sample = Float((lead * envelope) + low + hat)

                    for buffer in buffers {
                        guard let data = buffer.mData else { continue }
                        data.assumingMemoryBound(to: Float.self)[frame] = sample
                    }

                    self.sampleIndex += 1
                }

                return noErr
            }

            source = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.16
        }

        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - FF-style story cutscenes (original content)

/// One narrative text box. `speaker == nil` means the narrator.
struct CutscenePanel: Equatable {
    let speaker: String?
    let text: String
}

/// Original story copy that bridges into the fights (no real people / no IP).
enum FFScript {
    static let intro: [CutscenePanel] = [
        CutscenePanel(speaker: nil,
                      text: "The hundred-year gate of THE ASCENDANT grinds open. Champions go up the tower. None come back down."),
        CutscenePanel(speaker: nil,
                      text: "The town below stopped mourning long ago. Now it sells tickets and waits for the next fool to climb."),
        CutscenePanel(speaker: "NYRA",
                      text: "Another climber? Cute. The first floor is mine — and I don't do slow."),
        CutscenePanel(speaker: nil,
                      text: "Fifteen floors. Fifteen fighters who already gave everything to the tower. You tighten your wraps and step in."),
    ]

    /// Midpoint act-break (fires around the blackout-base floor).
    static let midpoint: [CutscenePanel] = [
        CutscenePanel(speaker: nil,
                      text: "Halfway up. The fighters here didn't choose the tower — the tower chose them, and never let go."),
        CutscenePanel(speaker: nil,
                      text: "You've started to understand: winning isn't the prize up here. Escaping is. Keep climbing."),
    ]

    /// Fired when you LOSE a floor but the run isn't over — the Pit narrative
    /// beat on the existing second-chance before you fight your way back up.
    static let pit: [CutscenePanel] = [
        CutscenePanel(speaker: nil,
                      text: "The floor drops out. You fall past the tower, past the town, into heat and smoke."),
        CutscenePanel(speaker: "THE PIT",
                      text: "Another one the tower couldn't keep. Crawl back up if you can — but you don't get to fall twice."),
        CutscenePanel(speaker: nil,
                      text: "You drag yourself back onto the floor you lost. One life left. Make it burn."),
    ]

    /// Act-break before the final boss arena.
    static let beforeBoss: [CutscenePanel] = [
        CutscenePanel(speaker: nil,
                      text: "The last door is a square of canvas and two gloves. The air hums like a struck bell that never rang."),
        CutscenePanel(speaker: "TITUS",
                      text: "(He says nothing. He raises his fists. No bell has rung for him in a thousand years.)"),
        CutscenePanel(speaker: nil,
                      text: "Damage alone won't drop him. Land the MILLION SHOT — a SPECIAL on an 8+ combo — or join the wall."),
    ]

    /// A short beat the FIRST time you reach a floor (plays once, not on refights).
    /// Boss (millionRoom) uses `beforeBoss`; floor 1 is covered by `intro`.
    static func chapter(_ chapter: StoryChapter) -> [CutscenePanel]? {
        let line: String?
        switch chapter {
        case .cinderGate, .millionRoom: line = nil
        case .neonRooftop:    line = "Floor two. Neon bleeds across wet rooftops, and something fast is already grinning at you."
        case .stormBridge:    line = "Wind screams across the bridge. The tower likes its champions off-balance."
        case .pirateCove:     line = "Salt, rum, and a captain who laughs at the gate. The tide takes the high ground back, he says."
        case .dragonAlley:    line = "A back-alley dojo of one. The dragon-fist here trains for an audience that never leaves."
        case .sunPier:        line = "Sun, surf, and a rescue brawler who fights like the undertow — fast, and impossible to hold."
        case .runwayTerminal: line = "Half the floor is catwalk, half is war. Strike a pose; the judges hit back."
        case .blackoutBase:   line = "Halfway up. The lights die. The fighters here didn't choose the tower — it chose them."
        case .launchFoundry:  line = "Sparks and steel. Whatever the tower is building up here, it needs champions for fuel."
        case .goldRally:      line = "All chrome and bravado. The loudest fighter yet — and somehow still standing."
        case .icePalace:      line = "The air bites. The ice regent doesn't rush; the cold does the work."
        case .redCarpet:      line = "Flashbulbs and finishers. Up here, losing is a very public thing."
        case .cageNight:      line = "No ropes, no exit. Just the cage, the crowd, and a crusher who never blinks."
        case .obsidianThrone: line = "The throne room. The host is a former climber who won — and never got to leave."
        }
        guard let line else { return nil }
        return [CutscenePanel(speaker: nil, text: line)]
    }
}

/// Self-contained cutscene overlay — speaker, text box, and an advance button.
struct CutsceneOverlay: View {
    let panels: [CutscenePanel]
    let index: Int
    let onAdvance: () -> Void

    var body: some View {
        let panel = panels.isEmpty ? CutscenePanel(speaker: nil, text: "")
                                   : panels[min(index, panels.count - 1)]
        return ZStack {
            LinearGradient(colors: [.black, Color(red: 0.12, green: 0.03, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(panel.speaker ?? "THE ASCENDANT")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color(red: 1, green: 0.32, blue: 0.55))
                    Text(panel.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.22), lineWidth: 1))
                    Button(action: onAdvance) {
                        Text(index + 1 < panels.count ? "NEXT \u{25B6}" : "FIGHT!")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(Color(red: 0.9, green: 0.1, blue: 0.4))
                    Text("\(index + 1) / \(max(1, panels.count))")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(8)
            }
        }
    }
}
