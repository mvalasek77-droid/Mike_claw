import Foundation

/// Every toggleable feature in MetaBro. Add a case here, default it in
/// `FeatureFlags`, then guard any experimental entry-point with
/// `flagService.isEnabled(.yourFlag)` — the live impl reads from a bundled
/// plist so flags can be updated without an App Store submission.
enum FeatureFlag: String, CaseIterable, Sendable {
    case marketplace
    case groups
    case events
    case liveActivity     // Live Activities (future target)
    case widgets          // Widget extension (future target)
    case algorithmFeedV2  // A/B: experimental ranking pass
}

/// Default values for every flag — change here for staged rollout in the
/// bundled plist (`FeatureFlags.plist`) without touching source.
struct FeatureFlags: Sendable {
    var marketplace: Bool      = true
    var groups: Bool           = true
    var events: Bool           = true
    var liveActivity: Bool     = false
    var widgets: Bool          = false
    var algorithmFeedV2: Bool  = false

    subscript(_ flag: FeatureFlag) -> Bool {
        switch flag {
        case .marketplace:      marketplace
        case .groups:           groups
        case .events:           events
        case .liveActivity:     liveActivity
        case .widgets:          widgets
        case .algorithmFeedV2:  algorithmFeedV2
        }
    }
}

/// Read-only flag evaluator — always synchronous so view code can gate
/// without async dispatches or state delay.
protocol FeatureFlagService: Sendable {
    func isEnabled(_ flag: FeatureFlag) -> Bool
}

/// In-memory flags for previews, tests, and offline demo. Enables every
/// shipped flag, disables future-targeted ones (matching the production
/// plist defaults).
struct MockFeatureFlagService: FeatureFlagService {
    var flags: FeatureFlags

    init(flags: FeatureFlags = FeatureFlags()) {
        self.flags = flags
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool { flags[flag] }
}

/// Reads flags from `FeatureFlags.plist` in the main bundle, falling back to
/// the hardcoded defaults in `FeatureFlags`. CI can swap the plist to test
/// different flag configurations without code changes.
struct LiveFeatureFlagService: FeatureFlagService {
    private let flags: FeatureFlags

    init() {
        guard let url = Bundle.main.url(forResource: "FeatureFlags", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Bool] else {
            self.flags = FeatureFlags()
            return
        }
        var f = FeatureFlags()
        for flag in FeatureFlag.allCases {
            if let value = dict[flag.rawValue] {
                switch flag {
                case .marketplace:      f.marketplace      = value
                case .groups:           f.groups           = value
                case .events:           f.events           = value
                case .liveActivity:     f.liveActivity     = value
                case .widgets:          f.widgets          = value
                case .algorithmFeedV2:  f.algorithmFeedV2  = value
                }
            }
        }
        self.flags = f
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool { flags[flag] }
}
