import Foundation

/// Ticket and box-office search links for a movie. Plain searches: no
/// affiliate or tracking parameters.
enum TicketAffiliate {
    /// Best-guess Fandango search URL for a movie title. Fandango's
    /// public search endpoint handles the URL-encoded title fine.
    static func fandangoURL(for title: String) -> URL? {
        var comps = URLComponents(string: "https://www.fandango.com/search/")
        comps?.queryItems = [.init(name: "q", value: title)]
        return comps?.url
    }

    static func amcURL(for title: String) -> URL? {
        var comps = URLComponents(string: "https://www.amctheatres.com/search")
        comps?.queryItems = [.init(name: "q", value: title)]
        return comps?.url
    }

    static func atomURL(for title: String) -> URL? {
        var comps = URLComponents(string: "https://www.atomtickets.com/search")
        comps?.queryItems = [.init(name: "q", value: title)]
        return comps?.url
    }

    static func boxOfficeMojoURL(for title: String) -> URL? {
        var comps = URLComponents(string: "https://www.boxofficemojo.com/search/")
        comps?.queryItems = [.init(name: "q", value: title)]
        return comps?.url
    }

    static func theNumbersURL(for title: String) -> URL? {
        let slug = title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        return URL(string: "https://www.the-numbers.com/search?searchterm=\(slug)")
    }
}
