import Foundation

// MARK: - Diagnostics

/// What actually happened the last time a source was asked for data.
///
/// Without this the app cannot tell "connected and quiet" apart from
/// "silently failing", and the Data Sources screen was reporting a
/// source as LIVE purely because an API key string was non-empty.
struct SocialSourceDiagnostics: Hashable {
    var name: String
    var configured: Bool
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var moviesCovered: Int
    var lastError: String?
    /// Set when the provider reported a quota / rate limit rejection.
    /// Distinct from a generic failure because the fix is different.
    var quotaExhausted: Bool

    init(name: String, configured: Bool = false, lastAttemptAt: Date? = nil,
         lastSuccessAt: Date? = nil, moviesCovered: Int = 0,
         lastError: String? = nil, quotaExhausted: Bool = false) {
        self.name = name
        self.configured = configured
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.moviesCovered = moviesCovered
        self.lastError = lastError
        self.quotaExhausted = quotaExhausted
    }

    /// One line for the Data Sources screen, describing reality rather
    /// than configuration.
    var statusLine: String {
        if !configured { return "Not configured." }
        if quotaExhausted { return "Daily API quota exhausted — resumes tomorrow." }
        if let err = lastError { return "Last attempt failed: \(err)" }
        if lastSuccessAt != nil {
            return "Connected — \(moviesCovered) title\(moviesCovered == 1 ? "" : "s") covered on the last pull."
        }
        if lastAttemptAt != nil { return "Configured, no successful pull yet." }
        return "Configured, not yet queried."
    }

    var isHealthy: Bool {
        configured && lastSuccessAt != nil && lastError == nil && !quotaExhausted
    }
}

// MARK: - Protocol

/// Anything that can produce a social signal for a movie.
protocol SocialSignalSource {
    func signal(for movie: Movie) async -> SocialSignal?

    /// Fetch for a whole slate at once.
    ///
    /// The default walks the list one movie at a time. Sources that can
    /// genuinely batch — YouTube can price 50 videos in a single request
    /// — override this, which is the difference between the catalog
    /// costing 1 API unit per refresh and costing thousands.
    func signals(for movies: [Movie]) async -> [String: SocialSignal]

    func diagnostics() async -> SocialSourceDiagnostics
}

extension SocialSignalSource {
    func signals(for movies: [Movie]) async -> [String: SocialSignal] {
        var out: [String: SocialSignal] = [:]
        for movie in movies {
            if let signal = await signal(for: movie) { out[movie.id] = signal }
        }
        return out
    }

    func diagnostics() async -> SocialSourceDiagnostics {
        SocialSourceDiagnostics(name: "Unknown source")
    }
}

// MARK: - Trailer view-curve model

enum TrailerViewCurve {
    /// Trailer views are heavily front-loaded. Model the cumulative
    /// curve as a saturating exponential with a 21-day time constant:
    ///
    ///     cumulative(t) ∝ 1 - exp(-t / tau)
    ///
    /// and take the trailing week as the slice between `age` and
    /// `age - 7`, as a fraction of everything accumulated so far.
    ///
    /// A video 7 days old or younger returns 1.0 — all of its views
    /// happened inside the window. A six-month-old trailer returns
    /// close to zero, which is correct: it is not driving this week's
    /// conversation no matter how large its lifetime count is.
    static func trailingWeekFraction(ageDays: Double, tau: Double = 21) -> Double {
        guard ageDays > 7 else { return 1 }
        func cumulative(_ t: Double) -> Double { 1 - exp(-max(0, t) / tau) }
        let total = cumulative(ageDays)
        guard total > 1e-9 else { return 1 }
        return max(0, min(1, (total - cumulative(ageDays - 7)) / total))
    }

    /// Trailing-7-day views from a lifetime count plus a publish date.
    static func trailingWeekViews(lifetime: Int, publishedAt: Date?,
                                  now: Date = Date()) -> Int {
        guard let publishedAt else {
            // No publish date means no way to age-adjust. Rather than
            // pretend a lifetime count is a weekly one, treat it as a
            // month-old video — the median case for a marketing trailer.
            return Int(Double(lifetime) * trailingWeekFraction(ageDays: 30))
        }
        let age = now.timeIntervalSince(publishedAt) / 86_400
        return Int(Double(lifetime) * trailingWeekFraction(ageDays: age))
    }
}

