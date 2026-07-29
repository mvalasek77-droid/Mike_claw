import Foundation

/// Which of the two App Store listings this binary is. Set at build time by
/// the `LITE` compilation condition (`PromptCoachLite` target in
/// project.yml) — never a runtime toggle, so there is no code path that
/// could accidentally unlock the paid tier for free.
///
/// Two apps, one codebase, no IAP: Prompt Coach Lite is free with a small,
/// fixed feature set; Prompt Coach is the one-time-purchase full app. This
/// is what "no in-app purchases, no subscriptions" (see LegalText) actually
/// means in practice — the upgrade is a separate App Store listing, not a
/// paywall inside this binary.
enum AppTier {
    #if LITE
    static let isLite = true
    #else
    static let isLite = false
    #endif

    /// Models the free tier can coach against. Deliberately two of five —
    /// enough to prove the "prompt each model correctly" premise without
    /// giving away the guidance for the frontier models, which is the paid
    /// app's core content.
    static let liteModelIDs: Set<String> = ["claude-haiku-4-5", "claude-sonnet-5"]

    /// Fallback when a Lite build ends up with a locked model selected
    /// (a stale recommendation, a pack update). Must be a member of
    /// `liteModelIDs` — enforced by a contract test, not just this comment.
    static let liteFallbackModelID = "claude-sonnet-5"

    /// Placeholder — replace with the real App Store listing before
    /// submission. Pointing this at a live listing is a release blocker,
    /// not a nice-to-have: an upsell link that 404s is a worse experience
    /// than no upsell at all.
    static let paidAppStoreURL = URL(string: "https://apps.apple.com/app/id0000000000")!
}
