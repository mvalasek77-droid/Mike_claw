import Testing
@testable import MetaBro

/// Coverage for the feature-flag gate: default values, custom overrides, and
/// the subscript accessor — ensuring flags can be individually toggled for A/B
/// tests without touching production code paths.
struct FeatureFlagTests {

    @Test func defaultFlagsEnableShippedFeatures() {
        let service = MockFeatureFlagService()
        #expect(service.isEnabled(.marketplace))
        #expect(service.isEnabled(.groups))
        #expect(service.isEnabled(.events))
    }

    @Test func defaultFlagsDisableFutureTargets() {
        let service = MockFeatureFlagService()
        #expect(!service.isEnabled(.liveActivity))
        #expect(!service.isEnabled(.widgets))
    }

    @Test func defaultFlagsDisableExperiments() {
        let service = MockFeatureFlagService()
        #expect(!service.isEnabled(.algorithmFeedV2))
    }

    @Test func customFlagsOverrideDefaults() {
        var flags = FeatureFlags()
        flags.marketplace = false
        flags.algorithmFeedV2 = true
        let service = MockFeatureFlagService(flags: flags)

        #expect(!service.isEnabled(.marketplace))
        #expect(service.isEnabled(.algorithmFeedV2))
        // others unchanged
        #expect(service.isEnabled(.groups))
    }

    @Test func allCasesAreAccessibleViaSubscript() {
        let flags = FeatureFlags()
        // Ensure the subscript doesn't crash for any case
        for flag in FeatureFlag.allCases {
            let _ = flags[flag]
        }
    }
}
