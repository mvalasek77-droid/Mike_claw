import SwiftUI

/// Terms of Service + Privacy Policy, bundled so they can be read offline.
struct LegalView: View {
    enum Kind { case terms, privacy }
    let kind: Kind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.title2.bold())
                Text(effectiveDate).font(.caption).foregroundStyle(.secondary)
                ForEach(sections, id: \.title) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.title).font(.headline)
                        Text(s.body).font(.callout).foregroundStyle(.primary.opacity(0.9))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        kind == .terms ? "Terms of Service" : "Privacy Policy"
    }

    private var effectiveDate: String {
        "Effective: 2026-01-01 · v1.0"
    }

    private var sections: [(title: String, body: String)] {
        switch kind {
        case .terms:  return Self.termsSections
        case .privacy: return Self.privacySections
        }
    }

    private static let termsSections: [(title: String, body: String)] = [
        ("1. What BoxCall is",
         "BoxCall is an entertainment app. You place virtual, play-money 'Call' and 'Put' contracts on the opening-weekend domestic box-office grosses of upcoming movies. Reel Coins are a play-money score and cannot be exchanged for cash, prizes, or anything of monetary value."),
        ("2. Not gambling, not investing",
         "Nothing on BoxCall is a securities offering, event contract, or wager under the laws of the United States or any other jurisdiction. No purchase or subscription gives you any chance of winning money or property of real-world value."),
        ("3. Subscriptions",
         "Optional monthly subscriptions grant more Reel Coins and cosmetic perks. Subscriptions auto-renew until cancelled in your App Store settings at least 24 hours before the renewal date."),
        ("4. Community conduct",
         "You will not post content that is unlawful, harassing, hateful, sexually explicit, threatening, or infringes on intellectual property. We may remove content and terminate accounts that violate these rules."),
        ("5. Movie data",
         "Movie titles, posters, and metadata are provided by third-party sources (TMDB, IMDb, Box Office Mojo, The Numbers, Deadline) under their respective terms. All trademarks belong to their owners."),
        ("6. Disclaimers",
         "BoxCall is provided 'as is' without warranties. We do not guarantee availability, accuracy of tracking numbers, or timeliness of settlement. Our liability is limited to the amount you paid us in the preceding 12 months."),
        ("7. Changes",
         "We may update these terms; continued use after an update means you accept the new terms.")
    ]

    private static let privacySections: [(title: String, body: String)] = [
        ("What we collect",
         "Everything you do in BoxCall — Reel Coins, trades, rank, posts and reviews — is stored only on your device. If you Sign in with Apple, the Apple user ID and, if you share it, your email are also stored only on your device. We do not run a server that holds your account."),
        ("What we do not collect",
         "We do not sell your data. We do not read your contacts. We do not track you across other apps or websites. We do not use third-party ad networks."),
        ("Analytics",
         "BoxCall does not send analytics off your device."),
        ("Third-party services",
         "TMDB delivers movie metadata directly to the app; YouTube's public API is used to fetch trailer view counts; opening-weekend results are downloaded from a public BoxCall data file hosted on GitHub Pages. These providers see the requests we send but not your identity."),
        ("Push notifications",
         "You can grant or deny notification permission at any time in iOS Settings. We only send transactional notifications (settlements, badges, opening reminders, refunds)."),
        ("Data deletion",
         "Go to Profile › Delete account and data. This permanently erases your account, trades, posts, reviews and sign-in details from your device. Deleting the app also removes all of it."),
        ("Children",
         "BoxCall is 13+. If we learn we have collected data from a child under 13, we will delete it.")
    ]
}
