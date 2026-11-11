import XCTest
@testable import CodeGenieLogic

final class CredentialCheckTests: XCTestCase {

    // A real-shaped PKCS#8 P-256 key body (DER SEQUENCE, 138 bytes).
    private let body = "MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgevZzL1gdAFr88hb2OF/2NxApJCzGCEDdfSp6VQO30hygCgYIKoZIzj0DAQehRANCAAQRWz+jn65BtOMvdyHKcvjBeBSDZH2r1RTwjmYSi9R/zpBnuQ4EiMnCqfMPWiZqB4QdbAd0E7oH50VpuZ1P087G"

    private var pem: String {
        var lines = ["-----BEGIN PRIVATE KEY-----"]
        var rest = Substring(body)
        while !rest.isEmpty { lines.append(String(rest.prefix(64))); rest = rest.dropFirst(64) }
        lines.append("-----END PRIVATE KEY-----")
        return lines.joined(separator: "\n")
    }

    // MARK: Provider keys

    func testAcceptsWellFormedProviderKeys() {
        XCTAssertEqual(CredentialCheck.providerKey("sk-ant-api03-" + String(repeating: "a", count: 40), for: .anthropic), .ok)
        XCTAssertEqual(CredentialCheck.providerKey("sk-proj-" + String(repeating: "b", count: 40), for: .openai), .ok)
    }

    func testCatchesAKeyPastedInTheWrongBox() {
        let anthropic = "sk-ant-api03-" + String(repeating: "a", count: 40)
        let openai = "sk-proj-" + String(repeating: "b", count: 40)
        XCTAssertFalse(CredentialCheck.providerKey(openai, for: .anthropic).isUsable)
        XCTAssertFalse(CredentialCheck.providerKey(anthropic, for: .openai).isUsable)
    }

    func testCatchesTruncatedEmptyAndBrokenKeys() {
        XCTAssertFalse(CredentialCheck.providerKey("", for: .anthropic).isUsable)
        XCTAssertFalse(CredentialCheck.providerKey("   ", for: .anthropic).isUsable)
        XCTAssertFalse(CredentialCheck.providerKey("sk-ant-abc", for: .anthropic).isUsable)
        XCTAssertFalse(CredentialCheck.providerKey("sk-ant-api03-aaaa aaaa\naaaaaaaaaaaaaaaa", for: .anthropic).isUsable)
    }

    func testAnUnfamiliarPrefixWarnsButDoesNotBlock() {
        let verdict = CredentialCheck.providerKey("key-" + String(repeating: "z", count: 40), for: .anthropic)
        XCTAssertTrue(verdict.isUsable)
        XCTAssertNotNil(verdict.message)
    }

    func testTidyRemovesWhatCopyingAdds() {
        XCTAssertEqual(CredentialCheck.tidy("  \"sk-ant-x\"\n"), "sk-ant-x")
        XCTAssertEqual(CredentialCheck.tidy("“ABCD123456”"), "ABCD123456")
    }

    // MARK: Apple identifiers

    func testTeamID() {
        XCTAssertEqual(CredentialCheck.teamID("ABCD123456"), .ok)
        XCTAssertEqual(CredentialCheck.teamID(" abcd123456\n"), .ok)
        for bad in ["", "ABCD12345", "ABCD1234567", "ABCD 123456", "jane@icloud.com", "ABCD-12345"] {
            XCTAssertFalse(CredentialCheck.teamID(bad).isUsable, bad)
        }
    }

    func testIssuerIDMustBeAUUID() {
        XCTAssertEqual(CredentialCheck.issuerID("57246542-96fe-1a63-e053-0824d011072a"), .ok)
        for bad in ["", "ABCD123456", "57246542-96fe-1a63-e053", "not an id"] {
            XCTAssertFalse(CredentialCheck.issuerID(bad).isUsable, bad)
        }
    }

    func testKeyIDCatchesTheIssuerIDPastedByMistake() {
        XCTAssertEqual(CredentialCheck.keyID("2X9R4HXF34"), .ok)
        XCTAssertFalse(CredentialCheck.keyID("57246542-96fe-1a63-e053-0824d011072a").isUsable)
        XCTAssertFalse(CredentialCheck.keyID("").isUsable)
        XCTAssertTrue(CredentialCheck.keyID("ABC123").isUsable, "an odd length warns rather than blocks")
        XCTAssertNotNil(CredentialCheck.keyID("ABC123").message)
    }

    func testKeyIDIsReadFromApplesFileName() {
        XCTAssertEqual(CredentialCheck.keyID(fromFileName: "AuthKey_2X9R4HXF34.p8"), "2X9R4HXF34")
        XCTAssertEqual(CredentialCheck.keyID(fromFileName: "/Downloads/AuthKey_2x9r4hxf34.P8"), "2X9R4HXF34")
        XCTAssertNil(CredentialCheck.keyID(fromFileName: "AuthKey_2X9R4HXF34 (1).p8"))
        XCTAssertNil(CredentialCheck.keyID(fromFileName: "key.p8"))
        XCTAssertNil(CredentialCheck.keyID(fromFileName: "AuthKey_2X9R4HXF34.txt"))
    }

