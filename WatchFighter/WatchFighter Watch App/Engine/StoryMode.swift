import CoreGraphics

/// One rung of the arcade ladder: an opponent plus the dialogue shown before
/// the fight and after the player wins it. All text is original to this game.
struct StoryBeat: Equatable {
    let opponentID: String
    let preFight: String      // spoken by the opponent at the VS screen
    let postWin: String       // player's reflection after winning
}

/// The single-player "Ascendant" arcade campaign. Pure progression logic;
/// narrative copy lives in `StoryScript`.
struct StoryMode {
    let playerID: String
    let beats: [StoryBeat]
    private(set) var ladderIndex = 0
    private(set) var isComplete = false

    init(playerID: String, beats: [StoryBeat] = StoryScript.ladder) {
        self.playerID = playerID
        self.beats = beats
    }

    var currentBeat: StoryBeat { beats[min(ladderIndex, beats.count - 1)] }
    var currentOpponent: CharacterSpec { CharacterSpec.byID(currentBeat.opponentID) }
    var progress: String { "\(ladderIndex + 1) / \(beats.count)" }

    /// Advance after a won fight. Returns `true` if another opponent remains.
    mutating func advance() -> Bool {
        if ladderIndex >= beats.count - 1 {
            isComplete = true
            return false
        }
        ladderIndex += 1
        return true
    }
}

/// Original story copy for WATCHFIGHTER: ASCENDANT.
enum StoryScript {
    static let synopsis = """
    Every hundred years the tower called THE ASCENDANT opens its gate, and the \
    six who answer climb it floor by floor. The host at the summit has never \
    been beaten — and never explained why he keeps the gate. You climb anyway.
    """

    static let ladder: [StoryBeat] = [
        StoryBeat(opponentID: "volt",
                  preFight: "You came up the wrong stairwell, slow-hand. I'll show you the express.",
                  postWin: "Fast. But speed alone never reached the top floor."),
        StoryBeat(opponentID: "ember",
                  preFight: "The flame remembers everyone who climbs. It will remember you burning.",
                  postWin: "Her fire guards something. I'll ask the summit what."),
        StoryBeat(opponentID: "frost",
                  preFight: "...you are warm. That is your only mistake.",
                  postWin: "She fought like someone still grieving. I know the feeling."),
        StoryBeat(opponentID: "mirage",
                  preFight: "Which of us is real? Win and I'll tell you. Lose and it won't matter.",
                  postWin: "Even the trickster bows to a true strike."),
        StoryBeat(opponentID: "bastion",
                  preFight: "The tower falls one day. I decide who is standing when it does.",
                  postWin: "A wall can be moved. So can a fate."),
        StoryBeat(opponentID: "onyx",
                  preFight: "You climbed well. Now learn why no one keeps what they win up here.",
                  postWin: "The gate is mine to keep now. I think I'll leave it open."),
    ]
}
