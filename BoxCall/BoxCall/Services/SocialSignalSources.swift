import Foundation

/// Anything that can produce a social signal for a movie.
protocol SocialSignalSource {
    func signal(for movie: Movie) async -> SocialSignal?
}

// MARK: - YouTube (free official API)

/// YouTube Data API v3. Free tier, official.
/// Strategy: search for `"<title> trailer"`, take the top result, then
/// fetch its statistics (views + likes). Real production would also
/// batch-fetch multiple trailers per title.
///
/// Configure by setting YOUTUBE_API_KEY in Info.plist.
final class YouTubeSignalSource: SocialSignalSource {
    private let apiKey: String
    private let session: URLSession
    private let searchBase = URL(string: "https://www.googleapis.com/youtube/v3/search")!
    private let videosBase = URL(string: "https://www.googleapis.com/youtube/v3/videos")!

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func signal(for movie: Movie) async -> SocialSignal? {
        guard !apiKey.isEmpty else { return nil }
        guard let videoId = await topTrailerVideoId(for: movie) else { return nil }
        guard let stats = await stats(for: videoId) else { return nil }

        // 7-day estimate: YouTube stats are cumulative. As a crude proxy,
        // scale by (7 / age-in-days) when we know publish date; else use
        // the full cumulative view count with a cap.
        let viewCount = stats.viewCount ?? 0
        let likes = stats.likeCount ?? 0
        let ratio: Double? = likes > 0 ? Double(likes) / Double(likes + max(1, likes / 10)) : nil

        return SocialSignal(
            youtubeTrailerViews7d: min(viewCount, 100_000_000),
            youtubeLikeRatio: ratio,
            xMentions24h: 0,       // filled by XSignalSource
            xSentiment: 0,         // filled by XSignalSource
            capturedAt: Date()
        )
    }

    // MARK: - Private

    private func topTrailerVideoId(for movie: Movie) async -> String? {
        var comps = URLComponents(url: searchBase, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "key", value: apiKey),
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            .init(name: "maxResults", value: "1"),
            .init(name: "q", value: "\(movie.title) official trailer")
        ]
        guard let url = comps.url else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let env = try JSONDecoder().decode(YTSearchResponse.self, from: data)
            return env.items.first?.id.videoId
        } catch {
            return nil
        }
    }

    private func stats(for videoId: String) async -> YTStatistics? {
        var comps = URLComponents(url: videosBase, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "key", value: apiKey),
            .init(name: "part", value: "statistics"),
            .init(name: "id", value: videoId)
        ]
        guard let url = comps.url else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let env = try JSONDecoder().decode(YTVideosResponse.self, from: data)
            return env.items.first?.statistics
        } catch {
            return nil
        }
    }
}

private struct YTSearchResponse: Decodable {
    struct Item: Decodable { let id: VideoIdWrap }
    struct VideoIdWrap: Decodable { let videoId: String? }
    let items: [Item]
}
private struct YTVideosResponse: Decodable {
    struct Item: Decodable { let statistics: YTStatistics? }
    let items: [Item]
}
private struct YTStatistics: Decodable {
    let viewCount: Int?
    let likeCount: Int?
    enum CodingKeys: String, CodingKey { case viewCount, likeCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viewCount = Int(try c.decodeIfPresent(String.self, forKey: .viewCount) ?? "0")
        likeCount = Int(try c.decodeIfPresent(String.self, forKey: .likeCount) ?? "0")
    }
}

// MARK: - X / Twitter (paid API, stubbed)

/// X API v2 recent-tweets counts endpoint. Requires paid X API tier.
/// Stubbed to always return nil so the pipeline falls through — real
/// production goes through the backend, which holds the paid key.
final class XSignalSource: SocialSignalSource {
    let backendURL: URL
    let session: URLSession
    init(backendURL: URL = URL(string: "https://api.boxcall.com/x-signal")!,
         session: URLSession = .shared) {
        self.backendURL = backendURL
        self.session = session
    }

    func signal(for movie: Movie) async -> SocialSignal? {
        var comps = URLComponents(url: backendURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "title", value: movie.title)]
        guard let url = comps.url else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            struct Payload: Decodable { let mentions24h: Int; let sentiment: Double }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return SocialSignal(
                youtubeTrailerViews7d: 0,
                youtubeLikeRatio: nil,
                xMentions24h: payload.mentions24h,
                xSentiment: payload.sentiment,
                capturedAt: Date()
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Merge multiple sources into one SocialSignal

/// Fans out to every source, merges non-nil fields, returns the union.
final class CompositeSignalSource: SocialSignalSource {
    private let sources: [SocialSignalSource]
    init(_ sources: [SocialSignalSource]) { self.sources = sources }

    func signal(for movie: Movie) async -> SocialSignal? {
        var merged: SocialSignal?
        for s in sources {
            guard let sig = await s.signal(for: movie) else { continue }
            if merged == nil {
                merged = sig
            } else {
                merged?.youtubeTrailerViews7d = max(merged?.youtubeTrailerViews7d ?? 0, sig.youtubeTrailerViews7d)
                merged?.youtubeLikeRatio = merged?.youtubeLikeRatio ?? sig.youtubeLikeRatio
                merged?.xMentions24h = max(merged?.xMentions24h ?? 0, sig.xMentions24h)
                if merged?.xSentiment == 0 { merged?.xSentiment = sig.xSentiment }
                merged?.capturedAt = Date()
            }
        }
        return merged
    }
}

// MARK: - TrackingDataSource wrapper that applies the signal

/// Takes any base TrackingDataSource and shifts its consensus by the
/// SocialSignal's adjustment. IV moves too — bullish crowds usually
/// tighten IV; bearish ones widen it.
final class SocialSignalTrackingSource: TrackingDataSource {
    let base: TrackingDataSource
    let signalSource: SocialSignalSource
    let baseline: SignalBaseline

    init(base: TrackingDataSource,
         signalSource: SocialSignalSource,
         baseline: SignalBaseline = .generic) {
        self.base = base
        self.signalSource = signalSource
        self.baseline = baseline
    }

    func tracking(for movie: Movie) async -> Tracking? {
        guard var base = await base.tracking(for: movie) else { return nil }
        guard let signal = await signalSource.signal(for: movie) else { return base }
        let shift = signal.consensusAdjustment(genreBaseline: baseline)
        base = Tracking(
            openingWeekendMillions: max(0.5, base.openingWeekendMillions * (1 + shift)),
            // IV widens when the crowd is uncertain (shift near zero and
            // low absolute magnitude) or bearish; tightens with strong
            // positive shift.
            impliedVolPct: max(15, base.impliedVolPct * (1 - shift * 0.4))
        )
        return base
    }
}

// MARK: - Config wiring

extension Config {
    /// YouTube v3 API key. Falls back to empty; the YT source no-ops.
    static var youtubeAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "YOUTUBE_API_KEY") as? String) ?? ""
    }

    /// Stack of social signal sources. Sources with no key gracefully
    /// return nil so they never block the pipeline.
    static var socialSignalSource: SocialSignalSource {
        CompositeSignalSource([
            YouTubeSignalSource(apiKey: youtubeAPIKey),
            XSignalSource()
        ])
    }

    /// Tracking stack with social-signal enrichment layered over the
    /// backend + algorithmic fallback we already had.
    static var enrichedTrackingSource: TrackingDataSource {
        SocialSignalTrackingSource(
            base: trackingSource,
            signalSource: socialSignalSource
        )
    }
}
