import XCTest
@testable import CodeGenieCompanion

/// Tiny smoke test that runs without launching the listener.
final class CompanionTests: XCTestCase {
    func testTokenStoreCreatesAndPersists() {
        let first = TokenStore.loadOrCreate()
        let second = TokenStore.loadOrCreate()
        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first.count, 16)
    }

    func testTokenRotationChangesValue() {
        let first = TokenStore.loadOrCreate()
        let rotated = TokenStore.rotate()
        XCTAssertNotEqual(first, rotated)
    }
}