// MARK: - Trailer id cache

/// Persists the resolved YouTube video id for each movie.
///
/// A `search.list` call costs 100 quota units against a 10,000/day
/// default; `videos.list` costs 1 regardless of how many ids it prices.
/// A trailer's video id never changes, so searching for it more than
/// once per movie is pure waste — and re-searching the whole catalog on
/// every pull-to-refresh exhausted the day's quota in a handful of taps.
struct TrailerIDCache {
    private let defaults: UserDefaults
    private let idsKey = "boxcall.trailerVideoIds"
    private let missesKey = "boxcall.trailerLookupMisses"
    /// How long to wait before re-searching for a movie we failed to
    /// match. Stops unmatched titles from burning 100 units per refresh.
    private let missBackoff: TimeInterval = 7 * 86_400

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func videoId(for movieId: String) -> String? {
        (defaults.dictionary(forKey: idsKey) as? [String: String])?[movieId]
    }

    func store(videoId: String, for movieId: String) {
        var map = (defaults.dictionary(forKey: idsKey) as? [String: String]) ?? [:]
        map[movieId] = videoId
        defaults.set(map, forKey: idsKey)
    }

    /// True when we looked recently, found nothing, and should not spend
    /// another search on this movie yet.
    func isInMissBackoff(_ movieId: String, now: Date = Date()) -> Bool {
        guard let map = defaults.dictionary(forKey: missesKey) as? [String: Double],
              let at = map[movieId] else { return false }
        return now.timeIntervalSince1970 - at < missBackoff
    }

    func recordMiss(for movieId: String, now: Date = Date()) {
        var map = (defaults.dictionary(forKey: missesKey) as? [String: Double]) ?? [:]
        map[movieId] = now.timeIntervalSince1970
        defaults.set(map, forKey: missesKey)
    }

    func forget(movieId: String) {
        var map = (defaults.dictionary(forKey: idsKey) as? [String: String]) ?? [:]
        map.removeValue(forKey: movieId)
        defaults.set(map, forKey: idsKey)
    }
}

// MARK: - Trailer matching

enum TrailerMatcher {
    /// Words that appear in almost every movie title and carry no
    /// identifying power when matching a search result.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "of", "and", "part", "chapter", "movie", "film"
    ]

    static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    /// Is this search hit plausibly the official trailer for this movie?
    ///
    /// Taking the top result on faith meant a reaction video, a fan edit,
    /// or an unrelated film with a similar name could silently become the
    /// engagement number that prices the chain.
    static func isPlausibleTrailer(videoTitle: String,
                                   channelTitle: String,
                                   movieTitle: String) -> Bool {
        let video = videoTitle.lowercased()
        // Must actually present as a trailer.
        guard video.contains("trailer") || video.contains("teaser") else { return false }

        // Reject the formats that reliably are not the trailer itself.
        let disqualifiers = ["reaction", "review", "breakdown", "explained",
                             "concept", "fan made", "fan-made", "recut",
                             "parody", "how to", "ranking"]
        if disqualifiers.contains(where: { video.contains($0) }) { return false }

        // Most of the distinctive words in the movie title should appear.
        let wanted = tokens(movieTitle)
        guard !wanted.isEmpty else { return false }
        let found = Set(tokens(videoTitle)).union(tokens(channelTitle))
        let hits = wanted.filter { found.contains($0) }.count
        return Double(hits) / Double(wanted.count) >= 0.6
    }
}

// MARK: - YouTube (free official API)

