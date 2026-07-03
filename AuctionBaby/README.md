# Auction Baby

> **Find a high value man, find out what you're worth.**

An auction-house dating app for iOS. Men bid what they'll spend on a date; women
set a floor and accept when the number's right. Both sides build a public
"credit score" from how the date actually went — and money is the whole point.

Built in SwiftUI with the iOS 26 **Liquid Glass** design language (fluid
glassmorphism, depth/parallax, adaptive haptics), gracefully degrading to a
hand-tuned material on iOS 17–25.

---

## The concept

| Side | Role | What they do |
| --- | --- | --- |
| **The Lot** (woman) | always-visible profile | sets an optional starting bid, reads each bidder's stats, accepts when a bid is high enough, then sends the first invite |
| **The Bidder** (man) | photo hidden until accepted | browses the floor, bids what a date is worth, buys a status archetype, builds reputation |

## Money model (important)

There is exactly **one** thing real money buys in the app, and one thing it does not:

- **Status & subscriptions → real money (StoreKit).** Buying status archetypes
  (paid in Gavels you top up) and any premium subscription are the *only* digital
  purchases. Apple takes its cut; all prices sit under the IAP ceiling.
- **A bid → a letter of intent. No money moves in the app.** A bid is a declared
  commitment of what he'll spend on a date — not a charge. The **actual date
  money is settled in the real world, peer-to-peer**, and the app never touches,
  holds, or processes it.
- **She confirms or declines after the date.** Her confirmation is what drives the
  deadbeat score and Trillionaire verification. Because the app never custodies
  the date money, there's no escrow / money-transmitter burden on the bid side.

### StoreKit

Real money flows through **StoreKit 2** only (`Services/StoreKitService.swift`,
`Products.storekit`):

- **Gavels** — consumable currency packs ($4.99–$99.99). Verified purchases
  credit the wallet; status archetypes are bought by spending Gavels. The grant
  path is keyed by `transaction.id` (no double-credit) and refunds are clawed
  back from `Transaction.updates` / `Transaction.all`.
- **Auction Baby Pass** — auto-renewable subscriptions (Paddle / Reserve / Black
  Card), tracked via `Transaction.currentEntitlements`.
- The store UI (`Features/Store/GavelStoreView.swift`) includes the required
  Restore action and auto-renew disclosure. The bundled `Products.storekit`
  scheme config lets the whole flow run in the simulator.

### Credit scores

- **Auction Credit** (men, 300–850): a credit-score analogue driven by archetype
  tier (money), a **deadbeat score** (did he actually pay what he bid?), repeat
  business, and a penalty for bidding on AI copycats.
- **Showcase score** (women, 0–100): built from the five traits a date rates her
  on — Fun, Interesting, Social, Polite, Genuine — plus her **market value**.

### Archetypes — buy your rating

The price *is* the flex: the app exists to surface whether a man has money.

| Price | Rating |
| --- | --- |
| Free | No Rating |
| $5 | Good Guy |
| $10 | In & Out Guy |
| $20 | Why Not Guy |
| $100 | Got a Good Job |
| $1,000 | Inheritance Money Guy |
| $2,500 | Influencer |
| $5,000 | I Drive a Ferrari |
| $9,999 | **Trillionaire** |

> Prices are kept under Apple's in-app purchase ceiling (~$9,999.99) so every
> tier can be a real StoreKit purchase. The "$1,000,000" flex lives on the
> *bid* side (a symbolic, credit-denominated date offer), which is what mints a
> woman's Masterpiece — not the badge price.

### Trillionaire (earned, not bought)

Trillionaire is the only *verified* tier — three gates, all required:

1. Buy the badge (**$9,999** IAP) → status reads **"Pending"**
2. Bid **and pay the full $9,999** on a real date
3. **She confirms** he paid in full → badge flips to **Trillionaire ✓**

### Masterpiece

