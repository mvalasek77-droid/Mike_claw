import Foundation

/// Seed content for the demo. Everything here is fictional and play-money — the
/// app ships no real users, photos, or payments. It exists so every flow on
/// both sides of the floor is fully explorable on first launch.
enum SampleData {

    // MARK: Women on the floor (what a bidder browses)

    static func floor() -> [Profile] {
        [
            Profile(name: "Mara Quinn", age: 27, role: .woman, location: "SoHo, NYC",
                    bio: "Gallery curator. I'll out-argue you about a film you haven't seen.",
                    hue: 0.92,
                    prompts: [
                        Prompt(question: "The way to win me over is", answer: "A reservation you actually kept."),
                        Prompt(question: "My simple pleasures", answer: "Negronis, Knausgård, and leaving early."),
                    ],
                    interests: ["Art", "Film", "Natural wine", "Architecture"],
                    reviews: [
                        DateReview(authorName: "Theo", authorHue: 0.6, stars: 5,
                                   text: "Sharp, funny, completely unbothered. Worth every dollar.",
                                   traits: [Trait.fun.rawValue: 5, Trait.interesting.rawValue: 5,
                                            Trait.social.rawValue: 4, Trait.polite.rawValue: 5,
                                            Trait.genuine.rawValue: 5],
                                   interestCategories: ["Art openings", "Wine bars"]),
                    ],
                    startingBid: 250),

            Profile(name: "Priya Sethi", age: 29, role: .woman, location: "Lincoln Park, Chicago",
                    bio: "ER doctor. Low tolerance for nonsense, high tolerance for spice.",
                    hue: 0.08,
                    prompts: [
                        Prompt(question: "I geek out on", answer: "Trauma medicine and 90s R&B. Ask me anything."),
                        Prompt(question: "Green flags I look for", answer: "Calls his mother. Tips 25%."),
                    ],
                    interests: ["Medicine", "Hot yoga", "Street food", "True crime"],
                    reviews: [
                        DateReview(authorName: "Devin", authorHue: 0.3, stars: 4,
                                   text: "Brilliant and warm. I talked too much; she still laughed.",
                                   traits: [Trait.fun.rawValue: 4, Trait.interesting.rawValue: 5,
                                            Trait.social.rawValue: 5, Trait.polite.rawValue: 4,
                                            Trait.genuine.rawValue: 5],
                                   interestCategories: ["Tasting menus"]),
                    ],
                    startingBid: 300),

            Profile(name: "Sloane Carter", age: 31, role: .woman, location: "Venice, LA",
                    bio: "Founder. I move fast and I expect the check to keep up.",
                    hue: 0.55,
                    prompts: [
                        Prompt(question: "Together we could", answer: "Skip the small talk and split a tasting menu."),
                        Prompt(question: "Dating me is like", answer: "A pre-seed round: high upside, do your diligence."),
                    ],
                    interests: ["Startups", "Surfing", "Espresso", "Design"],
                    startingBid: 500),

            // A copycat — AI-generated lure. Disclosed everywhere it appears.
            Profile(name: "Bella Rose", age: 23, role: .woman, location: "Miami Beach",
                    bio: "11/10 energy ✨ DM me, big spenders only 💎 (this profile is AI-generated)",
                    hue: 0.95,
                    prompts: [
                        Prompt(question: "My ideal date", answer: "You bid the most. That's the whole date."),
                    ],
                    interests: ["Yachts", "Bikinis", "Champagne"],
                    isCopycat: true),

            Profile(name: "Noor Haddad", age: 26, role: .woman, location: "Capitol Hill, Seattle",
                    bio: "Climate engineer. I will fact-check your fun facts. Lovingly.",
                    hue: 0.42,
                    prompts: [
                        Prompt(question: "Best travel story", answer: "Got stuck on a glacier. Would do it again."),
                        Prompt(question: "I'm weirdly good at", answer: "Parallel parking and reading people."),
                    ],
                    interests: ["Climbing", "Sustainability", "Pottery", "Jazz"],
                    startingBid: 200),

            Profile(name: "Valentina Cruz", age: 28, role: .woman, location: "Williamsburg, NYC",
                    bio: "Pastry chef. I taste everything twice. Bring an appetite.",
                    hue: 0.13,
                    prompts: [
                        Prompt(question: "My love language", answer: "Feeding you, then judging your reaction."),
                    ],
                    interests: ["Baking", "Markets", "Vinyl", "Ceramics"]),

            // A second copycat at a higher hue, deeper in the feed.
            Profile(name: "Crystal Lux", age: 22, role: .woman, location: "Las Vegas",
                    bio: "Your dream girl 😘 (AI-generated) — outbid them all 🥂",
                    hue: 0.78,
                    prompts: [
                        Prompt(question: "Two truths and a lie", answer: "I'm real. I'm real. I'm real."),
                    ],
                    interests: ["Pool parties", "Designer bags"],
                    isCopycat: true),
        ]
    }

