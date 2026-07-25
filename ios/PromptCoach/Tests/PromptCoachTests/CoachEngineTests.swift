import XCTest
@testable import PromptCoach

/// Unit tests for the coaching engine — the app's brain. These assert the
/// behaviours that actually matter to prompt quality, especially the
/// per-model differences that are easy to regress (Opus 5 self-verifies;
/// Haiku 4.5 has no effort ladder).
///
/// Note: `Tests/validate_pack.py` covers the JSON<->Swift decode contract and
/// runs anywhere Python does. These cover engine logic and need Xcode.
final class CoachEngineTests: XCTestCase {

    private var pack: ModelPack!
    private var engine: CoachEngine!

    override func setUpWithError() throws {
        // Loads from the test bundle if present, else the app bundle.
        pack = try Self.loadPack()
        engine = CoachEngine(pack: pack)
    }

    private static func loadPack() throws -> ModelPack {
        let candidates = [Bundle(for: CoachEngineTests.self), Bundle.main]
        for bundle in candidates {
            if let url = bundle.url(forResource: "model-pack", withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                return try JSONDecoder().decode(ModelPack.self, from: data)
            }
        }
        throw XCTSkip("model-pack.json not found in test or app bundle")
    }

    // MARK: - Pack integrity

    func testPackLoadsWithCurrentModels() {
        let ids = Set(pack.models.map(\.id))
        XCTAssertTrue(ids.contains("claude-opus-5"), "Opus 5 must be in the pack")
        XCTAssertTrue(ids.contains("claude-sonnet-5"))
        XCTAssertTrue(ids.contains("claude-fable-5"))
        XCTAssertTrue(ids.contains("claude-haiku-4-5"))
        XCTAssertFalse(pack.techniques.library.isEmpty)
        XCTAssertFalse(pack.packVersion.isEmpty)
    }

    func testEveryPlaybookResolvesToAKnownModelAndTechniques() {
        let modelIDs = Set(pack.models.map(\.id))
        let techniqueIDs = Set(pack.techniques.library.map(\.id))
        for pb in pack.taskPlaybooks.playbooks {
            XCTAssertTrue(modelIDs.contains(pb.recommend),
                          "playbook \(pb.task) recommends unknown model \(pb.recommend)")
            for t in pb.techniques {
                XCTAssertTrue(techniqueIDs.contains(t),
                              "playbook \(pb.task) references unknown technique \(t)")
            }
        }
    }

    func testEveryTaskTypeHasAPlaybook() {
        let tasks = Set(pack.taskPlaybooks.playbooks.map(\.task))
        for type in TaskType.allCases {
            XCTAssertTrue(tasks.contains(type.rawValue),
                          "TaskType.\(type.rawValue) has no playbook")
        }
    }

    // MARK: - Task detection

    func testTaskDetection() {
        let cases: [(String, TaskType)] = [
            ("need to reply to a customer who's mad about a late order", .email),
            ("write a python function to parse this csv", .code),
            ("postgres query for top 10 products by revenue, join products", .sql),
            ("getting a traceback, exception on line 40, why is this failing", .debug),
            ("research and compare the top three vendors, cite sources", .research),
            ("draft a blog post about our launch", .writing),
            ("summarize this document and pull out the key points", .summarize),
            ("classify these reviews by sentiment", .classify),
            ("design a landing page, need css and layout", .design),
            ("build an agent that automates this multi-step pipeline with tools", .agentic),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(TaskType.detect(from: input), expected,
                           "misdetected: \(input)")
        }
    }

    func testDetectionFallsBackToCodeForUnknownInput() {
        XCTAssertEqual(TaskType.detect(from: "zzz qqq"), .code)
    }

    // MARK: - Report card

    func testBareRambleScoresLowAndRichRambleScoresHigh() {
        let bare = engine.coach(ramble: "make it better")
        let rich = engine.coach(ramble: """
        You are a senior Swift engineer. I'm building a checkout flow for a \
        retail app because conversion is dropping, so that users can pay faster. \
        Only touch PaymentView.swift, do not change the networking layer. \
        Here is the code: ```swift func pay() {}``` \
        For example the button should read "Pay now". \
        It should compile and the existing tests must pass.
        """)
        XCTAssertLessThan(bare.reportCard.score, rich.reportCard.score,
                          "a well-formed ramble must outscore a bare one")
        XCTAssertGreaterThan(rich.reportCard.score, 50)
    }