/// YouTube Data API v3. Free tier, official.
///
/// Resolves each movie's trailer video id once (cached permanently, then
/// verified for relevance), and prices the whole slate's statistics in a
/// single batched request. Reports real 7-day view estimates rather than
/// lifetime counts, and engagement rate rather than a like ratio the API
/// stopped being able to provide in 2021.
///
/// Configure by setting YOUTUBE_API_KEY in Info.plist.
actor YouTubeSignalSource: SocialSignalSource {
    private let apiKey: String
    private let session: URLSession
    private let cache: TrailerIDCache
    private let searchBase = URL(string: "https://www.googleapis.com/youtube/v3/search")!
    private let videosBase = URL(string: "https://www.googleapis.com/youtube/v3/videos")!

    /// YouTube prices up to 50 ids per `videos.list` call.
    private let batchSize = 50
    /// Ceiling on `search.list` calls per pull. Each costs 100 units of a
    /// 10,000/day default quota, so an uncapped cold start across a large
    /// catalog would spend the whole day's budget in one refresh.
    private let maxSearchesPerPull = 8

    private var diag: SocialSourceDiagnostics

    init(apiKey: String,
         session: URLSession = .shared,
         cache: TrailerIDCache = TrailerIDCache()) {
        self.apiKey = apiKey
        self.session = session
        self.cache = cache
        self.diag = SocialSourceDiagnostics(name: "YouTube Data API v3",
                                            configured: !apiKey.isEmpty)
    }

    func diagnostics() async -> SocialSourceDiagnostics { diag }

    func signal(for movie: Movie) async -> SocialSignal? {
        await signals(for: [movie])[movie.id]
    }

    func signals(for movies: [Movie]) async -> [String: SocialSignal] {
        guard !apiKey.isEmpty, !movies.isEmpty else { return [:] }
        diag.lastAttemptAt = Date()
        diag.lastError = nil

        // 1. Resolve video ids, spending searches only on cache misses
        // and only up to the per-pull ceiling.
        var idByMovie: [String: String] = [:]
        var searchesSpent = 0
        for movie in movies {
            if let cached = cache.videoId(for: movie.id) {
                idByMovie[movie.id] = cached
                continue
            }
            guard searchesSpent < maxSearchesPerPull,
                  !cache.isInMissBackoff(movie.id) else { continue }
            searchesSpent += 1
            if let found = await resolveTrailerId(for: movie) {
                cache.store(videoId: found, for: movie.id)
                idByMovie[movie.id] = found
            } else {
                cache.recordMiss(for: movie.id)
            }
            if diag.quotaExhausted { break }
        }
        guard !idByMovie.isEmpty else {
            if diag.lastError == nil && !diag.quotaExhausted {
                diag.lastSuccessAt = Date()
                diag.moviesCovered = 0
            }
            return [:]
        }

        // 2. Price every resolved id in batches of 50 — one unit each.
        var statsById: [String: YTVideoStats] = [:]
        let allIds = Array(idByMovie.values)
        for chunk in stride(from: 0, to: allIds.count, by: batchSize) {
            let slice = Array(allIds[chunk..<min(chunk + batchSize, allIds.count)])
            let fetched = await stats(forIds: slice)
            statsById.merge(fetched) { a, _ in a }
            if diag.quotaExhausted { break }
        }

        // 3. Build one signal per movie we actually have numbers for.
        var out: [String: SocialSignal] = [:]
        let now = Date()
        for (movieId, videoId) in idByMovie {
            guard let s = statsById[videoId], let views = s.viewCount, views > 0 else { continue }
            let weekly = TrailerViewCurve.trailingWeekViews(
                lifetime: views, publishedAt: s.publishedAt, now: now)
            let engagement = s.likeCount.map { Double($0) / Double(views) }
            out[movieId] = SocialSignal(
                youtubeTrailerViews7d: weekly,
                youtubeEngagementRate: engagement,
                // Left nil on purpose: this source knows nothing about X,
                // and claiming zero mentions would read as a bearish fact.
                socialMentions24h: nil,
                socialSentiment: nil,
                capturedAt: now
            )
        }

        if diag.lastError == nil && !diag.quotaExhausted {
            diag.lastSuccessAt = now
        }
        diag.moviesCovered = out.count
        return out
    }

    // MARK: - Private

    private func resolveTrailerId(for movie: Movie) async -> String? {
        var comps = URLComponents(url: searchBase, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "key", value: apiKey),
            .init(name: "part", value: "snippet"),
            .init(name: "type", value: "video"),
            // Ask for a few so a bad top hit does not sink the lookup.
            .init(name: "maxResults", value: "5"),
            .init(name: "q", value: "\(movie.title) official trailer")
        ]
        guard let url = comps.url else { return nil }
        guard let data = await get(url) else { return nil }
        guard let env = try? JSONDecoder().decode(YTSearchResponse.self, from: data) else {
            diag.lastError = "Could not decode YouTube search response."
            return nil
        }
        for item in env.items {
            guard let id = item.id.videoId, let snippet = item.snippet else { continue }
            if TrailerMatcher.isPlausibleTrailer(videoTitle: snippet.title,
                                                 channelTitle: snippet.channelTitle,
                                                 movieTitle: movie.title) {
                return id
            }
        }
        return nil
    }

    private func stats(forIds ids: [String]) async -> [String: YTVideoStats] {
        guard !ids.isEmpty else { return [:] }
        var comps = URLComponents(url: videosBase, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "key", value: apiKey),
            .init(name: "part", value: "statistics,snippet"),
            .init(name: "id", value: ids.joined(separator: ","))
        ]
        guard let url = comps.url, let data = await get(url) else { return [:] }
        guard let env = try? JSONDecoder().decode(YTVideosResponse.self, from: data) else {
            diag.lastError = "Could not decode YouTube statistics response."
            return [:]
        }
        var out: [String: YTVideoStats] = [:]
        for item in env.items {
            out[item.id] = YTVideoStats(
                viewCount: item.statistics?.viewCount,
                likeCount: item.statistics?.likeCount,
                publishedAt: item.snippet?.publishedAtDate
            )
        }
        return out
    }

    /// Single place where HTTP errors are classified, so a quota
    /// rejection never looks like "no data".
    private func get(_ url: URL) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, resp) = try await session.data(for: request)
            guard let http = resp as? HTTPURLResponse else {
                diag.lastError = "Unexpected response type."
                return nil
            }
            switch http.statusCode {
            case 200..<300:
                return data
            case 403:
                // YouTube returns 403 for both quota exhaustion and a bad
                // key; the body distinguishes them.
                let body = String(data: data, encoding: .utf8) ?? ""
                if body.contains("quotaExceeded") || body.contains("rateLimitExceeded") {
                    diag.quotaExhausted = true
                    diag.lastError = "Daily quota exceeded."
                } else {
                    diag.lastError = "Access denied — check YOUTUBE_API_KEY."
                }
                return nil
            case 429:
                diag.quotaExhausted = true
                diag.lastError = "Rate limited."
                return nil
            default:
                diag.lastError = "HTTP \(http.statusCode)."
                return nil
            }
        } catch {
            diag.lastError = error.localizedDescription
            return nil
        }
    }
}

