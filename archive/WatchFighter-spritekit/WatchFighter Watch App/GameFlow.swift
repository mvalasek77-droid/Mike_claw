#if os(watchOS)
import SwiftUI

/// App-level state machine. Routes between menus, story, training, and versus.
/// All mutations happen on the main thread (UI + SpriteKit's main-thread loop),
/// so no explicit actor isolation is needed.
final class GameFlow: ObservableObject {
    enum Screen: Equatable {
        case title, menu, select, opponentSelect, trainingSetup, versusLobby,
             cutscene, storyCard, fight, ending, howTo
    }
    enum AppMode { case story, training, versus, versusCPU }
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

    /// When you've died and been dragged to the Pit, the next fight is the demon.
    @Published var inHell = false
    var opponentSpec: CharacterSpec { inHell ? .demon : story.currentOpponent }
    var stageSpec: StageSpec { StageLibrary.stage(id: opponentSpec.homeStageID) }

    /// Player-chosen CPU difficulty (the boss & the Pit demon get boss-tier AI).
    @Published var cpuDifficulty: AIController.Difficulty = .normal
    var storyDifficulty: AIController.Difficulty {
        (opponentSpec.id == "titus" || opponentSpec.id == "demon") ? .boss : cpuDifficulty
    }

    // MARK: Navigation

    func goToMenu() { screen = .menu }
    func backToTitle() { screen = .title }

    /// Leave a fight in progress — wired to the in-fight pause button so no mode
    /// (especially never-ending Training) can ever soft-lock.
    func exitFight() {
        switch appMode {
        case .training: screen = .trainingSetup
        case .story:    inHell = false; ResumeStore.clear(); screen = .menu   // abandon run
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
            inHell = false
            story = StoryMode(playerID: spec.id)
            cardKind = .preFight
            playCutscene(StoryScript.intro)     // FF-style opening, then floor 1
        case .training:
            screen = .trainingSetup
        case .versus:
            versusStatus = "Tap to search for an opponent"
            screen = .versusLobby
        case .versusCPU:
            screen = .opponentSelect            // now pick who to fight
        }
    }

    // MARK: - VS (CPU) quick match

    @Published var quickOpponent: CharacterSpec = .volt
    func selectOpponent(_ spec: CharacterSpec) { quickOpponent = spec; beginFight() }

    // MARK: - Cutscenes (FF-style narrative leading into fights)

    enum CutsceneThen { case storyCard, fight }
    @Published var cutscenePanels: [CutscenePanel] = []
    @Published var cutsceneIndex = 0
    private var cutsceneThen: CutsceneThen = .storyCard

    private func playCutscene(_ panels: [CutscenePanel], then: CutsceneThen = .storyCard) {
        cutscenePanels = panels; cutsceneIndex = 0; cutsceneThen = then; screen = .cutscene
    }
    func advanceCutscene() {
        if cutsceneIndex + 1 < cutscenePanels.count { cutsceneIndex += 1; return }
        switch cutsceneThen {
        case .storyCard: cardKind = .preFight; screen = .storyCard
        case .fight:     beginFight()          // e.g. into the Pit demon fight
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

    func beginFight() {
        if appMode == .story { ResumeStore.save(playerID: playerSpec.id, ladderIndex: story.ladderIndex) }
        fightToken += 1; screen = .fight
    }

    /// On launch, resume an interrupted story run (watch lock-out / suspend).
    func restoreIfNeeded() {
        guard screen == .title, let r = ResumeStore.load() else { return }
        appMode = .story
        playerSpec = CharacterSpec.byID(r.id)
        story = StoryMode(playerID: r.id, startIndex: r.index)
        cardKind = .preFight
        screen = .storyCard
    }

    /// Called by the fight scene when the match concludes.
    func matchEnded(winner: Side) {
        switch appMode {
        case .story:
            if inHell {
                // The Pit: win = claw back to the floor you fell from; lose = over.
                inHell = false
                if winner == .player { playCutscene(StoryScript.hellEscape, then: .storyCard) }
                else { ResumeStore.clear(); endKind = .defeat; screen = .ending }
            } else if winner == .player {
                unlock(progression.recordWin())     // each floor cleared is a win
                cardKind = .postWin; screen = .storyCard
            } else {
                // First death on a floor -> dragged to Hell for a second chance.
                inHell = true
                playCutscene(StoryScript.hellEntry, then: .fight)
            }
        case .training:
            screen = .trainingSetup            // back to the practice menu
        case .versus, .versusCPU:
            if winner == .player { unlock(progression.recordWin()) }
            endKind = winner == .player ? .victory : .defeat
            versusTransport = nil
            screen = .ending
        }
    }

    /// Continue after the player's post-win story card. Plays an act-break
    /// cutscene before the host (Onyx) and the finale (Titus).
    func continueStory() {
        newlyUnlocked = []
        guard story.advance() else {
            ResumeStore.clear(); unlock(progression.clearStory()); endKind = .victory; screen = .ending
            return
        }
        ResumeStore.save(playerID: playerSpec.id, ladderIndex: story.ladderIndex)
        switch story.currentOpponent.id {
        case "onyx":  playCutscene(StoryScript.beforeOnyx)
        case "titus": playCutscene(StoryScript.beforeTitus)
        default:      cardKind = .preFight; screen = .storyCard
        }
    }

    private func unlock(_ ids: [String]) {
        ProgressionStore.save(progression)
        if !ids.isEmpty { newlyUnlocked = ids }
    }
}
#endif
