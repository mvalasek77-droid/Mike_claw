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
        let healthValue = value.clamped(to: 0...1)
        let activeColor = healthValue < 0.24 ? Color.watchfighterRed : color

        return ZStack(alignment: trailing ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(.black.opacity(0.82))
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [activeColor.opacity(0.72), activeColor, .white.opacity(0.88)],
                        startPoint: trailing ? .trailing : .leading,
                        endPoint: trailing ? .leading : .trailing
                    )
                )
                .frame(width: max(3, width * healthValue))

            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(.black.opacity(0.35))
                        .frame(width: 0.7)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: width, height: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 0.6)
        )
        .shadow(color: activeColor.opacity(healthValue < 0.24 ? 0.7 : 0.28), radius: healthValue < 0.24 ? 2.5 : 1)
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
        let meterValue = value.clamped(to: 0...1)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.14))
            Capsule()
                .fill(color)
                .frame(width: max(3, width * meterValue))
        }
        .frame(width: width, height: 4)
        .overlay(Capsule().stroke(color.opacity(meterValue >= 0.99 ? 0.92 : 0.22), lineWidth: 0.7))
        .shadow(color: color.opacity(meterValue >= 0.99 ? 0.85 : 0), radius: 3)
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
        let beforeImpactSequence = engine.state.impactSequence

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
        let didImpact = engine.state.impactSequence != beforeImpactSequence
        if didImpact {
            arcadeAudio.playImpact(kind: engine.state.impactKind, strength: engine.state.impactStrength)
        }
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

        if activeMode == .tournament, !demoMode, engine.state.phase == .running, (engine.state.round != beforeRound || engine.state.chapter != beforeChapter) {
            screenMode = .fighterCard
            lastFrameDate = nil
            announce("NEXT FIGHT")
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

        if didImpact, engine.state.impactKind == .whiff {
            // Keep misses airy; a haptic here makes them feel like accidental hits.
        } else if engine.state.player.health < beforePlayerHealth {
            playHaptic(engine.state.phase == .gameOver ? .failure : .retry)
        } else if didImpact, (engine.state.impactKind == .guardBreak || engine.state.impactKind == .counter || engine.state.impactStrength > 0.72) {
            playHaptic(.directionDown)
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

    private func startTournament(skipCard: Bool) {
        activeMode = .tournament
        engine.reset()
        resetInputTracking()
        screenMode = skipCard ? .fighting : .fighterCard
        arcadeAudio.startMusic()
        if skipCard {
            announce("FIGHT")
        } else {
            announce("READY")
        }
        playHaptic(.start)
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

private enum ImpactCue: CaseIterable, Hashable {
    case wind
    case light
    case heavy
    case block
    case counter
    case guardBreak
    case energy
    case throwBody

    init(kind: StrikeKind, strength: CGFloat) {
        switch kind {
        case .whiff:
            self = .wind
        case .blocked:
            self = .block
        case .counter:
            self = .counter
        case .guardBreak:
            self = .guardBreak
        case .special, .projectile, .finisher:
            self = .energy
        case .throwImpact, .headPop, .bodyBurst, .armDrop:
            self = .throwBody
        case .hit, .blood, .round:
            self = strength >= 0.58 ? .heavy : .light
        }
    }
}

private final class ArcadeAudio {
    private var players: [String: AVAudioPlayer] = [:]
    private var lastPlayedAt = Date.distantPast
    private let music = ArcadeMusic()
    private let impacts = ImpactAudio()

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

    func playImpact(kind: StrikeKind, strength: CGFloat) {
        impacts.play(cue: ImpactCue(kind: kind, strength: strength), strength: strength)
    }

    func startMusic() {
        music.start()
        impacts.start()
    }
}

private final class ImpactAudio {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [ImpactCue: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private let sampleRate = 24_000.0

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }

        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            players.append(player)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        for cue in ImpactCue.allCases {
            buffers[cue] = Self.makeBuffer(cue: cue, format: format, sampleRate: sampleRate)
        }
        engine.mainMixerNode.outputVolume = 0.82
    }

    func start() {
        guard !engine.isRunning, !players.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    func play(cue: ImpactCue, strength: CGFloat) {
        start()
        guard !players.isEmpty, let buffer = buffers[cue] else { return }
        let player = players[nextPlayer % players.count]
        nextPlayer += 1
        player.stop()
        player.volume = Float((0.62 + strength * 0.34).clamped(to: 0.55...0.98))
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()
    }

    private static func makeBuffer(cue: ImpactCue, format: AVAudioFormat, sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration: Double
        switch cue {
        case .wind:
            duration = 0.10
        case .light, .block:
            duration = 0.12
        case .heavy, .counter:
            duration = 0.18
        case .guardBreak, .throwBody:
            duration = 0.22
        case .energy:
            duration = 0.28
        }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = frameCount

        var noiseState: UInt32 = 0xA11C_E551 ^ UInt32(cue.hashValue & 0xFFFF)
        var smoothedNoise = 0.0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let progress = min(1, t / duration)
            let attack = min(1, t / 0.0025)
            let release = pow(max(0, 1 - progress), 2.15)
            let envelope = attack * release

            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            let noise = (Double(noiseState >> 8) / Double(0x00FF_FFFF)) * 2 - 1
            smoothedNoise = smoothedNoise * 0.86 + noise * 0.14
            let brightNoise = noise - smoothedNoise

            let sample: Double
            switch cue {
            case .wind:
                let sweep = 780 - progress * 510
                sample = (brightNoise * 0.28 + sin(2 * .pi * sweep * t) * 0.055) * envelope
            case .light:
                let bodyFrequency = 165 - progress * 92
                let body = sin(2 * .pi * bodyFrequency * t) * 0.38
                let glove = brightNoise * 0.52 * exp(-t * 46)
                let snap = sin(2 * .pi * 920 * t) * 0.14 * exp(-t * 58)
                sample = (body + glove + snap) * envelope
            case .heavy:
                let bodyFrequency = 112 - progress * 62
                let body = sin(2 * .pi * bodyFrequency * t) * 0.62
                let chest = sin(2 * .pi * 225 * t) * 0.18
                let crack = brightNoise * 0.48 * exp(-t * 32)
                sample = tanh((body + chest + crack) * 1.35) * envelope
            case .block:
                let metal = sin(2 * .pi * 1_180 * t) * 0.28 + sin(2 * .pi * 1_760 * t) * 0.18
                let clack = brightNoise * 0.42 * exp(-t * 44)
                sample = (metal + clack) * envelope
            case .counter:
                let boom = sin(2 * .pi * (92 - progress * 53) * t) * 0.68
                let ring = sin(2 * .pi * 335 * t) * 0.22
                let crack = brightNoise * 0.58 * exp(-t * 35)
                sample = tanh((boom + ring + crack) * 1.5) * envelope
            case .guardBreak:
                let boom = sin(2 * .pi * (88 - progress * 45) * t) * 0.58
                let shards = sin(2 * .pi * 1_460 * t) * 0.20 + sin(2 * .pi * 2_210 * t) * 0.14
                let crackle = brightNoise * 0.62 * exp(-t * 22)
                sample = tanh((boom + shards + crackle) * 1.38) * envelope
            case .energy:
                let sweep = 540 - progress * 455
                let blast = sin(2 * .pi * sweep * t) * 0.52
                let sub = sin(2 * .pi * (72 - progress * 26) * t) * 0.46
                let edge = brightNoise * 0.38 * exp(-t * 18)
                sample = tanh((blast + sub + edge) * 1.28) * envelope
            case .throwBody:
                let secondHit = exp(-pow((t - 0.058) / 0.012, 2))
                let thump = sin(2 * .pi * (82 - progress * 36) * t) * (0.66 + secondHit * 0.22)
                let crunch = brightNoise * (0.38 * exp(-t * 26) + secondHit * 0.42)
                sample = tanh((thump + crunch) * 1.42) * envelope
            }
            samples[frame] = Float(sample.clamped(to: -0.98...0.98))
        }
        return buffer
    }
}

private final class ArcadeMusic {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var sampleIndex = 0.0
    private let sampleRate = 22_050.0
    private let tempo = 158.0
    private let melody = [196.0, 233.08, 293.66, 349.23, 392.0, 349.23, 293.66, 233.08]
    private let bass = [98.0, 98.0, 116.54, 146.83, 98.0, 174.61, 146.83, 116.54]

    func start() {
        guard !engine.isRunning else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let format else { return }

        if source == nil {
            let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self else { return noErr }
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

                for frame in 0..<Int(frameCount) {
                    let time = self.sampleIndex / self.sampleRate
                    let beat = time * self.tempo / 60.0
                    let step = Int(beat * 2.0) % self.melody.count
                    let eighthPhase = (beat * 2.0).truncatingRemainder(dividingBy: 1.0)
                    let beatPhase = beat.truncatingRemainder(dividingBy: 1.0)
                    let envelope = exp(-eighthPhase * 2.4)
                    let leadPhase = self.sampleIndex * self.melody[step] / self.sampleRate
                    let bassPhase = self.sampleIndex * self.bass[Int(beat) % self.bass.count] / self.sampleRate
                    let pseudoNoise = (sin(self.sampleIndex * 12.9898) * 43_758.5453).truncatingRemainder(dividingBy: 1.0)
                    let kickEnvelope = exp(-beatPhase * 13.0)
                    let kickFrequency = 48.0 + 38.0 * kickEnvelope
                    let kick = sin(time * kickFrequency * 2.0 * .pi) * 0.15 * kickEnvelope
                    let snareBeat = Int(beat).isMultiple(of: 2) ? 0.0 : exp(-beatPhase * 18.0)
                    let snare = pseudoNoise * 0.055 * snareBeat
                    let hatEnvelope = exp(-((beat * 4.0).truncatingRemainder(dividingBy: 1.0)) * 24.0)
                    let hat = pseudoNoise * 0.018 * hatEnvelope
                    let lead = (sin(leadPhase * 2.0 * .pi) + sin(leadPhase * 4.0 * .pi) * 0.28) * 0.078 * envelope
                    let low = sin(bassPhase * 2.0 * .pi) * 0.105
                    let sample = Float(tanh((lead + low + kick + snare + hat) * 1.15))

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