    // MARK: Private key

    func testAProperKeyPassesAndIsUnchanged() {
        XCTAssertEqual(CredentialCheck.privateKey(pem), .ok)
        XCTAssertEqual(CredentialCheck.normalisedPrivateKey(pem), pem)
    }

    func testAKeyWithItsLineBreaksStrippedIsRecovered() {
        // What a single-line secure field does to a pasted .p8.
        let flattened = pem.replacingOccurrences(of: "\n", with: "")
        XCTAssertEqual(CredentialCheck.normalisedPrivateKey(flattened), pem)
        XCTAssertEqual(CredentialCheck.privateKey(flattened), .ok)
    }

    func testOtherPasteDamageIsRecovered() {
        XCTAssertEqual(CredentialCheck.normalisedPrivateKey(pem.replacingOccurrences(of: "\n", with: "\r\n")), pem)
        XCTAssertEqual(CredentialCheck.normalisedPrivateKey(pem.replacingOccurrences(of: "\n", with: " ")), pem)
        XCTAssertEqual(CredentialCheck.normalisedPrivateKey(pem.replacingOccurrences(of: "\n", with: "\\n")), pem)
        XCTAssertEqual(CredentialCheck.normalisedPrivateKey("\n\n  " + pem + "  \n"), pem)
        XCTAssertEqual(CredentialCheck.normalisedPrivateKey(body), pem, "the body alone, without markers")
    }

    func testEveryNormalisedLineFitsPEMWidth() throws {
        let lines = try XCTUnwrap(CredentialCheck.normalisedPrivateKey(body)).split(separator: "\n")
        XCTAssertEqual(lines.first, "-----BEGIN PRIVATE KEY-----")
        XCTAssertEqual(lines.last, "-----END PRIVATE KEY-----")
        for line in lines.dropFirst().dropLast() { XCTAssertLessThanOrEqual(line.count, 64) }
    }

    func testThingsThatAreNotTheKeyAreRefusedWithAReason() {
        let wrong = [
            "", "hello", "ABCD123456",
            "-----BEGIN CERTIFICATE-----\n\(body)\n-----END CERTIFICATE-----",
            "-----BEGIN RSA PRIVATE KEY-----\n\(body)\n-----END RSA PRIVATE KEY-----",
            "-----BEGIN PRIVATE KEY-----\n" + String(body.prefix(60)) + "\n-----END PRIVATE KEY-----",
            "-----BEGIN PRIVATE KEY-----\n" + String(repeating: "!", count: 200) + "\n-----END PRIVATE KEY-----",
            String(repeating: "QUJD", count: 50),   // valid base64, not DER
        ]
        for text in wrong {
            let verdict = CredentialCheck.privateKey(text)
            XCTAssertFalse(verdict.isUsable, String(text.prefix(40)))
            XCTAssertGreaterThan(verdict.message?.count ?? 0, 20)
        }
    }
}

final class PersonalPrefixTests: XCTestCase {

    func testIsAValidPrefixAndNotTheSharedOne() {
        for _ in 0..<200 {
            let prefix = AppBundleID.personalPrefix()
            XCTAssertTrue(AppBundleID.isValidPrefix(prefix), prefix)
            XCTAssertFalse(AppBundleID.usesFallback(prefix: prefix), prefix)
            XCTAssertTrue(prefix.hasPrefix("com.codegenie.u"))
            XCTAssertEqual(prefix.count, "com.codegenie.u".count + 6)
            XCTAssertEqual(AppBundleID.make(prefix: prefix, title: "Tide Times"), "\(prefix).tidetimes")
        }
    }

    func testTwoInstallsAlmostNeverCollide() {
        let many = Set((0..<2_000).map { _ in AppBundleID.personalPrefix() })
        XCTAssertGreaterThan(many.count, 1_990)
    }

    func testJobsRememberTheIDTheyWereBuiltWith() throws {
        var job = BuildJob(description: AppDescription(title: "Tide Times", prompt: "tides"))
        XCTAssertNil(job.bundleID)
        job.bundleID = "com.jane.tidetimes"
        let decoded = try JSONDecoder().decode(BuildJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(decoded.bundleID, "com.jane.tidetimes")
        // A job saved before the field existed still loads.
        let legacy = #"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","description":{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5A","title":"T","prompt":"p","category":"utility","style":"minimal","features":[]},"stage":"Ready to test","startedAt":0}"#
        XCTAssertNil(try JSONDecoder().decode(BuildJob.self, from: Data(legacy.utf8)).bundleID)
    }
}