// MARK: - YouTube wire types

private struct YTVideoStats {
    let viewCount: Int?
    let likeCount: Int?
    let publishedAt: Date?
}

private struct YTSearchResponse: Decodable {
    struct Item: Decodable {
        let id: VideoIdWrap
        let snippet: Snippet?
    }
    struct VideoIdWrap: Decodable { let videoId: String? }
    struct Snippet: Decodable {
        let title: String
        let channelTitle: String
    }
    let items: [Item]
}

private struct YTVideosResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let statistics: YTStatistics?
        let snippet: YTSnippet?
    }
    let items: [Item]
}

private struct YTSnippet: Decodable {
    let publishedAt: String?
    /// YouTube publishes RFC 3339 timestamps.
    var publishedAtDate: Date? {
        guard let publishedAt else { return nil }
        return YTSnippet.formatter.date(from: publishedAt)
            ?? YTSnippet.fallbackFormatter.date(from: publishedAt)
    }
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

/// YouTube reports counts as strings. A missing count means "hidden by
/// the uploader", which is not zero — hence the optionals.
private struct YTStatistics: Decodable {
    let viewCount: Int?
    let likeCount: Int?
    enum CodingKeys: String, CodingKey { case viewCount, likeCount }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viewCount = (try c.decodeIfPresent(String.self, forKey: .viewCount)).flatMap(Int.init)
        likeCount = (try c.decodeIfPresent(String.self, forKey: .likeCount)).flatMap(Int.init)
    }
}

// MARK: - BoxCall published API (static JSON on GitHub Pages)

