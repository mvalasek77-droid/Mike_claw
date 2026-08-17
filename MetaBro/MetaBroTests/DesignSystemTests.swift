import Testing
@testable import MetaBro

/// Guards the small bits of logic inside the design system so refactors can't
/// silently break score formatting or vote math.
struct DesignSystemTests {

    @Test(arguments: [
        (5, "5"),
        (999, "999"),
        (1_000, "1k"),
        (1_200, "1.2k"),
        (1_500_000, "1.5m"),
        (-2_300, "-2.3k"),
    ])
    func abbreviatesScores(_ input: Int, _ expected: String) {
        #expect(input.abbreviated == expected)
    }

    @Test func voteDeltaMatchesDirection() {
        #expect(VoteDirection.up.delta == 1)
        #expect(VoteDirection.down.delta == -1)
        #expect(VoteDirection.none.delta == 0)
    }

    @Test func voteValueAndDirectionRoundTrip() {
        for value in [VoteValue.up, .down, .none] {
            #expect(value.direction.value == value)
        }
    }
}
