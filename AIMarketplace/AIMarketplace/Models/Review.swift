import Foundation

/// A buyer's star rating and written review of a title.
struct Review: Identifiable, Codable, Hashable {
    var id = UUID()
    let itemID: UUID
    let author: String
    let rating: Int        // 1...5
    let text: String
    let date: Date
}

/// Generates believable seed reviews for popular titles so the ratings surface
/// isn't empty on first launch. Deterministic per item, and only the highest-
/// traction titles get reviews (mirrors how real catalogues look).
enum ReviewSeeder {
    private static let authors = ["A. Okafor", "M. Sato", "L. Reyes", "J.Bauer", "P. Novak", "R. Singh", "C. Lindqvist", "D. Moreau", "S. Haddad", "T. Whitlock"]

    private static let blurbs: [Int: [String]] = [
        5: [
            "Genuinely couldn't tell it was AI-made — gripping start to finish.",
            "Worth every cent. The pacing is immaculate.",
            "Instant favourite. Already came back for a second pass.",
            "This is the bar everything else should be measured against."
        ],
        4: [
            "Really strong. A couple of slow stretches but I'd recommend it.",
            "Polished and confident. Looking forward to more from this one.",
            "Great craft. Lost half a star on the ending, but excellent overall."
        ],
        3: [
            "Solid and enjoyable, if a little familiar in places.",
            "Good value. Competent work that mostly lands.",
            "Decent — promising, with room to sharpen the hook."
        ]
    ]

    static func seed(for catalog: [MediaItem]) -> [Review] {
        let popular = catalog.sorted { $0.purchases > $1.purchases }.prefix(16)
        var out: [Review] = []
        for item in popular {
            let count = 2 + abs(stableHash(item.id.uuidString + "rc")) % 3   // 2–4
            for i in 0..<count {
                let salt = item.id.uuidString + "rv\(i)"
                let rating = 3 + abs(stableHash(salt + "r")) % 3              // 3–5, skews high
                let pool = blurbs[rating] ?? blurbs[5]!
                let text = pool[abs(stableHash(salt + "t")) % pool.count]
                let author = authors[abs(stableHash(salt + "a")) % authors.count]
                let age = Double(abs(stableHash(salt + "d")) % 4_000_000)
                out.append(Review(itemID: item.id, author: author, rating: rating,
                                  text: text, date: Date().addingTimeInterval(-age)))
            }
        }
        return out
    }
}
