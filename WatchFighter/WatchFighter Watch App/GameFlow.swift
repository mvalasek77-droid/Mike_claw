#if os(watchOS)
import SwiftUI

/// App-level state machine. Routes between menus, story, training, and versus.
/// All mutations happen on the main thread (UI + SpriteKit's main-thread loop),
/// so no explicit actor isolation is needed.
final class GameFlow: ObservableObject {
    enum Screen: Equatable {
        case title, menu, select, trainingSetup, versusLobby, prologue, storyCard, fight, ending, howTo
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

    // Versus matchup, resolved by the lobby handshake so both devices agree.
    var versusPlayer: CharacterSpec = .tetsu
    var versusOpponent: CharacterSpec = .volt

    // MARK: Derived

    var opponentSpec: CharacterSpec { story.currentOpponent }
    var stageSpec: StageSpec { StageLibrary.stage(id: opponentSpec.homeStageID) }

    /// Player-chosen CPU difficulty (the final boss always gets boss-tier AI).
    @Published var cpuDifficulty: AIController.Difficulty = .normal
    var storyDifficulty: AIController.Difficulty {
        opponentSpec.id == "titus" ? .boss : cpuDifficulty
    }

    // MARK: Navigation

    func goToMenu() { screen = .menu }
    func backToTitle() { screen = .title }

    /// Leave a fight in progress — wired to the in-fight pause button so no mode
    /// (especially never-ending Training) can ever soft-lock.
    func exitFight() {
        switch appMode {
        case .training: screen = .trainingSetup
        case .story:    screen = .menu            // abandon run, no win recorded
        case .versus:
            versusTransport?.disconnect(); versusTransport = nil
            screen = .menu
        }
    }

    func chooseMode(_ m: AppMode) {
        appMode = m
        screen = .select          // pick a fighter first (versus picks too)
    }

    func selectCharacter(_ spec: CharacterSpec) {
        playerSpec = spec
        switch appMode {
        case .story:
            story = StoryMode(playerID: spec.id)
            cardKind = .preFight
            screen = .prologue        // opening crawl, then the first fight
        case .training:
            screen = .trainingSetup
        case .versus:
            versusStatus = "Tap to search for an opponent"
            screen = .versusLobby
        }
    }

    // Handshake state (order-independent: connect + remote pick can arrive in
    // either order; we resolve once both are known).
    private var pendingSide: Side?
    private var pendingRemotePick: String?

    func versusConnected(side: Side, transport: MatchTransport) {
        pendingSide = side
        transport.send(.setup(characterID: playerSpec.id))   // announce my pick
        tryResolveVersus(transport)
    }

    func versusReceivedSetup(id: String, transport: MatchTransport) {
        pendingRemotePick = id
        tryResolveVersus(transport)
    }

    private func tryResolveVersus(_ transport: MatchTransport) {
        guard let side = pendingSide, let remote = pendingRemotePick else { return }
        pendingSide = nil; pendingRemotePick = nil
        let m = VersusMatchup.resolve(localSide: side,
                                      localPick: playerSpec.id, remotePick: remote)
        versusPlayer = m.player
        versusOpponent = m.opponent
        versusLocalSide = side
        versusTransport = transport
        beginFight()
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
