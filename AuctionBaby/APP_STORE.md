# Auction Baby — App Store Listing

Working draft of App Store Connect metadata. All copy is sized to Apple's
character limits.

## Identity

- **App name:** Auction Baby
- **Subtitle (30 chars):** Bid for the date. Earn it.
- **Primary category:** Social Networking
- **Secondary category:** Lifestyle
- **Age rating:** 17+ (mature/suggestive themes, simulated relationships)
- **Bundle ID:** com.valasek.auctionbaby

## Promotional text (170 chars)

> Find a high value man, find out what you're worth. Men bid what a date is
> worth; she accepts when the number's right. Reputation is everything.

## Description

> **Auction Baby is the dating app that runs like an auction house.**
>
> Men browse the floor and bid what a date is actually worth. Women set a floor,
> read every bidder's reputation, and accept when the number's right. A bid is a
> letter of intent — no money changes hands in the app; you settle in person and
> she confirms afterward. Pay what you bid and your reputation climbs. Fall short
> and you're flagged a deadbeat.
>
> **Reputation is the whole game.**
> • Auction Credit (300–900) for bidders — built on whether you actually pay
> • Showcase Credit (300–900) for the lot — earned from real date reviews
> • Identity verification — a blue check the floor can trust
>
> **Status you earn, not just buy.**
> Climb the archetypes from Good Guy to Trillionaire. The top tier is *earned*:
> bid and pay the full amount on a real date, and get confirmed. Only a verified
> Trillionaire can mint a woman's rarest honor — the Masterpiece.
>
> **Spot the fakes.** AI "Copycat" lures are labelled everywhere. Bidding on one
> is public and tanks your credit.
>
> **Premium that's worth it.**
> • Auction Baby Pass — see if you're the top bid, unlimited bids, auto-rebid,
>   read receipts, priority placement
> • Spotlight Boost — 30 minutes at the top of the floor
> • Gilded bids — pin your bid to the top of her inbox
>
> Beautiful, fast, and built for iOS — Liquid Glass design, adaptive haptics,
> full Dark Mode and Reduce Motion support.
>
> Auction Baby is for entertainment. Profiles in this build are fictional; all
> in-app currency is play money. Real date payments happen in the real world —
> never wire money or send deposits.

## Keywords (100 chars)

`dating,auction,bid,match,singles,date,chat,relationship,verified,luxury,premium,meet,love,flirt`

## What's New (first release)

> Welcome to the floor. Place your first bid, build your reputation, and find out
> what you're worth.

## In-App Purchases

| Display name | Type | Price |
| --- | --- | --- |
| Handful of Gavels | Consumable | $4.99 |
| Stack of Gavels | Consumable | $19.99 |
| Chest of Gavels | Consumable | $49.99 |
| Vault of Gavels | Consumable | $99.99 |
| Spotlight Boost | Consumable | $3.99 |
| Paddle (Pass) | Auto-renewable | $19.99/mo |
| Reserve (Pass) | Auto-renewable | $39.99/mo |
| Black Card (Pass) | Auto-renewable | $99.99/mo |
| Good Guy (status) | Non-consumable | $4.99 |
| In & Out Guy (status) | Non-consumable | $9.99 |
| Why Not Guy (status) | Non-consumable | $19.99 |
| Got a Good Job (status) | Non-consumable | $99.99 |
| Inheritance Money Guy (status) | Non-consumable | $999.99 |
| Influencer (status) | Non-consumable | $2,499.99 |
| I Drive a Ferrari (status) | Non-consumable | $4,999.99 |
| Trillionaire (status) | Non-consumable | $9,999.99 |

The eight status ratings are the app's core premise made literal — the rating
a man wears *is* what he paid for it. They're non-consumables: bought once,
owned forever, re-wearable free, and a refund drops the badge to the best
rating still held. Gavels (the consumable currency) buy tactical moves —
Gilded Bids, Bid Insurance, streak freezes — never status.

⚠️ **The three above $999.99 require requesting high price points in App Store
Connect** (Apple grants access case-by-case). Trillionaire sits exactly at
Apple's $9,999.99 ceiling.

The app never processes real date payments — those are a real-world,
person-to-person service and stay off-platform. The one real-world charge the
app *does* collect is the optional **"Reserve the date"** booking fee (Stripe,
not IAP — see review notes): a small platform-kept reservation fee, never paid
to the other person, unlocking nothing in the app.

## Privacy nutrition labels

This build is client-local for every consumer surface: no analytics SDKs, no
tracking identifiers, no third-party auth. A founder-only payout Worker
(gated behind admin credentials, never exercised by end users) handles Stripe
Connect payouts and Apple refund routing when the operator has configured it;
it is off in the default build.
- **Data used to track you:** None
- **Data linked to you:** None
- **Data not linked to you:** Purchases (IAP, via Apple); an anonymous
  `appAccountToken` (per-install UUID, no PII) sent with each IAP so Apple's
  refund webhook can route to the correct wallet.
- A production launch would add: name, photos, and identity-verification media
  (used for app functionality and safety; not for tracking).

## Review notes

- **Bids** are denominated in dollars but are *letters of intent* — no charge
  is made in the app. The eight status **ratings** are genuine non-consumable
  IAPs at their listed prices; the price is the product (the app's premise is
  that what a man pays for his rating is the signal). **Gavels**, the
  consumable currency, buy tactical moves only — never status.
- **"Reserve the date"** is a real-world booking fee (bidder picks a tier —
  $10 / $15 / $25 / $50 / $100) a bidder can pay *after* a match, to reserve
  the in-person date. It is intentionally **NOT** an in-app purchase: per
  guideline 3.1.3/3.1.5 it is a physical, real-world service between two
  people, so it is collected via **Stripe**, not IAP. It is kept by the
  platform (a reservation/booking fee), never paid to the other person, and it
  **unlocks no in-app content or functionality** — the app only shows the date
  as "reserved," identically at every tier (the amount is a real-world deposit,
  not a purchase of anything in the app). In Demo Mode a reviewer can exercise
  it free ("Demo: reserve free") with no Stripe account. The feature has a
  server-side kill-switch, so it can be disabled without an app update if
  needed.
- The "$1,000,000 Masterpiece" is a **real-world date payment** between two
  people, never an in-app charge.
- The **date payment** is a real-world service settled between two people; the
  app does not collect, hold, or process it (no escrow / money transmission).
- "Copycat" profiles are clearly disclosed as AI-generated.
- A `Products.storekit` configuration is included for testing all purchases in
  the simulator.

## Demo account

No login required — choose a role on launch and explore. Use the bid inbox's
"Summon the Trillionaire" action and the profile's verification + store flows to
exercise the full premium surface.
