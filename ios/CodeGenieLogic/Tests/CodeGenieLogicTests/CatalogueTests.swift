import XCTest
@testable import CodeGenieLogic

final class ModelCatalogueTests: XCTestCase {

    func testIDsAreUniqueAndTheDefaultExists() {
        XCTAssertEqual(Set(ModelCatalogue.all.map(\.id)).count, ModelCatalogue.all.count)
        XCTAssertNotNil(ModelCatalogue.model(id: ModelCatalogue.recommendedDefault))
    }

    func testSupersededIDsResolveToAModelStillOffered() {
        for (old, new) in ModelCatalogue.superseded {
            XCTAssertNil(ModelCatalogue.all.first { $0.id == old }, "\(old) is both offered and superseded")
            XCTAssertEqual(ModelCatalogue.model(id: old)?.id, new)
        }
        XCTAssertEqual(ModelCatalogue.currentID(for: "claude-sonnet-4-6"), "claude-sonnet-5-5")
        XCTAssertEqual(ModelCatalogue.currentID(for: "gpt-5"), "gpt-5")
    }

    func testUnknownIDIsNilSoCallersChooseTheFallback() {
        XCTAssertNil(ModelCatalogue.model(id: "made-up-model"))
    }

    func testPricesArePositiveAndOutputCostsMore() {
        for model in ModelCatalogue.all {
            XCTAssertGreaterThan(model.inputUSDPerMTok, 0, model.id)
            XCTAssertGreaterThan(model.outputUSDPerMTok, model.inputUSDPerMTok, model.id)
            XCTAssertGreaterThan(model.contextWindow, 0, model.id)
        }
    }

    func testBuildEstimateUsesBothRates() throws {
        let sonnet = try XCTUnwrap(ModelCatalogue.model(id: "claude-sonnet-5-5"))
        XCTAssertEqual(sonnet.estimatedBuildCostUSD(inputTokens: 1_000_000, outputTokens: 1_000_000), 12.0, accuracy: 0.0001)
        XCTAssertEqual(sonnet.estimatedBuildCostUSD(inputTokens: 0, outputTokens: 0), 0)
    }

    func testEachTierIsRepresentedForAnthropic() {
        let tiers = Set(ModelCatalogue.all.filter { $0.provider == .anthropic }.map(\.tier))
        XCTAssertEqual(tiers, Set(AIModel.Tier.allCases))
    }

    func testFableAndAstraAreOffered() {
        for id in ["claude-fable-5-2", "astra-6-1"] {
            let model = ModelCatalogue.model(id: id)
            XCTAssertNotNil(model, id)
            XCTAssertEqual(model?.tier, .frontier, id)
        }
    }

    func testOrdinaryModelsCostOneCreditAndAreNotPremium() {
        for id in ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "gpt-5", "gpt-5-mini"] {
            let model = ModelCatalogue.model(id: id)
            XCTAssertEqual(model?.creditsPerBuild, 1, id)
            XCTAssertEqual(model?.isPremium, false, id)
            XCTAssertNil(model?.note, id)
        }
    }

    func testFrontierModelsCostMoreThanOneCreditAndSayWhy() {
        let fable = ModelCatalogue.model(id: "claude-fable-5-2")
        XCTAssertEqual(fable?.creditsPerBuild, 3)
        XCTAssertEqual(fable?.isPremium, true)
        XCTAssertEqual(fable?.note?.contains("credits"), true, "the note must explain the extra credits")

        let astra = ModelCatalogue.model(id: "astra-6-1")
        XCTAssertEqual(astra?.creditsPerBuild, 4)
        XCTAssertGreaterThan(astra?.creditsPerBuild ?? 0, fable?.creditsPerBuild ?? 0,
                             "Astra is pitched as the heavier of the two")
        XCTAssertEqual(astra?.note?.isEmpty, false)
    }

    func testFrontierModelsAreDearerPerTokenThanTheFlagship() throws {
        let opus = try XCTUnwrap(ModelCatalogue.model(id: "claude-opus-5-5"))
        for id in ["claude-fable-5-2", "astra-6-1"] {
            let model = try XCTUnwrap(ModelCatalogue.model(id: id))
            XCTAssertGreaterThan(model.estimatedBuildCostUSD(), opus.estimatedBuildCostUSD(), id)
        }
    }

    func testTheDefaultStaysAnAffordableEverydayModel() {
        XCTAssertEqual(ModelCatalogue.model(id: ModelCatalogue.recommendedDefault)?.isPremium, false)
    }
}

final class BundleIDTests: XCTestCase {

    func testBuildsPrefixDotSlug() {
        XCTAssertEqual(AppBundleID.make(prefix: "com.jane", title: "Tide Times"), "com.jane.tidetimes")
    }

    func testOnlyCharactersAppleAcceptsSurvive() {
        let id = AppBundleID.make(prefix: " com.Jane Doe!.apps. ", title: "Tïde & Times™ 2")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        XCTAssertTrue(id.unicodeScalars.allSatisfy { allowed.contains($0) }, id)
        XCTAssertFalse(id.contains(".."))
        XCTAssertFalse(id.hasPrefix("."))
        XCTAssertFalse(id.hasSuffix("."))
    }

    func testEmptyInputsFallBackRatherThanProducingAnInvalidID() {
        XCTAssertEqual(AppBundleID.make(prefix: "", title: ""), "com.codegenie.app")
        XCTAssertEqual(AppBundleID.make(prefix: "...", title: "!!!"), "com.codegenie.app")
        XCTAssertTrue(AppBundleID.usesFallback(prefix: "  "))
        XCTAssertFalse(AppBundleID.usesFallback(prefix: "com.jane"))
    }

    func testSameInputsAlwaysGiveTheSameID() {
        XCTAssertEqual(
            AppBundleID.make(prefix: "com.jane", title: "Tide Times"),
            AppBundleID.make(prefix: "com.jane.", title: "tide times")
        )
    }

    func testPrefixValidationRejectsWhatNormalisingWouldHide() {
        for good in ["", "com.jane", "com.jane-doe.apps", "io.x9"] {
            XCTAssertTrue(AppBundleID.isValidPrefix(good), good)
        }
        for bad in [".com.jane", "com.jane.", "com..jane", "com bad name!", "com.jäne_x"] {
            XCTAssertFalse(AppBundleID.isValidPrefix(bad), bad)
        }
    }
}

final class BuildStageTests: XCTestCase {

    func testProgressNeverGoesBackwards() {
        let ordered: [BuildJob.Stage] = [.planning, .scaffolding, .generatingUI, .wiringLogic, .linting, .buildingIPA, .readyForTest, .shipping]
        let values = ordered.map(\.progress)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(values.last, 1.0)
    }

    func testEveryStageHasPlainWordsAndAnIcon() {
        for stage in BuildJob.Stage.allCases {
            XCTAssertFalse(stage.label.isEmpty)
            XCTAssertFalse(stage.humanCopy.isEmpty)
            XCTAssertFalse(stage.systemImage.isEmpty)
            XCTAssertFalse(stage.label.contains("IPA"), "jargon in \(stage)")
        }
    }

    func testSavedJobsSurviveEncoding() throws {
        let job = BuildJob(description: AppDescription(title: "Tide Times", prompt: "tides", features: ["a"]), stage: .linting)
        let decoded = try JSONDecoder().decode(BuildJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(decoded, job)
        XCTAssertEqual(BuildJob.Stage(rawValue: "Building IPA"), .buildingIPA, "raw values are persisted and must not change")
    }
}
