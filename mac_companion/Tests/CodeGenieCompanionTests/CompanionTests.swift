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

    func testPairingLinkCarriesEverythingThePhoneNeeds() throws {
        let fingerprint = String(repeating: "ab", count: 32)
        let pairing = CompanionServer.Pairing(
            host: "Janes-Mac.local", port: 51234, token: "tok-_1", fingerprint: fingerprint
        )
        let components = try XCTUnwrap(URLComponents(string: pairing.url))
        XCTAssertEqual(components.scheme, "codegenie")
        XCTAssertEqual(components.host, "pair")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items, ["host": "Janes-Mac.local", "port": "51234", "token": "tok-_1", "fp": fingerprint])
    }

    func testHostNameIsOneAPhoneCanReach() {
        let host = CompanionServer.reachableHostName()
        XCTAssertFalse(host.isEmpty)
        XCTAssertNotEqual(host, "127.0.0.1")
    }

    func testFingerprintIsSha256Hex() {
        let fingerprint = TLSIdentity.fingerprint(ofDER: Data("abc".utf8))
        XCTAssertEqual(fingerprint, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testIdentityIsCreatedOnceAndReused() throws {
        let first = try TLSIdentity.loadOrCreate()
        let second = try TLSIdentity.loadOrCreate()
        XCTAssertEqual(first.fingerprint, second.fingerprint, "a new certificate would unpair every phone")
        XCTAssertEqual(first.fingerprint.count, 64)
    }

    func testTokenComparison() {
        XCTAssertTrue(ClientConnection.equal("abc123", "abc123"))
        XCTAssertFalse(ClientConnection.equal("abc123", "abc124"))
        XCTAssertFalse(ClientConnection.equal("abc", "abc123"))
        XCTAssertFalse(ClientConnection.equal("", "abc"))
        XCTAssertTrue(ClientConnection.equal("", ""))
    }

    func testPairingQRRenders() throws {
        let qr = try XCTUnwrap(PairingQR.render("codegenie://pair?host=h&port=1&token=t&fp=00"))
        XCTAssertGreaterThan(qr.split(separator: "\n").count, 10)
    }
}
