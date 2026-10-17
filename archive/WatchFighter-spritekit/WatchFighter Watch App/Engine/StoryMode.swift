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

    init(playerID: String, beats: [StoryBeat] = StoryScript.ladder, startIndex: Int = 0) {
        self.playerID = playerID
        self.beats = beats
        self.ladderIndex = min(max(0, startIndex), beats.count - 1)
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

/// One narrative panel for the FF-style cutscenes (a text box, optionally with a
/// speaker whose portrait is drawn). `speakerID == nil` means the narrator.
struct CutscenePanel: Equatable {
    let speakerID: String?
    let text: String
}

/// Original story copy for ETERNAL COMBAT: ASCENDANT.
enum StoryScript {

    /// FF-style opening cutscene — narrative + characters that leads to the first
    /// fight of the tournament.
    static let intro: [CutscenePanel] = [
        CutscenePanel(speakerID: nil,
                      text: "The hundred-year gate has opened. The tower THE ASCENDANT hums awake over the town it has fed on for a thousand years."),
        CutscenePanel(speakerID: nil,
                      text: "Champions go up. None come down. The townsfolk no longer mourn them — they sell tickets, and wait for the next fool to climb."),
        CutscenePanel(speakerID: "volt",
                      text: "Another climber? Cute. The first floor is mine, and I don't do slow."),
        CutscenePanel(speakerID: nil,
                      text: "Nine floors. Nine fighters who already gave everything to the tower. And a summit champion who has never heard the bell ring."),
        CutscenePanel(speakerID: nil,
                      text: "You tighten your wraps. If the tower wants champions… it can have a problem instead. The climb begins."),
    ]

    /// Act break before the host, Onyx.
    static let beforeOnyx: [CutscenePanel] = [
        CutscenePanel(speakerID: nil,
                      text: "The stairs end at a throne of dead trophies. The host has been waiting a thousand years for someone worth standing up for."),
        CutscenePanel(speakerID: "onyx",
                      text: "I was a climber once. I won. The prize was THIS — guarding a door I never chose. Let me show you the cost of winning."),
    ]

    /// You died on a tournament floor — dragged down to the Pit.
    static let hellEntry: [CutscenePanel] = [
        CutscenePanel(speakerID: nil,
                      text: "The floor goes out from under you. You fall past the tower, past the town, past the light — into heat."),
        CutscenePanel(speakerID: "demon",
                      text: "Another one the tower couldn't keep. Good. The furnace runs cold. Beat me and you may crawl back up. Fail, and you stoke it forever."),
        CutscenePanel(speakerID: nil,
                      text: "It hefts a red-hot pitchfork. There is no bell down here — only the fight, and the climb back."),
    ]

    /// You beat the demon — clawing back to the tournament.
    static let hellEscape: [CutscenePanel] = [
        CutscenePanel(speakerID: "demon",
                      text: "…tch. Go. The stairs are yours again. But the tower never forgets a face it dropped."),
        CutscenePanel(speakerID: nil,
                      text: "You climb out of the smoke and back onto the floor you fell from. Second chances burn — use it."),
    ]

    /// Finale before Titus.
    static let beforeTitus: [CutscenePanel] = [
        CutscenePanel(speakerID: "onyx",
                      text: "Onyx steps aside, lighter than stone has any right to be. 'The last door was never mine,' he says. 'Ring the bell. Set us all free.'"),
        CutscenePanel(speakerID: nil,
                      text: "Beyond the last door: a square of canvas, two gloves, and a champion who cannot be beaten by damage alone. Only the rite will ring his bell."),
    ]
    static let prologue = """
    Every hundred years THE ASCENDANT opens. Climbers go up. None come back \
    down — not beaten, not victorious. Just… up. The tower keeps them.
    The town below stopped asking why and started selling tickets.
    You bought one. Nine floors. Nine fighters who already gave everything to \
    the tower and don't yet know it. At the summit: a champion who has never \
    heard the bell ring. Time someone rang it.
    """

    static let epilogue = """
    The bell rings. For the first time in a thousand years, the tower exhales. \
    Doors that were never doors swing open. Nine fighters blink awake on the \
    steps — free, confused, and very aware they skipped a hundred birthdays.
    Somewhere far below, a dusty film projector sputters awake, and a voice \
    starts shouting its own sound effects.
    You leave the gate open. Let them climb for fun this time.
    """

    static let ladder: [StoryBeat] = [
        StoryBeat(opponentID: "volt",
                  preFight: "You took the STAIRS? Adorable. I'll show you the express — try to keep your arms attached.",
                  postWin: "She went down grinning. 'Floor two,' she wheezed, 'is where it stops being cute.'"),
        StoryBeat(opponentID: "ember",
                  preFight: "The flame remembers every climber it has cooked. It is, frankly, a very long menu. You're the special.",
                  postWin: "Her fire guards something it's terrified to lose. The tower's been eating her too. She just keeps it lit."),
        StoryBeat(opponentID: "frost",
                  preFight: "...you are warm. That is your only mistake. I will fix it.",
                  postWin: "She fought like someone still grieving a clan the tower swallowed. I know that look. I'm starting to wear it."),
        StoryBeat(opponentID: "corsair",
                  preFight: "Climb all ye like — every tide takes the high ground back, and I AM the tide, mostly rum! Best two falls out of three? Of me. Falling.",
                  postWin: "He laughed the entire match. So did I. Then he whispered: 'None of us can leave, friend. Find the lock.'"),
        StoryBeat(opponentID: "mirage",
                  preFight: "Pick the real me. Go on. Wrong answer hurts, right answer also hurts, it's a whole THING.",
                  postWin: "Even the trickster bowed. 'I've been every climber the tower took,' it said. 'I forget which one was me first.'"),
        StoryBeat(opponentID: "nova",
                  preFight: "Nothing personal. You're just standing between me and a bounty that climbed up here and never came down. Like all of them. Huh.",
                  postWin: "She holstered it, did some quiet math, and stopped smiling. 'The contract was me,' she said. 'I'm chasing myself.'"),
        StoryBeat(opponentID: "bastion",
                  preFight: "The tower falls one day. I decide who is standing when it does. Spoiler: a WALL.",
                  postWin: "A wall can be moved. The big guy actually thanked me for it. 'Onyx holds the lock,' he rumbled. 'He's the saddest of us.'"),
        StoryBeat(opponentID: "onyx",
                  preFight: "You climbed well. Now learn what I learned a thousand years ago: the prize for winning is becoming the next warden. I was a climber once. Hello.",
                  postWin: "He stepped aside, lighter than a man his size should be. 'The last door was never mine to guard,' he said. 'Ring the bell. Set us all loose.'"),
        StoryBeat(opponentID: "titus",
                  preFight: "(He says nothing. He raises his fists. The bell has not rung for him in ten centuries — and damage alone will never ring it. Perform the rite, or join the collection.)",
                  postWin: "The undefeated, defeated. The bell sings. The tower, for once, has nothing to keep."),
    ]
}

