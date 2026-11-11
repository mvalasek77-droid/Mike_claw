import XCTest
@testable import CodeGenieLogic

final class MacPairingTests: XCTestCase {

    private let fp = String(repeating: "ab", count: 32)

    private func code(_ query: String) -> String { "codegenie://pair?\(query)" }

    func testParsesACompleteCode() throws {
        let pairing = try MacPairing.parse(code("host=Janes-Mac.local&port=51234&token=tok_1&fp=\(fp)")).get()
        XCTAssertEqual(pairing.host, "Janes-Mac.local")
        XCTAssertEqual(pairing.port, 51234)
        XCTAssertEqual(pairing.token, "tok_1")
        XCTAssertEqual(pairing.fingerprint, fp)
    }

    func testToleratesWhitespaceAndColonSeparatedUppercaseFingerprints() throws {
        let colons = stride(from: 0, to: 64, by: 2).map { _ in "AB" }.joined(separator: ":")
        let encoded = colons.replacingOccurrences(of: ":", with: "%3A")
        let pairing = try MacPairing.parse("  " + code("host=h&port=1&token=t&fp=\(encoded)") + "\n").get()
        XCTAssertEqual(pairing.fingerprint, fp)
    }

    func testACodeWithoutAFingerprintIsRefusedAsOutdated() {
        XCTAssertEqual(MacPairing.parse(code("host=h&port=1&token=t")), .failure(.outdatedCompanion))
    }

    func testRejectsThingsThatAreNotPairingCodes() {
        for text in ["", "https://example.com", "codegenie://other?host=h", "just words", "codegenie:pair"] {
            XCTAssertEqual(MacPairing.parse(text), .failure(.notAPairingCode), text)
        }
    }

    func testNamesTheMissingPart() {
        XCTAssertEqual(MacPairing.parse(code("port=1&token=t&fp=\(fp)")), .failure(.missing("host")))
        XCTAssertEqual(MacPairing.parse(code("host=h&token=t&fp=\(fp)")), .failure(.missing("port")))
        XCTAssertEqual(MacPairing.parse(code("host=h&port=1&fp=\(fp)")), .failure(.missing("token")))
        XCTAssertEqual(MacPairing.parse(code("host=&port=1&token=t&fp=\(fp)")), .failure(.missing("host")))
    }

    func testRejectsImpossiblePorts() {
        for port in ["0", "70000", "-1", "abc"] {
            XCTAssertEqual(MacPairing.parse(code("host=h&port=\(port)&token=t&fp=\(fp)")), .failure(.badPort), port)
        }
    }

    func testRejectsATruncatedFingerprint() {
        XCTAssertEqual(MacPairing.parse(code("host=h&port=1&token=t&fp=abcd")), .failure(.badFingerprint))
        XCTAssertEqual(MacPairing.parse(code("host=h&port=1&token=t&fp=\(fp)zz")), .success(
            MacPairing(host: "h", port: 1, token: "t", fingerprint: fp)
        ), "non-hex characters are separators, not data")
    }

    func testOnlyTheExactCertificateMatches() throws {
        let pairing = try MacPairing.parse(code("host=h&port=1&token=t&fp=\(fp)")).get()
        XCTAssertTrue(pairing.matches(certificateDigest: fp))
        XCTAssertTrue(pairing.matches(certificateDigest: fp.uppercased()))
        XCTAssertFalse(pairing.matches(certificateDigest: String(repeating: "ab", count: 31) + "ac"))
        XCTAssertFalse(pairing.matches(certificateDigest: ""))
        XCTAssertFalse(pairing.matches(certificateDigest: fp + "ab"))
    }

    func testEveryFailureExplainsItself() {
        let failures: [MacPairing.ParseError] = [.notAPairingCode, .missing("host"), .badPort, .badFingerprint, .outdatedCompanion]
        for failure in failures { XCTAssertGreaterThan(failure.message.count, 20) }
    }

    func testSurvivesStorage() throws {
        let pairing = MacPairing(host: "h", port: 9, token: "t", fingerprint: fp)
        XCTAssertEqual(try JSONDecoder().decode(MacPairing.self, from: JSONEncoder().encode(pairing)), pairing)
    }
}
