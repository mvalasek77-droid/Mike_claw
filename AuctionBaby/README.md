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

## What ships in v1.0

**Core auction loop** — role-aware tab bar, Hinge-style feed with prompts +
generated portraits (or user uploads), bid composer, accept/decline inbox,
matches with 24h reply clock, chat with reactions/typing/icebreakers,
two-sided post-date reviews, Reduce Motion + Dark Mode.

**Reputation ("credit scores")** — Auction Credit (300–900) for men,
Showcase Credit (300–900) for women, deadbeat score, factor-based written
credit reports, honors ladder (Fresh Canvas → Exhibition Star →
Masterpiece), earned-and-verified Trillionaire, blue-check verification,
hidden AI Copycat lures that only reveal after a bid.

**Multi-photo profile** — `PhotosPicker`-backed upload up to 6 photos
(primary + gallery), drag-reorder, ≥ 600×600 quality gate, JPEG resize to
1600px, rides the AES-GCM encrypted archive. Gradient monogram fallback
when the user skips.

**Reserve Requirements (dealbreaker filters)** — Reserve-tier gated;
minimum height (rendered ft/in from cm), smoking, drinking, kids,
education. Blank fields on a target profile always pass — we don't
punish incomplete profiles.

**Integrity + funnel bundle**
- **Gavel Confirmed** — mutual meetup verification; corroborated reviews
  carry +72 (men) / +60 (women) in the credit reports, self-reported
  reviews are downweighted.
- **Opening Bid Script** — Bumble-style woman-authored opener that
  auto-sends the moment she accepts a bid.
- **Whisper** — anonymous, zero-Gavel, zero-credit-impact signal of
  interest. Doesn't count against the free live-bid ceiling.
- **Lot of the Day** — daily-rotating pinned banner + full-screen
  first-open-of-day intro sheet.
- **On the Floor Now** — deterministic hour-of-day live-presence dots
  on ~30% of non-copycat profiles.

**Retention + revenue trio**
- **Bid Insurance** — 200-Gavel premium; if she declines, premium + a
  Gilded Bid credit refunded.
- **The Docket** — daily-claim variable-reward mystery box + streak-freeze
  inventory (purchasable for 500 Gavels).
- **The Standing** — weekly cosmetic city leaderboards for top bidders
  and most-contested lots.

**Money infrastructure** — StoreKit 2 with `appAccountToken` for refund
routing, transaction dedup, crash-safe credit-first ordering, AES-GCM
encrypted archive, Cloudflare Worker backend (Stripe Connect Express
payouts, Apple ASSN V2 JWS refund poll), founder admin console gated by
HMAC credentials, Demo Mode for App Review.

Full detail per feature lives in `ROADMAP.md`.

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

- **Auction Credit** (men, 300–900): a credit-score analogue driven by archetype
  tier (money), a **deadbeat score** (did he actually pay what he bid?), repeat
  business, and a penalty for bidding on AI copycats.
- **Showcase Credit** (women, 300–900): a matching bureau-scale rating built from
  the five traits a date rates her on — Fun, Interesting, Social, Polite,
  Genuine — plus her **market value**. Her `showcaseScore` (0–100) is the
  internal roll-up of the trait averages; `showcaseCredit` (300–900) is what
  the UI card displays, so the two sides read on the same scale.

### Archetypes — buy your rating

The price *is* the flex: the app exists to surface whether a man has money.
So **every rating is a real purchase** — the number under the badge is what he
actually paid. Gavels deliberately can't buy status.

| Rating | Price | Type |
| --- | --- | --- |
| No Rating | Free | — |
| Good Guy | $4.99 | Non-consumable |
| In & Out Guy | $9.99 | Non-consumable |
| Why Not Guy | $19.99 | Non-consumable |
| Got a Good Job | $99.99 | Non-consumable |
| Inheritance Money Guy | $999.99 | Non-consumable |
| Influencer | $2,499.99 | Non-consumable |
| I Drive a Ferrari | $4,999.99 | Non-consumable |
| **Trillionaire** | **$9,999.99** | Non-consumable |

