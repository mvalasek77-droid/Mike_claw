import Foundation

/// The live catalogue. These are real, creator-supplied works — their media
/// files live in `Resources/Samples` and are wired by `coverAssetName` /
/// `mediaFileName` slugs (see ContentResolver). No demo/placeholder content.
enum SampleData {
    static func catalog() -> [MediaItem] {
        [
            MediaItem(
                title: "The Odyssey Protocol",
                creator: "Mike Valasek",
                type: .novel,
                genre: "Literary Sci-Fi Thriller",
                synopsis: "Marine scientist Helena Karras knows the Aegean is lying to her. When the sea goes impossibly, unnaturally still over the research vessel Aegis, she's pulled into a mystery that reaches from Homer's Odyssey to the edge of the unknown — and asks what it means to keep sailing toward the thing that could destroy you. A 70,000-word novel.",
                aiTools: ["Claude Opus 4.7", "GPT-4"],
                commercialScore: 94,
                price: 7.99,
                releaseYear: 2026,
                length: 286,
                maturity: "13+",
                purchases: 0,
                trending: 72,
                coverAssetName: "the-odyssey-protocol",
                mediaFileName: "the-odyssey-protocol"
            ),
            MediaItem(
                title: "It's a Swifty World After All",
                creator: "Mike Valasek",
                type: .music,
                genre: "Pop",
                synopsis: "A glittering pop anthem with stadium-sized hooks and a wink in every line. Written by Mike Valasek and brought to life with Suno — bright, buoyant, and built around a chorus you'll be humming all day.",
                aiTools: ["Suno"],
                commercialScore: 90,
                price: 1.29,
                releaseYear: 2026,
                length: 1,
                maturity: "Everyone",
                purchases: 0,
                trending: 66,
                coverAssetName: "its-a-swifty-world-after-all",
                mediaFileName: "its-a-swifty-world-after-all"
            ),
            MediaItem(
                title: "Curves Like Keisha",
                creator: "Mike Valasek",
                type: .music,
                genre: "Hip-Hop / R&B",
                synopsis: "A smooth hip-hop / R&B cut with a confident groove and a melody that struts. Human songwriting by Mike Valasek, realized with Suno — late-night, low-lit, and effortlessly cool.",
                aiTools: ["Suno"],
                commercialScore: 89,
                price: 1.29,
                releaseYear: 2026,
                length: 1,
                maturity: "13+",
                purchases: 0,
                trending: 61,
                coverAssetName: "curves-like-keisha",
                mediaFileName: "curves-like-keisha"
            ),
            MediaItem(
                title: "Push Up Bra",
                creator: "Mike Valasek",
                type: .music,
                genre: "Pop",
                synopsis: "A cheeky, high-energy pop track that doesn't take itself too seriously. Written by Mike Valasek and produced with Suno — playful, punchy, and unapologetically catchy.",
                aiTools: ["Suno"],
                commercialScore: 88,
                price: 1.29,
                releaseYear: 2026,
                length: 1,
                maturity: "13+",
                purchases: 0,
                trending: 58,
                coverAssetName: "push-up-bra",
                mediaFileName: "push-up-bra"
            )
        ]
    }

    /// Lowercased, hyphenated slug used to match bundled media/cover files.
    static func slugify(_ title: String) -> String {
        let allowed = title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }
}
