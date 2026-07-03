import Foundation

/// Seed content for the demo. All profiles are fictional; the copy is written
/// to read like real people. Each profile carries a `photoName` slot — drop
/// licensed photos into Resources/Assets.xcassets under those names and they
/// render everywhere automatically (the generated portrait is the fallback).
enum SampleData {

    // MARK: Women on the floor (what a bidder browses)

    static func floor() -> [Profile] {
        [
            Profile(name: "Mara Quinn", age: 27, role: .woman, location: "SoHo, New York",
                    bio: "Gallery curator. I spend my weekends at openings and my weeknights pretending I'll stop buying art books.",
                    hue: 0.92,
                    photoName: "photo-mara",
                    prompts: [
                        Prompt(question: "The way to win me over is", answer: "Make the reservation and don't cancel it."),
                        Prompt(question: "My simple pleasures", answer: "A negroni, a window seat, and leaving the party at the right time."),
                    ],
                    interests: ["Art", "Film", "Wine", "Design"],
                    reviews: [
                        DateReview(authorName: "Theo", authorHue: 0.6, stars: 5,
                                   text: "Easy to talk to, funnier than her profile lets on. We closed the restaurant down.",
                                   traits: [Trait.fun.rawValue: 5, Trait.interesting.rawValue: 5,
                                            Trait.social.rawValue: 4, Trait.polite.rawValue: 5,
                                            Trait.genuine.rawValue: 5],
                                   interestCategories: ["Art openings", "Wine bars"]),
                    ],
                    verified: true,
                    startingBid: 250),

            Profile(name: "Priya Sethi", age: 29, role: .woman, location: "Lincoln Park, Chicago",
                    bio: "ER doctor. My schedule is chaos, so when I'm off, I'm actually present. Looking for the same.",
                    hue: 0.08,
                    photoName: "photo-priya",
                    prompts: [
                        Prompt(question: "I geek out on", answer: "Medicine, obviously — but also 90s R&B. I will take over the aux."),
                        Prompt(question: "Green flags I look for", answer: "Calls his mom. Tips well. Asks follow-up questions."),
                    ],
                    interests: ["Fitness", "Food", "Travel", "Music"],
                    reviews: [
                        DateReview(authorName: "Devin", authorHue: 0.3, stars: 4,
                                   text: "Smart and warm. I rambled about work and she still gave me a second round.",
                                   traits: [Trait.fun.rawValue: 4, Trait.interesting.rawValue: 5,
                                            Trait.social.rawValue: 5, Trait.polite.rawValue: 4,
                                            Trait.genuine.rawValue: 5],
                                   interestCategories: ["Tasting menus"]),
                    ],
                    verified: true,
                    startingBid: 300),

            Profile(name: "Sloane Carter", age: 31, role: .woman, location: "Venice, Los Angeles",
                    bio: "Founder, second company. I like early mornings, good espresso, and people who follow through.",
                    hue: 0.55,
                    photoName: "photo-sloane",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Skip the small talk and split the tasting menu."),
                        Prompt(question: "Dating me is like", answer: "Working with a good cofounder — direct, loyal, occasionally intense."),
                    ],
                    interests: ["Startups", "Fitness", "Food", "Design"],
                    startingBid: 500),

            // Copycat — AI-generated. Content reads natural; the small AI chip
            // on her card and profile carries the disclosure.
            Profile(name: "Bella Rose", age: 23, role: .woman, location: "Miami Beach",
                    bio: "Pool days, boat weekends, and a standing reservation at my favorite rooftop. Come keep up.",
                    hue: 0.95,
                    photoName: "photo-bella",
                    prompts: [
                        Prompt(question: "My ideal date", answer: "Sunset drinks somewhere over the water. You handle the details."),
                    ],
                    interests: ["Travel", "Nightlife", "Wine"],
                    isCopycat: true, copycatStyle: .poolside),

            Profile(name: "Noor Haddad", age: 26, role: .woman, location: "Capitol Hill, Seattle",
                    bio: "Climate engineer. I'll hike in any weather and I fact-check fun facts — lovingly.",
                    hue: 0.42,
                    photoName: "photo-noor",
                    prompts: [
                        Prompt(question: "Best travel story", answer: "Got weathered-in on a glacier for two days. Still the best trip of my life."),
                        Prompt(question: "I'm weirdly good at", answer: "Parallel parking and reading a room."),
                    ],
                    interests: ["Fitness", "Travel", "Reading", "Music"],
                    startingBid: 200),

            Profile(name: "Valentina Cruz", age: 28, role: .woman, location: "Williamsburg, Brooklyn",
                    bio: "Pastry chef. I work Saturdays, so impress me on a Tuesday. Bonus points if you actually like dessert.",
                    hue: 0.13,
                    photoName: "photo-valentina",
                    prompts: [
                        Prompt(question: "My love language", answer: "Cooking for people, then watching their face on the first bite."),
                    ],
                    interests: ["Food", "Music", "Art", "Dogs"]),

            // Copycat — AI-generated (glam styling).
            Profile(name: "Crystal Lux", age: 24, role: .woman, location: "Las Vegas",
                    bio: "Cocktail dresses over casual, always. If you can't decide where to take me, I already know how the date ends.",
                    hue: 0.78,
                    photoName: "photo-crystal",
                    prompts: [
                        Prompt(question: "Two truths and a lie", answer: "I've been to 30 countries, I hate champagne, and I always text back."),
                    ],
                    interests: ["Nightlife", "Travel", "Design"],
                    isCopycat: true, copycatStyle: .glam),

            // Copycat — AI-generated (yoga styling).
            Profile(name: "Jade Rivera", age: 25, role: .woman, location: "Tulum",
                    bio: "Yoga teacher splitting time between Tulum and wherever the next retreat is. Sunrise person, unapologetically.",
                    hue: 0.80,
                    photoName: "photo-jade",
                    prompts: [
                        Prompt(question: "My happy place", answer: "The beach at 6am before anyone else is up."),
                    ],
                    interests: ["Fitness", "Travel", "Reading"],
                    isCopycat: true, copycatStyle: .yoga),

            // Copycat — AI-generated (beach styling).
            Profile(name: "Amber Skye", age: 24, role: .woman, location: "Malibu",
                    bio: "Grew up on this coast and never left. Golden hour is a personality trait, I've accepted it.",
                    hue: 0.07,
                    photoName: "photo-amber",
                    prompts: [
                        Prompt(question: "Best first date", answer: "Tacos on the beach, then see where the night goes."),
                    ],
                    interests: ["Travel", "Fitness", "Music"],
                    isCopycat: true, copycatStyle: .beach),
        ]
    }

    // MARK: Men (used to seed incoming bids on the woman side)

    static func suitors() -> [Profile] {
        [
            // The first verified Trillionaire — founder's seat on the floor.
            Profile(name: "Mike Valasek", age: 39, role: .man, location: "Founder · Auction Baby",
                    bio: "Built the house. First to verify the top tier — bid the full $9,999, paid it, and she confirmed. Somebody had to go first.",
                    hue: 0.13,
                    photoName: "photo-mike",
                    prompts: [
                        Prompt(question: "Why I'm here", answer: "Someone had to set the standard. Bid honest, pay in full."),
                        Prompt(question: "Green flag I bring", answer: "I pay exactly what I bid. Every time."),
                    ],
                    interests: ["Startups", "Food", "Travel"],
                    reviews: [
                        DateReview(authorName: "Sloane", authorHue: 0.55, stars: 5,
                                   text: "Bid the full amount and paid it without being asked twice. The dinner wasn't bad either.",
                                   paidBid: true, bidAmount: 9_999, spentAmount: 9_999),
                    ],
                    verified: true,
                    archetype: .trillionaire,
                    trillionaireVerified: true),

            Profile(name: "Julian West", age: 34, role: .man, location: "Tribeca, New York",
                    bio: "Private equity by day. I keep my reservations, my word, and — according to my friends — too many boat photos.",
                    hue: 0.6,
                    photoName: "photo-julian",
                    prompts: [
                        Prompt(question: "My most controversial opinion", answer: "Brunch is overrated. Take the same people to dinner."),
                        Prompt(question: "I'll know it's going well when", answer: "You order dessert without checking the time."),
                    ],
                    interests: ["Travel", "Wine", "Design"],
                    reviews: [
                        DateReview(authorName: "Mara", authorHue: 0.92, stars: 5,
                                   text: "Paid what he bid, no drama, walked me to my train. Would say yes again.",
                                   paidBid: true, bidAmount: 400, spentAmount: 420),
                        DateReview(authorName: "Noor", authorHue: 0.42, stars: 4,
                                   text: "A gentleman. Heard a lot about the boat, but he asked good questions too.",
                                   paidBid: true, bidAmount: 300, spentAmount: 300),
                    ],
                    verified: true,
                    archetype: .goodJob),

            Profile(name: "Marcus Bell", age: 38, role: .man, location: "Buckhead, Atlanta",
                    bio: "Third-generation family business. Great table manners, questionable golf handicap.",
                    hue: 0.33,
                    photoName: "photo-marcus",
                    prompts: [
                        Prompt(question: "Unusual skills", answer: "I can read a wine list faster than a menu."),
                    ],
                    interests: ["Wine", "Travel", "Art"],
                    reviews: [
                        DateReview(authorName: "Sloane", authorHue: 0.55, stars: 3,
                                   text: "Charming all night, then his card 'didn't work' when the check came. I covered it.",
                                   paidBid: false, bidAmount: 5_000, spentAmount: 0),
                    ],
                    archetype: .inheritance),

            Profile(name: "Dominic Vance", age: 41, role: .man, location: "Bel Air, Los Angeles",
                    bio: "I'd rather show you a good evening than tell you about one. Ask me about the car if you must.",
                    hue: 0.0,
                    photoName: "photo-dominic",
                    prompts: [
                        Prompt(question: "Best advice I've gotten", answer: "Be on time and pick up the check. Everything else is style."),
                    ],
                    interests: ["Design", "Nightlife", "Travel"],
                    archetype: .ferrari),

            Profile(name: "Sam Okafor", age: 30, role: .man, location: "Capitol Hill, DC",
                    bio: "History teacher and three-time neighborhood trivia champion. I'll lose an argument graciously if you're right.",
                    hue: 0.5,
                    photoName: "photo-sam",
                    prompts: [
                        Prompt(question: "The way to win me over", answer: "Care about something and let me ask you questions about it."),
                    ],
                    interests: ["Reading", "Food", "Music"],
                    reviews: [
                        DateReview(authorName: "Priya", authorHue: 0.08, stars: 5,
                                   text: "Bid modestly and over-delivered. Paid every cent, walked me home, texted the next day.",
                                   paidBid: true, bidAmount: 120, spentAmount: 160),
                    ],
                    verified: true,
                    archetype: .goodGuy),
        ]
    }
}
