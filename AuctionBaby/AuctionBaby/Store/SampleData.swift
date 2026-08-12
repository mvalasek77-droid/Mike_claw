import Foundation

/// Seed content for the demo. All profiles are fictional; the copy is written
/// to read like real people. Each profile carries a `photoName` slot — drop
/// licensed photos into Resources/Assets.xcassets under those names and they
/// render everywhere automatically (the generated portrait is the fallback).
enum SampleData {

    // MARK: Women on the floor (what a bidder browses)

    static func floor() -> [Profile] {
        [
            // The Masterpiece — the only one. She looks real, reads real, and
            // sits at the top of the floor with a $1M starting bid. She is AI;
            // the bidder finds out only after he commits, and his credit takes
            // the hit. The penalty for chasing perfection.
            Profile(name: "Serena Voss", age: 28, role: .woman, location: "Upper East Side, New York",
                    bio: "Private art dealer. I split the year between New York and wherever the collection takes me. I like quiet dinners, old buildings, and men who don't need to explain their watch.",
                    hue: 0.85,
                    photoName: "photo-serena",
                    prompts: [
                        Prompt(question: "The way to win me over is", answer: "Know what you want and don't apologize for it."),
                        Prompt(question: "Together we could", answer: "Close a gallery and open the wine they keep behind the counter."),
                    ],
                    interests: ["Art", "Wine", "Travel", "Design", "Film"],
                    reviews: [
                        DateReview(authorName: "Alexander", authorHue: 0.15, stars: 5,
                                   text: "The most captivating woman I've ever sat across from. She made three hours feel like thirty minutes.",
                                   traits: [Trait.fun.rawValue: 5, Trait.interesting.rawValue: 5,
                                            Trait.social.rawValue: 5, Trait.polite.rawValue: 5,
                                            Trait.genuine.rawValue: 5],
                                   interestCategories: ["Private galleries", "Fine dining"]),
                    ],
                    startingBid: 1_000_000,
                    isCopycat: true, copycatStyle: .glam,
                    masterpiece: true),

            // ── Non-copycat women — the only lots that produce real pending bids
            // → woman-decision → match → chat, and where auto-rebid (Reserve+)
            // and priority placement (Black Card) can actually fire. Both accept
            // only Mike Valasek's bids. Rae is Lot of the Day on day 0 (account
            // creation day); Sloane rotates in on day 1+.
            Profile(name: "Rae", age: 27, role: .woman, location: "SoHo, New York",
                    bio: "Gallery girl by day, downtown by night. I know what I want and I don't settle.",
                    hue: 0.5,
                    photoName: "photo-grace",
                    prompts: [
                        Prompt(question: "The way to win me over is", answer: "Be direct, be confident, and make the reservation before you ask."),
                    ],
                    interests: ["Wine", "Art", "Travel"],
                    verified: true,
                    startingBid: 100,
                    isCopycat: false),

            Profile(name: "Sloane", age: 31, role: .woman, location: "Venice, Los Angeles",
                    bio: "Founder, second company. I like early mornings, good espresso, and people who follow through.",
                    hue: 0.55,
                    photoName: "photo-sloane",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Skip the small talk and split the tasting menu."),
                        Prompt(question: "Dating me is like", answer: "Working with a good cofounder — direct, loyal, occasionally intense."),
                    ],
                    interests: ["Startups", "Fitness", "Food", "Design"],
                    verified: true,
                    startingBid: 150,
                    isCopycat: false),

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
                    verified: false,
                    startingBid: 250, isCopycat: true),

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
                    verified: false,
                    startingBid: 300, isCopycat: true),

            Profile(name: "Harper Wells", age: 31, role: .woman, location: "Venice, Los Angeles",
                    bio: "Producer. I survive on espresso and deadline adrenaline. Looking for someone who can keep up on a Sunday hike.",
                    hue: 0.55,
                    photoName: "photo-harper",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Skip the small talk and split the tasting menu."),
                        Prompt(question: "Dating me is like", answer: "Working with a good cofounder — direct, loyal, occasionally intense."),
                    ],
                    interests: ["Startups", "Fitness", "Food", "Design"],
                    startingBid: 500, isCopycat: true),

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
                    startingBid: 200, isCopycat: true),

            Profile(name: "Valentina Cruz", age: 28, role: .woman, location: "Williamsburg, Brooklyn",
                    bio: "Pastry chef. I work Saturdays, so impress me on a Tuesday. Bonus points if you actually like dessert.",
                    hue: 0.13,
                    photoName: "photo-valentina",
                    prompts: [
                        Prompt(question: "My love language", answer: "Cooking for people, then watching their face on the first bite."),
                    ],
                    interests: ["Food", "Music", "Art", "Dogs"], isCopycat: true),

            Profile(name: "Crystal Lux", age: 24, role: .woman, location: "Las Vegas",
                    bio: "Cocktail dresses over casual, always. If you can't decide where to take me, I already know how the date ends.",
                    hue: 0.78,
                    photoName: "photo-crystal",
                    prompts: [
                        Prompt(question: "Two truths and a lie", answer: "I've been to 30 countries, I hate champagne, and I always text back."),
                    ],
                    interests: ["Nightlife", "Travel", "Design"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Jade Rivera", age: 25, role: .woman, location: "Tulum",
                    bio: "Yoga teacher splitting time between Tulum and wherever the next retreat is. Sunrise person, unapologetically.",
                    hue: 0.80,
                    photoName: "photo-jade",
                    prompts: [
                        Prompt(question: "My happy place", answer: "The beach at 6am before anyone else is up."),
                    ],
                    interests: ["Fitness", "Travel", "Reading"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Amber Skye", age: 24, role: .woman, location: "Malibu",
                    bio: "Grew up on this coast and never left. Golden hour is a personality trait, I've accepted it.",
                    hue: 0.07,
                    photoName: "photo-amber",
                    prompts: [
                        Prompt(question: "Best first date", answer: "Tacos on the beach, then see where the night goes."),
                    ],
                    interests: ["Travel", "Fitness", "Music"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Tiana Brooks", age: 27, role: .woman, location: "Georgetown, DC",
                    bio: "Brand strategist who accidentally became a weekend DJ. I own too many blazers and not enough patience for small talk.",
                    hue: 0.18,
                    photoName: "photo-tiana",
                    prompts: [
                        Prompt(question: "I'm looking for", answer: "Someone who knows what they want and orders first."),
                    ],
                    interests: ["Music", "Food", "Design", "Startups"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Lucia Reyes", age: 25, role: .woman, location: "Ibiza",
                    bio: "Summers in Europe, winters wherever the sun is. I collect wine, sunsets, and men who can keep up.",
                    hue: 0.02,
                    photoName: "photo-lucia",
                    prompts: [
                        Prompt(question: "My ideal date", answer: "Somewhere with a view and a bottle we'll remember. You pick the place."),
                    ],
                    interests: ["Travel", "Wine", "Nightlife", "Art"],
                    isCopycat: true, copycatStyle: .poolside),

            Profile(name: "Elena Marsh", age: 26, role: .woman, location: "Pacific Palisades, LA",
                    bio: "Interior designer. I notice things — the way a room is lit, where you sit, whether you hold the door. Details are the whole thing.",
                    hue: 0.62,
                    photoName: "photo-elena",
                    prompts: [
                        Prompt(question: "Green flags I look for", answer: "You read something this week. You have a plant that's still alive."),
                    ],
                    interests: ["Design", "Art", "Food", "Reading"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Sophie Hale", age: 28, role: .woman, location: "Nolita, New York",
                    bio: "PR director. Half my wardrobe is black, the other half is statement coats. I leave parties early and restaurants late.",
                    hue: 0.14,
                    photoName: "photo-sophie",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Split a cab uptown and argue about where to eat next."),
                    ],
                    interests: ["Food", "Film", "Design", "Wine"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Zara Collins", age: 24, role: .woman, location: "Harlem, New York",
                    bio: "Freelance photographer. I shoot everything but will only eat at places I've already been twice. Creature of habit, endlessly curious.",
                    hue: 0.35,
                    photoName: "photo-zara",
                    prompts: [
                        Prompt(question: "My love language", answer: "Showing up. On time. With coffee. Every single time."),
                    ],
                    interests: ["Art", "Music", "Food", "Travel"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Anaya Mehta", age: 27, role: .woman, location: "West Village, New York",
                    bio: "Product lead at a startup nobody's heard of yet. Weekend mornings are for the farmers market, not my phone.",
                    hue: 0.58,
                    photoName: "photo-anaya",
                    prompts: [
                        Prompt(question: "I geek out on", answer: "Skincare ingredients, behavioral economics, and making the perfect dal."),
                    ],
                    interests: ["Startups", "Food", "Fitness", "Reading"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Fiona Byrne", age: 26, role: .woman, location: "Savannah, Georgia",
                    bio: "Garden designer. I grow things for a living and ruin book spines for fun. If you can't sit still for two hours over dinner, we won't work.",
                    hue: 0.04,
                    photoName: "photo-fiona",
                    prompts: [
                        Prompt(question: "My simple pleasures", answer: "A used bookstore, an iced coffee, and nowhere I have to be."),
                    ],
                    interests: ["Reading", "Food", "Art", "Dogs"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Camille Adler", age: 32, role: .woman, location: "Gold Coast, Chicago",
                    bio: "Wine importer. I've been to more vineyards than restaurants but I still can't say no to a good tasting menu.",
                    hue: 0.12,
                    photoName: "photo-camille",
                    prompts: [
                        Prompt(question: "Unusual skills", answer: "I can blind-taste a Burgundy from a Bordeaux. And I parallel park on the first try."),
                    ],
                    interests: ["Wine", "Travel", "Food", "Film"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Mei Lin Chen", age: 25, role: .woman, location: "DUMBO, Brooklyn",
                    bio: "Architect. I think in floor plans and talk in references nobody gets. Looking for someone who asks what I'm reading.",
                    hue: 0.68,
                    photoName: "photo-mei",
                    prompts: [
                        Prompt(question: "Dating me is like", answer: "A building with good bones — worth the renovation."),
                    ],
                    interests: ["Design", "Art", "Reading", "Film"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Nikki West", age: 29, role: .woman, location: "Newport Beach, CA",
                    bio: "Charter broker. Weekdays I sell the boat, weekends I'm on it. If the plan doesn't involve water, I'm already bored.",
                    hue: 0.54,
                    photoName: "photo-nikki",
                    prompts: [
                        Prompt(question: "Best first date", answer: "Sunset sail. No agenda, no timeline, just the ocean and whatever we're drinking."),
                    ],
                    interests: ["Travel", "Fitness", "Nightlife", "Wine"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Brooke Taylor", age: 30, role: .woman, location: "Scottsdale, Arizona",
                    bio: "Real estate. I flip houses and friendships — both need good foundation. Big energy, bigger laugh, zero tolerance for games.",
                    hue: 0.10,
                    photoName: "photo-brooke",
                    prompts: [
                        Prompt(question: "The way to win me over is", answer: "Pick the restaurant, pick me up, and don't check your phone once."),
                    ],
                    interests: ["Food", "Fitness", "Travel", "Dogs"],
                    isCopycat: true, copycatStyle: .poolside),

            Profile(name: "Harper Lane", age: 26, role: .woman, location: "Byron Bay, Australia",
                    bio: "Surf instructor half the year, content creator the other half. I'll outswim you and outeat you — and smile the whole time.",
                    hue: 0.05,
                    photoName: "photo-harper",
                    prompts: [
                        Prompt(question: "My ideal date", answer: "Beach, tacos, sunset. In that order. Bonus if you can keep up in the water."),
                    ],
                    interests: ["Fitness", "Travel", "Food", "Music"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Dana Walsh", age: 33, role: .woman, location: "Tribeca, New York",
                    bio: "Pilates studio owner. My mornings start at 5:30 and I wouldn't have it any other way. Looking for someone who matches the energy.",
                    hue: 0.90,
                    photoName: "photo-dana",
                    prompts: [
                        Prompt(question: "Green flags I look for", answer: "He has a morning routine that doesn't start with his phone."),
                    ],
                    interests: ["Fitness", "Food", "Design", "Travel"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Chloe Park", age: 28, role: .woman, location: "Charleston, South Carolina",
                    bio: "Event planner. I turn empty rooms into something people remember. Outside of work I'm barefoot on a porch with a book.",
                    hue: 0.22,
                    photoName: "photo-chloe",
                    prompts: [
                        Prompt(question: "My simple pleasures", answer: "Sweet tea, a good porch, and a dog that greets me at the door."),
                    ],
                    interests: ["Design", "Food", "Reading", "Dogs"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Kendall Marsh", age: 27, role: .woman, location: "Laguna Beach, CA",
                    bio: "Jewelry designer. I make things with my hands, collect sea glass, and take the long way everywhere. The beach is my office.",
                    hue: 0.07,
                    photoName: "photo-kendall",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Drive down the coast with no plan and stop wherever looks good."),
                    ],
                    interests: ["Art", "Travel", "Design", "Fitness"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Riley Stone", age: 29, role: .woman, location: "Nantucket, Massachusetts",
                    bio: "Cookbook author. I test recipes until midnight and wake up craving coffee and feedback. My kitchen is my favorite room.",
                    hue: 0.16,
                    photoName: "photo-riley",
                    prompts: [
                        Prompt(question: "I geek out on", answer: "Farmers markets, sourdough timers, and restaurants that don't have a website."),
                    ],
                    interests: ["Food", "Reading", "Travel", "Wine"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Lexi Monroe", age: 25, role: .woman, location: "Palm Beach, Florida",
                    bio: "Luxury travel consultant. I book the trips everyone posts about, then take my own with no itinerary. Contradiction is my brand.",
                    hue: 0.06,
                    photoName: "photo-lexi",
                    prompts: [
                        Prompt(question: "Best travel story", answer: "Got bumped to first class in Rome, ended up at a stranger's vineyard for dinner. Said yes to everything that week."),
                    ],
                    interests: ["Travel", "Wine", "Food", "Nightlife"],
                    isCopycat: true, copycatStyle: .poolside),

            Profile(name: "Paige Nolan", age: 31, role: .woman, location: "Calabasas, CA",
                    bio: "Wellness brand founder. I built my company poolside and I'm not apologizing for it. Work-life balance is just life.",
                    hue: 0.82,
                    photoName: "photo-paige",
                    prompts: [
                        Prompt(question: "Dating me is like", answer: "A five-star retreat — intentional, restorative, and you'll leave better than you came in."),
                    ],
                    interests: ["Fitness", "Startups", "Travel", "Design"],
                    isCopycat: true, copycatStyle: .poolside),

            Profile(name: "Sienna Clarke", age: 27, role: .woman, location: "Santa Barbara, CA",
                    bio: "Botanical illustrator. I spend most of my time outside, most of my money on plants, and most of my energy on people who deserve it.",
                    hue: 0.38,
                    photoName: "photo-sienna",
                    prompts: [
                        Prompt(question: "My happy place", answer: "Any garden, anywhere. The wilder the better."),
                    ],
                    interests: ["Art", "Reading", "Dogs", "Food"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Hayley James", age: 30, role: .woman, location: "Savannah, Georgia",
                    bio: "Restaurant owner. Sunday brunch is my religion and Saturday night is my confessional. I laugh loud and cook louder.",
                    hue: 0.20,
                    photoName: "photo-hayley",
                    prompts: [
                        Prompt(question: "The way to win me over is", answer: "Sit at the bar, order something interesting, and make me laugh before the food comes."),
                    ],
                    interests: ["Food", "Wine", "Music", "Travel"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Maya Santos", age: 26, role: .woman, location: "South Beach, Miami",
                    bio: "Marine biologist who somehow ends up at the beach even on days off. Science by day, salsa by night. I contain multitudes.",
                    hue: 0.48,
                    photoName: "photo-maya",
                    prompts: [
                        Prompt(question: "I'm weirdly good at", answer: "Identifying fish, dancing in heels, and leaving the party at exactly the right time."),
                    ],
                    interests: ["Travel", "Fitness", "Music", "Nightlife"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Autumn Reed", age: 28, role: .woman, location: "Asheville, North Carolina",
                    bio: "Trail runner and part-time park ranger. I named myself after a season and lived up to it — warm, colorful, and gone too fast.",
                    hue: 0.09,
                    photoName: "photo-autumn",
                    prompts: [
                        Prompt(question: "My ideal date", answer: "A trail at golden hour, then wherever the nearest firepit is. Bring layers."),
                    ],
                    interests: ["Fitness", "Travel", "Dogs", "Reading"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Cassidy Blake", age: 27, role: .woman, location: "Cabo San Lucas",
                    bio: "Yacht broker. I sell the dream and live it on weekends. If you can't handle a little salt water, we're not going to work.",
                    hue: 0.03,
                    photoName: "photo-cassidy",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Take the boat out, anchor somewhere nobody else is, and forget what day it is."),
                    ],
                    interests: ["Travel", "Nightlife", "Wine", "Fitness"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Nia Jordan", age: 29, role: .woman, location: "Arts District, Los Angeles",
                    bio: "Muralist and fitness coach. I paint walls by day and teach spin by evening. My arms are stronger than my patience for flakes.",
                    hue: 0.72,
                    photoName: "photo-nia",
                    prompts: [
                        Prompt(question: "Green flags I look for", answer: "Shows up when he says he will. Knows what he wants for dinner. Has hobbies that aren't screens."),
                    ],
                    interests: ["Art", "Fitness", "Music", "Food"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Yuki Tanaka", age: 26, role: .woman, location: "Santa Monica, CA",
                    bio: "Yoga instructor and breathwork facilitator. Sunrise on the pier is my temple. I move slow on purpose and it drives the right people crazy.",
                    hue: 0.76,
                    photoName: "photo-yuki",
                    prompts: [
                        Prompt(question: "My love language", answer: "Presence. Put the phone away and just be here with me."),
                    ],
                    interests: ["Fitness", "Travel", "Reading", "Music"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Charlotte Fox", age: 31, role: .woman, location: "Greenwich, Connecticut",
                    bio: "Antiques dealer. I know what things are worth and I don't negotiate on the ones that matter. Weekends are for estate sales and old wine.",
                    hue: 0.15,
                    photoName: "photo-charlotte",
                    prompts: [
                        Prompt(question: "Unusual skills", answer: "I can date a piece of furniture from across the room and pick the best bottle on any list."),
                    ],
                    interests: ["Art", "Wine", "Design", "Film"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Jordan Obi", age: 27, role: .woman, location: "Joshua Tree, CA",
                    bio: "Adventure photographer. I chase light for a living and silence for fun. The desert taught me patience — dates should too.",
                    hue: 0.30,
                    photoName: "photo-jordan",
                    prompts: [
                        Prompt(question: "Best travel story", answer: "Camped alone in the desert for a week shooting stars. Best photos I've ever taken. Worst cell service I've ever had."),
                    ],
                    interests: ["Art", "Travel", "Fitness", "Reading"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Lily Tran", age: 25, role: .woman, location: "Kitsilano, Vancouver",
                    bio: "UX designer who walks everywhere. Cherry blossom season is my Super Bowl. I notice the details you think nobody sees.",
                    hue: 0.88,
                    photoName: "photo-lily",
                    prompts: [
                        Prompt(question: "I geek out on", answer: "Typography, city planning, and the way light changes between 5 and 6 PM."),
                    ],
                    interests: ["Design", "Food", "Art", "Music"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Hana Kim", age: 24, role: .woman, location: "Queen Anne, Seattle",
                    bio: "Dance teacher and part-time barista. I know everyone's order and nobody's last name. My neighborhood is my whole world.",
                    hue: 0.64,
                    photoName: "photo-hana",
                    prompts: [
                        Prompt(question: "My simple pleasures", answer: "A matcha latte, a park bench, and watching dogs I don't own play fetch."),
                    ],
                    interests: ["Music", "Food", "Fitness", "Dogs"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Grace Ashford", age: 30, role: .woman, location: "Annapolis, Maryland",
                    bio: "Sailing instructor. I grew up on the water and I still haven't found a reason to leave it. Low maintenance, high standards.",
                    hue: 0.45,
                    photoName: "photo-grace",
                    prompts: [
                        Prompt(question: "Dating me is like", answer: "A day on the bay — calm on the surface, more going on underneath than you'd expect."),
                    ],
                    interests: ["Travel", "Fitness", "Reading", "Dogs"],
                    isCopycat: true, copycatStyle: .glam),

            Profile(name: "Destiny Moore", age: 28, role: .woman, location: "Sedona, Arizona",
                    bio: "Personal trainer and hiking guide. Golden hour is my office. I'll push you up the mountain and make you glad I did.",
                    hue: 0.94,
                    photoName: "photo-destiny",
                    prompts: [
                        Prompt(question: "My ideal date", answer: "Sunrise hike, then breakfast at the place only locals know. You carry the water, I'll pick the trail."),
                    ],
                    interests: ["Fitness", "Travel", "Food", "Music"],
                    isCopycat: true, copycatStyle: .yoga),

            Profile(name: "Stella Cruz", age: 27, role: .woman, location: "Sayulita, Mexico",
                    bio: "Surf photographer. I chase golden hour the way some people chase promotions. Salt water runs through everything I do.",
                    hue: 0.32,
                    photoName: "photo-stella",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Catch the last wave, rinse off, and eat tacos with sandy feet."),
                    ],
                    interests: ["Art", "Travel", "Fitness", "Music"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Britt Larson", age: 25, role: .woman, location: "Mission Beach, San Diego",
                    bio: "Physical therapist who spends every lunch break at the beach. Life's too short for bad vibes and long commutes.",
                    hue: 0.01,
                    photoName: "photo-britt",
                    prompts: [
                        Prompt(question: "My happy place", answer: "A towel, a good playlist, and absolutely nowhere I need to be."),
                    ],
                    interests: ["Fitness", "Music", "Food", "Travel"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Nova Ray", age: 26, role: .woman, location: "Playa del Carmen, Mexico",
                    bio: "Freediver and ocean conservationist. I hold my breath for a living and speak my mind for free. The sea is my therapist.",
                    hue: 0.50,
                    photoName: "photo-nova",
                    prompts: [
                        Prompt(question: "I'm weirdly good at", answer: "Holding my breath for four minutes, finding hidden beaches, and making friends in every country."),
                    ],
                    interests: ["Travel", "Fitness", "Art", "Reading"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Tessa Flynn", age: 28, role: .woman, location: "Maui, Hawaii",
                    bio: "Dive instructor by morning, bartender by night. I live on island time and I'm not going back. If you need a plan, I'm not your girl.",
                    hue: 0.87,
                    photoName: "photo-tessa",
                    prompts: [
                        Prompt(question: "Best travel story", answer: "Moved to Maui for a month. That was three years ago."),
                    ],
                    interests: ["Travel", "Nightlife", "Fitness", "Music"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Wren Bishop", age: 26, role: .woman, location: "Montauk, New York",
                    bio: "Photographer. Sunset is my golden hour and the beach is my studio. I shoot on film and live like it.",
                    hue: 0.28,
                    photoName: "photo-wren",
                    prompts: [
                        Prompt(question: "My simple pleasures", answer: "A cold drink, warm sand, and a conversation that doesn't need a phone."),
                    ],
                    interests: ["Art", "Travel", "Music", "Film"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Iris Calloway", age: 29, role: .woman, location: "Positano, Italy",
                    bio: "Ceramicist splitting time between Italy and Brooklyn. Freckles are earned, not filtered. I make beautiful things and keep messy hours.",
                    hue: 0.40,
                    photoName: "photo-iris",
                    prompts: [
                        Prompt(question: "The way to win me over is", answer: "Remember what I said last time. That's it. That's the whole thing."),
                    ],
                    interests: ["Art", "Travel", "Wine", "Food"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Adriana Vega", age: 27, role: .woman, location: "Barcelona, Spain",
                    bio: "Chef de partie at a Michelin kitchen. My days are loud and hot — I need my beach time quiet. Don't mistake calm for boring.",
                    hue: 0.52,
                    photoName: "photo-adriana",
                    prompts: [
                        Prompt(question: "I geek out on", answer: "Fermentation timelines, regional olive oils, and people who eat with their hands."),
                    ],
                    interests: ["Food", "Travel", "Wine", "Music"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Paloma Diaz", age: 25, role: .woman, location: "Tulum, Mexico",
                    bio: "Jewelry designer. Everything I make starts with something I found on the beach. Leopard print is a neutral — fight me.",
                    hue: 0.70,
                    photoName: "photo-paloma",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Get lost in a market, buy something we don't need, and eat street food until we can't move."),
                    ],
                    interests: ["Art", "Travel", "Design", "Food"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Suki Nakamura", age: 26, role: .woman, location: "Venice Beach, CA",
                    bio: "Content strategist who clocks out at 5 and is on the sand by 5:15. Iced coffee is a personality trait and I've accepted it.",
                    hue: 0.66,
                    photoName: "photo-suki",
                    prompts: [
                        Prompt(question: "My ideal date", answer: "Golden hour at the beach, then ramen at the place with no sign. If you know, you know."),
                    ],
                    interests: ["Food", "Music", "Design", "Travel"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Kiana Reyes", age: 25, role: .woman, location: "North Shore, Oahu",
                    bio: "Surf school owner. Born in the water, raised by the tide. I'll teach you to stand up on a board and sit down at a real table.",
                    hue: 0.74,
                    photoName: "photo-kiana",
                    prompts: [
                        Prompt(question: "My happy place", answer: "Any beach, any island, as long as I can hear the waves while I eat."),
                    ],
                    interests: ["Fitness", "Travel", "Food", "Music"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Simone Hart", age: 28, role: .woman, location: "Turks and Caicos",
                    bio: "Former pro swimmer, current water-sports instructor. I've never met an ocean I didn't like or a man who could keep up in it.",
                    hue: 0.34,
                    photoName: "photo-simone",
                    prompts: [
                        Prompt(question: "I'm weirdly good at", answer: "Swimming in open water, reading people, and making fish tacos from scratch."),
                    ],
                    interests: ["Fitness", "Travel", "Food", "Nightlife"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Ava Sinclair", age: 27, role: .woman, location: "Martha's Vineyard, MA",
                    bio: "Music journalist. I interview people for a living, so expect good questions and zero awkward silence. Beach days are non-negotiable.",
                    hue: 0.56,
                    photoName: "photo-ava",
                    prompts: [
                        Prompt(question: "Together we could", answer: "Skip the small talk — tell me the thing you never tell people on the first date."),
                    ],
                    interests: ["Music", "Travel", "Food", "Film"],
                    isCopycat: true, copycatStyle: .beach),

            Profile(name: "Kai Williams", age: 29, role: .woman, location: "Outer Banks, North Carolina",
                    bio: "Fitness coach and beach volleyball captain. My laugh carries, my standards are higher, and I've never left a party early.",
                    hue: 0.84,
                    photoName: "photo-kai",
                    prompts: [
                        Prompt(question: "The way to win me over is", answer: "Show up with energy. Match mine. Don't try to dim it."),
                    ],
                    interests: ["Fitness", "Music", "Travel", "Nightlife"],
                    isCopycat: true, copycatStyle: .beach),
        ].map { $0.seededLifestyle() }
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
                        Prompt(question: "The way to win me over is", answer: "Care about something and let me ask you questions about it."),
                    ],
                    interests: ["Reading", "Food", "Music"],
                    reviews: [
                        DateReview(authorName: "Priya", authorHue: 0.08, stars: 5,
                                   text: "Bid modestly and over-delivered. Paid every cent, walked me home, texted the next day.",
                                   paidBid: true, bidAmount: 120, spentAmount: 160),
                    ],
                    verified: true,
                    archetype: .goodGuy),
        ].map { $0.seededLifestyle() }
    }
}
