#if os(watchOS)
import SwiftUI

/// App-level state machine. Routes between menus, story, training, and versus.
/// All mutations happen on the main thread (UI + SpriteKit's main-thread loop),
/// so no explicit actor isolation is needed.
final class GameFlow: ObservableObject {
    enum Screen: Equatable {
        case title, menu, select, trainingSetup, versusLobby, storyCard, fight, ending, howTo
    }
    enum AppMode { case story, training, versus }
    enum CardKind { case preFight, postWin }
    enum EndKind { case victory, defeat }

    @Published var screen: Screen = .title
    @Published var appMode: AppMode = .story
    @Published var playerSpec: CharacterSpec = .tetsu
    @Published var story = StoryMode(playerID: "tetsu")
    @Published var trainingOptions = TrainingOptions()
    @Published var cardKind: CardKind = .preFight
    @Published var endKind: EndKind = .defeat
    @Published var versusStatus = "Tap to search for an opponent"
    @Published var versusReady = false
    @Published var progression = ProgressionStore.load()
    @Published var newlyUnlocked: [String] = []
    /// Bumped each fight so SwiftUI rebuilds the SpriteView with a fresh scene.
    @Published var fightToken = 0

    // Versus connection (set by the lobby once matched).
    var versusTransport: MatchTransport?
    var versusLocalSide: Side = .player

    // Fixed versus matchup until character-select sync lands (M3). Both devices
    // must agree on both fighters for the deterministic lockstep sim.
    let versusPlayer: CharacterSpec = .tetsu
    let versusOpponent: CharacterSpec = .volt

    // MARK: Derived

    var opponentSpec: CharacterSpec { story.currentOpponent }
    var stageSpec: StageSpec { StageLibrary.stage(id: opponentSpec.homeStageID) }

    /// CPU difficulty scales as you climb the ladder; the boss gets boss AI.
    var storyDifficulty: AIController.Difficulty {
        if opponentSpec.id == "titus" { return .boss }
        switch story.ladderIndex {
        case 0...2: return .easy
        case 3...5: return .normal
        default:    return .hard
        }
    }

    // MARK: Navigation

    func goToMenu() { screen = .menu }
    func backToTitle() { screen = .title }

    func chooseMode(_ m: AppMode) {
        appMode = m
        switch m {
        case .story, .training: screen = .select
        case .versus:           versusReady = false; versusStatus = "Tap to search for an opponent"; screen = .versusLobby
        }
    }

    func selectCharacter(_ spec: CharacterSpec) {
        playerSpec = spec
        switch appMode {
        case .story:
            story = StoryMode(playerID: spec.id)
            cardKind = .preFight
            screen = .storyCard
        case .training:
            screen = .trainingSetup
        case .versus:
            break
        }
    }

    func beginFight() { fightToken += 1; screen = .fight }

    /// Called by the fight scene when the match concludes.
    func matchEnded(winner: Side) {
        switch appMode {
        case .story:
            if winner == .player {
                unlock(progression.recordWin())     // each floor cleared is a win
                cardKind = .postWin; screen = .storyCard
            } else { endKind = .defeat; screen = .ending }
        case .training:
            screen = .trainingSetup            // back to the practice menu
        case .versus:
            if winner == .player { unlock(progression.recordWin()) }
            endKind = winner == .player ? .victory : .defeat
            versusTransport = nil
            screen = .ending
        }
    }

    /// Continue after the player's post-win story card.
    func continueStory() {
        newlyUnlocked = []
        if story.advance() { cardKind = .preFight; screen = .storyCard }
        else { unlock(progression.clearStory()); endKind = .victory; screen = .ending }
    }

    private func unlock(_ ids: [String]) {
        ProgressionStore.save(progression)
        if !ids.isEmpty { newlyUnlocked = ids }
    }
}
#endif
