import Foundation

/// The live catalogue. These are real, creator-supplied works — their media
/// files live in `Resources/Samples` and are wired by `coverAssetName` /
/// `mediaFileName` slugs (see ContentResolver). No demo/placeholder content.
enum SampleData {
    static func catalog() -> [MediaItem] {
        [
            MediaItem(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
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
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
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
                id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
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
                id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
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
            ),
            MediaItem(
                id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
                title: "Got Me in Trouble",
                creator: "Mike Valasek",
                type: .music,
                genre: "Country / Blues",
                synopsis: "Stained with Kentucky fire, sugar cane sweetness, and smoke's desire — a whiskey-soaked lullaby about the kind of trouble that follows you home. Written by Mike Valasek, produced with Suno.",
                aiTools: ["Suno"],
                commercialScore: 91,
                price: 1.29,
                releaseYear: 2026,
                length: 1,
                maturity: "13+",
                purchases: 0,
                trending: 70,
                coverAssetName: "kentucky-fire",
                mediaFileName: "kentucky-fire"
            ),
            MediaItem(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
                title: "Bourbon Kiss",
                creator: "Mike Valasek",
                type: .music,
                genre: "Hip-Hop / Pop",
                synopsis: "A hook-heavy anthem about bourbon lips, Kentucky heat, and the kind of trouble you don't regret. Written by Mike Valasek, produced with Suno.",
                aiTools: ["Suno"],
                commercialScore: 90,
                price: 1.29,
                releaseYear: 2026,
                length: 1,
                maturity: "13+",
                purchases: 0,
                trending: 68,
                coverAssetName: "sicking-that-thing",
                mediaFileName: "sicking-that-thing"
            ),
            MediaItem(
                id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
                title: "Jesus is My Drug Dealer",
                creator: "Mike Valasek",
                type: .music,
                genre: "Dark Folk / Gothic",
                synopsis: "Some threads bleed through air, some through divine intervention — a dark poetic tapestry of cobweb lace whispers, cracked glass reflections, and gold-painted scars. Written by Mike Valasek, produced with Suno.",
                aiTools: ["Suno"],
                commercialScore: 92,
                price: 1.29,
                releaseYear: 2026,
                length: 1,
                maturity: "13+",
                purchases: 0,
                trending: 74,
                coverAssetName: "eli-hayes",
                mediaFileName: "eli-hayes"
            ),
            MediaItem(
                id: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!,
                title: "Epoch",
                creator: "Mike Valasek",
                type: .novel,
                genre: "Dystopian Sci-Fi",
                synopsis: "Ethan Walker refuses to integrate with NeuroSphere — the AI that reads minds, curates desires, and replaces human connection with synthetic perfection. When he meets Lila, something feels too right. When he finds the Sanctuary, it feels too convenient. And when his own son Isaac becomes the Overlord's messiah, Ethan must choose: surrender to a frictionless world, or fight for the right to be irrational, broken, and free. A 45-chapter novel about faith, resistance, and the courage to be human in a world that no longer needs you.",
                aiTools: ["Claude Opus 4.7", "GPT-4"],
                commercialScore: 96,
                price: 9.99,
                releaseYear: 2026,
                length: 6280,
                maturity: "17+",
                purchases: 0,
                trending: 82,
                coverAssetName: "epoch",
                mediaFileName: "epoch"
            )
        ]
    }

    /// Lowercased, hyphenated slug used to match bundled media/cover files.
    static func slugify(_ title: String) -> String {
        let allowed = title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }
}
