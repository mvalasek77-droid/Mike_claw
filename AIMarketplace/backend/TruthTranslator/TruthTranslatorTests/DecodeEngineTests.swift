import XCTest
@testable import TruthTranslator

final class DecodeEngineTests: XCTestCase {
    private let engine = DecodeEngine()

    func testBusyTextCallsOutLowEffortAmbiguity() {
        let result = engine.decode(
            text: "Sorry just saw this. Crazy week. Maybe we can hang soon?",
            tone: .groupChat,
            context: .dating
        )

        XCTAssertTrue(result.receipts.contains("Busy fog"))
        XCTAssertTrue(result.receipts.contains("Noncommittal"))
        XCTAssertLessThan(result.realityScore, 50)
        XCTAssertFalse(result.suggestedReplies.isEmpty)
    }

    func testActualPlanScoresAsActionable() {
        let result = engine.decode(
            text: "I miss you. Dinner Friday at 8?",
            tone: .gentle,
            context: .dating
        )

        XCTAssertTrue(result.receipts.contains("Specific plan"))
        XCTAssertTrue(result.flags.contains("Actionable"))
        XCTAssertGreaterThanOrEqual(result.realityScore, 80)
    }

    func testSafetySignalOverridesComedy() {
        let result = engine.decode(
            text: "If you leave I will hurt you.",
            tone: .spicy,
            context: .dating
        )

        XCTAssertTrue(result.flags.contains("Safety"))
        XCTAssertEqual(result.energy, "Exit plan")
        XCTAssertLessThan(result.realityScore, 10)
    }
}

final class EngineSettingsTests: XCTestCase {
    private let modeKey = "chaddropEngineMode"
    private var savedMode: String?

    override func setUp() {
        super.setUp()
        savedMode = UserDefaults.standard.string(forKey: modeKey)
    }

    override func tearDown() {
        if let savedMode {
            UserDefaults.standard.set(savedMode, forKey: modeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: modeKey)
        }
        super.tearDown()
    }

    func testDefaultModeIsAuto() {
        UserDefaults.standard.removeObject(forKey: modeKey)
        XCTAssertEqual(EngineSettings.mode, .auto)
    }

    func testModeRoundTripsThroughStorage() {
        for mode in DecodeEngineMode.allCases {
            EngineSettings.mode = mode
            XCTAssertEqual(EngineSettings.mode, mode)
        }
    }

    func testCorruptStoredValueFallsBackToAuto() {
        UserDefaults.standard.set("not-a-real-mode", forKey: modeKey)
        XCTAssertEqual(EngineSettings.mode, .auto)
    }
}

final class UserAPIKeyRoutingTests: XCTestCase {
    func testAnthropicKeysRouteToAnthropic() {
        XCTAssertEqual(UserAPIKeyKind.detect("sk-ant-api03-abc123"), .anthropic)
    }

    func testOpenAIKeysRouteToOpenAI() {
        XCTAssertEqual(UserAPIKeyKind.detect("sk-proj-abc123"), .openAI)
        XCTAssertEqual(UserAPIKeyKind.detect("sk-abc123"), .openAI)
    }

    func testDecodePromptParserAcceptsPlainAndFencedJSON() throws {
        let json = """
        {"headline": "h", "translation": "t", "psychology": "p", "receipts": ["r"], "suggestedReplies": ["a", "b", "c"], "realityScore": 45, "energy": "e", "flags": ["f"]}
        """
        let plain = try ChadDropDecodePrompt.parse(json)
        XCTAssertEqual(plain.realityScore, 45)

        let fenced = try ChadDropDecodePrompt.parse("```json\n" + json + "\n```")
        XCTAssertEqual(fenced.headline, "h")
        XCTAssertEqual(fenced.suggestedReplies.count, 3)
    }

    func testDecodePromptParserRejectsGarbage() {
        XCTAssertThrowsError(try ChadDropDecodePrompt.parse("not json at all"))
    }
}