/// Crowd chatter for the whole slate, read from the published BoxCall
/// data set.
///
/// The original design proxied X through a server. That can never be
/// free: X discontinued its free tier in February 2026 and now bills per
/// post read. This source instead reads a static JSON document that a
/// scheduled GitHub Action builds from Bluesky's public API — which
/// needs no key, no account, and no approval — scores with VADER, and
/// publishes to GitHub Pages. Actions is unmetered on public
/// repositories and Pages serves from a CDN, so the whole path costs
/// nothing at any volume this app will reach.
///
/// One request covers every movie, so adding titles does not add
/// requests.
actor BoxCallAPISource: SocialSignalSource {
    private let baseURL: URL
    private let session: URLSession
    private var diag = SocialSourceDiagnostics(name: "BoxCall published API",
                                               configured: true)

    /// Cached document plus when it was fetched. The upstream job runs
    /// every few hours, so re-fetching more often than that is waste.
    private var cached: [String: Wire]?
    private var cachedAt: Date?
    private let freshness: TimeInterval = 30 * 60

    init(baseURL: URL = Config.dataAPIBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func diagnostics() async -> SocialSourceDiagnostics { diag }

    func signal(for movie: Movie) async -> SocialSignal? {
        await signals(for: [movie])[movie.id]
    }

    func signals(for movies: [Movie]) async -> [String: SocialSignal] {
        guard let document = await document() else { return [:] }

        var out: [String: SocialSignal] = [:]
        for movie in movies {
            guard let wire = document[movie.id] ?? matchByTitle(movie, in: document) else {
                continue
            }
            let signal = wire.asSignal()
            if signal.hasAnyData { out[movie.id] = signal }
        }
        diag.moviesCovered = out.count
        return out
    }

    // MARK: - Private

    /// The published catalog is keyed by the id the pipeline assigned.
    /// A locally-seeded movie will not match, so fall back to title.
    private func matchByTitle(_ movie: Movie, in document: [String: Wire]) -> Wire? {
        let wanted = movie.title.lowercased()
        return document.values.first { $0.title?.lowercased() == wanted }
    }

    private func document() async -> [String: Wire]? {
        if let cached, let cachedAt, Date().timeIntervalSince(cachedAt) < freshness {
            return cached
        }
        diag.lastAttemptAt = Date()

        let url = baseURL.appendingPathComponent("signals.json")
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            // The document is rebuilt on a schedule; let the URL cache
            // revalidate rather than re-download an unchanged payload.
            request.cachePolicy = .useProtocolCachePolicy
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                diag.lastError = "Unexpected response type."
                return cached
            }
            guard (200..<300).contains(http.statusCode) else {
                diag.lastError = "HTTP \(http.statusCode)."
                // Serve stale rather than nothing: an old crowd read
                // beats pretending the crowd went silent.
                return cached
            }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            cached = envelope.signals
            cachedAt = Date()
            diag.lastSuccessAt = Date()
            diag.lastError = nil
            return envelope.signals
        } catch {
            diag.lastError = error.localizedDescription
            return cached
        }
    }

    // MARK: - Wire format

    struct Envelope: Decodable {
        let version: Int
        let generatedAt: String?
        let signals: [String: Wire]
    }

    /// Mirrors the pipeline's output. Every field is optional because
    /// the pipeline publishes null for a source that did not report,
    /// and null must survive the whole way to `SocialSignal`.
    struct Wire: Decodable {
        let title: String?
        let socialMentions24h: Int?
        let socialSentiment: Double?
        let socialDispersion: Double?
        let youtubeViews7d: Int?
        let youtubeEngagementRate: Double?

        func asSignal() -> SocialSignal {
            SocialSignal(
                youtubeTrailerViews7d: youtubeViews7d,
                youtubeEngagementRate: youtubeEngagementRate,
                socialMentions24h: socialMentions24h,
                socialSentiment: socialSentiment,
                capturedAt: Date()
            )
        }
    }
}

// MARK: - Merge multiple sources into one SocialSignal

/// Fans out to every source and unions their measurements.
///
/// A field only gets written by a source that actually measured it, so
/// merging never manufactures a value — an unreachable source leaves its
/// fields nil and the adjustment renormalizes around what is left.
final class CompositeSignalSource: SocialSignalSource {
    private let sources: [SocialSignalSource]
    init(_ sources: [SocialSignalSource]) { self.sources = sources }

