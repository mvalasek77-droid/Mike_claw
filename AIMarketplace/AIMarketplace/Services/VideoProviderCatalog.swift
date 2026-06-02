import Foundation

/// Catalog of external video-generation providers Scout can route film scenes
/// through, with rough per-scene cost estimates so the admin can pick a
/// budget that actually makes a 30-min film achievable. Real numbers — keep
/// them honest as provider pricing shifts.
///
/// Each provider exposes an HTTP API the Worker can call. The app never holds
/// the key; the Worker proxies. "available" reflects whether the Worker has
/// the corresponding env var set (surfaced via `/scout/providers`).
struct VideoProvider: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    /// Approximate USD cost for one 2–5 minute scene at the provider's standard
    /// quality, stitched from per-clip generations. Real ballparks as of 2026:
    let costPerSceneUSD: Double
    /// Max contiguous clip length the provider returns. Scenes longer than
    /// this require multiple generations stitched together (which is why the
    /// per-scene cost above already accounts for stitching).
    let maxClipSeconds: Int
    /// Strengths the admin should weigh — choreography, photoreal, anime, etc.
    let strengths: [String]

    static let catalog: [VideoProvider] = [
        VideoProvider(id: "runway-gen4",
                       displayName: "Runway Gen-4",
                       costPerSceneUSD: 9.00,
                       maxClipSeconds: 10,
                       strengths: ["Photoreal", "Camera control", "Fast turn-around"]),
        VideoProvider(id: "luma-dream-machine",
                       displayName: "Luma Dream Machine",
                       costPerSceneUSD: 7.20,
                       maxClipSeconds: 5,
                       strengths: ["Stylised", "Cheap", "Strong motion"]),
        VideoProvider(id: "pika-2",
                       displayName: "Pika 2.0",
                       costPerSceneUSD: 10.80,
                       maxClipSeconds: 10,
                       strengths: ["Lipsync", "Effects layer", "Image-to-video"]),
        VideoProvider(id: "kling-2",
                       displayName: "Kling 2.0",
                       costPerSceneUSD: 5.40,
                       maxClipSeconds: 10,
                       strengths: ["Cheapest", "Asian-aesthetic strong", "Good for action"]),
        VideoProvider(id: "veo-3",
                       displayName: "Google Veo 3",
                       costPerSceneUSD: 72.00,
                       maxClipSeconds: 60,
                       strengths: ["Photoreal", "Native audio", "Longest clips"]),
        VideoProvider(id: "sora-turbo",
                       displayName: "OpenAI Sora",
                       costPerSceneUSD: 27.00,
                       maxClipSeconds: 20,
                       strengths: ["Best narrative coherence", "World consistency"]),
    ]

    static func find(_ id: String) -> VideoProvider? { catalog.first { $0.id == id } }
}

/// Tells the admin (in plain English) whether a budget can produce a full
/// 30-min Scout film today, with which provider, and at what cost.
struct FilmFeasibility: Equatable {
    enum Verdict: Equatable {
        /// $0 budget — screenplay-only films, no real video.
        case onDeviceOnly
        /// Budget covers a full 30+ min film via one of the providers.
        case feasible(provider: VideoProvider, scenes: Int, runtimeMinutes: Int, totalCostUSD: Double)
        /// Budget covers some scenes but not a full 30-min cut.
        case partial(provider: VideoProvider, scenes: Int, runtimeMinutes: Int, totalCostUSD: Double, shortfallUSD: Double)
        /// Even the cheapest provider can't fit a single scene.
        case insufficient(needAtLeastUSD: Double, cheapestProvider: VideoProvider)
    }
    let budgetUSD: Double
    let verdict: Verdict
    let summary: String   // user-facing one-liner
    let detail: String    // longer explanation
}

extension VideoProvider {
    /// Scenes a budget can afford at this provider, given a target scene count.
    func scenesAffordable(budget: Double) -> Int { Int(budget / costPerSceneUSD) }
}