    func testReportCardScoresEveryChecklistItemFromThePack() {
        let result = engine.coach(ramble: "write a function")
        let scored = Set(result.reportCard.lines.map(\.item))
        let expected = Set(pack.advancedFeatures.reportCardChecklist.map(\.item))
        XCTAssertEqual(scored, expected,
                       "engine must score exactly the pack's checklist items")
    }

    func testReportCardFlagsRetiredPatterns() {
        let withRetired = engine.coach(ramble: "CRITICAL: you must set temperature to 0.7 and classify this")
        let line = withRetired.reportCard.lines.first { $0.item == "no_retired_patterns" }
        XCTAssertEqual(line?.passed, false,
                       "temperature + CRITICAL language must fail the retired-pattern check")
    }

    func testScoreIsBounded() {
        for text in ["", "x", "make it better", String(repeating: "detail ", count: 500)] {
            let s = engine.coach(ramble: text).reportCard.score
            XCTAssertTrue((0...100).contains(s), "score \(s) out of range for \(text.prefix(20))")
        }
    }

    // MARK: - Opus 5 behavioural specifics (the headline correctness case)

    func testOpus5DoesNotReceiveASelfCheckInstruction() throws {
        let result = engine.coach(ramble: "refactor this multi-file module and keep tests green",
                                  overrideModelID: "claude-opus-5")
        XCTAssertFalse(
            result.rewrittenPrompt.lowercased().contains("verify the result against"),
            "Opus 5 self-verifies — the prompt must not add a verification step"
        )
    }

    func testOpus5ExplainsWhySelfCheckWasWithheld() {
        let result = engine.coach(ramble: "write a python function to sort users",
                                  overrideModelID: "claude-opus-5")
        let labels = result.techniquesApplied.map(\.label).joined(separator: " ")
        XCTAssertTrue(labels.contains("self-verifies"),
                      "the app should teach why the usual advice was withheld")
    }

    func testSonnet5DoesReceiveASelfCheckInstruction() {
        let result = engine.coach(ramble: "write a python function to sort users",
                                  overrideModelID: "claude-sonnet-5")
        XCTAssertTrue(result.rewrittenPrompt.lowercased().contains("verify the result against"),
                      "Sonnet 5 benefits from an explicit self-check")
    }

    func testOpus5GetsConcisenessAndScopeLines() {
        let result = engine.coach(ramble: "explain how our auth works",
                                  overrideModelID: "claude-opus-5")
        let p = result.rewrittenPrompt.lowercased()
        XCTAssertTrue(p.contains("concise"), "Opus 5's long default responses need a conciseness line")
        XCTAssertTrue(p.contains("scope"), "Opus 5 widens scope — needs a boundary")
    }

    func testOpus5ThinkingNoteSaysOnByDefault() {
        let result = engine.coach(ramble: "refactor this", overrideModelID: "claude-opus-5")
        XCTAssertTrue(result.rewrittenPrompt.contains("thinking is on by default"),
                      "must match Opus 5's actual API default")
    }

    // MARK: - Haiku: no effort ladder

    func testHaikuNeverGetsAnEffortSuggestion() {
        let result = engine.coach(ramble: "classify this review as positive or negative",
                                  overrideModelID: "claude-haiku-4-5")
        XCTAssertFalse(result.rewrittenPrompt.lowercased().contains("effort"),
                       "Haiku 4.5 has no effort parameter — suggesting one is an API error")
    }

    func testFable5ThinkingNoteSaysAlwaysOn() {
        let result = engine.coach(ramble: "design a novel consensus algorithm",
                                  overrideModelID: "claude-fable-5")
        XCTAssertTrue(result.rewrittenPrompt.contains("always on"),
                      "Fable 5 thinking is always on; omit the parameter")
    }

    // MARK: - Rewrite behaviour

