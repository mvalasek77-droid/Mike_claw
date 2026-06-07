#if os(watchOS)
import SwiftUI

extension RGBA { var color: Color { Color(red: r, green: g, blue: b, opacity: a) } }

/// Top-level router.
struct RootView: View {
    @StateObject private var flow = GameFlow()

    var body: some View {
        Group {
            switch flow.screen {
            case .title:         TitleView(flow: flow)
            case .menu:          MainMenuView(flow: flow)
            case .select:        CharacterSelectView(flow: flow)
            case .trainingSetup: TrainingSetupView(flow: flow)
            case .versusLobby:   VersusLobbyView(flow: flow)
            case .storyCard:     StoryCardView(flow: flow)
            case .fight:         fightContent.id(flow.fightToken)
            case .ending:        EndingView(flow: flow)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: flow.screen)
    }

    @ViewBuilder private var fightContent: some View {
        switch flow.appMode {
        case .story:
            FightView(playerSpec: flow.playerSpec, opponentSpec: flow.opponentSpec,
                      stage: flow.stageSpec, mode: .story(flow.storyDifficulty),
                      onResult: { flow.matchEnded(winner: $0) })
        case .training:
            let opp = CharacterSpec.bastion
            FightView(playerSpec: flow.playerSpec, opponentSpec: opp,
                      stage: StageLibrary.stage(id: opp.homeStageID),
                      mode: .training(flow.trainingOptions),
                      onResult: { flow.matchEnded(winner: $0) })
        case .versus:
            if let t = flow.versusTransport {
                FightView(playerSpec: flow.versusPlayer, opponentSpec: flow.versusOpponent,
                          stage: StageLibrary.stage(id: flow.versusOpponent.homeStageID),
                          mode: .versus(localSide: flow.versusLocalSide, transport: t),
                          onResult: { flow.matchEnded(winner: $0) })
            } else {
                Color.black.onAppear { flow.backToTitle() }
            }
        }
    }
}

struct TitleView: View {
    @ObservedObject var flow: GameFlow
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.25, green: 0.02, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 6) {
                Text("WATCHFIGHTER").font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("ASCENDANT").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.55)).tracking(4)
                Button(action: { flow.goToMenu() }) {
                    Text("START").font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity)
                }
                .tint(Color(red: 0.9, green: 0.1, blue: 0.4)).padding(.top, 6)
            }
            .padding(.horizontal, 10)
        }
    }
}

struct MainMenuView: View {
    @ObservedObject var flow: GameFlow
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("MODE").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                menuButton("STORY", color: Color(red: 0.9, green: 0.1, blue: 0.4)) { flow.chooseMode(.story) }
                menuButton("TRAINING", color: .blue) { flow.chooseMode(.training) }
                menuButton("VERSUS", color: .green) { flow.chooseMode(.versus) }
                Text("Versus = two Watches over Game Center (experimental)")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
            }.padding(.vertical, 8)
        }.background(Color.black.ignoresSafeArea())
    }
    private func menuButton(_ t: String, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity)
        }.tint(color).padding(.horizontal, 12)
    }
}

struct CharacterSelectView: View {
    @ObservedObject var flow: GameFlow
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        ScrollView {
            Text("CHOOSE YOUR FIGHTER").font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary).padding(.vertical, 4)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(CharacterSpec.selectable, id: \.id) { spec in
                    Button(action: { flow.selectCharacter(spec) }) {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 6).fill(spec.bodyColor.color)
                                .frame(height: 38)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(spec.accentColor.color, lineWidth: 2))
                            Text(spec.name).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 6)
        }.background(Color.black.ignoresSafeArea())
    }
}

struct TrainingSetupView: View {
    @ObservedObject var flow: GameFlow
    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                Text("TRAINING").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                Text("Dummy: \(flow.trainingOptions.dummyBehavior.rawValue)")
                    .font(.system(size: 10)).foregroundStyle(.cyan)
                Button("Cycle Dummy") { cycleDummy() }.font(.system(size: 10)).tint(.blue)
                Toggle("Infinite Health", isOn: $flow.trainingOptions.infiniteHealth)
                    .font(.system(size: 10))
                Toggle("Infinite Meter", isOn: $flow.trainingOptions.infinitePlayerMeter)
                    .font(.system(size: 10))
                Toggle("Frame Data", isOn: $flow.trainingOptions.showFrameData)
                    .font(.system(size: 10))
                Button(action: { flow.beginFight() }) {
                    Text("START").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity)
                }.tint(.green)
                Button(action: { flow.goToMenu() }) {
                    Text("BACK").font(.system(size: 10)).frame(maxWidth: .infinity)
                }.tint(.gray)
            }.padding(8)
        }.background(Color.black.ignoresSafeArea())
    }
    private func cycleDummy() {
        let all = DummyBehavior.allCases
        let i = all.firstIndex(of: flow.trainingOptions.dummyBehavior) ?? 0
        flow.trainingOptions.dummyBehavior = all[(i + 1) % all.count]
    }
}

