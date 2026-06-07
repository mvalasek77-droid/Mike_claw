#if os(watchOS)
import SwiftUI

/// App-level state machine: Title -> Character Select -> Story card -> Fight ->
/// (win) next Story card / (lose) Ending. Drives which SwiftUI screen shows.
/// All mutations happen on the main thread (UI events + SpriteKit's main-thread
/// update loop), so no explicit actor isolation is needed.
final class GameFlow: ObservableObject {
    enum Screen: Equatable { case title, select, storyCard, fight, ending }
    enum CardKind { case preFight, postWin }
    enum EndKind { case victory, defeat }

    @Published var screen: Screen = .title
    @Published var playerSpec: CharacterSpec = .tetsu
    @Published var story = StoryMode(playerID: "tetsu")
    @Published var cardKind: CardKind = .preFight
    @Published var endKind: EndKind = .defeat
    /// Bumped each fight so SwiftUI rebuilds the SpriteView with a fresh scene.
    @Published var fightToken = 0

    var opponentSpec: CharacterSpec { story.currentOpponent }
    var stageSpec: StageSpec { StageLibrary.stage(id: opponentSpec.homeStageID) }

    func goToSelect() { screen = .select }

    func startStory(with spec: CharacterSpec) {
        playerSpec = spec
        story = StoryMode(playerID: spec.id)
        cardKind = .preFight
        screen = .storyCard
    }

    func beginFight() {
        fightToken += 1
        screen = .fight
    }

    /// Called by the fight scene when the match concludes.
    func matchEnded(winner: Side) {
        if winner == .player {
            cardKind = .postWin
            screen = .storyCard
        } else {
            endKind = .defeat
            screen = .ending
        }
    }

    /// Continue after the player's post-win card.
    func continueStory() {
        if story.advance() {
            cardKind = .preFight
            screen = .storyCard
        } else {
            endKind = .victory
            screen = .ending
        }
    }

    func backToTitle() { screen = .title }
}
#endif
