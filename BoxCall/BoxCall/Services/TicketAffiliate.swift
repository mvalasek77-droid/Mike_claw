import Foundation

/// Fandango + AMC + Atom Tickets affiliate deep-linking. In production,
/// replace `affiliateId` with your real partner id from each program
/// and route through the boxcall.com click tracker so revenue attribution
/// isn't lost when App Tracking Transparency is denied.
enum TicketAffiliate {
    static let fandangoAffiliateId = "BOXCALL"     // stub — replace with real id
    static let amcAffiliateId = "BOXCALL"
    static let atomAffiliateId = "BOXCALL"

    /// Best-guess Fandango search URL for a movie title. Fandango's
    /// public search endpoint handles the URL-encoded title fine.
    static func fandangoURL(for title: String) -> URL? {
        var comps = URLComponents(string: "https://www.fandango.com/search/")
        comps?.queryItems = [
            .init(name: "q", value: title),
            .init(name: "affid", value: fandangoAffiliateId)
        ]
        return comps?.url
    }

    static func amcURL(for title: String) -> URL? {
        var comps = URLComponents(string: "https://www.amctheatres.com/search")
        comps?.queryItems = [
            .init(name: "q", value: title),
            .init(name: "utm_source", value: amcAffiliateId)
        ]
        return comps?.url
    }

    static func atomURL(for title: String) -> URL? {
        var comps = URLComponents(string: "https://www.atomtickets.com/search")
        comps?.queryItems = [
            .init(name: "q", value: title),
            .init(name: "atom_source", value: atomAffiliateId)
        ]
        return comps?.url
    }
}