struct VersusLobbyView: View {
    @ObservedObject var flow: GameFlow
    @State private var transport: GameKitTransport?
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("VERSUS").font(.system(size: 14, weight: .heavy)).foregroundStyle(.green)
                Text("\(flow.versusPlayer.name)  vs  \(flow.versusOpponent.name)")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Text(flow.versusStatus).font(.system(size: 10)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
                Button(action: { search() }) {
                    Text("SEARCH").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity)
                }.tint(.green)
                Button(action: { transport?.disconnect(); flow.goToMenu() }) {
                    Text("BACK").font(.system(size: 10)).frame(maxWidth: .infinity)
                }.tint(.gray)
            }.padding(8)
        }.background(Color.black.ignoresSafeArea())
    }

    private func search() {
        let t = GameKitTransport()
        transport = t
        flow.versusStatus = "Connecting to Game Center…"
        t.onError = { msg in DispatchQueue.main.async { flow.versusStatus = msg } }
        t.onConnected = { side in
            DispatchQueue.main.async {
                flow.versusLocalSide = side
                flow.versusTransport = t
                flow.beginFight()
            }
        }
        t.authenticate { ok in
            DispatchQueue.main.async {
                if ok { flow.versusStatus = "Searching for an opponent…"; t.findMatch() }
                else  { flow.versusStatus = "Game Center sign-in required" }
            }
        }
    }
}

struct StoryCardView: View {
    @ObservedObject var flow: GameFlow
    var body: some View {
        let pre = flow.cardKind == .preFight
        let opp = flow.opponentSpec
        let speaker = pre ? opp : flow.playerSpec
        let line = pre ? flow.story.currentBeat.preFight : flow.story.currentBeat.postWin
        return ScrollView {
            VStack(spacing: 7) {
                if pre {
                    Text("FLOOR \(flow.story.progress)").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    portrait(flow.playerSpec)
                    Text("VS").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    portrait(opp)
                }
                Text(speaker.name).font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(speaker.accentColor.color)
                Text(speaker.title).font(.system(size: 8)).foregroundStyle(.secondary)
                Text("“\(line)”").font(.system(size: 10)).italic().foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
                Button(action: { pre ? flow.beginFight() : flow.continueStory() }) {
                    Text(pre ? "FIGHT" : "CONTINUE").font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(pre ? Color(red: 0.9, green: 0.1, blue: 0.4) : .blue).padding(.horizontal, 14)
            }.padding(.vertical, 8)
        }
        .background(LinearGradient(colors: [.black, opp.bodyColor.color.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
    private func portrait(_ spec: CharacterSpec) -> some View {
        RoundedRectangle(cornerRadius: 5).fill(spec.bodyColor.color)
            .frame(width: 34, height: 44)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(spec.accentColor.color, lineWidth: 2))
    }
}

struct EndingView: View {
    @ObservedObject var flow: GameFlow
    var body: some View {
        let win = flow.endKind == .victory
        return ZStack {
            LinearGradient(colors: [.black, win ? Color(red: 0.1, green: 0.2, blue: 0.1)
                                                 : Color(red: 0.2, green: 0.05, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 8) {
                    Text(win ? "ASCENDANT" : "DEFEATED")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(win ? Color(red: 0.4, green: 1, blue: 0.6) : .red)
                    Text(win ? "You kept the gate — and left it open for the next climber."
                             : "The tower keeps what it takes. Climb again.")
                        .font(.system(size: 10)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).padding(.horizontal, 10)
                    if !win && flow.appMode == .story {
                        Button(action: { flow.beginFight() }) {
                            Text("RETRY").font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity)
                        }.tint(.blue).padding(.horizontal, 14)
                    }
                    Button(action: { flow.backToTitle() }) {
                        Text("TITLE").font(.system(size: 11)).frame(maxWidth: .infinity)
                    }.tint(.gray).padding(.horizontal, 14)
                }.padding(.vertical, 10)
            }
        }
    }
}
#endif