    func testEveryPromptEndsUpWithASuccessCriterion() {
        for text in ["reply to this email", "write a sql query", "design a dashboard"] {
            let r = engine.coach(ramble: text)
            XCTAssertTrue(r.rewrittenPrompt.contains("Done means:"),
                          "missing success criterion for: \(text)")
        }
    }

    func testRetiredPatternsAreStrippedFromTheRewrite() {
        let r = engine.coach(ramble: "CRITICAL: you must refactor this function")
        XCTAssertFalse(r.rewrittenPrompt.contains("CRITICAL:"))
        XCTAssertTrue(r.techniquesApplied.contains { $0.techniqueID == "retired" },
                      "stripping should be surfaced to the user")
    }

    func testDuplicateSentencesAreCollapsed() {
        let r = engine.coach(ramble: "Fix the bug. Fix the bug. Fix the bug.")
        let occurrences = r.rewrittenPrompt.components(separatedBy: "Fix the bug").count - 1
        XCTAssertEqual(occurrences, 1, "repeated sentences should be deduped")
    }

    func testStructuredSchemaEmittedForMachineReadableTasks() {
        XCTAssertNotNil(engine.coach(ramble: "classify these tickets by urgency").structuredSchema)
        XCTAssertNotNil(engine.coach(ramble: "summarize this doc and extract key points").structuredSchema)
        XCTAssertNil(engine.coach(ramble: "draft a blog post about our launch").structuredSchema,
                     "prose tasks shouldn't force a schema")
    }

