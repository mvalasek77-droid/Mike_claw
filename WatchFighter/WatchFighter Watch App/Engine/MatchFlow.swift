import CoreGraphics

/// Best-of-three match orchestration around a `CombatSystem`. Pure + testable:
/// the scene drives the presentation timing (announcer beats), this owns the
/// scoreline and round resets.
struct MatchFlow {
    let playerSpec: CharacterSpec
    let opponentSpec: CharacterSpec
    let roundsToWin: Int

    private(set) var combat: CombatSystem
    private(set) var playerRoundsWon = 0
    private(set) var opponentRoundsWon = 0
    private(set) var currentRound = 1
    private(set) var matchWinner: Side?

    init(playerSpec: CharacterSpec, opponentSpec: CharacterSpec,
         roundsToWin: Int = 2, roundSeconds: Int = 30) {
        self.playerSpec = playerSpec
        self.opponentSpec = opponentSpec
        self.roundsToWin = roundsToWin
        self.combat = CombatSystem(playerSpec: playerSpec, opponentSpec: opponentSpec,
                                   roundSeconds: roundSeconds)
    }

    var isMatchOver: Bool { matchWinner != nil }

    /// Forward an intent to the live combat round.
    mutating func apply(_ intent: Intent, from side: Side) -> [CombatEvent] {
        combat.apply(intent, from: side)
    }

    /// Forward a tick to the live combat round.
    mutating func tick() -> [CombatEvent] { combat.tick() }

    /// Call when the live round has ended (combat reported `.roundOver`).
    /// Updates the scoreline and decides whether the match is over.
    mutating func recordRoundResult(_ winner: Side?) {
        switch winner {
        case .player:   playerRoundsWon += 1
        case .opponent: opponentRoundsWon += 1
        case .none:     break          // double-KO / timeout draw: no point awarded
        }
        if playerRoundsWon >= roundsToWin { matchWinner = .player }
        else if opponentRoundsWon >= roundsToWin { matchWinner = .opponent }
    }

    /// Reset combat for the next round (only valid when the match isn't over).
    mutating func startNextRound() {
        guard !isMatchOver else { return }
        currentRound += 1
        combat.resetForNewRound()
    }
}
