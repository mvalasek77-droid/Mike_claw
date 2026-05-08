import Foundation

struct EntertainmentSource: Sendable {
    let name: String
    let url: URL
    let purpose: String
}

struct EntertainmentSourceResult: Sendable {
    let source: EntertainmentSource
    let status: String
    let items: [String]
}

actor EntertainmentSourceFetcher {
    static let shared = EntertainmentSourceFetcher()

    private struct CacheEntry {
        let createdAt: Date
        let context: String
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 4 * 60

    private init() {}

    func sourceContext(for mode: CompanionExperienceMode?,
                       userQuery: String) async -> String {
        guard let mode, mode == .movieCharts || mode == .gameCharts else { return "" }

        let cacheKey = "\(mode.rawValue)::\(Self.cacheFragment(for: userQuery))"
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.createdAt) < cacheTTL {
            return cached.context
        }

        let sources = Self.sources(for: mode)
        DiagnosticsLog.info(
            "entertainment",
            "Entertainment source snapshot started.",
            details: ["mode": mode.rawValue, "sourceCount": "\(sources.count)"]
        )

        let results = await withTaskGroup(of: EntertainmentSourceResult.self,
                                          returning: [EntertainmentSourceResult].self) { group in
            for source in sources {
                group.addTask {
                    await Self.fetch(source)
                }
            }

            var gathered: [EntertainmentSourceResult] = []
            for await result in group {
                gathered.append(result)
            }
            return gathered.sorted { lhs, rhs in
                let lhsIndex = sources.firstIndex { $0.name == lhs.source.name } ?? 0
                let rhsIndex = sources.firstIndex { $0.name == rhs.source.name } ?? 0
                return lhsIndex < rhsIndex
            }
        }

        let context = Self.formatContext(mode: mode,
                                         userQuery: userQuery,
                                         results: results)
        cache[cacheKey] = CacheEntry(createdAt: Date(), context: context)
        DiagnosticsLog.info(
            "entertainment",
            "Entertainment source snapshot finished.",
            details: [
                "mode": mode.rawValue,
                "successfulSources": "\(results.filter { $0.status.hasPrefix("fetched") }.count)"
            ]
        )
        return context
    }

    private static func sources(for mode: CompanionExperienceMode) -> [EntertainmentSource] {
        switch mode {
        case .movieCharts:
            return [
                EntertainmentSource(
                    name: "Box Office Mojo Weekend",
                    url: URL(string: "https://www.boxofficemojo.com/weekend/")!,
                    purpose: "domestic weekend box office chart"
                ),
                EntertainmentSource(
                    name: "Box Office Mojo Daily",
                    url: URL(string: "https://www.boxofficemojo.com/daily/")!,
                    purpose: "daily box office chart"
                ),
                EntertainmentSource(
                    name: "Rotten Tomatoes In Theaters",
                    url: URL(string: "https://www.rottentomatoes.com/browse/movies_in_theaters")!,
                    purpose: "theatrical reviews and Tomatometer signals"
                ),
                EntertainmentSource(
                    name: "Rotten Tomatoes Streaming",
                    url: URL(string: "https://www.rottentomatoes.com/browse/movies_at_home/sort:popular")!,
                    purpose: "popular at-home movie reviews"
                ),
                EntertainmentSource(
                    name: "Metacritic Movies",
                    url: URL(string: "https://www.metacritic.com/browse/movie/")!,
                    purpose: "critic score and release context"
                )
            ]
        case .gameCharts:
            return [
                EntertainmentSource(
                    name: "Steam Top Sellers",
                    url: URL(string: "https://store.steampowered.com/search/?filter=topsellers")!,
                    purpose: "PC game sales chart"
                ),
                EntertainmentSource(
                    name: "Nintendo eShop Best Sellers",
                    url: URL(string: "https://www.nintendo.com/us/store/games/best-sellers/")!,
                    purpose: "Nintendo Switch best-seller chart"
                ),
                EntertainmentSource(
                    name: "Nintendo eShop New Releases",
                    url: URL(string: "https://www.nintendo.com/us/store/games/new-releases/")!,
                    purpose: "Nintendo Switch new release chart"
                ),
                EntertainmentSource(
                    name: "PlayStation Store Latest",
                    url: URL(string: "https://store.playstation.com/en-us/pages/latest")!,
                    purpose: "PS5/PS4 best sellers, top 10, new games, and pre-orders"
                ),
                EntertainmentSource(
                    name: "PlayStation Store Browse",
                    url: URL(string: "https://store.playstation.com/en-us/pages/browse/1")!,
                    purpose: "PlayStation Store browse catalogue for platform availability"
                ),
                EntertainmentSource(
                    name: "Xbox Store Most Played",
                    url: URL(string: "https://www.microsoft.com/en-us/store/most-played/games/xbox")!,
                    purpose: "Xbox most-played chart"
                ),
                EntertainmentSource(
                    name: "Xbox Store Top Paid",
                    url: URL(string: "https://www.microsoft.com/en-us/store/top-paid/games/xbox")!,
                    purpose: "Xbox paid game chart"
                ),
                EntertainmentSource(
                    name: "Xbox Store New Games",
                    url: URL(string: "https://www.microsoft.com/en-us/store/new/games/xbox")!,
                    purpose: "Xbox new release chart"
                ),
                EntertainmentSource(
                    name: "Metacritic Games",
                    url: URL(string: "https://www.metacritic.com/browse/game/")!,
                    purpose: "critic score and release context"
                ),
                EntertainmentSource(
                    name: "OpenCritic Browse",
                    url: URL(string: "https://opencritic.com/browse/all")!,
                    purpose: "cross-site game review aggregate"
                ),
                EntertainmentSource(
                    name: "IGN Game Reviews",
                    url: URL(string: "https://www.ign.com/reviews/games")!,
                    purpose: "major game review outlet"
                ),
                EntertainmentSource(
                    name: "GameSpot Game Reviews",
                    url: URL(string: "https://www.gamespot.com/reviews/games/")!,
                    purpose: "major game review outlet"
                )
            ]
        default:
            return []
        }
    }

    private nonisolated static func fetch(_ source: EntertainmentSource) async -> EntertainmentSourceResult {
        var request = URLRequest(url: source.url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 BareClaw/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return EntertainmentSourceResult(source: source, status: "no HTTP response", items: [])
            }
            guard (200...299).contains(http.statusCode) else {
                return EntertainmentSourceResult(source: source, status: "HTTP \(http.statusCode)", items: [])
            }

            let limitedData = Data(data.prefix(260_000))
            let html = String(decoding: limitedData, as: UTF8.self)
            let items = extractItems(from: html)
            return EntertainmentSourceResult(
                source: source,
                status: "fetched \(http.statusCode)",
                items: Array(items.prefix(12))
            )
        } catch {
            DiagnosticsLog.warning(
                "entertainment",
                "Entertainment source fetch failed.",
                details: ["source": source.name, "error": error.localizedDescription]
            )
            return EntertainmentSourceResult(source: source,
                                             status: "unavailable: \(error.localizedDescription)",
                                             items: [])
        }
    }

    private nonisolated static func formatContext(mode: CompanionExperienceMode,
                                                  userQuery: String,
                                                  results: [EntertainmentSourceResult]) -> String {
        let formatter = ISO8601DateFormatter()
        let fetchedAt = formatter.string(from: Date())
        let modeLabel = mode == .movieCharts ? "MOVIE CHARTS & REVIEWS" : "VIDEO GAME CHARTS & REVIEWS"
        let query = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryLine = query.isEmpty ? "" : "\nUser request that triggered this snapshot: \(query)"
        let rules: String
        if mode == .movieCharts {
            rules = "Movie sandbox rules: answer only movie, theater, streaming-movie, chart, release-date, and review questions in this mode. Prioritize current theatrical releases, new streaming releases, current box office, and current review sentiment. Do not rely on old memory for today's chart positions when the snapshot is available."
        } else {
            rules = "Game sandbox rules: answer only video game, console/PC, chart, new-release, platform, and review questions in this mode. Check Nintendo, PlayStation, Xbox, Steam, and review aggregators before judging what is current. Separate platform-specific chart signals from a combined recommendation."
        }

        var lines: [String] = [
            "## LIVE ENTERTAINMENT SOURCE SNAPSHOT: \(modeLabel)",
            "Fetched at: \(fetchedAt)\(queryLine)",
            rules,
            "Use this snapshot for current charts/reviews. Cite the source name and URL when using facts from it. Only state exact ranks/scores when the line clearly supports them; otherwise say the source surfaced the title but the exact rank/score was not readable. If a source is unavailable, do not invent what it would have said."
        ]

        for result in results {
            lines.append("")
            lines.append("Source: \(result.source.name)")
            lines.append("URL: \(result.source.url.absoluteString)")
            lines.append("Purpose: \(result.source.purpose)")
            lines.append("Status: \(result.status)")

            if result.items.isEmpty {
                lines.append("Extracted items: none")
            } else {
                lines.append("Extracted items:")
                for item in result.items {
                    lines.append("- \(item)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private nonisolated static func extractItems(from html: String) -> [String] {
        var candidates: [String] = []
        candidates += metaContent(named: "og:title", in: html)
        candidates += metaContent(named: "twitter:title", in: html)
        candidates += matches(
            pattern: "<title[^>]*>(.*?)</title>",
            in: html,
            group: 1,
            limit: 2
        ).map(cleanFragment)
        candidates += anchorCandidates(from: html)
        candidates += visibleLines(from: html)

        var seen = Set<String>()
        var result: [String] = []
        for candidate in candidates {
            let cleaned = cleanCandidate(candidate)
            guard isUseful(cleaned) else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cleaned)
            if result.count >= 18 { break }
        }
        return result
    }

    private nonisolated static func metaContent(named name: String, in html: String) -> [String] {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "<meta[^>]+property=[\"']\(escapedName)[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>",
            "<meta[^>]+name=[\"']\(escapedName)[\"'][^>]+content=[\"']([^\"']+)[\"'][^>]*>"
        ]
        return patterns.flatMap { pattern in
            matches(pattern: pattern, in: html, group: 1, limit: 1)
        }.map(cleanFragment)
    }

    private nonisolated static func anchorCandidates(from html: String) -> [String] {
        let relevantHrefs = [
            "boxofficemojo.com/title",
            "/title/tt",
            "rottentomatoes.com/m/",
            "/m/",
            "metacritic.com/game/",
            "metacritic.com/movie/",
            "/game/",
            "/movie/",
            "store.steampowered.com/app/",
            "/app/",
            "nintendo.com/us/store/products/",
            "nintendo.com/store/products/",
            "store.playstation.com/en-us/product/",
            "store.playstation.com/en-us/concept/",
            "microsoft.com/en-us/p/",
            "microsoft.com/store/productid/",
            "xbox.com/en-us/games/store/",
            "opencritic.com/game/",
            "ign.com/articles/",
            "gamespot.com/reviews/"
        ]

        return matches(
            pattern: "<a\\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
            in: html,
            group: 0,
            limit: 180
        ).compactMap { anchor in
            let lower = anchor.lowercased()
            guard relevantHrefs.contains(where: lower.contains) else { return nil }
            guard let text = matches(pattern: "<a\\b[^>]*>(.*?)</a>",
                                     in: anchor,
                                     group: 1,
                                     limit: 1).first else { return nil }
            return cleanFragment(text)
        }
    }

    private nonisolated static func visibleLines(from html: String) -> [String] {
        var text = html
        text = replacing(pattern: "(?is)<script\\b.*?</script>", in: text, with: " ")
        text = replacing(pattern: "(?is)<style\\b.*?</style>", in: text, with: " ")
        text = replacing(pattern: "(?is)<noscript\\b.*?</noscript>", in: text, with: " ")
        text = replacing(pattern: "(?i)</(tr|li|p|div|section|article|h1|h2|h3|h4)>", in: text, with: "\n")
        text = replacing(pattern: "(?i)<br\\s*/?>", in: text, with: "\n")
        text = replacing(pattern: "<[^>]+>", in: text, with: " ")
        text = decodeHTMLEntities(text)

        return text
            .components(separatedBy: .newlines)
            .map { normalizeWhitespace($0) }
            .filter(isUseful)
    }

    private nonisolated static func cleanFragment(_ text: String) -> String {
        var cleaned = replacing(pattern: "<[^>]+>", in: text, with: " ")
        cleaned = decodeHTMLEntities(cleaned)
        return normalizeWhitespace(cleaned)
    }

    private nonisolated static func cleanCandidate(_ text: String) -> String {
        let trimmed = normalizeWhitespace(text)
        if trimmed.count <= 140 { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 140)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isUseful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 220 else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }

        let lower = trimmed.lowercased()
        let noise = [
            "advertisement",
            "privacy policy",
            "terms of use",
            "cookie",
            "sign in",
            "sign up",
            "newsletter",
            "skip to",
            "download the app",
            "continue in browser",
            "javascript",
            "verify",
            "username",
            "password",
            "view all",
            "more in",
            "register"
        ]
        if noise.contains(where: lower.contains) { return false }
        return true
    }

    private nonisolated static func normalizeWhitespace(_ text: String) -> String {
        replacing(pattern: "\\s+", in: text, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func decodeHTMLEntities(_ text: String) -> String {
        var output = text
        let replacements = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#34;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#160;": " ",
            "&ndash;": "-",
            "&mdash;": "-",
            "&hellip;": "...",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\"",
            "&ldquo;": "\""
        ]
        for (entity, replacement) in replacements {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }
        return output
    }

    private nonisolated static func matches(pattern: String,
                                            in text: String,
                                            group: Int,
                                            limit: Int) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var results: [String] = []
        for match in regex.matches(in: text, options: [], range: range) {
            guard group < match.numberOfRanges,
                  let swiftRange = Range(match.range(at: group), in: text) else { continue }
            results.append(String(text[swiftRange]))
            if results.count >= limit { break }
        }
        return results
    }

    private nonisolated static func replacing(pattern: String,
                                              in text: String,
                                              with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text,
                                              options: [],
                                              range: range,
                                              withTemplate: replacement)
    }

    private nonisolated static func cacheFragment(for query: String) -> String {
        let normalized = normalizeWhitespace(query).lowercased()
        guard !normalized.isEmpty else { return "default" }
        return String(normalized.prefix(80))
    }
}