    func signal(for movie: Movie) async -> SocialSignal? {
        await signals(for: [movie])[movie.id]
    }

    func signals(for movies: [Movie]) async -> [String: SocialSignal] {
        var merged: [String: SocialSignal] = [:]
        for source in sources {
            let batch = await source.signals(for: movies)
            for (movieId, signal) in batch {
                merged[movieId] = Self.union(merged[movieId], signal)
            }
        }
        return merged.filter { $0.value.hasAnyData }
    }

    func diagnostics() async -> SocialSourceDiagnostics {
        // Roll the children up into one line: healthy if anything is.
        var covered = 0
        var errors: [String] = []
        var anySuccess: Date?
        var quota = false
        for source in sources {
            let d = await source.diagnostics()
            covered = max(covered, d.moviesCovered)
            if let e = d.lastError { errors.append("\(d.name): \(e)") }
            if let s = d.lastSuccessAt, s > (anySuccess ?? .distantPast) { anySuccess = s }
            quota = quota || d.quotaExhausted
        }
        return SocialSourceDiagnostics(
            name: "Composite social",
            configured: true,
            lastAttemptAt: Date(),
            lastSuccessAt: anySuccess,
            moviesCovered: covered,
            lastError: errors.isEmpty ? nil : errors.joined(separator: " · "),
            quotaExhausted: quota
        )
    }

    /// Field-wise union. Later sources fill gaps but never overwrite a
    /// measurement an earlier source already made.
    static func union(_ lhs: SocialSignal?, _ rhs: SocialSignal) -> SocialSignal {
        guard let lhs else { return rhs }
        return SocialSignal(
            youtubeTrailerViews7d: lhs.youtubeTrailerViews7d ?? rhs.youtubeTrailerViews7d,
            youtubeEngagementRate: lhs.youtubeEngagementRate ?? rhs.youtubeEngagementRate,
            socialMentions24h: lhs.socialMentions24h ?? rhs.socialMentions24h,
            socialSentiment: lhs.socialSentiment ?? rhs.socialSentiment,
            capturedAt: max(lhs.capturedAt, rhs.capturedAt)
        )
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
        guard let unadjusted = await base.tracking(for: movie) else { return nil }
        guard let signal = await signalSource.signal(for: movie),
              signal.hasAnyData else { return unadjusted }
        let shift = signal.consensusAdjustment(genreBaseline: baseline)
        // A partial read moves the number proportionally less than a
        // complete one, so a YouTube-only signal cannot swing consensus
        // as hard as a full YouTube + X read.
        let scaled = shift * signal.coverage
        return Tracking(
            openingWeekendMillions: max(0.5, unadjusted.openingWeekendMillions * (1 + scaled)),
            impliedVolPct: max(15, unadjusted.impliedVolPct * (1 - scaled * 0.4))
        )
    }
}

// MARK: - Config wiring

extension Config {
    /// YouTube v3 API key. Falls back to empty; the YT source no-ops.
    static var youtubeAPIKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "YOUTUBE_API_KEY") as? String) ?? ""
    }

    /// Where the published data set lives.
    ///
    /// Defaults to the GitHub Pages site the repository's scheduled
    /// Action publishes to. Override with BOXCALL_API_BASE in Info.plist
    /// to point at a fork, a staging build, or a local server.
    static var dataAPIBaseURL: URL {
        let configured = (Bundle.main.object(forInfoDictionaryKey: "BOXCALL_API_BASE") as? String) ?? ""
        if !configured.isEmpty, let url = URL(string: configured) { return url }
        return URL(string: "https://mvalasek77-droid.github.io/Mike_claw/api/v1/")!
    }

    /// Stack of social signal sources.
    ///
    /// The published API comes first so its numbers win on any field
    /// both sources measure, with the client's own YouTube call filling
    /// gaps when a key is configured. Either source may report nothing;
    /// neither ever contributes a fabricated zero.
    static var socialSignalSource: SocialSignalSource {
        CompositeSignalSource([
            BoxCallAPISource(),
            YouTubeSignalSource(apiKey: youtubeAPIKey)
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
