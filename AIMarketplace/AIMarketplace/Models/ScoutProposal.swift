import Foundation

/// A Scout-composed candidate awaiting admin authorization. Scout never
/// produces unilaterally any more — every prospective release surfaces here
/// with its estimated budget (tokens + USD), the recipe and masters it would
/// draw on, and which provider it needs. The admin reviews and authorizes
/// each one; only authorized proposals enter the Editor-gated production
/// loop. Persisted across launches via UserDefaults so a closed app doesn't
/// lose your queue.
struct ScoutProposal: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date

    // What Scout wants to make.
    let type: MediaType
    let layerRaw: String         // "commercial" / "experimental" / "niche"
    let title: String
    let creator: String          // the AI model assigned as creator-of-record
    let genre: String
    let recipeID: String?
    let recipeFormula: String
    let recipeMasters: [String]
    let experimental: Bool

    // The budget Scout reveals up front.
    let estimatedTokens: Int     // Foundation Model tokens, approx (words × 1.33)
    let estimatedUSD: Double     // External-provider spend, 0 for Foundation-only
    let providerNeeded: Provider // foundation / musicGen / videoGen
    let providerAvailable: Bool

    // Lifecycle.
    var status: Status = .pending
    var publishedItemID: UUID? = nil
    var editorScore: Int? = nil
    var statusNote: String = ""
    var resolvedAt: Date? = nil
    /// Actual Foundation-Model tokens used (counted from the generated text
    /// after production). Populated when the proposal reaches `.produced` or
    /// `.editorRejected`. The pre-production `estimatedTokens` stays as a
    /// reference so deviations are visible.
    var actualTokens: Int? = nil
    /// Actual USD spent at the external provider, if any. Foundation-only
    /// proposals stay at 0. Populated by the Worker's spend tracking.
    var actualUSD: Double? = nil

    enum Status: String, Codable, Hashable {
        case pending           // waiting on admin authorization
        case authorized        // admin approved; production in flight
        case produced          // Editor passed; published live
        case editorRejected    // production ran but Editor didn't pass
        case declined          // admin declined
    }

    enum Provider: String, Codable, Hashable {
        case foundation        // on-device Apple FoundationModels — free
        case musicGen          // external audio generation API (paid)
        case videoGen          // external video generation API (paid)

        var displayName: String {
            switch self {
            case .foundation: return "Foundation Model"
            case .musicGen:   return "Music generation API"
            case .videoGen:   return "Video generation API"
            }
        }

        var isFree: Bool { self == .foundation }
    }

    /// Default Provider given the medium + whether the operator wired an
    /// external generation provider. Novels are always Foundation-only.
    static func provider(for type: MediaType, externalConfigured: Bool) -> Provider {
        switch type {
        case .novel: return .foundation
        case .music: return externalConfigured ? .musicGen : .foundation
        case .movie: return externalConfigured ? .videoGen : .foundation
        }
    }
}