    func testEmittedSchemaIsValidJSON() throws {
        let r = engine.coach(ramble: "classify these tickets by urgency")
        let schema = try XCTUnwrap(r.structuredSchema)
        let data = Data(schema.utf8)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data),
                         "the schema we hand users must be valid JSON")
    }

    // MARK: - Recommender & override

    func testRecommendationFollowsThePlaybook() {
        let r = engine.coach(ramble: "classify these reviews by sentiment")
        let pb = pack.playbook(task: "classify")
        XCTAssertEqual(r.recommendedModelID, pb?.recommend)
    }

    func testOverrideWinsOverRecommendationButKeepsIt() {
        let r = engine.coach(ramble: "classify these reviews", overrideModelID: "claude-fable-5")
        XCTAssertEqual(r.chosenModelID, "claude-fable-5")
        XCTAssertNotEqual(r.recommendedModelID, "claude-fable-5",
                          "the original recommendation should be preserved for display")
    }

    func testAgenticWorkRecommendsOpus5() {
        let r = engine.coach(ramble: "build an agent that orchestrates a multi-step pipeline with tools")
        XCTAssertEqual(r.recommendedModelID, "claude-opus-5")
    }

    // MARK: - Robustness / edge cases

    func testEmptyAndWhitespaceInputDoNotCrash() {
        for text in ["", "   ", "\n\n\t"] {
            let r = engine.coach(ramble: text)
            XCTAssertTrue(r.rewrittenPrompt.contains("Done means:"))
        }
    }

    func testVeryLongInputIsHandled() {
        let long = String(repeating: "Refactor the payment module carefully. ", count: 400)
        let r = engine.coach(ramble: long)
        XCTAssertFalse(r.rewrittenPrompt.isEmpty)
        XCTAssertTrue(r.techniquesApplied.contains { $0.techniqueID == "long_context" },
                      "long input should trigger long-context layout advice")
    }

    func testUnicodeAndEmojiSurvive() {
        let r = engine.coach(ramble: "Écrire une fonction — 日本語 — 🎉 handle it")
        XCTAssertTrue(r.rewrittenPrompt.contains("🎉"))
    }

    func testUnknownOverrideFallsBackGracefully() {
        let r = engine.coach(ramble: "write a function", overrideModelID: "claude-does-not-exist")
        XCTAssertEqual(r.chosenModelID, "claude-does-not-exist")
        XCTAssertFalse(r.rewrittenPrompt.isEmpty, "must not crash on an unknown model")
    }

    func testProseAngleBracketsDoNotFalselyTriggerXMLAdvice() {
        // "5 < 10 and 20 > 15" should not look like pasted markup.
        let r = engine.coach(ramble: "explain why 5 < 10 and 20 > 15 in plain terms")
        XCTAssertFalse(r.techniquesApplied.contains { $0.techniqueID == "xml_structure" })
    }

    func testRealTagsDoTriggerXMLAdvice() {
        let r = engine.coach(ramble: "clean up this html <div>hello</div> for me")
        XCTAssertTrue(r.techniquesApplied.contains { $0.techniqueID == "xml_structure" })
    }

    func testResultIsCodableRoundTrip() throws {
        let r = engine.coach(ramble: "write a sql query for monthly revenue")
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(CoachResult.self, from: data)
        XCTAssertEqual(back.rewrittenPrompt, r.rewrittenPrompt)
        XCTAssertEqual(back.reportCard.score, r.reportCard.score)
        XCTAssertEqual(back.techniquesApplied.count, r.techniquesApplied.count)
    }

    func testDeterminism() {
        let a = engine.coach(ramble: "refactor the auth module")
        let b = engine.coach(ramble: "refactor the auth module")
        XCTAssertEqual(a.rewrittenPrompt, b.rewrittenPrompt,
                       "on-device coaching must be deterministic")
        XCTAssertEqual(a.reportCard.score, b.reportCard.score)
    }

    // MARK: - Sharpen (meta-prompting)

    func testSharpenAddsTaggedStructure() {
        let base = engine.coach(ramble: "reply to this angry customer about a late order")
        let sharp = engine.sharpen(base)
        XCTAssertTrue(sharp.rewrittenPrompt.contains("<task>"))
        XCTAssertTrue(sharp.rewrittenPrompt.contains("<success_criteria>"))
        XCTAssertTrue(sharp.isSharpened)
        XCTAssertFalse(base.isSharpened, "the original must be untouched")
    }

    func testSharpenIsIdempotentlyMarked() {
        let base = engine.coach(ramble: "write a sql query")
        let once = engine.sharpen(base)
        let twice = engine.sharpen(once)
        XCTAssertTrue(twice.isSharpened)
        XCTAssertEqual(once.id, twice.id, "sharpening must not fork the history entry")
    }

    func testSharpenPreservesIdentityForHistoryUpsert() {
        let base = engine.coach(ramble: "summarize this report")
        let sharp = engine.sharpen(base)
        XCTAssertEqual(sharp.id, base.id)
        XCTAssertEqual(sharp.ramble, base.ramble)
    }

    func testSharpenRespectsModelSuppression() {
        let base = engine.coach(ramble: "refactor this module", overrideModelID: "claude-opus-5")
        let sharp = engine.sharpen(base)
        XCTAssertFalse(sharp.rewrittenPrompt.lowercased().contains("verify the result against"),
                       "sharpening must not reintroduce a self-check on Opus 5")
    }

    func testSharpenAddsExamplesOnlyWhereShapeMatters() {
        let classify = engine.sharpen(engine.coach(ramble: "classify these tickets"))
        XCTAssertTrue(classify.rewrittenPrompt.contains("<examples>"))
        let debug = engine.sharpen(engine.coach(ramble: "traceback exception on line 40"))
        XCTAssertFalse(debug.rewrittenPrompt.contains("<examples>"),
                       "debugging doesn't need an output-shape example")
    }

    // MARK: - History backward compatibility

    func testHistoryJSONWithoutSharpenedFieldStillDecodes() throws {
        // Simulates a history file written before `sharpened` existed. A
        // non-optional Bool here would throw and silently wipe the user's
        // saved sessions on upgrade.
        let legacy = """
        {"id":"\(UUID().uuidString)","date":0,"ramble":"x","taskType":"code",
         "recommendedModelID":"claude-sonnet-5","chosenModelID":"claude-sonnet-5",
         "rewrittenPrompt":"p","techniquesApplied":[],
         "reportCard":{"lines":[]}}
        """
        let data = Data(legacy.utf8)
        let decoded = try JSONDecoder().decode(CoachResult.self, from: data)
        XCTAssertFalse(decoded.isSharpened)
        XCTAssertEqual(decoded.ramble, "x")
    }

    // MARK: - Performance

    func testCoachingIsFastEnoughForTypingLatency() {
        let text = "refactor this payment module and keep the tests passing"
        measure { _ = engine.coach(ramble: text) }
    }
}
