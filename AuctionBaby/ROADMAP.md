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
  rank reveal, unlimited bids, read receipts, weekly Boost claim,
  reserve price reveal (Reserve+), auto-rebid on decline (Reserve+),
  priority placement in inbox (Black Card)
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
- Credit-correlated reviews: a bidder's written verdicts always agree with his
  number — a short check always reads as a deadbeat, and among men who paid the
  praise scales with standing (poor credit reads guarded, exceptional glows)
- Founder admin console (add / remove lots on the floor, live + persisted),
  gated to the founder account

**Craft**
- iOS 26 Liquid Glass (graceful iOS 17–25 fallback), adaptive haptics,
  "SOLD!" match celebration, Reduce Motion + Dark Mode, vector logo + icon
- XCTest coverage of the domain logic; `Products.storekit` for IAP testing
- VoiceOver-announced toasts, accessibility labels on floor cards and bid rows

**Money infrastructure**
- StoreKit 2 with `appAccountToken`, transaction dedup, crash-safe
  credit-first ordering, revocation clawback, foreground refund polling
- AES-GCM encrypted state persistence with Keychain-backed master key
- Cloudflare Worker backend with Stripe Connect Express payouts,
  Apple ASSN V2 JWS verification, append-only KV money ledger
- HMAC-gated admin console: float status, pay-now, ledger, moderation
- Demo Mode for App Review (name "demo", free counterparts of every
  paid product, demo Pass, seeded wallet)

## 🔜 Next (v1.1)

- Real backend + accounts (guest vs verified tiers), cloud sync
- Live presence + push notifications ("You've been outbid")
- KYC-gated real-world date payments via a licensed processor (marketplace fee)
- Consumable credit purchases via Stripe Checkout — scaffolded as a standalone
  Cloudflare Worker (`ai-marketplace-consumables/`): catalog → hosted Checkout →
  signed webhook → idempotent crediting → spend/ledger. (Digital consumables in
  the iOS app itself stay on StoreKit per Apple's rules; Stripe is for web /
  real-world surfaces.)
- Photo upload + on-device safety/NSFW screening
- Onboarding glow-up: multi-step, dealbreakers, voice prompts
- Woman-side bidder filters & saved searches

## 🧊 iOS 26 Liquid Glass (v1.1 theme)

- Tab bar: `.glassEffect(.regular)` with adaptive tint per tab
- Navigation bars: native Liquid Glass chrome, translucent scroll behaviour
- Cards: swap GlassSurface to `GlassBackground` material with depth tinting
- Paywall + celebration: frosted depth layers with live blur radius animations
- Haptics: `SensoryFeedback` API (`.impact`, `.selection`, `.notification`)
  replacing the UIKit haptic engine for tighter Glass-era feel
- Floating action buttons: new `.glassProminentButtonStyle` on bid CTAs
- Adaptive color: use `Color.resolvedDynamic()` to tint glass surfaces with
  the gold/rose theme palette while respecting light/dark appearance
- Graceful fallback: `#available(iOS 26, *)` gates; iOS 17–25 gets the
  current hand-rolled glass aesthetic

## 🌅 Later (v1.2+)

- "We met?" safety check-ins and date-share
- Live outbid alerts and push notifications
- Localization, full accessibility audit (VoiceOver pass), iPad layout
- Trust graph: weighted reputation, fraud/Copycat detection
- Events / curated "auction nights"

## North star

The most honest dating market on the App Store: money proves intent,
reputation is earned, and the fakes are always labelled.