All eight are **non-consumables**: bought once, owned forever, and switching
between ratings you own is free. A refund drops the badge to the best rating
you still hold.

> **Apple's IAP ceiling is $9,999.99**, and price points above $999.99 require
> requesting access in App Store Connect. Trillionaire sits exactly at the
> ceiling; Influencer and Ferrari also need that request granted. Everything
> from Good Guy through Inheritance is a standard price point.
>
> Separately, the **$1,000,000 Masterpiece** figure lives on the *bid* side — a
> real-world date payment settled peer-to-peer, never an IAP. Buying the
> Trillionaire badge only unlocks the *attempt*; paying $9,999 on a confirmed
> date is what verifies it.

### Gavels — the tactical currency

Gavels are bought in consumable packs ($4.99–$99.99) and earned from the daily
claim. They buy **moves, not status**:

| Spend | Cost |
| --- | --- |
| Gilded Bid (pins to the top of her inbox) | 250 Gavels |
| Bid Insurance (refunded if she declines) | 200 Gavels |
| Streak freeze (protects the daily streak) | 500 Gavels |

### Trillionaire (earned, not bought)

Trillionaire is the only *verified* tier — three gates, all required:

1. Buy the badge (**$9,999** IAP) → status reads **"Pending"**
2. Bid **and pay the full $9,999** on a real date
3. **She confirms** he paid in full → badge flips to **Trillionaire ✓**

### Masterpiece

The rarest object on the floor. Separate, higher bar than Trillionaire
verification: a woman earns a **Masterpiece** rating *only* when a **verified
Trillionaire** bids and pays **$1,000,000** for one evening — and she confirms
it. The $9,999 gates verify the Trillionaire badge; the $1,000,000 gate mints
the Masterpiece.

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
- **Photos are optional.** Users can upload up to six real photos via
  `PhotosPicker`; without them, a deterministic gradient + monogram stands in
  so the concept reads clearly while staying tasteful and SFW.
- **Real StoreKit 2 monetization.** Gavel packs ($4.99–$99.99), Spotlight Boost
  ($3.99), Auction Baby Pass subscriptions ($19.99 / $39.99 / $99.99 / month).
  Refunds route through a Cloudflare Worker keyed on an anonymous
  `appAccountToken`. Real-world date money is peer-to-peer; the app doesn't
  route dates through IAP.
- **Stripe web Gavel shop.** A second Worker (`consumables/`) sells the same
  Gavel ladder through hosted Stripe Checkout for web surfaces — Apple's rules
  keep in-app digital Gavels on StoreKit, but the web shop pays Stripe's ~3%
  instead of Apple's cut. The app drains web-purchased Gavels into the local
  wallet on foreground (idempotent, refund-aware).
- **Accessibility first.** Honors Dark Mode and Reduce Motion system-wide; all
  scores, badges and bubbles carry accessibility labels.

## Real photos

Two paths, coexisting cleanly:

1. **User uploads (real users).** Onboarding and Profile → Edit photos open a
   `PhotosPicker` for up to six images (see `Features/Onboarding/PhotoUploadStep.swift`).
   Each photo is quality-gated (≥ 600×600, ≥ 30KB), resized to a 1600px long
   edge, re-encoded as JPEG(0.85), then written into the same AES-GCM
   encrypted profile archive as the rest of the account. `AvatarView` resolves
   `photoData` first, `photoName` (asset catalog) second, gradient monogram
   third — so bundled sample data keeps working unchanged.

2. **Bundled sample data.** Profiles carry a `photoName` (see
   `Store/SampleData.swift` — `photo-mara`, `photo-priya`, `photo-mike`, …).
   Drop **licensed** images into `AuctionBaby/Resources/Assets.xcassets` under
   those names and they render on the seeded floor. Portrait-crop (~3:4) looks
   best.

Copycat profiles with photos keep a small baked-in `AI` watermark: the
imagery can look completely real, but the disclosure always travels with
the picture (required for App Review and FTC compliance — fake undisclosed
profiles are what got Match.com sued).

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
