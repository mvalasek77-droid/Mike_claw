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
- Auction Credit (300–900) for men — archetype tier, deadbeat score, copycat penalty
- Showcase Credit (300–900) + market value for women — from trait reviews
- Earned-and-verified **Trillionaire** (buy → pay $9,999 on a date → confirmed)
- **Masterpiece** — minted only by a confirmed Trillionaire date
- Identity **verification** (blue check); copycats can never verify
- AI **Copycat** lures — richly animated, disclosed, credit-damaging

**Premium & monetization (StoreKit 2)**
- Gavels consumable currency → status archetypes
- Auction Baby Pass (Paddle / Reserve / Black Card) with real gated perks:
  rank reveal, unlimited bids, read receipts, weekly Boost claim,
  reserve price reveal (Reserve), auto-rebid on decline (Reserve),
  priority placement in inbox (Black Card)
- Contextual paywall fired at four peak-intent moments (outbid rank, bid
  cap, locked filters, "did she read it?") with a per-tier benefits matrix
- Spotlight Boost (consumable) — works both sides (lot side pulls bidders in)
- Gilded Bids (the "Rose") · bid on a specific prompt
- Lot of the Day (curated standout, full-screen intro once per day)

**Retention loops**
- Outbid → one-tap rebid ("take the top")
- Daily Gavel claim with growing streak (capped 7×)
- Activity feed (bids, accepts, reviews, milestones) with toolbar bell
- "SOLD!" celebration · "What you're worth tonight" dashboard
- 24-hour match-reply clock (Bumble-style urgency) with a live countdown;
  cold matches lock the composer
- Rewind your last bid (Reserve Pass perk)
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

**Photos**
- Multi-photo upload (PhotosPicker, up to 6), primary + gallery, ≥600×600
  quality gate, JPEG resize to 1600px, rides the AES-GCM encrypted archive
- Onboarding "Photos" step + Profile → "Edit photos" editor
- NSPhotoLibraryUsageDescription in Info.plist

**Dealbreakers (Reserve Requirements)**
- Minimum height (metric with ft/in rendering), smoking, drinking, kids,
  education requirements, gated on Reserve tier
- Blank fields on a target profile always pass — we don't punish incomplete
  profiles

**Integrity + funnel (agent-flagged P1 bundle)**
- **Gavel Confirmed** — mutual meetup verification, both sides attest;
  Gavel Confirmed reviews carry up to +72 (men) / +60 (women) in the
  credit report
- **Opening Bid Script** — Bumble-style woman-authored opener that
  auto-sends on accept, with 4 preset templates
- **Whisper** — anonymous, zero-Gavel, zero-credit-impact signal of interest;
  doesn't count against the free live-bid ceiling. Rendered as "Whisper" on
  the floor; "Whisper Bid" is the internal name only.
- **Lot of the Day** — full-screen "TONIGHT'S LOT" once-a-day intro sheet;
  gold-framed banner + full-screen intro once per day, both named Lot of the Day
- **On the Floor Now** — deterministic hour-of-day live-presence signal on
  ~30% of non-copycat profiles; pulsing green dot on the card
- **Bid Insurance** — Gavel premium on a bid; on decline, premium + a
  Gilded Bid credit refunded
- **The Docket** — daily-claim variable-reward mystery box (20% chance of
  a Gilded credit or bonus streak-freeze); streak-freeze token protects
  the streak on missed days, buyable for Gavels
- **The Standing** — weekly cosmetic leaderboards (top bidders, most-
  contested lots) by city, deterministic per-week

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

**Dating-app parity (agent-flagged P1 features, deferred from launch):**
- **Motion Placard** — video prompts (Hinge-style), 15-sec captures
- **Call from the Floor** — voice prompts, in-profile playback
- **Floor Call** — voice notes in chat
- **Podium Authentication** — live selfie liveness check tied to the blue
  check, so the "verified" signal actually resists spoofing
- **NSFW moderation** — on-device `SCSensitivityAnalyzer` gate at upload time
- **Provenance Check** — ID / gov verification tied into Auction Credit
- **Provenance Report** — background-check integration (Garbo-style) before
  a real-world date
- **Placard Captions** — captions/prompts pinned to individual photos
- Reserve Requirements: self-editor so users can set their own lifestyle
  (currently only bidder-side filters + seeded on sample floor)

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
