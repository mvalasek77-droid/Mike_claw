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

    // MARK: - Filler trim (token efficiency)

    private var estimator: TokenEstimator { engine.estimator }

    func testFillerTrimPreservesMeaningBearingText() throws {
        try XCTSkipUnless(estimator.isAvailable, "pack has no token_estimation block")
        // Each of these contains a substring that appears in the filler list
        // but is *not* leading a clause. Trimming them would change the ask.
        let mustSurvive = [
            "what kind of file should this write to?",
            "do you know the answer to this",
            "compute the balance at the end of the day for each account",
            "the basically-correct answer is fine"
        ]
        for sentence in mustSurvive {
            XCTAssertEqual(estimator.stripFiller(sentence).text, sentence,
                           "filler trim damaged: \(sentence)")
        }
    }

    func testFillerTrimRemovesClauseLeadingThroatClearing() throws {
        try XCTSkipUnless(estimator.isAvailable)
        let (text, removed) = estimator.stripFiller("ok so basically i need a date parser")
        XCTAssertEqual(text, "i need a date parser")
        XCTAssertFalse(removed.isEmpty, "the removed phrases drive the UI label")
    }

    func testFillerTrimNeverEditsFencedCode() throws {
        try XCTSkipUnless(estimator.isAvailable)
        let input = "clean this up\n```\nbasically = 1\nok so = 2\n```\nthanks in advance"
        let (text, _) = estimator.stripFiller(input)
        XCTAssertTrue(text.contains("basically = 1"), "code inside a fence must survive verbatim")
        XCTAssertTrue(text.contains("ok so = 2"))
    }

    func testFillerTrimIsIdempotent() throws {
        try XCTSkipUnless(estimator.isAvailable)
        // Coaching, then re-coaching the same text must not keep eating words.
        let once = estimator.stripFiller("ok so basically fix the parser").text
        let twice = estimator.stripFiller(once).text
        XCTAssertEqual(once, twice)
    }

    func testCleanCoreNeverReturnsEmptyForAllFillerInput() {
        // A ramble that is *nothing but* filler must fall back to the original
        // rather than handing an empty ask to the prompt builder.
        let (core, _) = engine.cleanCore("ok so basically")
        XCTAssertFalse(core.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Token report

    func testTokenReportIsAttachedAndInternallyConsistent() throws {
        let result = engine.coach(ramble: "ok so basically write me a python csv parser")
        let report = try XCTUnwrap(result.tokenReport, "coach must attach a token report")
        XCTAssertGreaterThan(report.promptTokens, 0)
        XCTAssertGreaterThan(report.rambleTokens, 0)
        XCTAssertLessThanOrEqual(report.cleanedTokens, report.rambleTokens,
                                 "cleaning can only shrink the user's own words")
        XCTAssertEqual(report.wordingTokensSaved, report.rambleTokens - report.cleanedTokens)
        XCTAssertEqual(report.modelID, result.chosenModelID)
    }

    func testTokenReportAdmitsWhenTheCoachedPromptIsLonger() throws {
        // The honest case: role + scope + success criteria cost tokens. The
        // report must expose that rather than implying every prompt shrinks.
        let result = engine.coach(ramble: "fix bug")
        let report = try XCTUnwrap(result.tokenReport)
        XCTAssertTrue(report.promptIsLonger,
                      "a two-word ramble always coaches into something longer")
    }

    func testTokenEstimateTracksTheModelTokenizer() throws {
        try XCTSkipUnless(estimator.isAvailable)
        let text = "summarize this quarterly report for the board"
        let haiku = estimator.estimate(text, modelID: "claude-haiku-4-5")
        let opus = estimator.estimate(text, modelID: "claude-opus-5")
        XCTAssertGreaterThan(haiku, 0)
        XCTAssertGreaterThanOrEqual(opus, haiku,
                                    "frontier tokenizers must not be cheaper than the baseline")
        XCTAssertEqual(estimator.multiplier(for: "not-a-real-model"), 1.0,
                       "an unknown model must fall back to baseline, not guess")
        XCTAssertEqual(estimator.estimate("   ", modelID: "claude-opus-5"), 0)
    }

    func testMoneyFormattingNeverRendersARealCostAsZero() {
        XCTAssertEqual(TokenReport.money(0), "$0")
        XCTAssertEqual(TokenReport.money(0.00001), "<$0.0001")
        XCTAssertEqual(TokenReport.money(0.0042), "$0.0042")
        XCTAssertEqual(TokenReport.money(1.5), "$1.50")
    }

    // MARK: - Adaptive controls (self-learning)

    /// A ramble plus a model the pack does *not* already recommend for it, so
    /// these tests keep testing the shift even if routing changes in the pack.
    private func shiftFixture(_ ramble: String) throws -> (task: String, other: String) {
        let baseline = engine.coach(ramble: ramble)
        let other = try XCTUnwrap(
            pack.models.map(\.id).first { $0 != baseline.recommendedModelID },
            "pack needs at least two models")
        return (baseline.taskType, other)
    }

    func testLearnedPreferenceShiftsTheRecommendation() throws {
        let ramble = "write a short story about a lighthouse"
        let (task, other) = try shiftFixture(ramble)

        var adaptive = CoachEngine(pack: pack)
        var snap = LearningSnapshot()
        snap.preferredModelByTask[task] = other
        adaptive.learning = snap

        let shifted = adaptive.coach(ramble: ramble)
        XCTAssertEqual(shifted.recommendedModelID, other)
        XCTAssertEqual(shifted.chosenModelID, other)
        XCTAssertTrue(shifted.techniquesApplied.contains { $0.techniqueID == "adaptive_defaults" },
                      "a learned shift must be disclosed, not silent")
    }

    func testExplicitOverrideAlwaysBeatsALearnedDefault() throws {
        let ramble = "refactor this payment module"
        let (task, other) = try shiftFixture(ramble)
        let explicit = try XCTUnwrap(pack.models.map(\.id).first { $0 != other })

        var adaptive = CoachEngine(pack: pack)
        var snap = LearningSnapshot()
        snap.preferredModelByTask[task] = other
        adaptive.learning = snap

        let result = adaptive.coach(ramble: ramble, overrideModelID: explicit)
        XCTAssertEqual(result.chosenModelID, explicit)
        XCTAssertFalse(result.techniquesApplied.contains { $0.techniqueID == "adaptive_defaults" },
                       "no learned-shift note when the user chose in the moment")
    }

    func testLearnedPreferenceForADroppedModelIsIgnored() {
        let ramble = "refactor this payment module"
        let baseline = engine.coach(ramble: ramble)

        var adaptive = CoachEngine(pack: pack)
        var snap = LearningSnapshot()
        snap.preferredModelByTask[baseline.taskType] = "claude-model-that-no-longer-ships"
        adaptive.learning = snap

        let result = adaptive.coach(ramble: ramble)
        XCTAssertEqual(result.chosenModelID, baseline.chosenModelID,
                       "a stale preference must fall back to the pack, not to nothing")
        XCTAssertNotNil(pack.model(id: result.chosenModelID))
    }

    func testAutoSharpenAppliesTheStructureUpFront() {
        let ramble = "refactor this payment module"
        let task = engine.coach(ramble: ramble).taskType

        var adaptive = CoachEngine(pack: pack)
        var snap = LearningSnapshot()
        snap.autoSharpenTasks.insert(task)
        adaptive.learning = snap

        let result = adaptive.coach(ramble: ramble)
        XCTAssertTrue(result.isSharpened)
        XCTAssertTrue(result.rewrittenPrompt.contains("<task>"))
    }

    func testMutingRemovesATechniqueFromTheOutput() throws {
        let before = engine.coach(ramble: "review this pull request for security issues")
        try XCTSkipUnless(before.techniquesApplied.contains { $0.techniqueID == "role" },
                          "this ramble didn't apply the role technique")

        var adaptive = CoachEngine(pack: pack)
        var snap = LearningSnapshot()
        snap.mutedTechniques.insert("role")
        adaptive.learning = snap

        let after = adaptive.coach(ramble: "review this pull request for security issues")
        XCTAssertFalse(after.techniquesApplied.contains { $0.techniqueID == "role" },
                       "a muted technique must not be applied")
    }

    func testMutingCanNeverReEnableAModelSuppression() {
        // The core guardrail: muting only ever subtracts, so no combination of
        // learned state can put Opus 5's suppressed self-check back.
        var adaptive = CoachEngine(pack: pack)
        var snap = LearningSnapshot()
        snap.mutedTechniques = Set(pack.techniques.library.map(\.id))
        adaptive.learning = snap

        let result = adaptive.coach(ramble: "refactor this module",
                                    overrideModelID: "claude-opus-5")
        XCTAssertFalse(result.rewrittenPrompt.lowercased().contains("verify the result against"))
        // Muting everything must still produce a usable prompt, not an empty one.
        XCTAssertFalse(result.rewrittenPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testLearningSnapshotDefaultsToInert() {
        XCTAssertFalse(LearningSnapshot.none.isActive)
        let untouched = CoachEngine(pack: pack)
        XCTAssertFalse(untouched.learning.isActive,
                       "a fresh engine must behave exactly like the pack says")
    }

    // MARK: - Learning record backward compatibility

    // `LearningStore` is @MainActor; these hop onto it so the nested `Record`
    // is reachable regardless of how isolation inference lands.
    @MainActor
    func testLearningRecordDecodesPartialAndEmptyJSON() throws {
        // A record written by an older build has fewer keys. Any non-optional
        // field here would throw and wipe everything this user taught the app.
        let partial = Data(#"{"coached":{"code":3}}"#.utf8)
        let decoded = try JSONDecoder().decode(LearningStore.Record.self, from: partial)
        XCTAssertEqual(decoded.coached["code"], 3)
        XCTAssertTrue(decoded.enabled, "learning defaults to on when the key is absent")
        XCTAssertTrue(decoded.muted.isEmpty)
        XCTAssertTrue(decoded.scores.isEmpty)

        let empty = try JSONDecoder().decode(LearningStore.Record.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.enabled)
        XCTAssertTrue(empty.coached.isEmpty)
        XCTAssertTrue(empty.overrides.isEmpty)
    }

    @MainActor
    func testLearningRecordRoundTrips() throws {
        var record = LearningStore.Record()
        record.coached["code"] = 4
        record.overrides["code"] = ["claude-opus-5": 3]
        record.muted = ["role"]
        let data = try JSONEncoder().encode(record)
        let back = try JSONDecoder().decode(LearningStore.Record.self, from: data)
        XCTAssertEqual(back.overrides["code"]?["claude-opus-5"], 3)
        XCTAssertEqual(back.muted, ["role"])
    }

    // MARK: - History backward compatibility (token report)

    func testHistoryJSONWithoutTokenReportStillDecodes() throws {
        // Sessions saved before the token report existed must still open.
        let legacy = """
        {"id":"\(UUID().uuidString)","date":0,"ramble":"x","taskType":"code",
         "recommendedModelID":"claude-sonnet-5","chosenModelID":"claude-sonnet-5",
         "rewrittenPrompt":"p","techniquesApplied":[],
         "reportCard":{"lines":[]}}
        """
        let decoded = try JSONDecoder().decode(CoachResult.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.tokenReport)
        XCTAssertFalse(decoded.isSharpened)
    }

    // MARK: - Performance

    func testCoachingIsFastEnoughForTypingLatency() {
        let text = "refactor this payment module and keep the tests passing"
        measure { _ = engine.coach(ramble: text) }
    }
}
