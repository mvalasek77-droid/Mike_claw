# Auction Baby — App Store Listing

Working draft of App Store Connect metadata. All copy is sized to Apple's
character limits.

## Identity

- **App name:** Auction Baby
- **Subtitle (30 chars):** Bid for the date. Earn it.
- **Primary category:** Lifestyle
- **Secondary category:** Social Networking
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
> • Showcase Score for the lot — earned from real date reviews
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

All prices are under Apple's IAP ceiling. The app never processes real date
payments — those are a real-world, person-to-person service and stay off-platform.

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

- Status archetypes and bids are denominated in **Gavels**, an in-app currency
  purchased via StoreKit. The "$9,999 / Trillionaire" figures are symbolic
  in-game status, not real charges.
- The **date payment** is a real-world service settled between two people; the
  app does not collect, hold, or process it (no escrow / money transmission).
- "Copycat" profiles are clearly disclosed as AI-generated.
- A `Products.storekit` configuration is included for testing all purchases in
  the simulator.

## Demo account

No login required — choose a role on launch and explore. Use the bid inbox's
"Summon the Trillionaire" action and the profile's verification + store flows to
exercise the full premium surface.