The rarest object on the floor. A woman earns a **Masterpiece** rating *only* on
that same confirmed date — when a **Trillionaire** pays the full **$9,999** and
she confirms it. So a Masterpiece inherits all three Trillionaire gates.

### Copycats

AI-generated "11/10" lure profiles. They're flagged everywhere (`Copycat · AI`),
and bidding on one is disclosed publicly and **lowers the bidder's Auction Credit**.

Each copycat renders as a **richly animated, deliberately *synthetic* portrait**
(`CopycatPortrait`) — iridescent holographic backdrops, a drifting bloom, a
sweeping holo-sheen, twinkling sparkles and a stylised fashion silhouette, with
the AI disclosure **baked into the image**. There is no photography: the
"bikini / poolside / beach / yoga" looks are carried by palette and silhouette
(`CopycatStyle`), never by exposed bodies — so the bait is gorgeous and
obviously generated, stays tasteful and App-Store-safe, and keeps the
credit-tanking gameplay legible. All animation is `TimelineView`-driven and goes
fully static under Reduce Motion.

---

## Architecture

```
AuctionBaby/
├── project.yml                  # XcodeGen source of truth
├── AuctionBaby.xcodeproj/       # committed project (objectVersion 77, synced groups)
├── Config/Build.xcconfig
├── ci_scripts/ci_post_clone.sh  # Xcode Cloud hook (regenerates project via XcodeGen)
├── AuctionBaby/
│   ├── App/                     # entry, root, splash, role-aware tab bar
│   ├── Theme/                   # colour/geometry tokens, Motion + adaptive Haptics
│   ├── Components/              # GlassKit, brand mark, avatars, gauges, badges, flow layout
│   ├── Models/                  # Role, Archetype, Profile (+ derived scores), Bid, Match
│   ├── Store/                   # AuctionStore (single source of truth) + sample data
│   ├── Features/                # Onboarding, Browse, Bids, Matches, Archetype, Profile
│   └── Resources/               # Info.plist, asset catalog (vector-rendered app icon)
└── AuctionBabyTests/            # XCTest coverage of the domain logic
```

**Design notes**

- **One value-typed model both ways.** `Profile`, `Bid` and `Match` are `Codable`
  value types; bids/matches carry profile *snapshots* so records are
  self-contained and the whole graph persists to `UserDefaults`.
- **Solo-playable simulation.** With no backend, `AuctionStore` simulates the
  other side — women weigh bids against their floor and the bidder's credit,
  copycats take the bait, chats reply — all Reduce-Motion- and main-actor-safe.
- **No real content.** Every "photo" is a deterministic gradient + monogram, so
  the concept reads clearly while staying tasteful and SFW. All money is play
  money; there is no IAP and no network.
- **Accessibility first.** Honours Dark Mode and Reduce Motion system-wide; all
  scores, badges and bubbles carry accessibility labels.

## Real photos

Profiles carry a `photoName` (see `Store/SampleData.swift` — `photo-mara`,
`photo-priya`, `photo-mike`, …). Add **licensed** images to
`AuctionBaby/Resources/Assets.xcassets` under those names and they render
everywhere automatically — feed cards, detail pages, chat, celebrations — with
the generated portrait as the fallback when an asset is missing. Portrait-crop
(~3:4) looks best. Copycat profiles with photos keep a small baked-in `AI`
watermark: the imagery can look completely real, but the disclosure always
travels with the picture (required for App Review and FTC compliance — fake
undisclosed profiles are what got Match.com sued).

## Building

```bash
# Open directly (project is committed):
open AuctionBaby/AuctionBaby.xcodeproj

# …or regenerate from project.yml:
cd AuctionBaby && xcodegen generate
```

Target: iOS 17+. No third-party dependencies.

## Tests

`AuctionBabyTests/AuctionLogicTests.swift` covers archetype pricing, the credit
and showcase score math, the deadbeat calculation, the copycat penalty, the
Masterpiece rule, and the core store flows (register → bid → accept → review).
