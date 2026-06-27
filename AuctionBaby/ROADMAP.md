# Auction Baby — Feature Roadmap

A living plan. Shipped items reflect what's in the branch today.

## ✅ Shipped (v1.0)

**Core auction loop**
- Two roles: The Lot (woman) and The Bidder (man), role-aware tab bar
- Hinge-style floor feed with prompts, interests, generated portraits
- Bid composer; bids are no-money **letters of intent**
- Bid inbox: accept / decline; the woman sends the first invite
- Matches, chat, mark-date-done, two-sided post-date reviews

**Reputation system ("credit scores")**
- Auction Credit (300–850) for men — archetype tier, deadbeat score, copycat penalty
- Showcase Score + market value for women — from trait reviews
- Earned-and-verified **Trillionaire** (buy → pay $9,999 on a date → confirmed)
- **Masterpiece** — minted only by a confirmed Trillionaire date
- Identity **verification** (blue check); copycats can never verify
- AI **Copycat** lures — richly animated, disclosed, credit-damaging

**Premium & monetization (StoreKit 2)**
- Gavels consumable currency → status archetypes
- Auction Baby Pass (Paddle / Reserve / Black Card) with real gated perks:
  rank reveal, unlimited bids, read receipts
- Spotlight Boost (consumable) — works both sides
- Gilded bids (the "Rose")
- Headliner of the Day (curated standout)

**Trust & safety**
- Safety Center, Report & Block, premium floor filters

**Craft**
- iOS 26 Liquid Glass (graceful iOS 17–25 fallback), adaptive haptics,
  "SOLD!" match celebration, Reduce Motion + Dark Mode, vector logo + icon
- XCTest coverage of the domain logic; `Products.storekit` for IAP testing

## 🔜 Next (v1.1)

- Real backend + accounts (guest vs verified tiers), cloud sync
- Live presence + push notifications ("You've been outbid")
- KYC-gated real-world date payments via a licensed processor (marketplace fee)
- Photo upload + on-device safety/NSFW screening
- Onboarding glow-up: multi-step, dealbreakers, voice prompts
- Woman-side bidder filters & saved searches

## 🌅 Later (v1.2+)

- "We met?" safety check-ins and date-share
- Proxy / auto-rebid engine and live outbid alerts
- Localization, accessibility audit (VoiceOver pass), iPad layout
- Trust graph: weighted reputation, fraud/Copycat detection
- Events / curated "auction nights"

## North star

The most honest dating market on the App Store: money proves intent,
reputation is earned, and the fakes are always labelled.
