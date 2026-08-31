import XCTest
@testable import WatchFighter_Watch_App

/// Guardrails for the balance pass — catch accidental out-of-band tuning.
final class BalanceTests: XCTestCase {

    func testSelectableHealthBand() {
        for spec in CharacterSpec.selectable {
            XCTAssertGreaterThanOrEqual(spec.maxHealth, 90, "\(spec.id) too fragile")
            XCTAssertLessThanOrEqual(spec.maxHealth, 130, "\(spec.id) too tanky")
        }
    }

    func testBossesAreTougherThanTheCast() {
        let maxSelectable = CharacterSpec.selectable.map(\.maxHealth).max() ?? 0
        XCTAssertGreaterThan(CharacterSpec.onyx.maxHealth, maxSelectable)
        XCTAssertGreaterThan(CharacterSpec.titus.maxHealth, CharacterSpec.onyx.maxHealth)
    }

    func testSpecialDamageInRange() {
        for spec in CharacterSpec.selectable {
            XCTAssertGreaterThanOrEqual(spec.special.damage, 10)
            XCTAssertLessThanOrEqual(spec.special.damage, 30)
        }
    }

    func testLongPokesPairWithLowerHealth() {
        // The two longest pokes (Vesper, Corsair) should not also be the tankiest.
        let longReach = [CharacterSpec.vesper, .corsair]
        for spec in longReach {
            XCTAssertLessThan(spec.maxHealth, CharacterSpec.bastion.maxHealth)
        }
    }

    func testComboScalingIsMonotonic() {
        let s = CombatSystem.scaling
        for i in 1..<s.count { XCTAssertLessThanOrEqual(s[i], s[i - 1]) }
        XCTAssertGreaterThanOrEqual(s.last ?? 0, CombatSystem.minScale)
    }

    func testPhysicsConstantsSane() {
        XCTAssertGreaterThan(CombatSystem.jumpVelocity, 0)
        XCTAssertGreaterThan(CombatSystem.gravity, 0)
        // A jump should last roughly half a second to a second at 60fps.
        let airtimeTicks = 2 * CombatSystem.jumpVelocity / CombatSystem.gravity
        XCTAssertGreaterThan(airtimeTicks, 15)
        XCTAssertLessThan(airtimeTicks, 60)
    }

    func testBossesExcludedFromSelect() {
        let ids = CharacterSpec.selectable.map(\.id)
        XCTAssertFalse(ids.contains("titus"))
        XCTAssertFalse(ids.contains("onyx"))
    }
}