    // MARK: Men (used to seed incoming bids on the woman side)

    static func suitors() -> [Profile] {
        [
            Profile(name: "Julian West", age: 34, role: .man, location: "Tribeca, NYC",
                    bio: "PE, two exits, terrible at golf. I keep reservations and promises.",
                    hue: 0.6,
                    prompts: [
                        Prompt(question: "My most controversial opinion", answer: "Brunch is a scam. Dinner or nothing."),
                        Prompt(question: "I'll know it's going well when", answer: "You order dessert without asking."),
                    ],
                    interests: ["Sailing", "Bourbon", "Architecture"],
                    reviews: [
                        DateReview(authorName: "Mara", authorHue: 0.92, stars: 5,
                                   text: "Paid exactly what he bid, no theatrics. Rare.",
                                   paidBid: true, bidAmount: 400, spentAmount: 420),
                        DateReview(authorName: "Noor", authorHue: 0.42, stars: 4,
                                   text: "Gentleman. Talked about his boat a lot.",
                                   paidBid: true, bidAmount: 300, spentAmount: 300),
                    ],
                    archetype: .goodJob),

            Profile(name: "Marcus Bell", age: 38, role: .man, location: "Buckhead, Atlanta",
                    bio: "Family money, family manners. Will fly you somewhere with a beach.",
                    hue: 0.33,
                    prompts: [
                        Prompt(question: "Unusual skills", answer: "I can read a wine list in the dark."),
                    ],
                    interests: ["Polo", "Yachting", "Art collecting"],
                    reviews: [
                        DateReview(authorName: "Sloane", authorHue: 0.55, stars: 3,
                                   text: "Bid $5k, 'forgot' his card. Generous with stories, not the bill.",
                                   paidBid: false, bidAmount: 5_000, spentAmount: 0),
                    ],
                    archetype: .inheritance),

            Profile(name: "Dateo Vance", age: 41, role: .man, location: "Bel Air, LA",
                    bio: "I don't tell people what I do. The car does it for me.",
                    hue: 0.0,
                    prompts: [
                        Prompt(question: "Best advice I've gotten", answer: "Lease the car, own the moment."),
                    ],
                    interests: ["Racing", "Watches", "Nightlife"],
                    archetype: .ferrari),

            Profile(name: "Sam Okafor", age: 30, role: .man, location: "Capitol Hill, DC",
                    bio: "Teacher by day, trivia menace by night. I'll lose graciously.",
                    hue: 0.5,
                    prompts: [
                        Prompt(question: "The way to win me over", answer: "Care about something. Anything."),
                    ],
                    interests: ["Trivia", "Hiking", "Cooking"],
                    reviews: [
                        DateReview(authorName: "Priya", authorHue: 0.08, stars: 5,
                                   text: "Bid small, delivered big. Walked me home. Paid every cent.",
                                   paidBid: true, bidAmount: 120, spentAmount: 160),
                    ],
                    archetype: .goodGuy),
        ]
    }
}
