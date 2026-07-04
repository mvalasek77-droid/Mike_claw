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
  rank reveal, unlimited bids, read receipts, weekly Boost claim
- Contextual paywall fired at four peak-intent moments (outbid rank, bid
  cap, locked filters, "did she read it?") with a per-tier benefits matrix
- Spotlight Boost (consumable) — works both sides (lot side pulls bidders in)
- Gilded bids (the "Rose") · bid on a specific prompt
- Headliner of the Day (curated standout)

**Retention loops**
- Outbid → one-tap rebid ("take the top")
- Daily Gavel claim with growing streak (capped 7×)
- Activity feed (bids, accepts, reviews, milestones) with toolbar bell
- "SOLD!" celebration · "What you're worth tonight" dashboard
- 24-hour match-reply clock (Bumble-style urgency) with a live countdown;
  cold matches lock the composer
- Rewind your last bid (Reserve+ Pass perk)
- Typing indicators + double-tap / long-press message reactions
- Icebreaker suggestions generated from the other profile's own prompts
  and interests, shown until the human sends their first real reply

**Credit system**
- Bureau-style Auction Credit / Showcase Credit (300–900, 900 = perfect),
  factor-based with a written report (payment history, status, track
  record, identity, copycat incidents, personality-weighted for women)
- Honors ladder (Fresh Canvas → Exhibition Star) achievable through dates
  and reputation; Masterpiece sits above it, minted only by a Trillionaire
  paying $1,000,000 for one evening and confirmed by her — never climbed to
- Animated odometer score count-ups, perfect-900 crown, "credit moved"
  Activity pings, honors-ladder climb celebrations

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
