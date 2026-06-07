#if os(watchOS)
import SwiftUI

extension RGBA { var color: Color { Color(red: r, green: g, blue: b, opacity: a) } }

/// Top-level router. Switches screens based on `GameFlow`.
struct RootView: View {
    @StateObject private var flow = GameFlow()

    var body: some View {
        Group {
            switch flow.screen {
            case .title:     TitleView(flow: flow)
            case .select:    CharacterSelectView(flow: flow)
            case .storyCard: StoryCardView(flow: flow)
            case .fight:
                FightView(playerSpec: flow.playerSpec,
                          opponentSpec: flow.opponentSpec,
                          stage: flow.stageSpec,
                          onResult: { flow.matchEnded(winner: $0) })
                    .id(flow.fightToken)        // fresh scene per fight
            case .ending:    EndingView(flow: flow)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: flow.screen)
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
                    .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.55))
                    .tracking(4)
                Button(action: { flow.goToSelect() }) {
                    Text("START").font(.system(size: 13, weight: .bold)).frame(maxWidth: .infinity)
                }
                .tint(Color(red: 0.9, green: 0.1, blue: 0.4))
                .padding(.top, 6)
            }
            .padding(.horizontal, 10)
        }
    }
}

struct CharacterSelectView: View {
    @ObservedObject var flow: GameFlow
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            Text("CHOOSE YOUR FIGHTER")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                .padding(.vertical, 4)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(CharacterSpec.selectable, id: \.id) { spec in
                    Button(action: { flow.startStory(with: spec) }) {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(spec.bodyColor.color)
                                .frame(height: 38)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(spec.accentColor.color, lineWidth: 2))
                            Text(spec.name).font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
        }
        .background(Color.black.ignoresSafeArea())
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
                    Text("FLOOR \(flow.story.progress)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    portrait(flow.playerSpec)
                    Text("VS").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    portrait(opp)
                }
                Text(speaker.name).font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(speaker.accentColor.color)
                Text(speaker.title).font(.system(size: 8)).foregroundStyle(.secondary)
                Text("“\(line)”").font(.system(size: 10)).italic()
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                Button(action: { pre ? flow.beginFight() : flow.continueStory() }) {
                    Text(pre ? "FIGHT" : "CONTINUE")
                        .font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity)
                }
                .tint(pre ? Color(red: 0.9, green: 0.1, blue: 0.4) : .blue)
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 8)
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
                    Text(win
                         ? "You kept the gate — and left it open for the next climber."
                         : "The tower keeps what it takes. Climb again.")
                        .font(.system(size: 10)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).padding(.horizontal, 10)
                    Button(action: {
                        win ? flow.backToTitle() : flow.beginFight()
                    }) {
                        Text(win ? "TITLE" : "RETRY").font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.blue).padding(.horizontal, 14)
                    if !win {
                        Button(action: { flow.backToTitle() }) {
                            Text("TITLE").font(.system(size: 11)).frame(maxWidth: .infinity)
                        }
                        .tint(.gray).padding(.horizontal, 14)
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }
}
#endif
